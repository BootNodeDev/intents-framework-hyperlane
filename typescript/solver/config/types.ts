import z from "zod";
import { ethers } from "ethers";
import { chainNames } from "./index.js";

export const addressSchema = z
  .string()
  .refine((address) => ethers.utils.isAddress(address), {
    message: "Invalid address",
  });
export const addressValueSchema = z.union([
  addressSchema,
  z.array(addressSchema).default([]),
  z.literal("*"),
]);

export const domainSchema = z
  .string()
  .refine((domain) => chainNames.includes(domain), {
    message: "Invalid domain",
  });
export const domainValueSchema = z.union([
  domainSchema,
  z.array(domainSchema).default([]),
  z.literal("*"),
]);

export const AllowBlockListItemSchema = z.object({
  senderAddress: addressValueSchema,
  destinationDomain: domainValueSchema,
  recipientAddress: addressValueSchema,
});

export const AllowBlockListsSchema = z.object({
  allowList: z.array(AllowBlockListItemSchema).default([]),
  blockList: z.array(AllowBlockListItemSchema).default([]),
});

export type AllowBlockListItem = z.infer<typeof AllowBlockListItemSchema>;
export type AllowBlockLists = z.infer<typeof AllowBlockListsSchema>;

export const ConfigSchema = z.record(
  z.string(),
  z.union([domainValueSchema, addressValueSchema]),
);
