import { eq, and, sql, desc, gte, isNotNull } from "drizzle-orm";
import { readingStats, userArticleStates, articles, feeds, folders } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

// Ported from server/src/routes/stats.routes.ts GET /overview.
export async function loader({ context }: { context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const db = await getDb();

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
          eq(userArticleStates.userId, auth.id),
        ),
      )
      .leftJoin(folders, eq(folders.userId, auth.id))
      .where(eq(feeds.userId, auth.id));

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
          eq(userArticleStates.userId, auth.id),
          eq(userArticleStates.isRead, true),
          gte(userArticleStates.readAt, thirtyDaysAgo),
        ),
      );

    const topFeeds = await db
      .select({
        feedId: feeds.id,
        feedTitle: feeds.title,
        feedFavicon: feeds.favicon,
        readCount: sql<number>`
          COUNT(DISTINCT ${userArticleStates.articleId})
        `.as("readCount"),
      })
      .from(userArticleStates)
      .innerJoin(articles, eq(userArticleStates.articleId, articles.id))
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .where(
        and(
          eq(userArticleStates.userId, auth.id),
          eq(userArticleStates.isRead, true),
        ),
      )
      .groupBy(feeds.id)
      .orderBy(desc(sql`COUNT(DISTINCT ${userArticleStates.articleId})`))
      .limit(5);

    const readingStreak = await calculateReadingStreak(db, auth.id);

    return jsonResponse({
      totals: {
        ...totals,
        readPercentage: totals.totalArticles > 0
          ? Math.round((Number(totals.readArticles) / Number(totals.totalArticles)) * 100)
          : 0,
      },
      velocity: {
        averagePerDay: Math.round(Number(velocity?.averagePerDay || 0)),
      },
      topFeeds,
      readingStreak,
    });
  });
}

// Ported from the stats.routes.ts helper of the same name.
async function calculateReadingStreak(db: Awaited<ReturnType<typeof getDb>>, userId: string): Promise<{
  currentStreak: number;
  longestStreak: number;
  lastReadDate: string | null;
}> {
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

  const lastRead = dates[0];
  const daysDiff = Math.floor((today.getTime() - lastRead.getTime()) / (1000 * 60 * 60 * 24));

  if (daysDiff <= 1) {
    currentStreak = 1;
  }

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
