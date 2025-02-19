import { IToken, MultiProtocolProvider, Token } from '@hyperlane-xyz/sdk';
import { isValidAddress } from '@hyperlane-xyz/utils';
import { useAccountAddressForChain } from '@hyperlane-xyz/widgets';
import { useQuery } from '@tanstack/react-query';
import { createConfig, getBlockNumber, http, watchContractEvent } from '@wagmi/core';
import { toast } from 'react-toastify';
import { defineChain, type Address as ViemAddress } from 'viem';
import * as viemChains from 'viem/chains';
import { chainConfig } from 'viem/op-stack';
import { useToastError } from '../../components/toast/useToastError';
import { logger } from '../../utils/logger';
import { useMultiProvider } from '../chains/hooks';
import { getChainDisplayName } from '../chains/utils';
import { TransferFormValues } from '../transfer/types';
import { useTokenByIndex } from './hooks';

const artela = defineChain({
  id: 11820,
  name: 'artela',
  nativeCurrency: {
    decimals: 18,
    name: 'Artela',
    symbol: 'ART',
  },
  rpcUrls: {
    default: {
      http: ['https://node-euro.artela.network/rpc', 'https://node-hongkong.artela.network/rpc'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Artela Explorer',
      url: 'https://artscan.artela.network',
      apiUrl: 'https://artscan.artela.network/api',
    },
  },
});

const sourceId = 1;
const unichain = defineChain({
  ...chainConfig,
  id: 130,
  name: 'Unichain',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: {
      http: ['https://mainnet.unichain.org/'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Unichain Explorer',
      url: 'https://uniscan.xyz',
      apiUrl: 'https://api.uniscan.xyz/api',
    },
  },
  contracts: {
    ...chainConfig.contracts,
    multicall3: {
      address: '0xca11bde05977b3631167028862be2a173976ca11',
      blockCreated: 0,
    },
    disputeGameFactory: {
      [sourceId]: {
        address: '0x2F12d621a16e2d3285929C9996f478508951dFe4',
      },
    },
    portal: {
      [sourceId]: {
        address: '0x0bd48f6B86a26D3a217d0Fa6FfE2B491B956A7a2',
      },
    },
    l1StandardBridge: {
      [sourceId]: {
        address: '0x81014F44b0a345033bB2b3B21C7a1A308B35fEeA',
      },
    },
  },
  sourceId,
});

const chains = { artela, unichain, ...viemChains };

export function useBalance(chain?: ChainName, token?: IToken, address?: Address) {
  const multiProvider = useMultiProvider();
  const { isLoading, isError, error, data } = useQuery({
    // The Token and Multiprovider classes are not serializable, so we can't use it as a key
    // eslint-disable-next-line @tanstack/query/exhaustive-deps
    queryKey: ['useBalance', chain, address, token?.addressOrDenom],
    queryFn: () => {
      if (!chain || !token || !address || !isValidAddress(address, token.protocol)) return null;
      return token.getBalance(multiProvider, address);
    },
    refetchInterval: 5000,
  });

  useToastError(error, 'Error fetching balance');

  return {
    isLoading,
    isError,
    balance: data ?? undefined,
  };
}

export function useOriginBalance({ origin, tokenIndex }: TransferFormValues) {
  const multiProvider = useMultiProvider();
  const address = useAccountAddressForChain(multiProvider, origin);
  const token = useTokenByIndex(tokenIndex);
  return useBalance(origin, token, address);
}

export function useDestinationBalance({ destination, tokenIndex, recipient }: TransferFormValues) {
  const originToken = useTokenByIndex(tokenIndex);
  const connection = originToken?.getConnectionForChain(destination);
  return useBalance(destination, connection?.token, recipient);
}

export async function getDestinationNativeBalance(
  multiProvider: MultiProtocolProvider,
  { destination, recipient }: TransferFormValues,
) {
  try {
    const chainMetadata = multiProvider.getChainMetadata(destination);
    const token = Token.FromChainMetadataNativeToken(chainMetadata);
    const balance = await token.getBalance(multiProvider, recipient);
    return balance.amount;
  } catch (error) {
    const msg = `Error checking recipient balance on ${getChainDisplayName(multiProvider, destination)}`;
    logger.error(msg, error);
    toast.error(msg);
    return undefined;
  }
}

const abi = [
  {
    type: 'event',
    name: 'Filled',
    inputs: [
      { indexed: false, name: 'orderId', type: 'bytes32' },
      { indexed: false, name: 'originData', type: 'bytes' },
      { indexed: false, name: 'fillerData', type: 'bytes' },
    ],
  },
] as const;

export async function checkOrderFilled({
  destination,
  orderId,
  originToken,
  multiProvider,
}: {
  destination: ChainName;
  orderId: string;
  originToken: Token;
  multiProvider: MultiProtocolProvider;
}): Promise<string> {
  const destinationChainId = multiProvider.getEvmChainId(destination);

  const chain = Object.values(chains).find(
    (chain) => chain.id === destinationChainId,
  )! as chains.Chain;

  const config = createConfig({
    chains: [chain],
    transports: {
      [chain.id]: http(chain.id === 8453 ? 'https://base.llamarpc.com' : undefined),
    },
  });

  const fromBlock = await getBlockNumber(config);

  return new Promise((resolve, reject) => {
    const connection = originToken?.getConnectionForChain(destination);

    const unwatch = watchContractEvent(config, {
      address: connection?.token.collateralAddressOrDenom as ViemAddress,
      chainId: destinationChainId,
      eventName: 'Filled',
      fromBlock: fromBlock,
      args: { orderId },
      abi,
      onLogs([{ data, transactionHash }]) {
        if (data?.toLowerCase().startsWith(orderId.toLowerCase())) {
          // stop listening
          unwatch();
          resolve(transactionHash);
        }
      },
      onError(error) {
        unwatch();
        reject(error);
      },
    });
  });
}
