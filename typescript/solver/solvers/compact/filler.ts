import { Zero } from "@ethersproject/constants";
import { type MultiProvider } from "@hyperlane-xyz/sdk";
import { type Result } from "@hyperlane-xyz/utils";

import { Erc20__factory } from "../../typechain/factories/contracts/Erc20__factory.js";
import type { Compact, CompactMetadata } from "./types.js";
import {
  log,
  metadata,
  retrieveOriginInfo,
  retrieveTargetInfo,
} from "./utils.js";
import { HyperlaneArbiter__factory } from "../../typechain/factories/compact/contracts/HyperlaneArbiter__factory.js";

export const create = (multiProvider: MultiProvider) => {
  const { solverName } = setup();

  return async function compact(intent: Compact) {
    const origin = await retrieveOriginInfo(intent, multiProvider);
    const target = await retrieveTargetInfo(intent, multiProvider);

    log.info({
      msg: "Intent Indexed",
      intent: `${solverName}-${intent.hash}`,
      origin: origin.join(", "),
      target: target.join(", "),
    });

    const result = await prepareIntent(
      intent,
      adapters,
      multiProvider,
      solverName,
    );

    if (!result.success) {
      log.error(
        `${solverName} Failed evaluating filling Intent: ${result.error}`,
      );
      return;
    }

    await fill(
      intent,
      result.data.adapter,
      intentSource,
      multiProvider,
      solverName,
    );

    // await withdrawRewards(intent, intentSource, multiProvider, solverName);
  };
};

function setup() {
  if (!metadata.solverName) {
    metadata.solverName = "UNKNOWN_SOLVER";
  }

  if (
    !metadata.arbiters.every(
      ({ address, chainId, chainName }) =>
        !!address && !!chainId && !!chainName,
    )
  ) {
    throw new Error("Arbiter address must be provided");
  }

  return metadata;
}

// We're assuming the filler will pay out of their own stock, but in reality they may have to
// produce the funds before executing each leg.
async function prepareIntent(
  intent: Compact,
  arbiters: CompactMetadata["arbiters"],
  multiProvider: MultiProvider,
  solverName: string,
): Promise<Result<IntentData>> {
  log.info({
    msg: "Evaluating filling Intent",
    intent: `${solverName}-${intent.hash}`,
  });

  try {
    const destinationChainId = intent.intent.chainId;
    const arbiter = arbiters.find(
      ({ chainId }) => chainId === destinationChainId,
    );

    if (!arbiter) {
      return {
        error: "No arbiter found for destination chain",
        success: false,
      };
    }

    const signer = multiProvider.getSigner(destinationChainId);

    const requiredAmountsByTarget = {
      [intent.intent.token]: intent.intent.amount,
    };

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
      `${solverName} - Approving tokens: ${intent.hash}, for ${arbiter.address}`,
    );
    await Promise.all(
      Object.entries(requiredAmountsByTarget).map(
        async ([target, requiredAmount]) => {
          const erc20 = Erc20__factory.connect(target, signer);

          const tx = await erc20.approve(arbiter.address, requiredAmount);
          await tx.wait();
        },
      ),
    );

    return { data: { arbiter }, success: true };
  } catch (error: any) {
    return {
      error: error.message ?? "Failed to prepare Compact Intent.",
      success: false,
    };
  }
}

async function fill(
  intent: Compact,
  arbiterInfo: CompactMetadata["arbiters"][number],
  multiProvider: MultiProvider,
  solverName: string,
): Promise<void> {
  log.info({
    msg: "Filling Intent",
    intent: `${solverName}-${intent.hash}`,
  });

  const _chainId = intent.intent.chainId;

  const filler = multiProvider.getSigner(_chainId);
  const arbiter = HyperlaneArbiter__factory.connect(
    arbiterInfo.address,
    filler,
  );

  const value = 0;
  const tx = await arbiter.fill(
    intent.claimChain,
    intent.compact,
    intent.intent,
    intent.allocatorSignature,
    intent.sponsorSignature,
    { value },
  );

  const receipt = await tx.wait();

  log.info({
    msg: "Filled Intent",
    intent: `${solverName}-${intent.hash}`,
    txDetails: receipt.transactionHash,
    txHash: receipt.transactionHash,
  });
}
