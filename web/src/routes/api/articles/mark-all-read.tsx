import { z } from "zod";
import { eq, and, sql, or, type SQL } from "drizzle-orm";
import { articles, userArticleStates, feeds } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { handle, jsonResponse } from "../../../lib/api/errors.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const filterSchema = z.object({
  feedId: z.string().uuid().optional(),
  folderId: z.string().uuid().optional(),
  isRead: z.string().transform(val => val === "true").optional(),
  isStarred: z.string().transform(val => val === "true").optional(),
  search: z.string().optional(),
});

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const query = Object.fromEntries(new URL(request.url).searchParams.entries());
    const filters = filterSchema.parse(query);
    const db = await getDb();

    const conditions: Array<SQL | undefined> = [eq(feeds.userId, auth.id)];

    if (filters.feedId) {
      conditions.push(eq(articles.feedId, filters.feedId));
    }

    if (filters.folderId) {
      conditions.push(eq(feeds.folderId, filters.folderId));
    }

    conditions.push(
      or(
        eq(userArticleStates.isRead, false),
        sql`${userArticleStates.isRead} IS NULL`,
      ),
    );

    const unreadArticles = await db
      .select({ id: articles.id })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .leftJoin(
        userArticleStates,
        and(
          eq(userArticleStates.articleId, articles.id),
          eq(userArticleStates.userId, auth.id),
        ),
      )
      .where(and(...conditions));

    for (const article of unreadArticles) {
      await db
        .insert(userArticleStates)
        .values({
          userId: auth.id,
          articleId: article.id,
          isRead: true,
          readAt: new Date(),
        })
        .onConflictDoUpdate({
          target: [userArticleStates.userId, userArticleStates.articleId],
          set: {
            isRead: true,
            readAt: new Date(),
            updatedAt: new Date(),
          },
        });
    }

    return jsonResponse({
      message: "All articles marked as read",
      count: unreadArticles.length,
    });
  });
}
