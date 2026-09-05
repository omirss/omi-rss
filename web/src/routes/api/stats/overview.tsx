import { eq, and, sql, desc, gte, isNotNull } from "drizzle-orm";
import { userArticleStates, articles, feeds, folders } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { computeReadingStreaks } from "../../../services/analytics.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

// Ported from Express routes/stats.routes.ts GET /overview.
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
      .where(eq(feeds.userId, auth.id));

    const [folderCount] = await db
      .select({
        totalFolders: sql<number>`COUNT(*)`,
      })
      .from(folders)
      .where(eq(folders.userId, auth.id));

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

    const readDates = await db
      .select({
        date: sql<string>`DATE(${userArticleStates.readAt})`,
      })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, auth.id),
          eq(userArticleStates.isRead, true),
          isNotNull(userArticleStates.readAt),
        ),
      )
      .groupBy(sql`DATE(${userArticleStates.readAt})`)
      .orderBy(desc(sql`DATE(${userArticleStates.readAt})`));

    const dates = readDates.map((r: { date: string }) => new Date(r.date));
    const { currentStreak, longestStreak } = computeReadingStreaks(dates);

    return jsonResponse({
      totals: {
        totalArticles: Number(totals?.totalArticles || 0),
        readArticles: Number(totals?.readArticles || 0),
        starredArticles: Number(totals?.starredArticles || 0),
        totalFeeds: Number(totals?.totalFeeds || 0),
        totalFolders: Number(folderCount?.totalFolders || 0),
        readPercentage: Number(totals?.totalArticles || 0) > 0
          ? Math.round((Number(totals?.readArticles || 0) / Number(totals?.totalArticles || 0)) * 100)
          : 0,
      },
      velocity: {
        averagePerDay: Math.round(Number(velocity?.averagePerDay || 0)),
      },
      topFeeds: topFeeds.map(f => ({
        ...f,
        readCount: Number(f.readCount),
      })),
      readingStreak: {
        currentStreak,
        longestStreak,
        lastReadDate: dates.length > 0 ? dates[0].toISOString() : null,
      },
    });
  });
}
