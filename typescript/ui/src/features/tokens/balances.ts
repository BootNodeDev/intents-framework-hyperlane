import { IToken, MultiProtocolProvider, Token } from '@hyperlane-xyz/sdk';
import { isValidAddress } from '@hyperlane-xyz/utils';
import { useAccountAddressForChain } from '@hyperlane-xyz/widgets';
import { useQuery } from '@tanstack/react-query';
import { createConfig, getBlockNumber, http, watchContractEvent } from '@wagmi/core';
import { toast } from 'react-toastify';
import type { Address as ViemAddress } from 'viem';
import * as chains from 'viem/chains';
import { useToastError } from '../../components/toast/useToastError';
import { logger } from '../../utils/logger';
import { useMultiProvider } from '../chains/hooks';
import { getChainDisplayName } from '../chains/utils';
import { AppState } from '../store';
import { TransferFormValues, TransferStatus } from '../transfer/types';
import { useTokenByIndex } from './hooks';

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
  transferIndex,
  orderId,
  originToken,
  multiProvider,
  updateTransferStatus,
}: {
  destination: ChainName;
  transferIndex: number;
  orderId: string;
  originToken: Token;
  multiProvider: MultiProtocolProvider;
  updateTransferStatus: AppState['updateTransferStatus'];
}): Promise<string> {
  const destinationChainId = multiProvider.getEvmChainId(destination);

  const chain = Object.values(chains).find(
    (chain) => chain.id === destinationChainId,
  )! as chains.Chain;

  const config = createConfig({
    chains: [chain],
    transports: {
      [chain.id]: http(),
    },
  });

  const fromBlock = await getBlockNumber(config);

  return new Promise((resolve, reject) => {
    const connection = originToken?.getConnectionForChain(destination);
    updateTransferStatus(transferIndex, TransferStatus.Preparing);

    const unwatch = watchContractEvent(config, {
      address: connection?.token.collateralAddressOrDenom as ViemAddress,
      chainId: destinationChainId,
      eventName: 'Filled',
      fromBlock: fromBlock,
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