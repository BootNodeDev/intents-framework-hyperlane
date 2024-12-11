import { type MultiProvider } from "@hyperlane-xyz/sdk";
import {
  addressToBytes32,
  bytes32ToAddress,
  type Result,
} from "@hyperlane-xyz/utils";

import { Erc20__factory } from "../../typechain/factories/contracts/Erc20__factory.js";
import { Hyperlane7683__factory } from "../../typechain/factories/hyperlane7683/contracts/Hyperlane7683__factory.js";
import type {
  IntentData,
  OpenEventArgs,
  ResolvedCrossChainOrder,
} from "./types.js";
import {
  getChainIdsWithEnoughTokens,
  log,
  retrieveOriginInfo,
  retrieveTargetInfo,
  settleOrder,
} from "./utils.js";

import { allowBlockLists, metadata } from "./config/index.js";
import { chainIdsToName, isAllowedIntent } from "../../config/index.js";

export const create = (multiProvider: MultiProvider) => {
  const { originSettler, protocolName } = setup();

  return async function hyperlane7683({
    orderId,
    resolvedOrder,
  }: OpenEventArgs) {
    const origin = await retrieveOriginInfo(
      resolvedOrder,
      originSettler,
      multiProvider,
    );
    const target = await retrieveTargetInfo(resolvedOrder, multiProvider);

    log.info({
      msg: "Intent Indexed",
      intent: `${protocolName}-${orderId}`,
      origin: origin.join(", "),
      target: target.join(", "),
    });

    const result = await prepareIntent(
      orderId,
      resolvedOrder,
      multiProvider,
      protocolName,
    );

    if (!result.success) {
      log.error(
        `${protocolName} Failed evaluating filling Intent: ${result.error}`,
      );
      return;
    }

    const { fillInstructions, maxSpent } = result.data;

    await fill(
      orderId,
      fillInstructions,
      maxSpent,
      multiProvider,
      protocolName,
    );

    await settleOrder(fillInstructions, orderId, multiProvider, protocolName);
  };
};

function setup() {
  return metadata;
}

// We're assuming the filler will pay out of their own stock, but in reality they may have to
// produce the funds before executing each leg.
async function prepareIntent(
  orderId: string,
  resolvedOrder: ResolvedCrossChainOrder,
  multiProvider: MultiProvider,
  protocolName: string,
): Promise<Result<IntentData>> {
  log.info({
    msg: "Evaluating filling Intent",
    intent: `${protocolName}-${orderId}`,
  });

  try {
    if (
      !resolvedOrder.maxSpent.every((maxSpent) =>
        isAllowedIntent(allowBlockLists, {
          senderAddress: resolvedOrder.user,
          destinationDomain: chainIdsToName[maxSpent.chainId.toString()],
          recipientAddress: maxSpent.recipient,
        }),
      )
    ) {
      return {
        error: "Not allowed intent",
        success: false,
      };
    }

    const chainIdsWithEnoughTokens = await getChainIdsWithEnoughTokens(
      resolvedOrder,
      multiProvider,
    );

    log.debug(
      `${protocolName} - Chain IDs with enough tokens: ${chainIdsWithEnoughTokens}`,
    );

    const fillInstructions = resolvedOrder.fillInstructions.filter(
      ({ destinationChainId }) =>
        chainIdsWithEnoughTokens.includes(destinationChainId.toString()),
    );
    log.debug(
      `${protocolName} - fillInstructions: ${JSON.stringify(fillInstructions)}`,
    );

    const maxSpent = resolvedOrder.maxSpent.filter(({ chainId }) =>
      chainIdsWithEnoughTokens.includes(chainId.toString()),
    );
    log.debug(`${protocolName} - maxSpent: ${JSON.stringify(maxSpent)}`);

    return { data: { fillInstructions, maxSpent }, success: true };
  } catch (error: any) {
    return {
      error:
        error.message ?? "Failed find chain IDs with enough tokens to fill.",
      success: false,
    };
  }
}

async function fill(
  orderId: string,
  fillInstructions: ResolvedCrossChainOrder["fillInstructions"],
  maxSpent: ResolvedCrossChainOrder["maxSpent"],
  multiProvider: MultiProvider,
  protocolName: string,
): Promise<void> {
  log.info({
    msg: "Filling Intent",
    intent: `${protocolName}-${orderId}`,
  });

  await Promise.all(
    maxSpent.map(async ({ chainId, token, amount, recipient }) => {
      token = bytes32ToAddress(token);
      recipient = bytes32ToAddress(recipient);
      const _chainId = chainId.toString();

      const filler = multiProvider.getSigner(_chainId);
      const tx = await Erc20__factory.connect(token, filler).approve(
        recipient,
        amount,
      );

      const receipt = await tx.wait();
      const baseUrl =
        multiProvider.getChainMetadata(_chainId).blockExplorers?.[0].url;

      if (baseUrl) {
        log.debug(
          `${protocolName} - Approval Tx: ${baseUrl}/tx/${receipt.transactionHash}`,
        );
      } else {
        log.debug(`${protocolName} - Approval Tx: ${receipt.transactionHash}`);
      }

      log.debug(
        `${protocolName} - Approved ${amount.toString()} of ${token} to ${recipient} on ${_chainId}`,
      );
    }),
  );

  await Promise.all(
    fillInstructions.map(
      async ({ destinationChainId, destinationSettler, originData }) => {
        destinationSettler = bytes32ToAddress(destinationSettler);
        const _chainId = destinationChainId.toString();

        const filler = multiProvider.getSigner(_chainId);
        const fillerAddress = await filler.getAddress();
        const destination = Hyperlane7683__factory.connect(
          destinationSettler,
          filler,
        );

        // Depending on the implementation we may call `destination.fill` directly or call some other
        // contract that will produce the funds needed to execute this leg and then in turn call
        // `destination.fill`
        const tx = await destination.fill(
          orderId,
          originData,
          addressToBytes32(fillerAddress),
        );

        const receipt = await tx.wait();
        const baseUrl =
          multiProvider.getChainMetadata(_chainId).blockExplorers?.[0].url;

        const txInfo = baseUrl
          ? `${baseUrl}/tx/${receipt.transactionHash}`
          : receipt.transactionHash;

        log.info({
          msg: "Filled Intent",
          intent: `${protocolName}-${orderId}`,
          txDetails: txInfo,
          txHash: receipt.transactionHash,
        });
      },
    ),
  );
}
