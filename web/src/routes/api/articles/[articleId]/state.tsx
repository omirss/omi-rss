import { z } from "zod";
import { eq, and } from "drizzle-orm";
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

    const stateData: Record<string, unknown> = {
      userId: auth.id,
      articleId,
      updatedAt: new Date(),
    };

    if (updates.isRead !== undefined) {
      stateData.isRead = updates.isRead;
      if (updates.isRead) {
        stateData.readAt = new Date();
      }
    }

    if (updates.isStarred !== undefined) {
      stateData.isStarred = updates.isStarred;
      if (updates.isStarred) {
        stateData.starredAt = new Date();
      }
    }

    await db
      .insert(userArticleStates)
      .values(stateData as typeof userArticleStates.$inferInsert)
      .onConflictDoUpdate({
        target: [userArticleStates.userId, userArticleStates.articleId],
        set: stateData,
      });

    return jsonResponse({ message: "Article state updated" });
  });
}
