import { AddressZero } from "@ethersproject/constants";
import { formatUnits } from "@ethersproject/units";
import type { MultiProvider } from "@hyperlane-xyz/sdk";

import { createLogger } from "../../logger.js";
import {
  HyperlaneArbiter__factory,
  TheCompact__factory,
} from "../../typechain/factories/compact/contracts/index.js";
import { Erc20__factory } from "../../typechain/factories/contracts/Erc20__factory.js";
import { metadata } from "./config/index.js";
import { chainIds } from "../../config/index.js";

import type { Compact } from "./types.js";

export const log = createLogger(metadata.protocolName);

export async function retrieveOriginInfo(
  intent: Compact,
  multiProvider: MultiProvider,
): Promise<Array<string>> {
  const provider = multiProvider.getProvider(intent.claimChain);
  const arbiterData = metadata.arbiters.find(
    (a) => chainIds[a.chainName] == intent.claimChain,
  )!;
  const arbiter = HyperlaneArbiter__factory.connect(
    arbiterData.address,
    provider,
  );
  const compact = TheCompact__factory.connect(
    await arbiter.theCompact(),
    provider,
  );
  const [tokenAddress] = await compact.getLockDetails(intent.compact.id);

  const isNative = tokenAddress === AddressZero;

  const erc20 = Erc20__factory.connect(tokenAddress, provider);
  const [decimals, symbol] = await Promise.all([
    isNative ? 18 : erc20.decimals(),
    isNative ? 'ETH' : erc20.symbol(),
  ]);
  const amount = intent.compact.amount;

  return [
    `${formatUnits(amount, decimals)} ${symbol} in on ${arbiterData.chainName}`,
  ];
}

export async function retrieveTargetInfo(
  intent: Compact,
  multiProvider: MultiProvider,
): Promise<Array<string>> {
  const arbiterData = metadata.arbiters.find(
    (a) => chainIds[a.chainName] == intent.intent.chainId,
  )!;
  const provider = multiProvider.getProvider(intent.intent.chainId);
  const erc20 = Erc20__factory.connect(intent.intent.token, provider);
  const isNative = intent.intent.token === AddressZero;
  const [decimals, symbol] = await Promise.all([
    isNative ? 18 : erc20.decimals(),
    isNative ? 'ETH' : erc20.symbol(),
  ]);
  const amount = intent.intent.amount;

  return [
    `${formatUnits(amount, decimals)} ${symbol} out on ${arbiterData.chainName ?? "UNKNOWN_CHAIN"}`,
  ];
}
