import { TypedListener } from "../../typechain/common.js";
import { Hyperlane7683__factory } from "../../typechain/factories/hyperlane7683/contracts/Hyperlane7683__factory.js";
import type {
  Hyperlane7683,
  OpenEvent,
} from "../../typechain/hyperlane7683/contracts/Hyperlane7683.js";
import { BaseListener } from "../BaseListener.js";
import { OpenEventArgs } from "./types.js";
import { metadata } from "./config/index.js";
import { log } from "./utils.js";

export class Hyperlane7683Listener extends BaseListener<
  Hyperlane7683,
  OpenEvent,
  OpenEventArgs
> {
  constructor() {
    const {
      originSettler: { address, chainName },
      protocolName,
    } = metadata;
    const hyperlane7683Metadata = { address, chainName, protocolName };

    super(Hyperlane7683__factory, "Open", hyperlane7683Metadata, log);
  }

  protected override parseEventArgs(
    args: Parameters<TypedListener<OpenEvent>>,
  ) {
    const [orderId, resolvedOrder] = args;
    return { orderId, resolvedOrder };
  }
}

export const create = () => new Hyperlane7683Listener().create();
