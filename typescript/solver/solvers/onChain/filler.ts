import { Wallet } from "@ethersproject/wallet";
import { chainMetadata } from "@hyperlane-xyz/registry";
import { MultiProvider } from "@hyperlane-xyz/sdk";
import { bytes32ToAddress, ensure0x, type Result } from "@hyperlane-xyz/utils";

import { MNEMONIC, PRIVATE_KEY } from "../../config.js";
import { DestinationSettler__factory } from "../../contracts/typechain/factories/DestinationSettler__factory.js";
import { Erc20__factory } from "../../contracts/typechain/factories/Erc20__factory.js";
import { logDebug, logError, logGreen } from "../../logger.js";
import type { OpenEventArgs, ResolvedCrossChainOrder } from "../../types.js";
import { getChainIdsWithEnoughTokens, settleOrder } from "./utils.js";

type IntentData = {
  fillInstructions: ResolvedCrossChainOrder["fillInstructions"];
  maxSpent: ResolvedCrossChainOrder["maxSpent"];
};

export const create = () => {
  const { multiProvider } = setup();

  return async function onChain({ orderId, resolvedOrder }: OpenEventArgs) {
    logGreen("Received Order:", orderId);

    const result = await prepareIntent(resolvedOrder, multiProvider);

    if (!result.success) {
      logError("Failed to gather the information for the intent:", result.error);
      return;
    }

    const { fillInstructions, maxSpent } = result.data;

    await fill(orderId, fillInstructions, maxSpent, multiProvider);

    logGreen(`Filled ${fillInstructions.length} leg(s) for:`, orderId);
  };
};

function setup() {
  if (!PRIVATE_KEY && !MNEMONIC) {
    throw new Error("Either a private key or mnemonic must be provided");
  }

  const multiProvider = new MultiProvider(chainMetadata);
  const wallet = PRIVATE_KEY
    ? new Wallet(ensure0x(PRIVATE_KEY))
    : Wallet.fromMnemonic(MNEMONIC!);
  multiProvider.setSharedSigner(wallet);

  return { multiProvider };
}

// We're assuming the filler will pay out of their own stock, but in reality they may have to
// produce the funds before executing each leg.
async function prepareIntent(
  resolvedOrder: ResolvedCrossChainOrder,
  multiProvider: MultiProvider,
): Promise<Result<IntentData>> {
  try {
    const chainIdsWithEnoughTokens = await getChainIdsWithEnoughTokens(
      resolvedOrder,
      multiProvider,
    );

    logDebug("Chain IDs with enough tokens:", chainIdsWithEnoughTokens);

    const fillInstructions = resolvedOrder.fillInstructions.filter(
      ({ destinationChainId }) =>
        chainIdsWithEnoughTokens.includes(destinationChainId.toString()),
    );
    logDebug("fillInstructions:", JSON.stringify(fillInstructions));

    const maxSpent = resolvedOrder.maxSpent.filter(({ chainId }) =>
      chainIdsWithEnoughTokens.includes(chainId.toString()),
    );
    logDebug("maxSpent:", JSON.stringify(maxSpent));

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
): Promise<void> {
  logGreen("About to fill", fillInstructions.length, "leg(s) for", orderId);

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
        logGreen(`Approval Tx: ${baseUrl}/tx/${receipt.transactionHash}`);
      } else {
        logGreen("Approval Tx:", receipt.transactionHash);
      }

      logDebug(
        "Approved",
        amount.toString(),
        "of",
        token,
        "to",
        recipient,
        "on",
        _chainId,
      );
    }),
  );

  await Promise.all(
    fillInstructions.map(
      async ({ destinationChainId, destinationSettler, originData }) => {
        destinationSettler = bytes32ToAddress(destinationSettler);
        const _chainId = destinationChainId.toString();

        const filler = multiProvider.getSigner(_chainId);
        const destination = DestinationSettler__factory.connect(
          destinationSettler,
          filler,
        );

        // Depending on the implementation we may call `destination.fill` directly or call some other
        // contract that will produce the funds needed to execute this leg and then in turn call
        // `destination.fill`
        const tx = await destination.fill(orderId, originData, "0x");

        const receipt = await tx.wait();
        const baseUrl =
          multiProvider.getChainMetadata(_chainId).blockExplorers?.[0].url;

        if (baseUrl) {
          logGreen(`Fill Tx: ${baseUrl}/tx/${receipt.transactionHash}`);
        } else {
          logGreen("Fill Tx:", receipt.transactionHash);
        }

        logDebug("Filled leg on", _chainId, "with data", originData);
      },
    ),
  );

  // This section is only an example for the settlement process
  await settleOrder(fillInstructions, orderId, multiProvider);
}
