import Redis from 'ioredis';
import { logger } from '../utils/logger';

let redisClient: Redis;
let redisSubscriber: Redis;
let redisPublisher: Redis;

export async function initializeRedis() {
  try {
    // Create Redis connections
    redisClient = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');
    redisSubscriber = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');
    redisPublisher = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');

    // Test connection
    await redisClient.ping();
    logger.info('Redis connection established');

    // Handle errors
    redisClient.on('error', (err) => logger.error('Redis Client Error:', err));
    redisSubscriber.on('error', (err) => logger.error('Redis Subscriber Error:', err));
    redisPublisher.on('error', (err) => logger.error('Redis Publisher Error:', err));

    return { redisClient, redisSubscriber, redisPublisher };
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

export function getRedisSubscriber() {
  if (!redisSubscriber) {
    throw new Error('Redis subscriber not initialized');
  }
  return redisSubscriber;
}

export function getRedisPublisher() {
  if (!redisPublisher) {
    throw new Error('Redis publisher not initialized');
  }
  return redisPublisher;
}

export async function closeRedis() {
  if (redisClient) {
    await redisClient.quit();
  }
  if (redisSubscriber) {
    await redisSubscriber.quit();
  }
  if (redisPublisher) {
    await redisPublisher.quit();
  }
  logger.info('Redis connections closed');
}

// Cache utilities
export async function getCached<T>(key: string): Promise<T | null> {
  const data = await redisClient.get(key);
  return data ? JSON.parse(data) : null;
}

export async function setCached<T>(key: string, value: T, ttl?: number): Promise<void> {
  const data = JSON.stringify(value);
  if (ttl) {
    await redisClient.set(key, data, 'EX', ttl);
  } else {
    await redisClient.set(key, data);
  }
}

export async function deleteCached(pattern: string): Promise<void> {
  const keys = await redisClient.keys(pattern);
  if (keys.length > 0) {
    await redisClient.del(...keys);
  }
}

// Pub/Sub utilities
export async function publish(channel: string, message: any): Promise<void> {
  await redisPublisher.publish(channel, JSON.stringify(message));
}

export async function subscribe(channel: string, callback: (message: any) => void): Promise<void> {
  await redisSubscriber.subscribe(channel);
  redisSubscriber.on('message', (ch, message) => {
    if (ch === channel) {
      callback(JSON.parse(message));
    }
  });
}