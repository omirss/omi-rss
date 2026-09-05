import { eq, and } from "drizzle-orm";
import { feeds, articles, userArticleStates } from "../../../../data/db/schema.js";
import { getDb } from "../../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../../lib/api/errors.js";
import { requireAuth } from "../../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

export async function action({ params, context }: { params: Record<string, string>; context: Record<string, unknown> }) {
  return handle(async () => {
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

    const feedArticles = await db
      .select({ id: articles.id })
      .from(articles)
      .where(eq(articles.feedId, feedId));

    for (const article of feedArticles) {
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
      count: feedArticles.length,
    });
  });
}
