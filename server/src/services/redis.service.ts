import Redis from 'ioredis';
import { logger } from '../utils/logger';
import { resolveRedisUrl } from '../utils/redisUrl';

let redisClient: Redis;

export async function initializeRedis(): Promise<Redis> {
  try {
    redisClient = new Redis(resolveRedisUrl());

    // Test connection
    await redisClient.ping();
    logger.info('Redis connection established');

    // Handle errors
    redisClient.on('error', (err) => logger.error('Redis Client Error:', err));

    return redisClient;
  } catch (error) {
    logger.error('Failed to initialize Redis:', error);
    throw error;
  }
}

export function getRedisClient() {
  if (!redisClient) {
    throw new Error('Redis not initialized');
  }
  return redisClient;
}

export function getRedis() {
  return getRedisClient();
}

export async function closeRedis() {
  if (redisClient) {
    await redisClient.quit();
  }
  logger.info('Redis connection closed');
}
