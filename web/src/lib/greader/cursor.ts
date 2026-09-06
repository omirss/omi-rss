import { createHmac } from "node:crypto";

// Continuation tokens (SPEC 3.5): opaque, signed, keyset cursors.
//
// Payload: { o: "d"|"a" (direction), r: rank usec string, i: article uuid }
// — the rank+id of the LAST ITEM EMITTED on the previous page. Encoded as
// base64url(json) + "." + base64url(hmac-sha256, JWT_SECRET, truncated).
// Pages are keyset-filtered so items cannot dup/drop across page boundaries
// regardless of churn. HMAC ties the cursor to this server's secret.

export interface ContinuationPayload {
  o: "d" | "a";
  r: string;
  i: string;
}

function b64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

function sign(data: string): string {
  return createHmac("sha256", process.env.JWT_SECRET || "").update(data).digest().subarray(0, 16).toString("base64url");
}

export function encodeContinuation(payload: ContinuationPayload): string {
  const body = b64url(JSON.stringify(payload));
  return `${body}.${sign(body)}`;
}

export function decodeContinuation(token: string): ContinuationPayload | null {
  const dot = token.lastIndexOf(".");
  if (dot <= 0) {
    return null;
  }
  const body = token.slice(0, dot);
  const mac = token.slice(dot + 1);
  if (sign(body) !== mac) {
    return null;
  }
  try {
    const parsed = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as Record<string, unknown>;
    if (
      (parsed.o === "d" || parsed.o === "a") &&
      typeof parsed.r === "string" &&
      /^\d+$/.test(parsed.r) &&
      typeof parsed.i === "string" &&
      parsed.i.length > 0
    ) {
      return { o: parsed.o, r: parsed.r, i: parsed.i };
    }
    return null;
  } catch {
    return null;
  }
}
