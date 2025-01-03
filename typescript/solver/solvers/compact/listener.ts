import type { Compact } from "./types.js";
import { allowBlockLists, COMPACT_API_KEY } from "./config/index.js";
import {
  chainIdsToName,
  isAllowedIntent,
} from "../../config/index.js";

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
    if (!COMPACT_API_KEY) throw new Error("COMPACT_API_KEY is not set");
    const response = await fetch(url, {method: "GET", headers: {"X-API-KEY": COMPACT_API_KEY}});

    if (!response.ok) {
      throw new Error(`HTTP error! Status: ${response.status}`);
    }

    // This is reading all the non-filled compacts
    const {
      data: { compacts }
    } = await response.json() as { data: { compacts: Compact[] } };

    // This is filtering the compacts to only include the ones that are allowed
    compacts.filter((compact: Compact) =>
      isAllowedIntent(allowBlockLists, {
        senderAddress: compact.compact.sponsor,
        destinationDomain: chainIdsToName[compact.intent.chainId.toString()],
        recipientAddress: compact.intent.recipient,
      })
    );

    for await (const compact of compacts) {
      await handler(compact as TResolve);
    }

    setTimeout(poller, interval);
  };

  poller();
}
