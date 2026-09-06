// Bring-your-own-subscription header validation. Shared by the API route
// (server) and the feed edit dialog (client) so both reject the same way:
// default-deny request-header allowlist plus size caps. Hop-by-hop and
// framing headers (Host, Content-Length, Connection, ...) can never pass —
// they are either transport-owned or would let a stored value alter the
// request the fetch stack sends.

export const HTTP_HEADER_VALUE_MAX = 4096;
export const HTTP_HEADERS_TOTAL_MAX = 8192;
export const HTTP_HEADER_COUNT_MAX = 20;

const ALLOWED_REQUEST_HEADERS = new Set([
  "cookie",
  "user-agent",
  "referer",
  "accept",
  "accept-language",
  "authorization",
]);

const HEADER_NAME_RE = /^[a-zA-Z0-9-]+$/;

// Names rejected with a targeted message (everything not allowlisted is
// rejected; these just say why).
const BLOCKED_HEADER_REASONS: Record<string, string> = {
  host: "Host is set by the fetch stack and cannot be overridden",
  "content-length": "Content-Length is set by the fetch stack and cannot be overridden",
  connection: "Connection is a hop-by-hop header and cannot be sent",
  "keep-alive": "Keep-Alive is a hop-by-hop header and cannot be sent",
  "proxy-authenticate": "Proxy-Authenticate is a hop-by-hop header and cannot be sent",
  "proxy-authorization": "Proxy-Authorization is a hop-by-hop header and cannot be sent",
  te: "TE is a hop-by-hop header and cannot be sent",
  trailer: "Trailer is a hop-by-hop header and cannot be sent",
  "transfer-encoding": "Transfer-Encoding is a hop-by-hop header and cannot be sent",
  upgrade: "Upgrade is a hop-by-hop header and cannot be sent",
};

export type HttpHeadersValidation =
  | { ok: true; value: Record<string, string> }
  | { ok: false; error: string };

export function validateHttpHeaders(input: unknown): HttpHeadersValidation {
  if (input === null || input === undefined) {
    return { ok: true, value: {} };
  }
  if (typeof input !== "object" || Array.isArray(input)) {
    return { ok: false, error: "httpHeaders must be an object of header names to values" };
  }

  const entries = Object.entries(input as Record<string, unknown>);
  if (entries.length > HTTP_HEADER_COUNT_MAX) {
    return { ok: false, error: `Too many headers (max ${HTTP_HEADER_COUNT_MAX})` };
  }

  const result: Record<string, string> = {};
  let total = 0;

  for (const [rawName, rawValue] of entries) {
    const name = rawName.trim();
    if (!name) {
      return { ok: false, error: "Header name is required" };
    }
    if (!HEADER_NAME_RE.test(name)) {
      return { ok: false, error: `Invalid header name: ${name}` };
    }
    const canonical = name.toLowerCase();
    if (!ALLOWED_REQUEST_HEADERS.has(canonical) && !canonical.startsWith("x-")) {
      const reason = BLOCKED_HEADER_REASONS[canonical];
      return { ok: false, error: reason ?? `Header not allowed: ${name}` };
    }
    if (typeof rawValue !== "string") {
      return { ok: false, error: `Header ${name} must have a string value` };
    }
    if (/[\u0000-\u001f\u007f]/.test(rawValue)) {
      return { ok: false, error: `Header ${name} value must not contain control characters` };
    }
    if (rawValue.length > HTTP_HEADER_VALUE_MAX) {
      return { ok: false, error: `Header ${name} exceeds ${HTTP_HEADER_VALUE_MAX} characters` };
    }
    if (canonical in result) {
      return { ok: false, error: `Duplicate header (case-insensitive): ${canonical}` };
    }
    result[canonical] = rawValue;
    total += canonical.length + rawValue.length;
    if (total > HTTP_HEADERS_TOTAL_MAX) {
      return { ok: false, error: `Headers exceed the ${HTTP_HEADERS_TOTAL_MAX} character total limit` };
    }
  }

  return { ok: true, value: result };
}
