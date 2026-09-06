import Redis from "ioredis";
import { RateLimiterRedis, RateLimiterRes } from "rate-limiter-flexible";
import { AppError } from "../api/errors.js";

// greader-specific per-user budget: sync clients burst (NetNewsWire/FeedMe
// easily exceed the 100/15min web-user budget during initial sync), so the
// greader auth wrapper consumes this dedicated bucket instead of
// consumeUserRateLimit. Same redis limiter pattern as rate-limit.ts; skips
// with a warning when Redis is down (the fail-closed mandate covers the
// auth limiter only, which ClientLogin shares with web login).

const POINTS = 600;
const WINDOW_SECONDS = 900;

let greaderLimiter: RateLimiterRedis | null = null;
let limiterRedisClient: Redis | null = null;

function getGreaderLimiter(): RateLimiterRedis {
  if (!greaderLimiter) {
    limiterRedisClient = new Redis(process.env.REDIS_URL || "redis://localhost:6380", {
      maxRetriesPerRequest: 1,
      enableOfflineQueue: false,
    });
    limiterRedisClient.on("error", (err) => console.warn("greader rate limiter Redis error:", err.message));
    greaderLimiter = new RateLimiterRedis({
      storeClient: limiterRedisClient,
      keyPrefix: "omiweb_greader_limit",
      points: POINTS,
      duration: WINDOW_SECONDS,
      blockDuration: WINDOW_SECONDS,
    });
  }
  return greaderLimiter;
}

export async function consumeGreaderRateLimit(userId: string): Promise<void> {
  try {
    await getGreaderLimiter().consume(userId);
  } catch (error) {
    if (error instanceof RateLimiterRes) {
      throw new AppError("Too many requests, please try again later", 429);
    }
    console.warn("greader rate limiter unavailable, skipping rate limiting");
  }
}
