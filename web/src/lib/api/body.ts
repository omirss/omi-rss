// Express's express.json() equivalent: parses the raw body as JSON, defaults
// to {} when empty (matching express.json's req.body default), and maps a
// parse failure to a 400 AppError — malformed client input is a client error,
// not the 500 the bare SyntaxError used to surface.

import { AppError } from "./errors.js";

export async function readJsonBody(request: Request): Promise<Record<string, unknown>> {
  const raw = await request.text();
  if (!raw) {
    return {};
  }
  try {
    return JSON.parse(raw) as Record<string, unknown>;
  } catch {
    throw new AppError("Malformed JSON body", 400);
  }
}
