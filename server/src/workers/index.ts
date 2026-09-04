import Queue from 'bull';
import { logger } from '../utils/logger';
import { resolveRedisUrl } from '../utils/redisUrl';
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
    const redisUrl = resolveRedisUrl();

    // Initialize queues
    feedUpdateQueue = new Queue('feed-updates', redisUrl);
    notificationQueue = new Queue('notifications', redisUrl);
    analyticsQueue = new Queue('analytics', redisUrl);
    cleanupQueue = new Queue('cleanup', redisUrl);

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
    },
  );

  // Cleanup old data - daily at 3 AM
  await cleanupQueue.add(
    'cleanup-old-data',
    {},
    {
      repeat: {
        cron: '0 3 * * *',
      },
    },
  );

  // Analytics aggregation - every hour
  await analyticsQueue.add(
    'aggregate-stats',
    {},
    {
      repeat: {
        cron: '0 * * * *',
      },
    },
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
    }),
  );

  logger.info('Workers shut down gracefully');
}