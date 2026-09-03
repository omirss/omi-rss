import { Request, Response, NextFunction } from 'express';
import { RateLimiterRedis } from 'rate-limiter-flexible';
import Redis from 'ioredis';
import { logger } from '../utils/logger';

let rateLimiter: RateLimiterRedis;

// Initialize rate limiter with Redis
export function initializeRateLimiter(redisClient: Redis) {
  rateLimiter = new RateLimiterRedis({
    storeClient: redisClient,
    keyPrefix: 'rate_limit',
    points: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100'), // Number of requests
    duration: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000') / 1000, // Per 15 minutes
    blockDuration: 900, // Block for 15 minutes
  });
}

export async function rateLimitMiddleware(req: Request, res: Response, next: NextFunction) {
  if (!rateLimiter) {
    logger.warn('Rate limiter not initialized, skipping rate limiting');
    return next();
  }

  try {
    const key = req.user?.id || req.ip;
    await rateLimiter.consume(key);
    next();
  } catch (error) {
    if (error instanceof Error) {
      logger.warn(`Rate limit exceeded for ${req.user?.id || req.ip}`);
      res.status(429).json({
        error: 'Too many requests',
        retryAfter: Math.round(error.msBeforeNext / 1000) || 900,
        timestamp: new Date().toISOString(),
      });
    } else {
      next();
    }
  }
}

// Different rate limiters for different endpoints
export const authRateLimiter = new RateLimiterRedis({
  storeClient: new Redis(process.env.REDIS_URL!),
  keyPrefix: 'auth_limit',
  points: 5, // 5 attempts
  duration: 900, // Per 15 minutes
  blockDuration: 900, // Block for 15 minutes
});

export const apiRateLimiter = new RateLimiterRedis({
  storeClient: new Redis(process.env.REDIS_URL!),
  keyPrefix: 'api_limit',
  points: 1000, // 1000 requests
  duration: 3600, // Per hour
});

export const uploadRateLimiter = new RateLimiterRedis({
  storeClient: new Redis(process.env.REDIS_URL!),
  keyPrefix: 'upload_limit',
  points: 10, // 10 uploads
  duration: 3600, // Per hour
});

// Export for use in routes
export const rateLimiter = rateLimitMiddleware;