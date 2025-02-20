import { type MultiProvider } from "@hyperlane-xyz/sdk";
import { type Result } from "@hyperlane-xyz/utils";

import { BigNumber } from "@ethersproject/bignumber";
import { AddressZero } from "@ethersproject/constants";
import { HyperlaneArbiter__factory } from "../../typechain/factories/compact/contracts/HyperlaneArbiter__factory.js";
import { Erc20__factory } from "../../typechain/factories/contracts/Erc20__factory.js";
import type { Compact, CompactMetadata } from "./types.js";
import {
  log,
  retrieveOriginInfo,
  retrieveTargetInfo,
} from "./utils.js";
import {
  chainIds
} from "../../config/index.js";
import { metadata , COMPACT_API_KEY } from "./config/index.js";

export const create = (multiProvider: MultiProvider) => {
  const { protocolName, arbiters } = setup();

  return async function compact(intent: Compact) {
    const origin = await retrieveOriginInfo(intent, multiProvider);
    const target = await retrieveTargetInfo(intent, multiProvider);

    log.info({
      msg: "Intent Indexed",
      intent: `${protocolName}-${intent.hash}`,
      origin: origin.join(", "),
      target: target.join(", "),
    });

    const result = await prepareIntent(intent, arbiters, multiProvider, protocolName);

    if (!result.success) {
      log.error(
        `${protocolName} Failed evaluating filling Intent: ${result.error}`,
      );
      return;
    }

    await fill(
      intent,
      result.data.arbiter,
      multiProvider,
      protocolName,
    );

    // await withdrawRewards(intent, intentSource, multiProvider, protocolName);
  };
};

function setup() {
  return metadata;
}

// We're assuming the filler will pay out of their own stock, but in reality they may have to
// produce the funds before executing each leg.
async function prepareIntent(
  intent: Compact,
  arbiters: CompactMetadata["arbiters"],
  multiProvider: MultiProvider,
  protocolName: string,
): Promise<Result<{
  arbiter: CompactMetadata["arbiters"][number];
}>> {
  log.info({
    msg: "Evaluating filling Intent",
    intent: `${protocolName}-${intent.hash}`,
  });

  try {
    const destinationChainId = intent.intent.chainId;
    const arbiter = arbiters.find(
      ({ chainName }) => chainIds[chainName] === destinationChainId,
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
          let balance: BigNumber;
          if (target === AddressZero) {
            balance = await signer.getBalance();
          } else {
            const erc20 = Erc20__factory.connect(target, signer);
            balance = await erc20.balanceOf(fillerAddress);
          }

          return balance.gte(requiredAmount);
        },
      ),
    );

    if (!areTargetFundsAvailable.every(Boolean)) {
      return { error: "Not enough tokens", success: false };
    }

    log.debug(
      `${protocolName} - Approving tokens: ${intent.hash}, for ${arbiter.address}`,
    );
    await Promise.all(
      Object.entries(requiredAmountsByTarget).map(
        async ([target, requiredAmount]) => {
          if (target === AddressZero) {
            return;
          }

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
  protocolName: string,
): Promise<void> {
  log.info({
    msg: "Filling Intent",
    intent: `${protocolName}-${intent.hash}`,
  });

  const _chainId = intent.intent.chainId;

  const filler = multiProvider.getSigner(_chainId);
  const arbiter = HyperlaneArbiter__factory.connect(arbiterInfo.address, filler);

  if (!COMPACT_API_KEY) throw new Error("COMPACT_API_KEY is not set");

  const compact = JSON.stringify(intent);
  const baseUrl = 'https://the-compact-allocator-api.vercel.app/api';
  const apiUrl = `${baseUrl}/quote?compact=${compact}`;
  const response = await fetch(apiUrl, {method: "GET", headers: {"X-API-KEY": COMPACT_API_KEY}});
  const { data } = await response.json() as any;

  const value = BigNumber.from(data.fee).add(intent.intent.amount);

  const tx = await arbiter.fill(
    intent.claimChain,
    intent.compact,
    intent.intent,
    intent.allocatorSignature,
    intent.sponsorSignature,
    { value },
  );

  const receipt = await tx.wait();
  const setFilledUrl = `${baseUrl}/compacts/${intent.id}/setFilled`;
  await fetch(setFilledUrl, { method: "POST", headers: {"X-API-KEY": COMPACT_API_KEY} });

  log.info({
    msg: "Filled Intent",
    intent: `${protocolName}-${intent.hash}`,
    txDetails: receipt.transactionHash,
    txHash: receipt.transactionHash,
  });
}
