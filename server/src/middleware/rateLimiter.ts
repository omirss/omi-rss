import type { Request, Response, NextFunction } from 'express';
import { RateLimiterRedis, RateLimiterRes } from 'rate-limiter-flexible';
import Redis from 'ioredis';
import { logger } from '../utils/logger';

let apiLimiter: RateLimiterRedis;

export function initializeRateLimiter(redisClient: Redis) {
  apiLimiter = new RateLimiterRedis({
    storeClient: redisClient,
    keyPrefix: 'rate_limit',
    points: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100'),
    duration: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000') / 1000,
    blockDuration: 900,
  });
}

export async function rateLimitMiddleware(req: Request, res: Response, next: NextFunction) {
  if (!apiLimiter) {
    logger.warn('Rate limiter not initialized, skipping rate limiting');
    return next();
  }

  try {
    const key = req.user?.id || req.ip || 'anonymous';
    await apiLimiter.consume(key);
    return next();
  } catch (error) {
    if (error instanceof RateLimiterRes) {
      logger.warn(`Rate limit exceeded for ${req.user?.id || req.ip}`);
      return res.status(429).json({
        error: 'Too many requests',
        retryAfter: Math.round(error.msBeforeNext / 1000) || 900,
        timestamp: new Date().toISOString(),
      });
    }
    return next(error);
  }
}

export const authRateLimiter = new RateLimiterRedis({
  storeClient: new Redis(process.env.REDIS_URL!),
  keyPrefix: 'auth_limit',
  points: 5,
  duration: 900,
  blockDuration: 900,
});

export const apiRateLimiter = new RateLimiterRedis({
  storeClient: new Redis(process.env.REDIS_URL!),
  keyPrefix: 'api_limit',
  points: 1000,
  duration: 3600,
});

export const uploadRateLimiter = new RateLimiterRedis({
  storeClient: new Redis(process.env.REDIS_URL!),
  keyPrefix: 'upload_limit',
  points: 10,
  duration: 3600,
});

export const rateLimiter = rateLimitMiddleware;
