import Queue from 'bull';
import { getRedisClient } from '../services/redis.service';
import { logger } from '../utils/logger';
import { feedUpdateWorker } from './feedUpdate.worker';
import { notificationWorker } from './notification.worker';
import { analyticsWorker } from './analytics.worker';
import { cleanupWorker } from './cleanup.worker';

// Queue instances
export let feedUpdateQueue: Queue.Queue;
export let notificationQueue: Queue.Queue;
export let analyticsQueue: Queue.Queue;
export let cleanupQueue: Queue.Queue;

export async function initializeWorkers() {
  try {
    const redisClient = getRedisClient();
    const redisConfig = {
      redis: {
        host: process.env.REDIS_HOST || 'localhost',
        port: parseInt(process.env.REDIS_PORT || '6379'),
        password: process.env.REDIS_PASSWORD,
      },
    };

    // Initialize queues
    feedUpdateQueue = new Queue('feed-updates', redisConfig);
    notificationQueue = new Queue('notifications', redisConfig);
    analyticsQueue = new Queue('analytics', redisConfig);
    cleanupQueue = new Queue('cleanup', redisConfig);

    // Register workers
    feedUpdateWorker(feedUpdateQueue);
    notificationWorker(notificationQueue);
    analyticsWorker(analyticsQueue);
    cleanupWorker(cleanupQueue);

    // Schedule recurring jobs
    await scheduleRecurringJobs();

    logger.info('Background workers initialized successfully');
  } catch (error) {
    logger.error('Failed to initialize workers:', error);
    throw error;
  }
}

async function scheduleRecurringJobs() {
  // Feed updates - every 5 minutes
  await feedUpdateQueue.add(
    'update-all-feeds',
    {},
    {
      repeat: {
        cron: '*/5 * * * *',
      },
    }
  );

  // Cleanup old data - daily at 3 AM
  await cleanupQueue.add(
    'cleanup-old-data',
    {},
    {
      repeat: {
        cron: '0 3 * * *',
      },
    }
  );

  // Analytics aggregation - every hour
  await analyticsQueue.add(
    'aggregate-stats',
    {},
    {
      repeat: {
        cron: '0 * * * *',
      },
    }
  );

  logger.info('Recurring jobs scheduled');
}

// Graceful shutdown
export async function closeWorkers() {
  const queues = [
    feedUpdateQueue,
    notificationQueue,
    analyticsQueue,
    cleanupQueue,
  ];

  await Promise.all(
    queues.map(async (queue) => {
      if (queue) {
        await queue.close();
      }
    })
  );

  logger.info('Workers shut down gracefully');
}