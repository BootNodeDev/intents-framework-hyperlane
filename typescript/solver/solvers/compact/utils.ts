import { formatUnits } from "@ethersproject/units";
import type { MultiProvider } from "@hyperlane-xyz/sdk";
import type { BigNumber } from "ethers";

import { createLogger } from "../../logger.js";
import type { IntentCreatedEventObject } from "../../typechain/eco/contracts/IntentSource.js";
import { Erc20__factory } from "../../typechain/factories/contracts/Erc20__factory.js";
import { HyperProver__factory } from "../../typechain/factories/eco/contracts/HyperProver__factory.js";
import { IntentSource__factory } from "../../typechain/factories/eco/contracts/IntentSource__factory.js";
import { getMetadata } from "../utils.js";
import type { EcoMetadata } from "./types.js";

export const metadata = getMetadata<EcoMetadata>(import.meta.dirname);

export const log = createLogger(metadata.solverName);

export async function withdrawRewards(
  intent: IntentCreatedEventObject,
  intentSource: EcoMetadata["intentSource"],
  multiProvider: MultiProvider,
  solverName: string,
) {
  log.info({
    msg: "Settling Intent",
    intent: `${solverName}-${intent._hash}`,
  });

  const { _hash, _prover } = intent;
  const signer = multiProvider.getSigner(intentSource.chainId);
  const claimantAddress = await signer.getAddress();
  const prover = HyperProver__factory.connect(_prover, signer);

  await new Promise((resolve) =>
    prover.once(
      prover.filters.IntentProven(_hash, claimantAddress),
      async () => {
        log.debug(`${solverName} - Intent proven: ${_hash}`);

        const settler = IntentSource__factory.connect(
          intentSource.address,
          signer,
        );
        const tx = await settler.withdrawRewards(_hash);
        const receipt = await tx.wait();
        const baseUrl = multiProvider.getChainMetadata(intentSource.chainId)
          .blockExplorers?.[0].url;

        const txInfo = baseUrl
          ? `${baseUrl}/tx/${receipt.transactionHash}`
          : receipt.transactionHash;

        log.info({
          msg: "Settled Intent",
          intent: `${solverName}-${_hash}`,
          txDetails: txInfo,
          txHash: receipt.transactionHash,
        });

        resolve(_hash);
      },
    ),
  );
}

export async function retrieveOriginInfo(
  intent: IntentCreatedEventObject,
  intentSource: EcoMetadata["intentSource"],
  multiProvider: MultiProvider,
): Promise<Array<string>> {
  const originInfo = await Promise.all(
    intent._rewardTokens.map(async (tokenAddress, index) => {
      const erc20 = Erc20__factory.connect(
        tokenAddress,
        multiProvider.getProvider(intentSource.chainId),
      );
      const [decimals, symbol] = await Promise.all([
        erc20.decimals(),
        erc20.symbol(),
      ]);
      const amount = intent._rewardAmounts[index];

      return { amount, decimals, symbol };
    }),
  );

  return originInfo.map(
    ({ amount, decimals, symbol }) =>
      `${formatUnits(amount, decimals)} ${symbol} in on ${intentSource.chainName}`,
  );
}

export async function retrieveTargetInfo(
  intent: IntentCreatedEventObject,
  adapters: EcoMetadata["adapters"],
  multiProvider: MultiProvider,
): Promise<Array<string>> {
  const erc20Interface = Erc20__factory.createInterface();

  const targetInfo = await Promise.all(
    intent._targets.map(async (tokenAddress, index) => {
      const erc20 = Erc20__factory.connect(
        tokenAddress,
        multiProvider.getProvider(intent._destinationChain.toString()),
      );
      const [decimals, symbol] = await Promise.all([
        erc20.decimals(),
        erc20.symbol(),
      ]);

      const [, amount] = erc20Interface.decodeFunctionData(
        "transfer",
        intent._data[index],
      ) as [string, BigNumber];

      return { amount, decimals, symbol };
    }),
  );

  const targetChain = adapters.find(
    ({ chainId }) => chainId === intent._destinationChain.toNumber(),
  );

  return targetInfo.map(
    ({ amount, decimals, symbol }) =>
      `${formatUnits(amount, decimals)} ${symbol} out on ${targetChain?.chainName ?? "UNKNOWN_CHAIN"}`,
  );
}
