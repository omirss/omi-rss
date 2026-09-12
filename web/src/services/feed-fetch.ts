import { lookup } from "node:dns/promises";
import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";
import type { RequestOptions } from "node:https";
import { checkServerIdentity } from "node:tls";
import type { IncomingHttpHeaders } from "node:http";
import type { PeerCertificate } from "node:tls";
import { AppError } from "../lib/api/errors.js";
import { ipVersion, isBlockedOutboundAddress, normalizeIp } from "../lib/api/ip.js";
import { sameSiteHost } from "./site-host.js";

// Ported from Express services/feedFetch.ts (v0.2.1): same User-Agent,
// timeouts, retry delays and backoff semantics.
//
// v0.3.1 security audit (SSRF): feed URLs are validated before any bytes
// leave the process. assertSafeFeedUrl rejects non-http(s) schemes and any
// hostname whose literal or DNS-resolved address lands in a loopback,
// private or link-local range (IPv4 and IPv6). Redirects are followed
// manually and every hop is re-validated, so a public feed redirecting to
// 127.0.0.1 or a metadata IP is refused. ALLOW_PRIVATE_FEED_URLS=true skips
// all checks — dev convenience only. DNS resolution failures throw AppErrors
// tagged TRANSIENT_FEED_URL_CODE (retryable); scheme and blocked-range
// failures are untagged (terminal validation failures).
//
// The validation is pinned to the actual connection (fetchPinned): DNS is
// resolved and range-checked, then the request connects to the validated
// numeric address while keeping the original hostname for TLS SNI, cert
// identity and the Host header — closing the resolve-public/connect-private
// (DNS rebinding) gap. Every response body is either fully read under a
// byte cap or the connection is destroyed.

const FEED_USER_AGENT = "omi-rss/0.6.0 (+https://omirss.com)";
const FEED_TIMEOUT_MS = 15000;
const FEED_RETRY_DELAYS_MS = [1000, 3000];
const FEED_RATE_LIMIT_RETRY_DELAY_MS = 10000;
const FEED_MAX_REDIRECT_HOPS = 3;
const FEED_MAX_BODY_BYTES = 5 * 1024 * 1024;

// Error classification: DNS resolution failures are transient (a later
// retry may resolve them — callers leave retryable state in place);
// scheme/blocked-range failures are terminal validation failures.
export const TRANSIENT_FEED_URL_CODE = "feed_url_transient";

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function privateFeedUrlsAllowed(): boolean {
  return process.env.ALLOW_PRIVATE_FEED_URLS === "true";
}

export function isTransientFeedUrlError(error: unknown): boolean {
  return error instanceof AppError && error.code === TRANSIENT_FEED_URL_CODE;
}

function unsafeFeedUrl(url: string, reason: string, code?: string): AppError {
  return new AppError(`Blocked feed URL (${reason}): ${url}`, 400, true, code);
}

async function assertAddressAllowed(address: string, url: string): Promise<void> {
  const normalized = normalizeIp(address);
  if (ipVersion(normalized) === null) {
    throw unsafeFeedUrl(url, `unparseable resolved address ${normalized}`);
  }
  if (isBlockedOutboundAddress(normalized)) {
    throw unsafeFeedUrl(url, `resolved address ${normalized} is loopback, private or link-local`);
  }
}

// Validates a feed URL for outbound fetching. Throws AppError 400 for
// non-http(s) schemes, literal blocked-range hostnames, and hostnames whose
// DNS resolution returns ANY blocked address (resolved once, pre-fetch —
// the hostname is not re-resolved between retries).
export async function assertSafeFeedUrl(url: string): Promise<void> {
  if (privateFeedUrlsAllowed()) {
    return;
  }

  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw unsafeFeedUrl(url, "not a valid URL");
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw unsafeFeedUrl(url, `scheme ${parsed.protocol} is not http(s)`);
  }

  const hostname = parsed.hostname.replace(/^\[|\]$/g, "");
  const literal = normalizeIp(hostname);
  if (ipVersion(literal) !== null) {
    await assertAddressAllowed(literal, url);
    return;
  }

  let resolved: { address: string; family: number }[];
  try {
    resolved = await lookup(hostname, { all: true });
  } catch {
    throw unsafeFeedUrl(url, `DNS resolution failed for ${hostname}`, TRANSIENT_FEED_URL_CODE);
  }
  if (resolved.length === 0) {
    throw unsafeFeedUrl(url, `DNS resolution returned no addresses for ${hostname}`, TRANSIENT_FEED_URL_CODE);
  }
  for (const entry of resolved) {
    await assertAddressAllowed(entry.address, url);
  }
}

