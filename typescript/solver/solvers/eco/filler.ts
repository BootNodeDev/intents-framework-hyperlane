import { Zero } from "@ethersproject/constants";
import { type MultiProvider } from "@hyperlane-xyz/sdk";
import { type Result } from "@hyperlane-xyz/utils";

import { type BigNumber } from "ethers";

import type { IntentCreatedEventObject } from "../../typechain/eco/contracts/IntentSource.js";
import { Erc20__factory } from "../../typechain/factories/contracts/Erc20__factory.js";
import { EcoAdapter__factory } from "../../typechain/factories/eco/contracts/EcoAdapter__factory.js";
import type { EcoMetadata, IntentData } from "./types.js";
import {
  log,
  retrieveOriginInfo,
  retrieveTargetInfo,
  withdrawRewards,
} from "./utils.js";
import { metadata, allowBlockLists } from "./config/index.js";
import {
  chainIds,
  chainIdsToName,
  isAllowedIntent,
} from "../../config/index.js";

export const create = (multiProvider: MultiProvider) => {
  const { adapters, intentSource, protocolName } = setup();

  return async function eco(intent: IntentCreatedEventObject) {
    const origin = await retrieveOriginInfo(
      intent,
      intentSource,
      multiProvider,
    );
    const target = await retrieveTargetInfo(intent, adapters, multiProvider);

    log.info({
      msg: "Intent Indexed",
      intent: `${protocolName}-${intent._hash}`,
      origin: origin.join(", "),
      target: target.join(", "),
    });

    const result = await prepareIntent(
      intent,
      adapters,
      multiProvider,
      protocolName,
    );

    if (!result.success) {
      log.error(
        `${protocolName} Failed evaluating filling Intent: ${result.error}`,
      );
      return;
    }

    await fill(
      intent,
      result.data.adapter,
      intentSource,
      multiProvider,
      protocolName,
    );

    await withdrawRewards(intent, intentSource, multiProvider, protocolName);
  };
};

function setup() {
  return metadata;
}

// We're assuming the filler will pay out of their own stock, but in reality they may have to
// produce the funds before executing each leg.
async function prepareIntent(
  intent: IntentCreatedEventObject,
  adapters: EcoMetadata["adapters"],
  multiProvider: MultiProvider,
  protocolName: string,
): Promise<Result<IntentData>> {
  log.info({
    msg: "Evaluating filling Intent",
    intent: `${protocolName}-${intent._hash}`,
  });

  try {
    const destinationChainId = intent._destinationChain.toNumber();
    const adapter = adapters.find(
      ({ chainName }) => chainIds[chainName] === destinationChainId,
    );

    if (!adapter) {
      return {
        error: "No adapter found for destination chain",
        success: false,
      };
    }

    const signer = multiProvider.getSigner(destinationChainId);
    const erc20Interface = Erc20__factory.createInterface();

    const { requiredAmountsByTarget, receivers } = intent._targets.reduce<{
      requiredAmountsByTarget: { [tokenAddress: string]: BigNumber };
      receivers: string[];
    }>(
      (acc, target, index) => {
        const [receiver, amount] = erc20Interface.decodeFunctionData(
          "transfer",
          intent._data[index],
        ) as [string, BigNumber];

        acc.requiredAmountsByTarget[target] ||= Zero;
        acc.requiredAmountsByTarget[target] =
          acc.requiredAmountsByTarget[target].add(amount);

        acc.receivers.push(receiver);

        return acc;
      },
      {
        requiredAmountsByTarget: {},
        receivers: [],
      },
    );

    if (
      !receivers.every((recipientAddress) =>
        isAllowedIntent(allowBlockLists, {
          senderAddress: intent._creator,
          destinationDomain: chainIdsToName[destinationChainId.toString()],
          recipientAddress,
        }),
      )
    ) {
      return {
        error: "Not allowed intent",
        success: false,
      };
    }

    const fillerAddress =
      await multiProvider.getSignerAddress(destinationChainId);

    const areTargetFundsAvailable = await Promise.all(
      Object.entries(requiredAmountsByTarget).map(
        async ([target, requiredAmount]) => {
          const erc20 = Erc20__factory.connect(target, signer);

          const balance = await erc20.balanceOf(fillerAddress);
          return balance.gte(requiredAmount);
        },
      ),
    );

    if (!areTargetFundsAvailable.every(Boolean)) {
      return { error: "Not enough tokens", success: false };
    }

    log.debug(
      `${protocolName} - Approving tokens: ${intent._hash}, for ${adapter.address}`,
    );
    await Promise.all(
      Object.entries(requiredAmountsByTarget).map(
        async ([target, requiredAmount]) => {
          const erc20 = Erc20__factory.connect(target, signer);

          const tx = await erc20.approve(adapter.address, requiredAmount);
          await tx.wait();
        },
      ),
    );

    return { data: { adapter }, success: true };
  } catch (error: any) {
    return {
      error: error.message ?? "Failed to prepare Eco Intent.",
      success: false,
    };
  }
}

async function fill(
  intent: IntentCreatedEventObject,
  adapter: EcoMetadata["adapters"][number],
  intentSource: EcoMetadata["intentSource"],
  multiProvider: MultiProvider,
  protocolName: string,
): Promise<void> {
  log.info({
    msg: "Filling Intent",
    intent: `${protocolName}-${intent._hash}`,
  });

  const _chainId = intent._destinationChain.toString();

  const filler = multiProvider.getSigner(_chainId);
  const ecoAdapter = EcoAdapter__factory.connect(adapter.address, filler);

  const claimantAddress = await multiProvider.getSignerAddress(
    intentSource.chainName,
  );

  const { _targets, _data, _expiryTime, nonce, _hash, _prover } = intent;
  const value = await ecoAdapter.fetchFee(
    chainIds[intentSource.chainName],
    [_hash],
    [claimantAddress],
    _prover,
  );
  const tx = await ecoAdapter.fulfillHyperInstant(
    chainIds[intentSource.chainName],
    _targets,
    _data,
    _expiryTime,
    nonce,
    claimantAddress,
    _hash,
    _prover,
    { value },
  );

  const receipt = await tx.wait();

  log.info({
    msg: "Filled Intent",
    intent: `${protocolName}-${intent._hash}`,
    txDetails: receipt.transactionHash,
    txHash: receipt.transactionHash,
  });
}
