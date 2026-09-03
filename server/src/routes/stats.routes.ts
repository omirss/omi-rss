import { Router } from 'express';
import { z } from 'zod';
import { getDb } from '../database';
import { 
  readingStats, 
  userArticleStates, 
  articles, 
  feeds, 
  folders, 
} from '../database/schema';
import { eq, and, sql, between, desc, gte, isNotNull } from 'drizzle-orm';
import { AppError } from '../middleware/errorHandler';

const router = Router();

// Validation schemas
const dateRangeSchema = z.object({
  startDate: z.string().datetime().optional(),
  endDate: z.string().datetime().optional(),
  period: z.enum(['day', 'week', 'month', 'year']).default('month'),
});

// Get reading statistics overview
router.get('/overview', async (req, res, next) => {
  try {
    const db = getDb();

    // Get total statistics
    const [totals] = await db
      .select({
        totalArticles: sql<number>`
          COUNT(DISTINCT ${articles.id})
        `,
        readArticles: sql<number>`
          COUNT(DISTINCT ${userArticleStates.articleId}) 
          FILTER (WHERE ${userArticleStates.isRead} = true)
        `,
        starredArticles: sql<number>`
          COUNT(DISTINCT ${userArticleStates.articleId}) 
          FILTER (WHERE ${userArticleStates.isStarred} = true)
        `,
        totalFeeds: sql<number>`
          COUNT(DISTINCT ${feeds.id})
        `,
        totalFolders: sql<number>`
          COUNT(DISTINCT ${folders.id})
        `,
      })
      .from(feeds)
      .leftJoin(articles, eq(articles.feedId, feeds.id))
      .leftJoin(
        userArticleStates,
        and(
          eq(userArticleStates.articleId, articles.id),
          eq(userArticleStates.userId, req.user!.id),
        ),
      )
      .leftJoin(folders, eq(folders.userId, req.user!.id))
      .where(eq(feeds.userId, req.user!.id));

    // Get reading velocity (articles read per day for last 30 days)
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const [velocity] = await db
      .select({
        averagePerDay: sql<number>`
          COUNT(*)::float / 30
        `,
      })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, req.user!.id),
          eq(userArticleStates.isRead, true),
          gte(userArticleStates.readAt, thirtyDaysAgo),
        ),
      );

    // Get most read feeds
    const topFeeds = await db
      .select({
        feedId: feeds.id,
        feedTitle: feeds.title,
        feedFavicon: feeds.favicon,
        readCount: sql<number>`
          COUNT(DISTINCT ${userArticleStates.articleId})
        `.as('readCount'),
      })
      .from(userArticleStates)
      .innerJoin(articles, eq(userArticleStates.articleId, articles.id))
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .where(
        and(
          eq(userArticleStates.userId, req.user!.id),
          eq(userArticleStates.isRead, true),
        ),
      )
      .groupBy(feeds.id)
      .orderBy(desc(sql`COUNT(DISTINCT ${userArticleStates.articleId})`))
      .limit(5);

    // Get reading streak
    const readingStreak = await calculateReadingStreak(db, req.user!.id);

    res.json({
      totals: {
        ...totals,
        readPercentage: totals.totalArticles > 0 
          ? Math.round((totals.readArticles / totals.totalArticles) * 100)
          : 0,
      },
      velocity: {
        averagePerDay: Math.round(velocity?.averagePerDay || 0),
      },
      topFeeds,
      readingStreak,
    });
  } catch (error) {
    next(error);
  }
});

// Get reading history
router.get('/history', async (req, res, next) => {
  try {
    const { startDate, endDate, period } = dateRangeSchema.parse(req.query);
    const db = getDb();

    const start = startDate ? new Date(startDate) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const end = endDate ? new Date(endDate) : new Date();

    // Get reading data grouped by period
    const dateFormat = {
      day: '%Y-%m-%d',
      week: '%Y-%W',
      month: '%Y-%m',
      year: '%Y',
    }[period];

    const readingData = await db
      .select({
        period: sql<string>`
          TO_CHAR(${userArticleStates.readAt}, '${dateFormat}')
        `,
        count: sql<number>`COUNT(*)`,
      })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, req.user!.id),
          eq(userArticleStates.isRead, true),
          between(userArticleStates.readAt, start, end),
        ),
      )
      .groupBy(sql`TO_CHAR(${userArticleStates.readAt}, '${dateFormat}')`)
      .orderBy(sql`TO_CHAR(${userArticleStates.readAt}, '${dateFormat}')`);

    res.json({
      period,
      startDate: start.toISOString(),
      endDate: end.toISOString(),
      data: readingData,
    });
  } catch (error) {
    next(error);
  }
});

