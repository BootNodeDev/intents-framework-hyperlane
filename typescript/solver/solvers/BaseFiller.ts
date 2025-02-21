import type { MultiProvider } from "@hyperlane-xyz/sdk";
import type { Result } from "@hyperlane-xyz/utils";
import {
  type GenericAllowBlockLists,
  isAllowedIntent,
} from "../config/index.js";
import type { Logger } from "../logger.js";

type Metadata = {
  protocolName: string;
};

export type ParsedArgs = {
  orderId: string;
  senderAddress: string;
  recipients: Array<{
    destinationChainName: string;
    recipientAddress: string;
  }>;
};

export type Rule<
  TMetadata extends Metadata,
  TParsedArgs extends ParsedArgs,
  TIntentData extends unknown,
> = (
  parsedArgs: TParsedArgs,
  context: BaseFiller<TMetadata, TParsedArgs, TIntentData>,
) => Promise<Result<string>>;

export abstract class BaseFiller<
  TMetadata extends Metadata,
  TParsedArgs extends ParsedArgs,
  TIntentData extends unknown,
> {
  rules: Array<Rule<TMetadata, TParsedArgs, TIntentData>> = [];

  protected constructor(
    readonly multiProvider: MultiProvider,
    readonly allowBlockLists: GenericAllowBlockLists,
    readonly metadata: TMetadata,
    readonly log: Logger,
    rules?: Array<Rule<TMetadata, TParsedArgs, TIntentData>>,
  ) {
    if (rules) this.rules = rules;
  }

  create() {
    return async (
      parsedArgs: TParsedArgs,
      originChainName: string,
      blockNumber: number,
    ) => {
      const origin = await this.retrieveOriginInfo(parsedArgs, originChainName);
      const target = await this.retrieveTargetInfo(parsedArgs);

      this.log.info({
        msg: "Intent Indexed",
        intent: `${this.metadata.protocolName}-${parsedArgs.orderId}`,
        origin: origin.join(", "),
        target: target.join(", "),
      });

      const intent = await this.prepareIntent(parsedArgs);

      if (!intent.success) {
        this.log.error(`Failed evaluating filling Intent: ${intent.error}`);
        return;
      }

      const { data } = intent;

      try {
        await this.fill(parsedArgs, data, originChainName, blockNumber);

        await this.settleOrder(parsedArgs, data);
      } catch (error) {
        this.log.error({
          msg: `Failed processing intent`,
          intent: `${this.metadata.protocolName}-${parsedArgs.orderId}`,
          error: JSON.stringify(error),
        });
      }
    };
  }

  protected abstract retrieveOriginInfo(
    parsedArgs: TParsedArgs,
    chainName: string,
  ): Promise<Array<string>>;

  protected abstract retrieveTargetInfo(
    parsedArgs: TParsedArgs,
  ): Promise<Array<string>>;

  protected async prepareIntent(
    parsedArgs: TParsedArgs,
  ): Promise<Result<TIntentData>> {
    this.log.info({
      msg: "Evaluating filling Intent",
      intent: `${this.metadata.protocolName}-${parsedArgs.orderId}`,
    });

    const { senderAddress, recipients } = parsedArgs;

    if (!this.isAllowedIntent({ senderAddress, recipients })) {
      throw new Error("Not allowed intent");
    }

    const result = await this.evaluateRules(parsedArgs);

    if (!result.success) {
      throw new Error(result.error);
    }

    return { error: "Not implemented", success: false };
  }

  protected async evaluateRules(parsedArgs: TParsedArgs) {
    let result: Result<string> = { success: true, data: "No rules" };

    for (const rule of this.rules) {
      result = await rule(parsedArgs, this);

      if (!result.success) {
        break;
      }
    }

    return result;
  }

  protected abstract fill(
    parsedArgs: TParsedArgs,
    data: TIntentData,
    originChainName: string,
    blockNumber: number,
  ): Promise<void>;

  protected async settleOrder(parsedArgs: TParsedArgs, data: TIntentData) {
    return;
  }

  protected isAllowedIntent({
    senderAddress,
    recipients,
  }: {
    senderAddress: string;
    recipients: Array<{
      destinationChainName: string;
      recipientAddress: string;
    }>;
  }) {
    return recipients.every(({ destinationChainName, recipientAddress }) =>
      isAllowedIntent(this.allowBlockLists, {
        senderAddress,
        destinationDomain: destinationChainName,
        recipientAddress,
      }),
    );
  }
}
