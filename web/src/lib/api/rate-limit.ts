import type { MiddlewareFn } from "@neutron-build/core";
import { createHash } from "node:crypto";
import Redis from "ioredis";
import { RateLimiterRedis, RateLimiterRes } from "rate-limiter-flexible";
import { ipInCidr, ipVersion, normalizeIp } from "./ip.js";
import { AppError } from "./errors.js";

// Ported from Express middleware/rateLimiter.ts (v0.2.1): same points,
// windows and block durations. Key prefixes get an omiweb_ prefix so the
// Neutron app enforces its own budget on the shared dev Redis instead of
// burning the Express server's limiter state (and vice versa) while both
// dev servers run side by side.
//
// v0.3.1 security audit: the old clientKey trusted x-forwarded-for
// unconditionally (spoofable — rotating the header rotated the bucket) and
// fell back to a single "unknown" bucket for all direct-exposure clients.
// Keying is now governed by TRUSTED_PROXY:
//   - Not trusted (default): forwarding headers are IGNORED entirely. The
//     Neutron runtime hands route middleware a plain web Request and an empty
//     context — no socket peer address — so per-IP keying is impossible.
//     Authenticated routes are limited per userId inside requireAuth (after
//     token verification); anonymous auth routes fall back to per-identifier
//     plus per-process buckets (see consumeAnonAuthRateLimit).
//   - Trusted ("true" or a CIDR list): the client IP is read from
//     X-Forwarded-For rightmost-untrusted-hop — with a CIDR list, entries
//     inside trusted CIDRs are skipped from the right; with a bare bool the
//     last entry (appended by our own proxy) is used.

let apiLimiter: RateLimiterRedis | null = null;
let authLimiter: RateLimiterRedis | null = null;
let anonFallbackLimiter: RateLimiterRedis | null = null;
let userLimiter: RateLimiterRedis | null = null;
let limiterRedisClient: Redis | null = null;

function getLimiterRedisClient(): Redis {
  if (!limiterRedisClient) {
    limiterRedisClient = new Redis(process.env.REDIS_URL || "redis://localhost:6380", {
      maxRetriesPerRequest: 1,
      enableOfflineQueue: false,
    });
    limiterRedisClient.on("error", (err) => console.warn("Rate limiter Redis error:", err.message));
  }
  return limiterRedisClient;
}

function getApiLimiter(): RateLimiterRedis {
  if (!apiLimiter) {
    apiLimiter = new RateLimiterRedis({
      storeClient: getLimiterRedisClient(),
      keyPrefix: "omiweb_rate_limit",
      points: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || "100"),
      duration: parseInt(process.env.RATE_LIMIT_WINDOW_MS || "900000") / 1000,
      blockDuration: 900,
    });
  }
  return apiLimiter;
}

function getAuthLimiter(): RateLimiterRedis {
  if (!authLimiter) {
    authLimiter = new RateLimiterRedis({
      storeClient: getLimiterRedisClient(),
      keyPrefix: "omiweb_auth_limit",
      points: 5,
      duration: 900,
      blockDuration: 900,
    });
  }
  return authLimiter;
}

// Shared cap for ALL anonymous auth attempts when no client IP is
// trustworthy — tighter than the global limiter so a header-rotating
// attacker cannot hammer login/register/reset, while a small self-hosted
// instance still functions.
function getAnonFallbackLimiter(): RateLimiterRedis {
  if (!anonFallbackLimiter) {
    anonFallbackLimiter = new RateLimiterRedis({
      storeClient: getLimiterRedisClient(),
      keyPrefix: "omiweb_auth_anon",
      points: parseInt(process.env.AUTH_ANON_FALLBACK_MAX || "20"),
      duration: 900,
      blockDuration: 900,
    });
  }
  return anonFallbackLimiter;
}

// Per-user bucket consumed by requireAuth after token verification — the
// per-client granularity replacement for direct exposure (no proxy).
// 300/15min (v0.6.0 R7): heavy reading sessions were exhausting the old
// 100 budget; greader sync has its own 600 bucket, so this one mainly
// guards UI+API abuse and 300 is still honest protection.
function getUserLimiter(): RateLimiterRedis {
  if (!userLimiter) {
    userLimiter = new RateLimiterRedis({
      storeClient: getLimiterRedisClient(),
      keyPrefix: "omiweb_user_limit",
      points: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || "300"),
      duration: parseInt(process.env.RATE_LIMIT_WINDOW_MS || "900000") / 1000,
      blockDuration: 900,
    });
  }
  return userLimiter;
}

export interface TrustedProxyConfig {
  trusted: boolean;
  cidrs: string[];
}

// TRUSTED_PROXY accepts "true"/"false" (or 1/0/yes/no) or a comma-separated
// CIDR/IP list ("10.0.0.0/8,192.168.1.5"). Default: not trusted.
export function parseTrustedProxy(raw: string | undefined): TrustedProxyConfig {
  const value = (raw ?? "").trim().toLowerCase();
  if (!value || value === "false" || value === "0" || value === "no" || value === "off") {
    return { trusted: false, cidrs: [] };
  }
  if (value === "true" || value === "1" || value === "yes" || value === "on") {
    return { trusted: true, cidrs: [] };
  }
  const cidrs = value
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
  return { trusted: cidrs.length > 0, cidrs };
}

