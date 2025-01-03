import z from "zod";
import { chainNames } from "../../config/index.js";

export const CompactMetadataSchema = z.object({
  protocolName: z.string(),
  arbiters: z.array(
    z.object({
      address: z.string(),
      chainName: z.string().refine((name) => chainNames.includes(name), {
          message: "Invalid chainName",
      }),
    }),
  ),
});

export type CompactMetadata = z.infer<typeof CompactMetadataSchema>;

export type Compact = {
  id: number;
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
