import { chainIdsToName } from "../../config/index.js";
import type { TypedListener } from "../../typechain/common.js";
import { Hyperlane7683__factory } from "../../typechain/factories/hyperlane7683/contracts/Hyperlane7683__factory.js";
import type {
  Hyperlane7683,
  OpenEvent,
} from "../../typechain/hyperlane7683/contracts/Hyperlane7683.js";
import { BaseListener } from "../BaseListener.js";
import { metadata } from "./config/index.js";
import type { OpenEventArgs, Hyperlane7683Metadata } from "./types.js";
import { log } from "./utils.js";
import { getLastIndexedBlocks } from "./db.js";

export class Hyperlane7683Listener extends BaseListener<
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

export const create = async () => {
  const { originSettlers } = metadata;
  const blocksByChain = await getLastIndexedBlocks();

  metadata.originSettlers = originSettlers.map((originSettler) => {
    const chainBlockNumber = blocksByChain[originSettler.chainName]?.blockNumber;

    if (chainBlockNumber && chainBlockNumber >= (originSettler.initialBlock ?? 0)) {
      return {
        ...originSettler,
        initialBlock: blocksByChain[originSettler.chainName].blockNumber,
        processedIds: blocksByChain[originSettler.chainName].processedIds,
      };
    }
    return originSettler;
  });

  return new Hyperlane7683Listener(metadata).create();
};
