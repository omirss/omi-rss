import { z } from "zod";
import { eq, and, sql, isNotNull } from "drizzle-orm";
import { readingStats, userArticleStates, articles, feeds } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse, errorResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const readingTimeSchema = z.object({
  articleId: z.string().uuid(),
  timeSpent: z.number().min(0).max(3600),
});

// Ported from Express routes/stats.routes.ts GET /reading-time.
export async function loader({ context }: { context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const db = await getDb();

    const [stats] = await db
      .select({
        totalReadingTime: sql<number>`COALESCE(SUM(${readingStats.readingTime}), 0)`,
        articlesRead: sql<number>`COALESCE(SUM(${readingStats.articlesRead}), 0)`,
        lastUpdated: sql<string>`MAX(${readingStats.updatedAt})`,
      })
      .from(readingStats)
      .where(eq(readingStats.userId, auth.id));

    const totalReadingTime = Number(stats?.totalReadingTime || 0);
    const articlesRead = Number(stats?.articlesRead || 0);

    const averageReadingTime = articlesRead > 0
      ? Math.round(totalReadingTime / articlesRead)
      : 0;

    const readingByHour = await db
      .select({
        hour: sql<number>`EXTRACT(HOUR FROM ${userArticleStates.readAt})`,
        count: sql<number>`COUNT(*)`,
      })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, auth.id),
          eq(userArticleStates.isRead, true),
          isNotNull(userArticleStates.readAt),
        ),
      )
      .groupBy(sql`EXTRACT(HOUR FROM ${userArticleStates.readAt})`)
      .orderBy(sql`EXTRACT(HOUR FROM ${userArticleStates.readAt})`);

    const readingByDayOfWeek = await db
      .select({
        dayOfWeek: sql<number>`EXTRACT(DOW FROM ${userArticleStates.readAt})`,
        count: sql<number>`COUNT(*)`,
      })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, auth.id),
          eq(userArticleStates.isRead, true),
          isNotNull(userArticleStates.readAt),
        ),
      )
      .groupBy(sql`EXTRACT(DOW FROM ${userArticleStates.readAt})`)
      .orderBy(sql`EXTRACT(DOW FROM ${userArticleStates.readAt})`);

    return jsonResponse({
      totalReadingTime,
      articlesRead,
      averageReadingTime,
      estimatedWordsPerMinute: 200,
      readingByHour: readingByHour.map(row => ({
        hour: Number(row.hour),
        count: Number(row.count),
      })),
      readingByDayOfWeek: readingByDayOfWeek.map(row => ({
        dayOfWeek: Number(row.dayOfWeek),
        count: Number(row.count),
      })),
    });
  });
}

// Ported from Express routes/stats.routes.ts POST /reading-time.
export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };

    const parsed = readingTimeSchema.safeParse(await readJsonBody(request));
    if (!parsed.success) {
      return errorResponse(parsed.error);
    }
    const { articleId, timeSpent } = parsed.data;

    const db = await getDb();

    const [article] = await db
      .select({ id: articles.id })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .where(
        and(
          eq(articles.id, articleId),
          eq(feeds.userId, auth.id),
        ),
      )
      .limit(1);

    if (!article) {
      throw new AppError("Article not found", 404);
    }

    const day = new Date();
    day.setHours(0, 0, 0, 0);

    await db
      .insert(readingStats)
      .values({
        userId: auth.id,
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

    return jsonResponse({ message: "Reading time updated" });
  });
}
