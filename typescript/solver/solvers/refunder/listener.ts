import { chainIdsToName } from "../../config/index.js";
import type { TypedListener } from "../../typechain/common.js";
import { Hyperlane7683__factory } from "../../typechain/factories/hyperlane7683/contracts/Hyperlane7683__factory.js";
import type {
  Hyperlane7683,
  OnchainCrossChainOrderStruct,
  OpenEvent,
} from "../../typechain/hyperlane7683/contracts/Hyperlane7683.js";
import { BaseListener } from "../BaseListener.js";
import { metadata } from "./config/index.js";
import type { OpenEventArgs, Hyperlane7683Metadata } from "./types.js";
import type { OpenEventObject } from "../../typechain/hyperlane7683/contracts/Hyperlane7683.js";
import { log } from "./utils.js";
import { saveOpenOrder, saveOrderStatus, getExpiredOrders } from "./db.js";

import { MultiProvider } from "@hyperlane-xyz/sdk";
import { bytes32ToAddress } from "@hyperlane-xyz/utils";

export class Hyperlane7683Refunder extends BaseListener<
  Hyperlane7683,
  OpenEvent,
  OpenEventArgs
> {
  constructor(metadata: Hyperlane7683Metadata) {
    const { originSettlers, protocolName } = metadata;
    const hyperlane7683Metadata = { contracts: originSettlers, protocolName };

    super(Hyperlane7683__factory, "Open", hyperlane7683Metadata, log);
  }

  protected override parseEventArgs(
    args: Parameters<TypedListener<OpenEvent>>,
  ) {
    const [orderId, resolvedOrder] = args;
    return {
      orderId,
      senderAddress: resolvedOrder.user,
      recipients: resolvedOrder.maxSpent.map(({ chainId, recipient }) => ({
        destinationChainName: chainIdsToName[chainId.toString()],
        recipientAddress: recipient,
      })),
      resolvedOrder,
    };
  }
}

function handler(
  args: OpenEventObject,
  originChainName: string,
  blockNumber: number,
): void {
  const { resolvedOrder } = args;
  const { fillInstructions } = resolvedOrder;

  saveOpenOrder(
    resolvedOrder.originChainId.toNumber(),
    fillInstructions[0].destinationChainId.toNumber(),
    fillInstructions[0].destinationSettler,
    resolvedOrder.orderId,
    parseInt(resolvedOrder.fillDeadline.toString()),
    fillInstructions[0].originData
  )
}

const UNKNOWN =
    "0x0000000000000000000000000000000000000000000000000000000000000000";

async function refund(multiProvider: MultiProvider,) {
  const now = Math.floor(new Date().getTime() / 1000);
  const expiredOrders = await getExpiredOrders(now);

  for (const [destinationChainId, orders] of Object.entries(expiredOrders)) {
    const provider = multiProvider.getProvider(destinationChainId);
    const filler = multiProvider.getSigner(destinationChainId);

    for (const order of orders) {
      const contract = Hyperlane7683__factory.connect(bytes32ToAddress(order.destinationChainSettler), filler);

      const providerTimestamp = (await provider.getBlock("latest")).timestamp


      if (providerTimestamp > order.fillDeadline) {
        const orderStatus = await contract.orderStatus(order.orderId);

        if (orderStatus === UNKNOWN) {
          log.info({
            msg: "Refunding Intent",
            intent: `${metadata.protocolName}-${order.orderId}`,
          });

          await saveOrderStatus(order.orderId, 'REFUNDING')

          try {
            const value = await contract.quoteGasPayment(order.originChainId);

            const onchainCrossChainOrder: OnchainCrossChainOrderStruct = {
              fillDeadline: order.fillDeadline,
              orderDataType: "0x08d75650babf4de09c9273d48ef647876057ed91d4323f8a2e3ebc2cd8a63b5e",
              orderData: order.orderData
            }

            const _tx = await contract.populateTransaction["refund((uint32,bytes32,bytes)[])"](
              [onchainCrossChainOrder],
              { value },
            );

            const gasLimit = await multiProvider.estimateGas(
              destinationChainId,
              _tx,
              await filler.getAddress(),
            );

            const tx = await contract["refund((uint32,bytes32,bytes)[])"]([onchainCrossChainOrder], {
              value,
              gasLimit: gasLimit.mul(110).div(100),
            });

            const receipt = await tx.wait();

            log.info({
              msg: "Refund Intent",
              intent: `${metadata.protocolName}-${order.orderId}`,
              txDetails: `https://explorer.hyperlane.xyz/?search=${receipt.transactionHash}`,
              txHash: receipt.transactionHash,
            });

            await saveOrderStatus(order.orderId, 'REFUNDED')

          } catch (error) {
            await saveOrderStatus(order.orderId, 'OPEN')

            log.error({
              msg: `Failed refunding`,
              intent: `${metadata.protocolName}-${order.orderId}`,
              error,
            });
            return;
          }
        } else {
          await saveOrderStatus(order.orderId, 'FILED')
        }

      }
    }
  }
}

export const create = async (multiProvider: MultiProvider) => {
  const refunder = new Hyperlane7683Refunder(metadata).create();

  refunder(handler)

  setInterval(
    () => refund(multiProvider),
    15000
  );

  return refunder;
};
