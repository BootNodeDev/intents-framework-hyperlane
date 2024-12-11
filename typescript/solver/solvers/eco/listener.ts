import type { TypedListener } from "../../typechain/common.js";
import type {
  IntentCreatedEvent,
  IntentCreatedEventObject,
  IntentSource,
} from "../../typechain/eco/contracts/IntentSource.js";
import { IntentSource__factory } from "../../typechain/factories/eco/contracts/IntentSource__factory.js";
import { BaseListener } from "../BaseListener.js";
import { log } from "./utils.js";
import { metadata } from "./config/index.js";

export class EcoListener extends BaseListener<
  IntentSource,
  IntentCreatedEvent,
  IntentCreatedEventObject
> {
  constructor() {
    const {
      intentSource: { address, chainName },
      protocolName,
    } = metadata;
    const ecoMetadata = { address, chainName, protocolName };

    super(IntentSource__factory, "IntentCreated", ecoMetadata, log);
  }

  protected parseEventArgs([
    _hash,
    _creator,
    _destinationChain,
    _targets,
    _data,
    _rewardTokens,
    _rewardAmounts,
    _expiryTime,
    nonce,
    _prover,
  ]: Parameters<TypedListener<IntentCreatedEvent>>) {
    return {
      _hash,
      _creator,
      _destinationChain,
      _targets,
      _data,
      _rewardTokens,
      _rewardAmounts,
      _expiryTime,
      nonce,
      _prover,
    };
  }
}

export const create = () => new EcoListener().create();
