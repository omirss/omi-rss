import { ZodError } from "zod";
import { jsonResponse } from "./errors.js";

// Express-validator `validate` middleware shape used by the discovery
// routes (no timestamp — these bypassed the shared zod validateRequest).
export function validationFailure(error: ZodError): Response {
  return jsonResponse(
    {
      success: false,
      error: "Validation failed",
      errors: error.errors.map((e) => ({
        field: e.path.join("."),
        message: e.message,
      })),
    },
    400
  );
}
