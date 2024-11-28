
export type Compact = {
  hash: string;
  claimChain: number;
  compact: {
    arbiter: string;
    sponsor: string;
    nonce: string;
    expires: string;
    id: string;
    amount: string;
  };
  intent: {
    token: string;
    amount: string;
    fee: string;
    chainId: number;
    recipient: string;
  };
  allocatorSignature: string;
  sponsorSignature: string;
  filled: boolean;
};

export const create = () => {
  return function (handler: (args: Compact) => void) {
    poll<Compact>("https://the-compact-allocator-api.vercel.app/api/compacts/?filled=false", handler);
  };
};

interface PollOptions {
  interval?: number;
  timeout?: number;
}

/**
 * Polling wrapper for a GET request.
 *
 * @param {string} url - The URL to fetch data from.
 * @param {function} handler - Handler function.
 * @param {object} options - Configuration options.
 * @param {number} options.interval - Interval between requests (in milliseconds).
 * @returns {void} - Nothing.
 */
function poll<TResolve>(url: string, handler: (args: TResolve) => void, options: PollOptions = {}) {
  const {
    interval = 4_000, // Default polling interval: 1 second
  } = options;

    const poller = async () => {
      console.log("Polling...");
      const response = await fetch(url);

      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }

      const data = await response.json();

      handler(data.data.compact);

      setTimeout(poller, interval);
    };

    poller();
}
