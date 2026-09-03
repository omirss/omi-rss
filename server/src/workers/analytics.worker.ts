import type Queue from 'bull';
import { getDb } from '../database';
import { articles, userArticleStates, readingStats } from '../database/schema';
import { and, eq, gte, sql } from 'drizzle-orm';
import { logger } from '../utils/logger';

export function analyticsWorker(queue: Queue.Queue) {
  void queue.process('aggregate-stats', async () => {
    const db = getDb();
    const day = new Date();
    day.setHours(0, 0, 0, 0);

    const rows = await db
      .select({
        userId: userArticleStates.userId,
        articleId: userArticleStates.articleId,
        readingTime: userArticleStates.readingTime,
        readAt: userArticleStates.readAt,
        words: sql<number>`
          ARRAY_LENGTH(REGEXP_SPLIT_TO_ARRAY(COALESCE(${articles.content}, ''), '\\s+'), 1)
        `,
        categories: articles.categories,
        feedId: articles.feedId,
      })
      .from(userArticleStates)
      .innerJoin(articles, eq(articles.id, userArticleStates.articleId))
      .where(
        and(
          eq(userArticleStates.isRead, true),
          gte(userArticleStates.readAt, day),
        ),
      );

    const byUser = new Map<
      string,
      {
        articlesRead: number;
        readingTime: number;
        wordsRead: number;
        feedsVisited: Set<string>;
        categories: Record<string, number>;
        hourlyDistribution: Record<string, number>;
      }
    >();

    for (const row of rows) {
      const entry = byUser.get(row.userId) || {
        articlesRead: 0,
        readingTime: 0,
        wordsRead: 0,
        feedsVisited: new Set<string>(),
        categories: {},
        hourlyDistribution: {},
      };

      entry.articlesRead++;
      entry.readingTime += row.readingTime || 0;
      entry.wordsRead += Number(row.words || 0);
      if (row.feedId) entry.feedsVisited.add(row.feedId);

      if (Array.isArray(row.categories)) {
        for (const category of row.categories as string[]) {
          entry.categories[category] = (entry.categories[category] || 0) + 1;
        }
      }

      if (row.readAt) {
        const hour = new Date(row.readAt).getHours().toString();
        entry.hourlyDistribution[hour] = (entry.hourlyDistribution[hour] || 0) + 1;
      }

      byUser.set(row.userId, entry);
    }

    const now = new Date();
    let upserted = 0;

    for (const [userId, entry] of byUser) {
      await db
        .insert(readingStats)
        .values({
          userId,
          date: day,
          articlesRead: entry.articlesRead,
          readingTime: entry.readingTime,
          wordsRead: entry.wordsRead,
          feedsVisited: Array.from(entry.feedsVisited),
          categories: entry.categories,
          hourlyDistribution: entry.hourlyDistribution,
        })
        .onConflictDoUpdate({
          target: [readingStats.userId, readingStats.date],
          set: {
            articlesRead: entry.articlesRead,
            readingTime: entry.readingTime,
            wordsRead: entry.wordsRead,
            feedsVisited: Array.from(entry.feedsVisited),
            categories: entry.categories,
            hourlyDistribution: entry.hourlyDistribution,
            updatedAt: now,
          },
        });
      upserted++;
    }

    logger.info(`Analytics aggregation complete: ${upserted} users updated`);

    return { users: upserted };
  });

  queue.on('failed', (job, err) => {
    logger.error(`Analytics job ${job?.id} failed:`, err);
  });

  logger.info('Analytics worker initialized');
}