export function headerValue(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

export interface PinnedFetchOptions {
  headers?: Record<string, string>;
  timeoutMs: number;
  maxBytes: number;
  // Oversize bodies either truncate at maxBytes (extraction semantics) or
  // fail the request (feed XML must stay parseable).
  truncateOnOversize?: boolean;
  // Bodies on excluded statuses are destroyed instead of read (redirect
  // hops, non-OK statuses) so sockets release immediately.
  readBody?: (status: number) => boolean;
}

export interface PinnedFetchResponse {
  status: number;
  headers: IncomingHttpHeaders;
  body: Buffer | null;
}

// SSRF-safe outbound GET: resolve + range-check the hostname, then connect
// to the validated numeric address (never re-resolving at connect time)
// while the original hostname stays in TLS SNI, the certificate identity
// check and the Host header. One deadline covers connect + headers + body,
// and the body is capped at maxBytes.
export async function fetchPinned(url: string, options: PinnedFetchOptions): Promise<PinnedFetchResponse> {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw unsafeFeedUrl(url, "not a valid URL");
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw unsafeFeedUrl(url, `scheme ${parsed.protocol} is not http(s)`);
  }
  if ((parsed.username || parsed.password) && !privateFeedUrlsAllowed()) {
    throw unsafeFeedUrl(url, "embedded credentials are not allowed");
  }

  const hostname = parsed.hostname.replace(/^\[|\]$/g, "");
  let connectHost = hostname;
  let tlsHostname: string | null = null;

  if (!privateFeedUrlsAllowed()) {
    const literal = normalizeIp(hostname);
    if (ipVersion(literal) !== null) {
      await assertAddressAllowed(literal, url);
    } else {
      let resolved: { address: string; family: number }[];
      try {
        resolved = await lookup(hostname, { all: true });
      } catch {
        throw unsafeFeedUrl(url, `DNS resolution failed for ${hostname}`, TRANSIENT_FEED_URL_CODE);
      }
      if (resolved.length === 0) {
        throw unsafeFeedUrl(url, `DNS resolution returned no addresses for ${hostname}`, TRANSIENT_FEED_URL_CODE);
      }
      for (const entry of resolved) {
        await assertAddressAllowed(entry.address, url);
      }
      const preferred = resolved.find((entry) => entry.family === 4) ?? resolved[0];
      connectHost = preferred.address;
      tlsHostname = hostname;
    }
  }

  return pinnedRequest(parsed, connectHost, tlsHostname, options);
}

function pinnedRequest(
  url: URL,
  connectHost: string,
  tlsHostname: string | null,
  options: PinnedFetchOptions,
): Promise<PinnedFetchResponse> {
  const isHttps = url.protocol === "https:";
  const transport = isHttps ? httpsRequest : httpRequest;
  const requestOptions: RequestOptions = {
    host: connectHost,
    port: url.port ? Number(url.port) : isHttps ? 443 : 80,
    path: `${url.pathname}${url.search}`,
    method: "GET",
    headers: { ...options.headers, Host: url.host },
  };
  if (isHttps && tlsHostname !== null) {
    requestOptions.servername = tlsHostname;
    requestOptions.checkServerIdentity = (host: string, cert: PeerCertificate) =>
      checkServerIdentity(tlsHostname, cert);
  }

  return new Promise<PinnedFetchResponse>((resolve, reject) => {
    let settled = false;
    let truncated = false;
    const chunks: Buffer[] = [];
    let total = 0;
    const settle = (finish: () => void) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      finish();
    };

    const req = transport(requestOptions, (res) => {
      const status = res.statusCode ?? 0;
      const shouldRead = options.readBody ? options.readBody(status) : true;
      if (!shouldRead) {
        res.destroy();
        settle(() => resolve({ status, headers: res.headers, body: null }));
        return;
      }
      res.on("data", (chunk: Buffer) => {
        if (truncated) return;
        if (total + chunk.length > options.maxBytes) {
          if (options.truncateOnOversize) {
            chunks.push(chunk.subarray(0, options.maxBytes - total));
            total = options.maxBytes;
            truncated = true;
            res.destroy();
          } else {
            res.destroy(new Error(`Response body exceeded ${options.maxBytes} bytes: ${url}`));
          }
          return;
        }
        chunks.push(chunk);
        total += chunk.length;
      });
      res.on("end", () => settle(() => resolve({ status, headers: res.headers, body: Buffer.concat(chunks, total) })));
      res.on("error", (error) => settle(() => reject(error)));
      res.on("close", () => {
        if (truncated) {
          settle(() => resolve({ status, headers: res.headers, body: Buffer.concat(chunks, total) }));
        } else if (!settled) {
          settle(() => reject(new Error(`Response closed before completion: ${url}`)));
        }
      });
    });
    const timer = setTimeout(() => {
      req.destroy(new Error(`Pinned fetch timed out after ${options.timeoutMs}ms: ${url}`));
    }, options.timeoutMs);
    req.on("error", (error) => settle(() => reject(error)));
    req.end();
  });
}

