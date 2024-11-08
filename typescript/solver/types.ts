import type { BigNumber } from "ethers";
import type { OpenEventObject } from "./contracts/typechain/OriginSettler.js";

export type ExtractStruct<T, K extends object> = T extends (infer U & K)[]
  ? U[]
  : never;

export type ResolvedCrossChainOrder = Omit<
  OpenEventObject["resolvedOrder"],
  "minReceived" | "maxSpent" | "fillInstructions"
> & {
  minReceived: ExtractStruct<
    OpenEventObject["resolvedOrder"]["minReceived"],
    { token: string }
  >;
  maxSpent: ExtractStruct<
    OpenEventObject["resolvedOrder"]["maxSpent"],
    { token: string }
  >;
  fillInstructions: ExtractStruct<
    OpenEventObject["resolvedOrder"]["fillInstructions"],
    { destinationChainId: BigNumber }
  >;
};

export interface OpenEventArgs {
  orderId: string;
  resolvedOrder: ResolvedCrossChainOrder;
}
