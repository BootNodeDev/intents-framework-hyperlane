import type { Compact } from "./types.js";

export const create = () => {
  return function (handler: (args: Compact) => void) {
    poll<Compact>(
      "https://the-compact-allocator-api.vercel.app/api/compacts/?filled=false",
      handler,
    );
  };
};

interface PollOptions {
  interval?: number;
  timeout?: number;
}

function poll<TResolve>(
  url: string,
  handler: (args: TResolve) => void,
  options: PollOptions = {},
) {
  const {
    interval = 4_000, // Default polling interval: 1 second
  } = options;

  const poller = async () => {
    console.log("Polling...");
    const response = await fetch(url);

    if (!response.ok) {
      throw new Error(`HTTP error! Status: ${response.status}`);
    }

    // This is reading all the non-filled compacts
    const {
      data: { compacts: _compacts }
    } = await response.json();

    const compacts = _compacts.map((_compact: any) => ({
      id: _compact.id,
      hash: _compact.hash,
      claimChain: _compact.claimChain,
      compact: {
        arbiter: _compact.compact_arbiter,
        sponsor: _compact.compact_sponsor,
        nonce: _compact.compact_nonce,
        expires: _compact.compact_expires,
        id: _compact.compact_id,
        amount: _compact.compact_amount,
      },
      intent: {
        token: _compact.intent_token,
        amount: _compact.intent_amount,
        fee: _compact.intent_fee,
        chainId: _compact.intent_chainId,
        recipient: _compact.intent_recipient,
      },
      allocatorSignature: _compact.allocatorSignature,
      sponsorSignature: _compact.sponsorSignature,
      filled: _compact.filled,
    }));


    for await (const compact of compacts) {
      await handler(compact as TResolve);
    }

    setTimeout(poller, interval);
  };

  poller();
}
