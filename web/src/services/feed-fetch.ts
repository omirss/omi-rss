import { lookup } from "node:dns/promises";
import { AppError } from "../lib/api/errors.js";
import { ipVersion, isBlockedOutboundAddress, normalizeIp } from "../lib/api/ip.js";

// Ported from Express services/feedFetch.ts (v0.2.1): same User-Agent,
// timeouts, retry delays and backoff semantics.
//
// v0.3.1 security audit (SSRF): feed URLs are validated before any bytes
// leave the process. assertSafeFeedUrl rejects non-http(s) schemes and any
// hostname whose literal or DNS-resolved address lands in a loopback,
// private or link-local range (IPv4 and IPv6). Redirects are followed
// manually and every hop is re-validated, so a public feed redirecting to
// 127.0.0.1 or a metadata IP is refused. ALLOW_PRIVATE_FEED_URLS=true skips
// all checks — dev convenience only.

const FEED_USER_AGENT = "omi-rss/0.2 (+https://omirss.com)";
const FEED_TIMEOUT_MS = 15000;
const FEED_RETRY_DELAYS_MS = [1000, 3000];
const FEED_RATE_LIMIT_RETRY_DELAY_MS = 10000;
const FEED_MAX_REDIRECT_HOPS = 3;

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function privateFeedUrlsAllowed(): boolean {
  return process.env.ALLOW_PRIVATE_FEED_URLS === "true";
}

function unsafeFeedUrl(url: string, reason: string): AppError {
  return new AppError(`Blocked feed URL (${reason}): ${url}`, 400);
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
    throw unsafeFeedUrl(url, `DNS resolution failed for ${hostname}`);
  }
  if (resolved.length === 0) {
    throw unsafeFeedUrl(url, `DNS resolution returned no addresses for ${hostname}`);
  }
  for (const entry of resolved) {
    await assertAddressAllowed(entry.address, url);
  }
}

interface FeedHttpResponse {
  status: number;
  body: string | null;
}

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

async function fetchFeedOnce(url: string): Promise<FeedHttpResponse> {
  let currentUrl = url;
  const controller = new AbortController();

  for (let hop = 0; hop <= FEED_MAX_REDIRECT_HOPS; hop++) {
    const timeout = setTimeout(() => controller.abort(), FEED_TIMEOUT_MS);

    try {
      const response = await fetch(currentUrl, {
        headers: {
          "User-Agent": FEED_USER_AGENT,
          Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
        },
        redirect: "manual",
        signal: controller.signal,
      });

      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get("location");
        if (!location) {
          return { status: response.status, body: null };
        }
        if (hop === FEED_MAX_REDIRECT_HOPS) {
          throw unsafeFeedUrl(url, `exceeded ${FEED_MAX_REDIRECT_HOPS} redirect hops`);
        }
        currentUrl = await assertRedirectLocation(currentUrl, location);
        continue;
      }

      const body = response.ok ? await response.text() : null;
      return { status: response.status, body };
    } catch (error) {
      if (error instanceof AppError) {
        throw error;
      }
      if (error instanceof Error && error.name === "AbortError") {
        throw new Error(`Feed fetch timed out after ${FEED_TIMEOUT_MS}ms: ${url}`);
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  throw unsafeFeedUrl(url, `exceeded ${FEED_MAX_REDIRECT_HOPS} redirect hops`);
}

export async function fetchFeedXml(url: string): Promise<string> {
  await assertSafeFeedUrl(url);

  const maxAttempts = FEED_RETRY_DELAYS_MS.length + 1;
  let retryDelay = 0;
  let lastError: unknown = new Error(`Failed to fetch feed: ${url}`);

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (retryDelay > 0) {
      await sleep(retryDelay);
    }

    try {
      const { status, body } = await fetchFeedOnce(url);

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