// Get reading time statistics
router.get('/reading-time', async (req, res, next) => {
  try {
    const db = getDb();

    const [stats] = await db
      .select({
        totalReadingTime: sql<number>`COALESCE(SUM(${readingStats.readingTime}), 0)`,
        articlesRead: sql<number>`COALESCE(SUM(${readingStats.articlesRead}), 0)`,
        lastUpdated: sql<string>`MAX(${readingStats.updatedAt})`,
      })
      .from(readingStats)
      .where(eq(readingStats.userId, req.user!.id));

    const totalReadingTime = Number(stats?.totalReadingTime || 0);
    const articlesRead = Number(stats?.articlesRead || 0);

    // Calculate average reading time
    const averageReadingTime = articlesRead > 0
      ? Math.round(totalReadingTime / articlesRead)
      : 0;

    // Get reading time by hour of day
    const readingByHour = await db
      .select({
        hour: sql<number>`EXTRACT(HOUR FROM ${userArticleStates.readAt})`,
        count: sql<number>`COUNT(*)`,
      })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, req.user!.id),
          eq(userArticleStates.isRead, true),
          isNotNull(userArticleStates.readAt),
        ),
      )
      .groupBy(sql`EXTRACT(HOUR FROM ${userArticleStates.readAt})`)
      .orderBy(sql`EXTRACT(HOUR FROM ${userArticleStates.readAt})`);

    // Get reading time by day of week
    const readingByDayOfWeek = await db
      .select({
        dayOfWeek: sql<number>`EXTRACT(DOW FROM ${userArticleStates.readAt})`,
        count: sql<number>`COUNT(*)`,
      })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, req.user!.id),
          eq(userArticleStates.isRead, true),
          isNotNull(userArticleStates.readAt),
        ),
      )
      .groupBy(sql`EXTRACT(DOW FROM ${userArticleStates.readAt})`)
      .orderBy(sql`EXTRACT(DOW FROM ${userArticleStates.readAt})`);

    res.json({
      totalReadingTime,
      articlesRead,
      averageReadingTime,
      estimatedWordsPerMinute: 200,
      readingByHour,
      readingByDayOfWeek,
    });
  } catch (error) {
    next(error);
  }
});

// Update reading time
router.post('/reading-time', async (req, res, next) => {
  try {
    const { articleId, timeSpent } = z.object({
      articleId: z.string().uuid(),
      timeSpent: z.number().min(0).max(3600),
    }).parse(req.body);

    const db = getDb();

    // Verify article ownership
    const [article] = await db
      .select({ id: articles.id })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .where(
        and(
          eq(articles.id, articleId),
          eq(feeds.userId, req.user!.id),
        ),
      )
      .limit(1);

    if (!article) {
      throw new AppError('Article not found', 404);
    }

    const day = new Date();
    day.setHours(0, 0, 0, 0);

    // Update or create reading stats
    await db
      .insert(readingStats)
      .values({
        userId: req.user!.id,
        date: day,
        readingTime: timeSpent,
        articlesRead: 1,
      })
      .onConflictDoUpdate({
        target: [readingStats.userId, readingStats.date],
        set: {
          readingTime: sql`${readingStats.readingTime} + ${timeSpent}`,
          articlesRead: sql`${readingStats.articlesRead} + 1`,
          updatedAt: new Date(),
        },
      });

    res.json({ message: 'Reading time updated' });
  } catch (error) {
    next(error);
  }
});

// Helper function to calculate reading streak
async function calculateReadingStreak(db: any, userId: string): Promise<{
  currentStreak: number;
  longestStreak: number;
  lastReadDate: string | null;
}> {
  // Get all dates when user read articles
  const readDates = await db
    .select({
      date: sql<string>`DATE(${userArticleStates.readAt})`,
    })
    .from(userArticleStates)
    .where(
      and(
        eq(userArticleStates.userId, userId),
        eq(userArticleStates.isRead, true),
        isNotNull(userArticleStates.readAt),
      ),
    )
    .groupBy(sql`DATE(${userArticleStates.readAt})`)
    .orderBy(desc(sql`DATE(${userArticleStates.readAt})`));

  if (readDates.length === 0) {
    return {
      currentStreak: 0,
      longestStreak: 0,
      lastReadDate: null,
    };
  }

  const dates = readDates.map((r: { date: string }) => new Date(r.date));
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  let currentStreak = 0;
  let longestStreak = 0;
  let tempStreak = 1;

  // Check if user read today or yesterday
  const lastRead = dates[0];
  const daysDiff = Math.floor((today.getTime() - lastRead.getTime()) / (1000 * 60 * 60 * 24));

  if (daysDiff <= 1) {
    currentStreak = 1;
  }

  // Calculate streaks
  for (let i = 1; i < dates.length; i++) {
    const diff = Math.floor((dates[i - 1].getTime() - dates[i].getTime()) / (1000 * 60 * 60 * 24));
    
    if (diff === 1) {
      tempStreak++;
      if (daysDiff <= 1 && i === 1) {
        currentStreak = tempStreak;
      }
    } else {
      longestStreak = Math.max(longestStreak, tempStreak);
      tempStreak = 1;
    }
  }

  longestStreak = Math.max(longestStreak, tempStreak);

  return {
    currentStreak,
    longestStreak,
    lastReadDate: dates[0].toISOString(),
  };
}

export default router;