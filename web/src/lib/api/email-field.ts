import { z } from "zod";

// Email is optional across the auth surface (username+password accounts).
// Empty string and null are tolerated as absent so client forms can send
// the field unconditionally. Shared by register and profile update.
export const optionalEmail = z
  .union([z.string().email(), z.literal(""), z.null()])
  .optional()
  .transform((value) => (value ? value : undefined));
