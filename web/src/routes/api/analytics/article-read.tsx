import { z } from "zod";
import { eq, and } from "drizzle-orm";
import { articles, feeds } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, jsonResponse, errorResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { analyticsService } from "../../../services/analytics.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const MAX_INTERACTION_TIME_SECONDS = 24 * 60 * 60;

const trackArticleReadSchema = z.object({
  articleId: z.string().uuid(),
  scrollDepth: z.number().min(0).max(100),
  interactionTime: z.number().positive().max(MAX_INTERACTION_TIME_SECONDS),
  completed: z.boolean(),
});

// Ported from Express routes/analytics.ts POST /article-read.
export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };

    const parsed = trackArticleReadSchema.safeParse(await readJsonBody(request));
    if (!parsed.success) {
      return errorResponse(parsed.error);
    }

    const { articleId } = parsed.data;

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

    await analyticsService.trackArticleRead(auth.id, parsed.data);
    return jsonResponse({ success: true });
  });
}
