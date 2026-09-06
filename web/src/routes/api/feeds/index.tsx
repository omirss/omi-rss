import { z } from "zod";
import { eq, and, sql } from "drizzle-orm";
import Parser from "rss-parser";
import { feeds, articles, userArticleStates } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, handleLoader, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { getDataRuntime } from "../../../data/runtime.js";
import { fetchFeedXml } from "../../../services/feed-fetch.js";
import { faviconUrlFor } from "../../../lib/favicon.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

const parser = new Parser();

const createFeedSchema = z.object({
  url: z.string().url(),
  folderId: z.string().uuid().optional(),
  customTitle: z.string().optional(),
  updateInterval: z.number().min(5).max(1440).optional(),
  fullTextEnabled: z.boolean().optional(),
});

export async function loader({ context }: { context: Record<string, unknown> }) {
  return handleLoader(async () => {
    const auth = context.user as { id: string };
    const db = await getDb();

    const userFeeds = await db
      .select({
        id: feeds.id,
        url: feeds.url,
        title: feeds.title,
        description: feeds.description,
        siteUrl: feeds.siteUrl,
        favicon: feeds.favicon,
        imageUrl: feeds.imageUrl,
        customTitle: feeds.customTitle,
        folderId: feeds.folderId,
        updateInterval: feeds.updateInterval,
        lastFetchedAt: feeds.lastFetchedAt,
        lastFetchError: feeds.lastFetchError,
        errorCount: feeds.errorCount,
        isActive: feeds.isActive,
        settings: feeds.settings,
        fullTextEnabled: feeds.fullTextEnabled,
        sourceType: feeds.sourceType,
        pageUrl: feeds.pageUrl,
        pageSelector: feeds.pageSelector,
        createdAt: feeds.createdAt,
        updatedAt: feeds.updatedAt,
        unreadCount: sql<number>`
          COUNT(DISTINCT ${articles.id}) FILTER (
            WHERE ${articles.id} IS NOT NULL
            AND NOT EXISTS (
              SELECT 1 FROM ${userArticleStates}
              WHERE ${userArticleStates.articleId} = ${articles.id}
              AND ${userArticleStates.userId} = ${auth.id}
              AND ${userArticleStates.isRead} = true
            )
          )
        `.as("unreadCount"),
      })
      .from(feeds)
      .leftJoin(articles, eq(articles.feedId, feeds.id))
      .where(eq(feeds.userId, auth.id))
      .groupBy(feeds.id)
      .orderBy(feeds.customTitle, feeds.title);

    return jsonResponse({
      feeds: userFeeds.map(feed => ({
        ...feed,
        unreadCount: Number(feed.unreadCount),
      })),
    });
  });
}

export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const data = createFeedSchema.parse(await readJsonBody(request));
    const db = await getDb();

    const [existingFeed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.url, data.url),
        eq(feeds.userId, auth.id),
      ))
      .limit(1);

    if (existingFeed) {
      throw new AppError("Already subscribed to this feed", 409);
    }

    let feedData;
    try {
      feedData = await parser.parseString(await fetchFeedXml(data.url));
    } catch (parseError) {
      throw new AppError("Invalid feed URL or unable to parse feed", 400);
    }

    const feedImage = feedData.image as string | { url?: string } | undefined;
    const [newFeed] = await db
      .insert(feeds)
      .values({
        userId: auth.id,
        url: data.url,
        title: feedData.title || "Untitled Feed",
        description: feedData.description,
        siteUrl: feedData.link,
        imageUrl: typeof feedImage === "string" ? feedImage : feedImage?.url,
        customTitle: data.customTitle,
        folderId: data.folderId,
        updateInterval: data.updateInterval || 30,
        fullTextEnabled: data.fullTextEnabled ?? false,
        favicon: faviconUrlFor(feedData.link),
      })
      .returning();

    const runtime = await getDataRuntime();
    await runtime.queue.add("feed.update-single", {
      feedId: newFeed.id,
    });

    console.info(`User ${auth.id} subscribed to feed: ${newFeed.title}`);

    return jsonResponse({ feed: newFeed }, 201);
  });
}
