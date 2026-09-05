import { ZodError } from "zod";
import { jsonResponse } from "./errors.js";

// Validation failure envelope — same shape errors.ts produces for a thrown
// ZodError ({error, errors[], timestamp}); the webui client reads .error /
// .errors.
export function validationFailure(error: ZodError): Response {
  return jsonResponse(
    {
      error: "Validation failed",
      errors: error.errors.map((e) => ({
        field: e.path.join("."),
        message: e.message,
      })),
      timestamp: new Date().toISOString(),
    },
    400
  );
}
