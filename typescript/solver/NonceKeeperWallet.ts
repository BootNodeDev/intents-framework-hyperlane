import { defaultPath, HDNode } from "@ethersproject/hdnode";
import type { Deferrable } from "@ethersproject/properties";
import type {
  Provider,
  TransactionRequest,
  TransactionResponse,
} from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";
import type { Wordlist } from "@ethersproject/wordlists";

import { log } from "./logger.js";

const nonces: Record<number, Promise<number>> = {};

export class NonceKeeperWallet extends Wallet {
  connect(provider: Provider): NonceKeeperWallet {
    return new NonceKeeperWallet(this, provider);
  }

  async getNextNonce(): Promise<number> {
    const chainId = await this.getChainId();
    nonces[chainId] ||= super.getTransactionCount();
    const nonce = nonces[chainId];
    nonces[chainId] = nonces[chainId].then((nonce) => nonce + 1);

    return nonce;
  }

  sendTransaction(
    transaction: Deferrable<TransactionRequest>,
  ): Promise<TransactionResponse> {
    if (transaction.nonce == null) {
      transaction.nonce = this.getNextNonce();
    }

    log.debug({ msg: "transaction", transaction });

    return super.sendTransaction(transaction);
  }

  static override fromMnemonic(
    mnemonic: string,
    path?: string,
    wordlist?: Wordlist,
  ) {
    if (!path) {
      path = defaultPath;
    }

    return new NonceKeeperWallet(
      HDNode.fromMnemonic(mnemonic, undefined, wordlist).derivePath(path),
    );
  }
}
