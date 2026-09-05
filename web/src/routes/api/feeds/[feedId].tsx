import { z } from "zod";
import { eq, and, sql } from "drizzle-orm";
import { feeds, articles, userArticleStates } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse, noContent } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { validateHttpHeaders } from "../../../lib/feed-headers.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

// Extraction health is reported over a bounded recent-articles window so the
// detail endpoint stays cheap on large feeds.
const EXTRACTION_STATS_WINDOW = 200;

async function extractionStatsFor(db: Awaited<ReturnType<typeof getDb>>, feedId: string) {
  const [row] = await db
    .select({
      scanned: sql<number>`COUNT(*)`,
      extracted: sql<number>`COUNT(*) FILTER (WHERE recent_articles.content_extracted IS NOT NULL AND recent_articles.content_extracted <> '')`,
      failed: sql<number>`COUNT(*) FILTER (WHERE recent_articles.content_extracted = '')`,
      pending: sql<number>`COUNT(*) FILTER (WHERE recent_articles.content_extracted IS NULL)`,
    })
    .from(sql`(
      SELECT content_extracted FROM ${articles}
      WHERE ${articles.feedId} = ${feedId}
      ORDER BY ${articles.createdAt} DESC
      LIMIT ${EXTRACTION_STATS_WINDOW}
    ) AS recent_articles`);

  if (!row) return null;
  return {
    scanned: Number(row.scanned),
    extracted: Number(row.extracted),
    failed: Number(row.failed),
    pending: Number(row.pending),
    windowLimit: EXTRACTION_STATS_WINDOW,
  };
}

const updateFeedSchema = z.object({
  customTitle: z.string().optional(),
  folderId: z.string().uuid().nullable().optional(),
  updateInterval: z.number().min(5).max(1440).optional(),
  isActive: z.boolean().optional(),
  fullTextEnabled: z.boolean().optional(),
  httpHeaders: z.record(z.string()).nullable().optional(),
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

    const extractionStats = feed.fullTextEnabled ? await extractionStatsFor(db, feedId) : undefined;

    return jsonResponse({
      feed,
      stats: stats
        ? {
            totalArticles: Number(stats.totalArticles),
            unreadArticles: Number(stats.unreadArticles),
          }
        : { totalArticles: 0, unreadArticles: 0 },
      ...(extractionStats ? { extractionStats } : {}),
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

    // Page feeds extract their content by construction — full-text is an
    // RSS-feed-only toggle.
    if (data.fullTextEnabled !== undefined && existingFeed.sourceType === "page") {
      throw new AppError("fullTextEnabled cannot be set on page feeds", 400);
    }

    let httpHeaders: Record<string, string> | null | undefined;
    if (data.httpHeaders !== undefined) {
      const validated = validateHttpHeaders(data.httpHeaders);
      if (!validated.ok) {
        throw new AppError(validated.error, 400);
      }
      // An empty object clears the headers (stored as NULL).
      httpHeaders = Object.keys(validated.value).length > 0 ? validated.value : null;
    }

    const [updatedFeed] = await db
      .update(feeds)
      .set({
        ...data,
        ...(httpHeaders !== undefined && { httpHeaders }),
        updatedAt: new Date(),
      })
      .where(eq(feeds.id, feedId))
      .returning();

    return jsonResponse({ feed: updatedFeed });
  });
}
