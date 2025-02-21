import { isValidAddress } from "@hyperlane-xyz/utils";
import z from "zod";

export const addressSchema = z
  .string()
  .refine((address) => isValidAddress(address), {
    message: "Invalid address",
  });
