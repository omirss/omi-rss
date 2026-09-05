import { eq, and } from "drizzle-orm";
import { feeds } from "../../../data/db/schema.js";
import { getDb } from "../../../lib/api/db.js";
import { AppError, handle, jsonResponse } from "../../../lib/api/errors.js";
import { readJsonBody } from "../../../lib/api/body.js";
import { requireAuth } from "../../../lib/api/auth.js";
import { getDataRuntime } from "../../../data/runtime.js";
import { validatePageFeedInput, verifyPageSelector } from "../../../services/page-feed.js";

export const config = { mode: "app" };

export const middleware = requireAuth;

// POST /api/feeds/page — subscribe to a page-feed: items are scraped from
// an HTML page via CSS selector instead of parsed from RSS/Atom. The page
// is fetched once here through the hardened core to verify the selector
// matches at least one element before the feed row is stored.
export async function action({ request, context }: { request: Request; context: Record<string, unknown> }) {
  return handle(async () => {
    const auth = context.user as { id: string };
    const input = await validatePageFeedInput(await readJsonBody(request));
    const db = await getDb();

    const [existingFeed] = await db
      .select({ id: feeds.id })
      .from(feeds)
      .where(and(
        eq(feeds.url, input.pageUrl),
        eq(feeds.sourceType, "page"),
        eq(feeds.userId, auth.id),
      ))
      .limit(1);

    if (existingFeed) {
      throw new AppError("Already subscribed to this page feed", 409);
    }

    const verification = await verifyPageSelector(input.pageUrl, input.pageSelector);

    let hostname = input.pageUrl;
    let siteUrl: string | null = null;
    try {
      const parsed = new URL(input.pageUrl);
      hostname = parsed.hostname;
      siteUrl = parsed.origin;
    } catch {
      // validatePageFeedInput already parsed it — unreachable in practice.
    }

    const [newFeed] = await db
      .insert(feeds)
      .values({
        userId: auth.id,
        url: input.pageUrl,
        title: (input.title || verification.documentTitle || hostname).slice(0, 500),
        siteUrl,
        folderId: input.folderId,
        updateInterval: input.updateInterval || 30,
        sourceType: "page",
        pageUrl: input.pageUrl,
        pageSelector: input.pageSelector,
        favicon: `https://www.google.com/s2/favicons?domain=${hostname}&sz=64`,
      })
      .returning();

    const runtime = await getDataRuntime();
    await runtime.queue.add("feed.update-single", {
      feedId: newFeed.id,
    });

    console.info(`User ${auth.id} subscribed to page feed: ${newFeed.title}`);

    return jsonResponse({ feed: newFeed }, 201);
  });
}
