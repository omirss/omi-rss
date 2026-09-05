import { eq, and, sql, or } from "drizzle-orm";
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

    // Insert-select must list EVERY userArticleStates column, in table
    // order — drizzle validates the selection keys against the table
    // definition and rejects partial/reordered selects.
    const marked = await db
      .insert(userArticleStates)
      .select(
        db
          .select({
            userId: sql`${auth.id}::uuid`.as("userId"),
            articleId: articles.id,
            isRead: sql`true`.as("isRead"),
            isStarred: sql`COALESCE(${userArticleStates.isStarred}, false)`.as("isStarred"),
            readAt: sql`now()`.as("readAt"),
            starredAt: userArticleStates.starredAt,
            readingTime: userArticleStates.readingTime,
            createdAt: sql`now()`.as("createdAt"),
            updatedAt: sql`now()`.as("updatedAt"),
          })
          .from(articles)
          .innerJoin(feeds, eq(articles.feedId, feeds.id))
          .leftJoin(
            userArticleStates,
            and(
              eq(userArticleStates.articleId, articles.id),
              eq(userArticleStates.userId, auth.id),
            ),
          )
          .where(
            and(
              eq(articles.feedId, feedId),
              eq(feeds.userId, auth.id),
              or(
                eq(userArticleStates.isRead, false),
                sql`${userArticleStates.isRead} IS NULL`,
              ),
            ),
          ),
      )
      .onConflictDoUpdate({
        target: [userArticleStates.userId, userArticleStates.articleId],
        set: {
          isRead: true,
          readAt: new Date(),
          updatedAt: new Date(),
        },
      })
      .returning({ articleId: userArticleStates.articleId });

    return jsonResponse({
      message: "All articles marked as read",
      count: marked.length,
    });
  });
}
