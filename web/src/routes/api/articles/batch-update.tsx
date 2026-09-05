import { z } from "zod";
import { eq, and, inArray } from "drizzle-orm";
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

    const ownedArticles = await db
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

    for (const articleId of ownedArticleIds) {
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
    }

    return jsonResponse({
      message: "Articles updated",
      updatedCount: ownedArticleIds.length,
    });
  });
}
