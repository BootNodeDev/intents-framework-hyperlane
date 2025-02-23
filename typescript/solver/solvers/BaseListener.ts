import type { Provider } from "@ethersproject/providers";
import { MultiProvider } from "@hyperlane-xyz/sdk";
import type { Contract, EventFilter, Signer } from "ethers";

import { chainMetadata } from "../config/chainMetadata.js";
import type { Logger } from "../logger.js";
import type { TypedEvent, TypedListener } from "../typechain/common.js";
import type { ParsedArgs } from "./BaseFiller.js";

export abstract class BaseListener<
  TContract extends Contract,
  TEvent extends TypedEvent,
  TParsedArgs extends ParsedArgs,
> {
  protected constructor(
    private readonly contractFactory: {
      connect(address: string, signerOrProvider: Signer | Provider): TContract;
    },
    private readonly eventName: Extract<keyof TContract["filters"], string>,
    private readonly metadata: {
      contracts: Array<{
        address: string;
        chainName: string;
        pollInterval?: number;
        confirmationBlocks?: number;
        initialBlock?: number;
        processedIds?: string[];
      }>;
      protocolName: string;
    },
    private readonly log: Logger,
  ) {}

  private lastProcessedBlocks: Record<string, number> = {};

  private defaultPollInterval: number = 3000; // 3 seconds

  private defaultMaxBlockRange: number = 3000;

  create() {
    return async (
      handler: (
        args: TParsedArgs,
        originChainName: string,
        blockNumber: number,
      ) => void,
    ) => {
      for (const value of Object.values(chainMetadata)) {
        value.rpcUrls = value.rpcUrls.map((rpc) => {
          rpc.pagination = rpc.pagination ?? {};
          rpc.pagination.maxBlockRange =
            rpc.pagination.maxBlockRange ?? this.defaultMaxBlockRange;
          return rpc;
        });
      }

      const multiProvider = new MultiProvider(chainMetadata);

      this.metadata.contracts.forEach(
        async ({
          address,
          chainName,
          pollInterval,
          confirmationBlocks,
          initialBlock,
          processedIds,
        }) => {
          const provider = multiProvider.getProvider(chainName);
          const contract = this.contractFactory.connect(address, provider);
          const filter = contract.filters[this.eventName]();

          const latest = await provider.getBlockNumber();
          this.lastProcessedBlocks[chainName] = latest;

          if (initialBlock && initialBlock < latest - 1) {
            this.processPrevBlocks(
              chainName,
              contract,
              filter,
              initialBlock,
              latest - 1,
              handler,
              processedIds,
            );
          }

          setInterval(
            () =>
              this.pollEvents(
                chainName,
                contract,
                filter,
                handler,
                confirmationBlocks,
              ),
            pollInterval ?? this.defaultPollInterval,
          );

          contract.provider.getNetwork().then((network) => {
            this.log.info({
              msg: "Listener started",
              event: this.eventName,
              protocol: this.metadata.protocolName,
              chainId: network.chainId,
              chainName: chainName,
            });
          });
        },
      );
    };
  }

  protected async pollEvents(
    chainName: string,
    contract: TContract,
    filter: EventFilter,
    handler: (
      args: TParsedArgs,
      originChainName: string,
      blockNumber: number,
    ) => void,
    confirmationBlocks?: number,
  ) {
    const latestBlock = await contract.provider.getBlockNumber();
    const fromBlock = this.lastProcessedBlocks[chainName] + 1;
    const toBlock = latestBlock - (confirmationBlocks ?? 0);

    if (toBlock <= fromBlock) {
      this.log.debug({
        msg: "No new confirmed blocks yet",
        protocolName: this.metadata.protocolName,
        chainName,
      });

      return;
    }

    const events = await contract.queryFilter(filter, fromBlock, toBlock);

    this.log.debug({
      msg: "Polling",
      protocolName: this.metadata.protocolName,
      chainName,
      fromBlock,
      toBlock,
      eventsFound: events.length,
    });

    for (let i = 0; i < events.length; i++) {
      handler(
        this.parseEventArgs((events[i] as TEvent).args),
        chainName,
        events[i].blockNumber,
      );
    }

    this.lastProcessedBlocks[chainName] = toBlock;
  }

  protected async processPrevBlocks(
    chainName: string,
    contract: TContract,
    filter: EventFilter,
    from: number,
    to: number,
    handler: (
      args: TParsedArgs,
      originChainName: string,
      blockNumber: number,
    ) => void,
    processedIds?: string[],
  ) {
    const pastEvents = await contract.queryFilter(filter, from, to);

    for (let event of pastEvents) {
      const parsedArgs = this.parseEventArgs((event as TEvent).args);
      if (
        event.blockNumber === from &&
        processedIds?.includes(parsedArgs.orderId)
      ) {
        continue;
      }
      await handler(parsedArgs, chainName, event.blockNumber);
    }
  }

  protected abstract parseEventArgs(
    args: Parameters<TypedListener<TEvent>>,
  ): TParsedArgs;
}
