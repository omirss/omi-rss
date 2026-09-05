import { z } from "zod";
import { eq, and, sql } from "drizzle-orm";
import { feeds, articles, userArticleStates } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse, noContent } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const updateFeedSchema = z.object({
  customTitle: z.string().optional(),
  folderId: z.string().uuid().nullable().optional(),
  updateInterval: z.number().min(5).max(1440).optional(),
  isActive: z.boolean().optional(),
  fullTextEnabled: z.boolean().optional(),
});

export async function loader({ params, context }: { params: Record<string, string>; context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const { feedId } = params;
    const db = await getDb();

    const [feed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.id, feedId),
        eq(feeds.userId, auth.id),
      ))
      .limit(1);

    if (!feed) {
      throw new AppError("Feed not found", 404);
    }

    const [stats] = await db
      .select({
        totalArticles: sql<number>`COUNT(*)`,
        unreadArticles: sql<number>`
          COUNT(*) FILTER (
            WHERE NOT EXISTS (
              SELECT 1 FROM ${userArticleStates}
              WHERE ${userArticleStates.articleId} = ${articles.id}
              AND ${userArticleStates.userId} = ${auth.id}
              AND ${userArticleStates.isRead} = true
            )
          )
        `,
      })
      .from(articles)
      .where(eq(articles.feedId, feedId));

    return jsonResponse({
      feed,
      stats: stats
        ? {
            totalArticles: Number(stats.totalArticles),
            unreadArticles: Number(stats.unreadArticles),
          }
        : { totalArticles: 0, unreadArticles: 0 },
    });
  });
}

export async function action({ request, params, context }: { request: Request; params: Record<string, string>; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const { feedId } = params;

    const db = await getDb();

    const [existingFeed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.id, feedId),
        eq(feeds.userId, auth.id),
      ))
      .limit(1);

    if (!existingFeed) {
      throw new AppError("Feed not found", 404);
    }

    if (request.method === "DELETE") {
      await db
        .delete(feeds)
        .where(eq(feeds.id, feedId));

      console.info(`User ${auth.id} deleted feed: ${existingFeed.title}`);

      return noContent();
    }

    const data = updateFeedSchema.parse(await readJsonBody(request));

    const [updatedFeed] = await db
      .update(feeds)
      .set({
        ...data,
        updatedAt: new Date(),
      })
      .where(eq(feeds.id, feedId))
      .returning();

    return jsonResponse({ feed: updatedFeed });
  });
}
