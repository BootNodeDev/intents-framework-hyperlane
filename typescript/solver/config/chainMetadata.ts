import { z } from "zod";

import { chainMetadata as defaultChainMetadata } from "@hyperlane-xyz/registry";

import { ChainMetadataSchema } from "@hyperlane-xyz/sdk";
import type { ChainMap, ChainMetadata } from "@hyperlane-xyz/sdk";

import { objMerge } from "@hyperlane-xyz/utils";

const customChainMetadata = {
  // Example custom configuration
  // "base": {
  //   "rpcUrls": [
  //     {
  //       "http": "https://base.llamarpc.com"
  //     }
  //   ]
  // }
};

const chainMetadata = objMerge<ChainMap<ChainMetadata>>(
  defaultChainMetadata,
  customChainMetadata,
  10,
  false,
);

z.record(z.string(), ChainMetadataSchema).parse(chainMetadata);

export { chainMetadata };
