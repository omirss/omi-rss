import type Queue from 'bull';
import { getDb } from '../database';
import { articles, feeds } from '../database/schema';
import { eq, inArray, sql } from 'drizzle-orm';
import { logger } from '../utils/logger';

export function cleanupWorker(queue: Queue.Queue) {
  void queue.process('cleanup-old-data', async () => {
    const retentionDays = parseInt(process.env.ARTICLE_RETENTION_DAYS || '90', 10);
    const cutoff = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000);
    const db = getDb();

    const inactiveFeeds = await db
      .select({ id: feeds.id })
      .from(feeds)
      .where(eq(feeds.isActive, false));

    let inactiveDeleted = 0;
    if (inactiveFeeds.length > 0) {
      const inactiveIds = inactiveFeeds.map((f) => f.id);
      const removed = await db
        .delete(articles)
        .where(inArray(articles.feedId, inactiveIds))
        .returning({ id: articles.id });
      inactiveDeleted = removed.length;
    }

    const expired = await db
      .delete(articles)
      .where(
        sql`COALESCE(${articles.publishedAt}, ${articles.createdAt}) < ${cutoff}`,
      )
      .returning({ id: articles.id });

    logger.info(
      `Cleanup complete: ${expired.length} articles past ${retentionDays}-day retention, ` +
        `${inactiveDeleted} from inactive feeds`,
    );

    return { expired: expired.length, inactive: inactiveDeleted };
  });

  queue.on('failed', (job, err) => {
    logger.error(`Cleanup job ${job?.id} failed:`, err);
  });

  logger.info('Cleanup worker initialized');
}
