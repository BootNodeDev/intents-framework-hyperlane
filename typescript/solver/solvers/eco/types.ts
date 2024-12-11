import z from "zod";
import { chainNames } from "../../config/index.js";

export const EcoMetadataSchema = z.object({
  protocolName: z.string(),
  intentSource: z.object({
    address: z.string(),
    chainName: z.string().refine((name) => chainNames.includes(name), {
      message: "Invalid chainName",
    }),
  }),
  adapters: z.array(
    z.object({
      address: z.string(),
      chainName: z.string().refine((name) => chainNames.includes(name), {
        message: "Invalid chainName",
      }),
    }),
  ),
});

export type EcoMetadata = z.infer<typeof EcoMetadataSchema>;

export type IntentData = { adapter: EcoMetadata["adapters"][number] };
