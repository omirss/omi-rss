import { z } from "zod";
import { eq, and, inArray, sql, type SQL } from "drizzle-orm";
import { articles, userArticleStates, feeds } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const updateArticleStateSchema = z.object({
  isRead: z.boolean().optional(),
  isStarred: z.boolean().optional(),
}).refine(
  (data) => data.isRead !== undefined || data.isStarred !== undefined,
  { message: "At least one of isRead or isStarred must be provided" },
);

const batchUpdateSchema = z.object({
  articleIds: z.array(z.string().uuid()),
  updates: updateArticleStateSchema,
});

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const { articleIds, updates } = batchUpdateSchema.parse(await readJsonBody(request));
    const db = await getDb();

    const result = await db.transaction(async (tx) => {
      const ownedArticles = await tx
        .select({ id: articles.id })
        .from(articles)
        .innerJoin(feeds, eq(articles.feedId, feeds.id))
        .where(
          and(
            inArray(articles.id, articleIds),
            eq(feeds.userId, auth.id),
          ),
        );

      const ownedArticleIds = ownedArticles.map(a => a.id);

      if (ownedArticleIds.length === 0) {
        throw new AppError("No valid articles found", 404);
      }

      // Unspecified fields carry their current value through EXCLUDED (the
      // SELECT coalesces them from the existing row, or uses the column
      // default for brand-new rows), so partial updates never clobber state.
      // Insert-select must also list EVERY userArticleStates column, in
      // table order — drizzle validates the selection keys against the
      // table definition and rejects partial/reordered selects.
      const isReadExpr: SQL = updates.isRead === undefined
        ? sql`COALESCE(${userArticleStates.isRead}, false)`
        : sql`${updates.isRead}`;
      const readAtExpr: SQL = updates.isRead === true
        ? sql`now()`
        : updates.isRead === false
          ? sql`NULL`
          : sql`${userArticleStates.readAt}`;
      const isStarredExpr: SQL = updates.isStarred === undefined
        ? sql`COALESCE(${userArticleStates.isStarred}, false)`
        : sql`${updates.isStarred}`;
      const starredAtExpr: SQL = updates.isStarred === true
        ? sql`now()`
        : updates.isStarred === false
          ? sql`NULL`
          : sql`${userArticleStates.starredAt}`;

      await tx
        .insert(userArticleStates)
        .select(
          tx
            .select({
              userId: sql`${auth.id}::uuid`.as("userId"),
              articleId: articles.id,
              isRead: isReadExpr.as("isRead"),
              isStarred: isStarredExpr.as("isStarred"),
              readAt: readAtExpr.as("readAt"),
              starredAt: starredAtExpr.as("starredAt"),
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
                inArray(articles.id, ownedArticleIds),
                eq(feeds.userId, auth.id),
              ),
            ),
        )
        .onConflictDoUpdate({
          target: [userArticleStates.userId, userArticleStates.articleId],
          set: {
            isRead: sql`excluded.is_read`,
            readAt: sql`excluded.read_at`,
            isStarred: sql`excluded.is_starred`,
            starredAt: sql`excluded.starred_at`,
            updatedAt: sql`excluded.updated_at`,
          },
        });

      return ownedArticleIds.length;
    });

    return jsonResponse({
      message: "Articles updated",
      updatedCount: result,
    });
  });
}
