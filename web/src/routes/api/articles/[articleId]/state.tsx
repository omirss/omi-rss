import { z } from "zod";
import { eq, and, sql } from "drizzle-orm";
import { articles, userArticleStates, feeds } from "../../../../data/db/schema.js";
import { getDb } from "../../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../../lib/api/errors.js";
import { readJsonBody } from "../../../../lib/api/body.js";
import { requireAuth } from "../../../../lib/api/auth.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const updateArticleStateSchema = z.object({
  isRead: z.boolean().optional(),
  isStarred: z.boolean().optional(),
}).refine(
  (data) => data.isRead !== undefined || data.isStarred !== undefined,
  { message: "At least one of isRead or isStarred must be provided" },
);

export async function action({ request, params, context }: { request: Request; params: Record<string, string>; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const { articleId } = params;
    const updates = updateArticleStateSchema.parse(await readJsonBody(request));
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

    // Timestamps are consistent with batch-update and greader: clearing a
    // flag clears its timestamp, and a repeated true keeps the ORIGINAL
    // event time (COALESCE against the current row) instead of rewriting
    // history.
    const stateData: Record<string, unknown> = {
      userId: auth.id,
      articleId,
      updatedAt: new Date(),
    };
    const setPatch: Record<string, unknown> = {
      updatedAt: new Date(),
    };

    if (updates.isRead !== undefined) {
      stateData.isRead = updates.isRead;
      stateData.readAt = updates.isRead ? new Date() : null;
      setPatch.isRead = updates.isRead;
      setPatch.readAt = updates.isRead
        ? sql`CASE WHEN ${userArticleStates.isRead} THEN COALESCE(${userArticleStates.readAt}, now()) ELSE now() END`
        : null;
    }

    if (updates.isStarred !== undefined) {
      stateData.isStarred = updates.isStarred;
      stateData.starredAt = updates.isStarred ? new Date() : null;
      setPatch.isStarred = updates.isStarred;
      setPatch.starredAt = updates.isStarred
        ? sql`CASE WHEN ${userArticleStates.isStarred} THEN COALESCE(${userArticleStates.starredAt}, now()) ELSE now() END`
        : null;
    }

    await db
      .insert(userArticleStates)
      .values(stateData as typeof userArticleStates.$inferInsert)
      .onConflictDoUpdate({
        target: [userArticleStates.userId, userArticleStates.articleId],
        set: setPatch,
      });

    return jsonResponse({ message: "Article state updated" });
  });
}
