import type { Request, Response, NextFunction } from 'express';
import { RateLimiterRedis, RateLimiterRes } from 'rate-limiter-flexible';
import Redis from 'ioredis';
import { AppError } from './errorHandler';
import { logger } from '../utils/logger';
import { resolveRedisUrl } from '../utils/redisUrl';

let apiLimiter: RateLimiterRedis | null = null;

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

let limiterRedisClient: Redis | null = null;

function getLimiterRedisClient(): Redis {
  if (!limiterRedisClient) {
    limiterRedisClient = new Redis(resolveRedisUrl(), {
      maxRetriesPerRequest: 1,
      enableOfflineQueue: false,
    });
    limiterRedisClient.on('error', (err) => logger.warn('Rate limiter Redis error:', err.message));
  }
  return limiterRedisClient;
}

let authLimiter: RateLimiterRedis | null = null;

export function getAuthRateLimiter(): RateLimiterRedis {
  if (!authLimiter) {
    authLimiter = new RateLimiterRedis({
      storeClient: getLimiterRedisClient(),
      keyPrefix: 'auth_limit',
      points: 5,
      duration: 900,
      blockDuration: 900,
    });
  }
  return authLimiter;
}

export async function consumeAuthRateLimit(key: string): Promise<void> {
  try {
    await getAuthRateLimiter().consume(key);
  } catch (error) {
    if (error instanceof RateLimiterRes) {
      throw new AppError('Too many requests, please try again later', 429);
    }
    logger.warn('Auth rate limiter unavailable, skipping rate limiting');
  }
}

export const rateLimiter = rateLimitMiddleware;
