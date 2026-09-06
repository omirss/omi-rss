import { describe, it, expect } from "vitest";
import {
  validateHttpHeaders,
  HTTP_HEADER_VALUE_MAX,
  HTTP_HEADERS_TOTAL_MAX,
} from "../lib/feed-headers.js";

// Bring-your-own-subscription header allowlist: default-deny with an
// explicit request-header allowlist (Cookie, User-Agent, Referer, Accept,
// Accept-Language, Authorization, X-*), CRLF rejection, and size caps.

describe("validateHttpHeaders allowlist", () => {
  it("accepts the allowlisted request headers", () => {
    const result = validateHttpHeaders({
      Cookie: "session=abc",
      "User-Agent": "MyReader/1.0",
      Referer: "https://example.com/",
      Accept: "text/html",
      "Accept-Language": "en",
      Authorization: "Bearer tok",
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value).toEqual({
        cookie: "session=abc",
        "user-agent": "MyReader/1.0",
        referer: "https://example.com/",
        accept: "text/html",
        "accept-language": "en",
        authorization: "Bearer tok",
      });
    }
  });

  it("accepts X-* custom headers", () => {
    const result = validateHttpHeaders({ "X-Custom": "1", "x-api-key": "k" });
    expect(result.ok).toBe(true);
  });

  it("rejects Host", () => {
    const result = validateHttpHeaders({ Host: "evil.example" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("Host");
  });

  it("rejects Content-Length", () => {
    const result = validateHttpHeaders({ "Content-Length": "999" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("Content-Length");
  });

  it("rejects hop-by-hop headers", () => {
    for (const name of ["Connection", "Keep-Alive", "TE", "Trailer", "Transfer-Encoding", "Upgrade", "Proxy-Authorization"]) {
      const result = validateHttpHeaders({ [name]: "x" });
      expect(result.ok).toBe(false);
    }
  });

  it("rejects non-allowlisted end-to-end headers", () => {
    for (const name of ["Content-Type", "Origin", "Set-Cookie", "If-Modified-Since", "Range"]) {
      const result = validateHttpHeaders({ [name]: "x" });
      expect(result.ok).toBe(false);
    }
  });

  it("rejects case-colliding duplicates (Cookie + cookie)", () => {
    const result = validateHttpHeaders({ Cookie: "a=1", cookie: "b=2" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("Duplicate");
  });

  it("treats null/undefined as no headers", () => {
    expect(validateHttpHeaders(null)).toEqual({ ok: true, value: {} });
    expect(validateHttpHeaders(undefined)).toEqual({ ok: true, value: {} });
  });
});

describe("validateHttpHeaders size caps", () => {
  it("rejects values over 4KB", () => {
    const result = validateHttpHeaders({ Cookie: "a".repeat(HTTP_HEADER_VALUE_MAX + 1) });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("exceeds");
  });

  it("accepts a value at exactly 4KB", () => {
    const result = validateHttpHeaders({ Cookie: "a".repeat(HTTP_HEADER_VALUE_MAX) });
    expect(result.ok).toBe(true);
  });

  it("rejects headers whose combined size exceeds 8KB", () => {
    const half = "a".repeat(HTTP_HEADERS_TOTAL_MAX / 2);
    const result = validateHttpHeaders({ "X-One": half, "X-Two": half });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("total limit");
  });

  it("rejects more than 20 headers", () => {
    const headers: Record<string, string> = {};
    for (let i = 0; i < 21; i++) headers[`X-H${i}`] = "v";
    const result = validateHttpHeaders(headers);
    expect(result.ok).toBe(false);
  });

  it("rejects CRLF header injection in values", () => {
    const result = validateHttpHeaders({ Cookie: "a=1\r\nHost: evil.example" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("control characters");
  });

  it("rejects NUL and other C0 control characters in values", () => {
    for (const value of ["a=1\u0000b", "a=1\u0001b", "a=1\u0007b", "a=1\u000bb", "a=1\tb", "a=1\u001fb"]) {
      const result = validateHttpHeaders({ Cookie: value });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error).toContain("control characters");
    }
  });

  it("rejects DEL (0x7f) in values", () => {
    const result = validateHttpHeaders({ Cookie: "a=1\u007fb" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("control characters");
  });

  it("accepts non-ASCII text in values", () => {
    expect(validateHttpHeaders({ "Accept-Language": "français, 中文" }).ok).toBe(true);
  });

  it("rejects non-token header names", () => {
    expect(validateHttpHeaders({ "Bad Name": "v" }).ok).toBe(false);
    expect(validateHttpHeaders({ "": "v" }).ok).toBe(false);
    expect(validateHttpHeaders({ "X Bad": "v" }).ok).toBe(false);
  });
});
