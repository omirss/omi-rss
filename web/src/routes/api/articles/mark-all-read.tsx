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
});

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const query = Object.fromEntries(new URL(request.url).searchParams.entries());
    const filters = filterSchema.parse(query);
    const db = await getDb();

    const conditions: Array<SQL | undefined> = [
      eq(feeds.userId, auth.id),
      or(
        eq(userArticleStates.isRead, false),
        sql`${userArticleStates.isRead} IS NULL`,
      ),
    ];

    if (filters.feedId) {
      conditions.push(eq(articles.feedId, filters.feedId));
    }

    if (filters.folderId) {
      conditions.push(eq(feeds.folderId, filters.folderId));
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
          .where(and(...conditions)),
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
