import type { Provider } from "@ethersproject/abstract-provider";
import type { BigNumber } from "@ethersproject/bignumber";
import { isHexString } from "@ethersproject/bytes";
import { AddressZero } from "@ethersproject/constants";
import { formatUnits } from "@ethersproject/units";
import type { ChainMap, ChainMetadata } from "@hyperlane-xyz/sdk";
import { MultiProvider } from "@hyperlane-xyz/sdk";
import { ensure0x } from "@hyperlane-xyz/utils";
import { password } from "@inquirer/prompts";

import { MNEMONIC, PRIVATE_KEY } from "../config/index.js";
import { NonceKeeperWallet } from "../NonceKeeperWallet.js";
import { Erc20__factory } from "../typechain/factories/contracts/Erc20__factory.js";

export async function getMultiProvider(chainMetadata: ChainMap<ChainMetadata>) {
  const multiProvider = new MultiProvider(chainMetadata);
  const wallet = await getSigner();

  multiProvider.setSharedSigner(wallet);

  return multiProvider;
}

export async function getSigner() {
  const key = await retrieveKey();
  const signer = privateKeyToSigner(key);
  return signer;
}

function privateKeyToSigner(key: string) {
  if (!key) throw new Error("No private key provided");

  const formattedKey = key.trim().toLowerCase();
  if (isHexString(ensure0x(formattedKey))) {
    return new NonceKeeperWallet(ensure0x(formattedKey));
  }

  if (formattedKey.split(" ").length >= 6) {
    return NonceKeeperWallet.fromMnemonic(formattedKey);
  }

  throw new Error("Invalid private key format");
}

async function retrieveKey() {
  if (PRIVATE_KEY) {
    return PRIVATE_KEY;
  }
  if (MNEMONIC) {
    return MNEMONIC;
  }
  return password({
    message: `Please enter private key or mnemonic.`,
  });
}

export async function retrieveTokenInfo({
  chainName,
  multiProvider,
  tokenAddress,
}: {
  chainName: string;
  multiProvider: MultiProvider;
  tokenAddress: string;
}) {
  if (tokenAddress === AddressZero) {
    const { nativeToken } = multiProvider.getChainMetadata(chainName);

    return {
      decimals: nativeToken?.decimals ?? 18,
      symbol: nativeToken?.symbol ?? "ETH",
    };
  }

  const erc20 = Erc20__factory.connect(
    tokenAddress,
    multiProvider.getProvider(chainName),
  );

  const [decimals, symbol] = await Promise.all([
    erc20.decimals(),
    erc20.symbol(),
  ]);

  return { decimals, symbol };
}

type TransfersInfo = {
  multiProvider: MultiProvider;
  tokens: Array<{
    amount: BigNumber;
    chainName: string;
    tokenAddress: string;
  }>;
};

export async function retrieveTransfersInfo({
  multiProvider,
  tokens,
}: TransfersInfo) {
  return Promise.all(
    tokens.map(async ({ amount, chainName, tokenAddress }) => {
      const { decimals, symbol } = await retrieveTokenInfo({
        chainName,
        multiProvider,
        tokenAddress,
      });

      return { amount, chainName, decimals, symbol };
    }),
  );
}

export async function retrieveOriginInfo({
  multiProvider,
  tokens,
}: TransfersInfo) {
  const transfersInfo = await retrieveTransfersInfo({ multiProvider, tokens });

  return transfersInfo.map(
    ({ amount, chainName, decimals, symbol }) =>
      `${formatUnits(amount, decimals)} ${symbol} in on ${chainName}`,
  );
}

export async function retrieveTargetInfo({
  multiProvider,
  tokens,
}: TransfersInfo) {
  const transfersInfo = await retrieveTransfersInfo({ multiProvider, tokens });

  return transfersInfo.map(
    ({ amount, chainName, decimals, symbol }) =>
      `${formatUnits(amount, decimals)} ${symbol} out on ${chainName}`,
  );
}

export function retrieveTokenBalance(
  tokenAddress: string,
  ownerAddress: string,
  provider: Provider,
) {
  if (tokenAddress === AddressZero) {
    return provider.getBalance(ownerAddress);
  }

  const erc20 = Erc20__factory.connect(tokenAddress, provider);
  return erc20.balanceOf(ownerAddress);
}