interface FeedHttpResponse {
  status: number;
  body: string | null;
}

// Custom headers (bring-your-own-subscription) survive a redirect hop only
// while the destination stays on the original request's origin
// (sameSiteHost: exact scheme+host+port match): cookies and authorization
// are origin-scoped, so any other hop drops them instead of leaking the
// owner's credentials to whoever the feed redirects to.

// Resolves a redirect hop to an absolute URL and re-validates it through the
// same assert — exported for unit tests.
export async function assertRedirectLocation(currentUrl: string, location: string): Promise<string> {
  let next: URL;
  try {
    next = new URL(location, currentUrl);
  } catch {
    throw unsafeFeedUrl(location, "redirect Location is not a valid URL");
  }
  await assertSafeFeedUrl(next.toString());
  return next.toString();
}

async function fetchFeedOnce(url: string, customHeaders?: Record<string, string>): Promise<FeedHttpResponse> {
  let currentUrl = url;
  let currentCustomHeaders = customHeaders;

  for (let hop = 0; hop <= FEED_MAX_REDIRECT_HOPS; hop++) {
    const response = await fetchPinned(currentUrl, {
      headers: {
        "User-Agent": FEED_USER_AGENT,
        Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
        ...(currentCustomHeaders ?? {}),
      },
      timeoutMs: FEED_TIMEOUT_MS,
      maxBytes: FEED_MAX_BODY_BYTES,
      readBody: (status) => status >= 200 && status < 300,
    });

    if (response.status >= 300 && response.status < 400) {
      const location = headerValue(response.headers.location);
      if (!location) {
        return { status: response.status, body: null };
      }
      if (hop === FEED_MAX_REDIRECT_HOPS) {
        throw unsafeFeedUrl(url, `exceeded ${FEED_MAX_REDIRECT_HOPS} redirect hops`);
      }
      const nextUrl = await assertRedirectLocation(currentUrl, location);
      if (currentCustomHeaders && !sameSiteHost(url, nextUrl)) {
        currentCustomHeaders = undefined;
      }
      currentUrl = nextUrl;
      continue;
    }

    const body =
      response.body !== null && response.status >= 200 && response.status < 300
        ? response.body.toString("utf8")
        : null;
    return { status: response.status, body };
  }

  throw unsafeFeedUrl(url, `exceeded ${FEED_MAX_REDIRECT_HOPS} redirect hops`);
}

export async function fetchFeedXml(url: string, customHeaders?: Record<string, string>): Promise<string> {
  await assertSafeFeedUrl(url);

  const maxAttempts = FEED_RETRY_DELAYS_MS.length + 1;
  let retryDelay = 0;
  let lastError: unknown = new Error(`Failed to fetch feed: ${url}`);

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (retryDelay > 0) {
      await sleep(retryDelay);
    }

    try {
      const { status, body } = await fetchFeedOnce(url, customHeaders);

      if (body !== null) {
        return body;
      }

      lastError = new Error(`HTTP ${status} fetching feed: ${url}`);
      retryDelay = status === 429 ? FEED_RATE_LIMIT_RETRY_DELAY_MS : FEED_RETRY_DELAYS_MS[attempt - 1];
    } catch (error) {
      // Blocked URLs never retry — the address will not become safe by
      // trying again.
      if (error instanceof AppError) {
        throw error;
      }
      lastError = error;
      retryDelay = FEED_RETRY_DELAYS_MS[attempt - 1];
    }

    if (attempt < maxAttempts) {
      console.warn(
        `Feed fetch attempt ${attempt}/${maxAttempts} failed for ${url}: ${
          lastError instanceof Error ? lastError.message : String(lastError)
        }`
      );
    }
  }

  throw lastError instanceof Error ? lastError : new Error(`Failed to fetch feed: ${url}`);
}
