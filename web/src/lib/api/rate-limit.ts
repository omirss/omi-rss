import type { MiddlewareFn } from "@neutron-build/core";
import Redis from "ioredis";
import { RateLimiterRedis, RateLimiterRes } from "rate-limiter-flexible";
import { AppError } from "./errors.js";

// Ported from Express middleware/rateLimiter.ts (v0.2.1): same points,
// windows and block durations. Key prefixes get an omiweb_ prefix so the
// Neutron app enforces its own budget on the shared dev Redis instead of
// burning the Express server's limiter state (and vice versa) while both
// dev servers run side by side.

let apiLimiter: RateLimiterRedis | null = null;
let authLimiter: RateLimiterRedis | null = null;
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

// Express keyed the global limiter on req.user?.id || req.ip; the middleware
// ran before authentication so it was effectively req.ip. The web Request
// exposes no socket address, so x-forwarded-for is the closest equivalent.
function clientKey(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) {
    return forwarded.split(",")[0].trim();
  }
  return request.headers.get("x-real-ip") || "unknown";
}

export const apiRateLimit: MiddlewareFn = async (request, _context, next) => {
  try {
    await getApiLimiter().consume(clientKey(request));
    return next();
  } catch (error) {
    if (error instanceof RateLimiterRes) {
      console.warn(`Rate limit exceeded for ${clientKey(request)}`);
      return new Response(
        JSON.stringify({
          error: "Too many requests",
          retryAfter: Math.round(error.msBeforeNext / 1000) || 900,
          timestamp: new Date().toISOString(),
        }),
        {
          status: 429,
          headers: { "Content-Type": "application/json; charset=utf-8" },
        }
      );
    }
    console.warn("Rate limiter unavailable, skipping rate limiting");
    return next();
  }
};

export async function consumeAuthRateLimit(key: string): Promise<void> {
  try {
    await getAuthLimiter().consume(key);
  } catch (error) {
    if (error instanceof RateLimiterRes) {
      throw new AppError("Too many requests, please try again later", 429);
    }
    console.warn("Auth rate limiter unavailable, skipping rate limiting");
  }
}

export function authRateLimitKey(request: Request): string {
  return clientKey(request);
}