let cachedTrustedProxy: TrustedProxyConfig | null = null;

function trustedProxyConfig(): TrustedProxyConfig {
  if (!cachedTrustedProxy) {
    cachedTrustedProxy = parseTrustedProxy(process.env.TRUSTED_PROXY);
  }
  return cachedTrustedProxy;
}

// Resolves the rate-limit client key for a request, or null when no
// trustworthy per-client address exists (direct exposure, TRUSTED_PROXY
// unset). Callers must NOT fall back to spoofable headers themselves.
export function resolveRateLimitClientKey(request: Request): string | null {
  const config = trustedProxyConfig();
  if (!config.trusted) {
    return null;
  }
  const forwarded = request.headers.get("x-forwarded-for");
  if (!forwarded) {
    const realIp = request.headers.get("x-real-ip");
    return realIp ? realIp.trim() : null;
  }
  const hops = forwarded
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
  if (hops.length === 0) {
    return null;
  }
  if (config.cidrs.length === 0) {
    // Bare trust: the rightmost entry was appended by our own proxy.
    return hops[hops.length - 1];
  }
  // CIDR trust: walk right-to-left past trusted proxies; the first
  // non-trusted entry is the client as far as we can know it.
  for (let i = hops.length - 1; i >= 0; i--) {
    const hop = normalizeIp(hops[i]);
    const trustedHop = ipVersion(hop) !== null && config.cidrs.some((cidr) => ipInCidr(hop, cidr));
    if (!trustedHop) {
      return hops[i];
    }
  }
  return hops[0];
}

let warnedNoClientKey = false;

function rateLimitResponse(msBeforeNext: number): Response {
  return new Response(
    JSON.stringify({
      error: "Too many requests",
      retryAfter: Math.round(msBeforeNext / 1000) || 900,
      timestamp: new Date().toISOString(),
    }),
    {
      status: 429,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    }
  );
}

export const apiRateLimit: MiddlewareFn = async (request, _context, next) => {
  const key = resolveRateLimitClientKey(request);
  if (key === null) {
    if (!warnedNoClientKey) {
      warnedNoClientKey = true;
      console.warn(
        "Rate limiter has no trustworthy client address (TRUSTED_PROXY unset); " +
          "skipping the global /api limiter. Auth routes use per-user and " +
          "per-identifier fallbacks."
      );
    }
    return next();
  }
  try {
    await getApiLimiter().consume(key);
    return next();
  } catch (error) {
    if (error instanceof RateLimiterRes) {
      console.warn(`Rate limit exceeded for ${key}`);
      return rateLimitResponse(error.msBeforeNext);
    }
    console.warn("Rate limiter unavailable, skipping rate limiting");
    return next();
  }
};

function isProduction(): boolean {
  return process.env.NODE_ENV === "production";
}

// The auth limiter (5/15min) FAILS CLOSED in production: if Redis is down we
// cannot know the budget is unspent, so the request is rejected instead of
// letting unthrottled password guessing through.
export async function consumeAuthRateLimit(key: string): Promise<void> {
  try {
    await getAuthLimiter().consume(key);
  } catch (error) {
    if (error instanceof RateLimiterRes) {
      throw new AppError("Too many requests, please try again later", 429);
    }
    if (isProduction()) {
      throw new AppError("Authentication is temporarily unavailable, please try again later", 503);
    }
    console.warn("Auth rate limiter unavailable, skipping rate limiting");
  }
}

// Fallback for anonymous auth routes (login/register/forgot-password) when
// no trustworthy client IP exists. Two buckets, both fail-closed in
// production: per-identifier (5/15min — caps brute force on one account)
// and a shared process-wide cap (AUTH_ANON_FALLBACK_MAX, default 20/15min —
// caps identifier rotation).
export async function consumeAnonAuthRateLimit(identifier: string): Promise<void> {
  const digest = createHash("sha256").update(identifier.trim().toLowerCase()).digest("hex").slice(0, 32);
  await consumeAuthRateLimit(`ident:${digest}`);
  try {
    await getAnonFallbackLimiter().consume("shared");
  } catch (error) {
    if (error instanceof RateLimiterRes) {
      throw new AppError("Too many requests, please try again later", 429);
    }
    if (isProduction()) {
      throw new AppError("Authentication is temporarily unavailable, please try again later", 503);
    }
    console.warn("Auth rate limiter unavailable, skipping rate limiting");
  }
}

// Per-user bucket for authenticated routes; skips with a warning when Redis
// is down (the fail-closed mandate covers the auth limiter only).
export async function consumeUserRateLimit(userId: string): Promise<void> {
  try {
    await getUserLimiter().consume(userId);
  } catch (error) {
    if (error instanceof RateLimiterRes) {
      throw new AppError("Too many requests, please try again later", 429);
    }
    console.warn("User rate limiter unavailable, skipping rate limiting");
  }
}

// Returns the trustworthy client key for an auth route, or null when the
// caller must use the anonymous fallback (consumeAnonAuthRateLimit).
export function authRateLimitKey(request: Request): string | null {
  return resolveRateLimitClientKey(request);
}
