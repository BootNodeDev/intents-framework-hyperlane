import type { MultiProvider } from "@hyperlane-xyz/sdk";

import { createLogger } from "../../logger.js";
import type { IntentCreatedEventObject } from "../../typechain/eco/contracts/IntentSource.js";
import { HyperProver__factory } from "../../typechain/factories/eco/contracts/HyperProver__factory.js";
import { IntentSource__factory } from "../../typechain/factories/eco/contracts/IntentSource__factory.js";
import { metadata } from "./config/index.js";

export const log = createLogger(metadata.protocolName);

export async function withdrawRewards(
  intent: IntentCreatedEventObject,
  originChainName: string,
  multiProvider: MultiProvider,
  protocolName: string,
) {
  log.info({
    msg: "Settling Intent",
    intent: `${protocolName}-${intent._hash}`,
  });

  const { _hash, _prover } = intent;
  const signer = multiProvider.getSigner(originChainName);
  const claimantAddress = await signer.getAddress();
  const prover = HyperProver__factory.connect(_prover, signer);

  await new Promise((resolve) =>
    prover.once(
      prover.filters.IntentProven(_hash, claimantAddress),
      async () => {
        log.debug(`${protocolName} - Intent proven: ${_hash}`);

        const settler = IntentSource__factory.connect(
          metadata.intentSources.find(
            (source) => source.chainName == originChainName,
          )!.address,
          signer,
        );
        const tx = await settler.withdrawRewards(_hash);
        const receipt = await tx.wait();
        const baseUrl =
          multiProvider.getChainMetadata(originChainName).blockExplorers?.[0]
            .url;

        const txInfo = baseUrl
          ? `${baseUrl}/tx/${receipt.transactionHash}`
          : receipt.transactionHash;

        log.info({
          msg: "Settled Intent",
          intent: `${protocolName}-${_hash}`,
          txDetails: txInfo,
          txHash: receipt.transactionHash,
        });

        resolve(_hash);
      },
    ),
  );
}
