import { Queue } from "bullmq";
import crypto from "node:crypto";
import Parser from "rss-parser";
import { eq, and, sql, gte, isNull, ne, desc } from "drizzle-orm";
import { createBullMqQueueDriver, type BullMqQueueDriver } from "@neutron-build/data";
import { getDataRuntime, QUEUE_NAME, QUEUE_PREFIX } from "./data/runtime.js";
import { getDb, type Database } from "./lib/api/db.js";
import { AppError } from "./lib/api/errors.js";
import { validateAuthBootEnv } from "./lib/api/tokens.js";
import { feeds, articles, userArticleStates, readingStats, notifications } from "./data/db/schema.js";
import { assertSafeFeedUrl, fetchFeedXml, isTransientFeedUrlError } from "./services/feed-fetch.js";
import { withHostGate } from "./services/host-gate.js";
import { sameSiteHost } from "./services/site-host.js";
import { decodeBody, extractArticle, fetchDocument } from "./services/extraction.js";
import { runPageFeedUpdate, type PageFeedStore } from "./services/page-feed.js";
import { initializeEmailService, isEmailConfigured, sendEmail } from "./services/email.js";
import { warmDiscoveryCatalog } from "./services/discovery.js";

interface WorkerContext {
  mode: string;
  args: string[];
  signal: AbortSignal;
  log: (message: string) => void;
}

// Ported from Express workers (v0.2.1). Express ran four Bull queues
// (feed-updates, notifications, analytics, cleanup); the Neutron runtime has
// a single prefixed queue, so the workers live here as job names on it.
// Repeatable (cron) registration needs raw BullMQ — neutron-data's
// QueueDriver has no repeatable-job API — but consumption goes through the
// same runtime queue so route-enqueued jobs and cron jobs meet here.

const FEED_UPDATE_ALL_JOB = "feed.update-all";
const FEED_UPDATE_SINGLE_JOB = "feed.update-single";
const CLEANUP_JOB = "cleanup.old-data";
const ANALYTICS_JOB = "analytics.aggregate";
const NOTIFICATION_SEND_EMAIL_JOB = "notification.send-email";
const NOTIFICATION_MARK_READ_JOB = "notification.mark-read";
const EXTRACT_ARTICLE_JOB = "extract.article";
const DISCOVERY_WARM_JOB = "discovery.warm-catalog";

// v0.4.0 extraction engine: extraction jobs run on a dedicated queue
// (concurrency 2) so an extraction backlog can never delay feed refreshes
// (concurrency 4). Per-run budget: one update run enqueues at most 20
// extraction jobs or spends at most 10s enqueuing; articles beyond the
// budget keep contentExtracted NULL and are picked up by a later run's
// backfill query. Article fetches happen once (at insert time) and are
// never automatically re-fetched.
const EXTRACT_QUEUE_NAME = "omiweb-extract";
const EXTRACT_QUEUE_CONCURRENCY = 2;
const EXTRACT_RUN_MAX_ARTICLES = 20;
const EXTRACT_RUN_BUDGET_MS = 10000;

type FeedRow = typeof feeds.$inferSelect;

let extractQueuePromise: Promise<BullMqQueueDriver> | null = null;
const pageFeedInFlight = new Set<string>();

function getExtractQueue(): Promise<BullMqQueueDriver> {
  if (!extractQueuePromise) {
    extractQueuePromise = createBullMqQueueDriver({
      url: process.env.REDIS_URL || "redis://localhost:6380",
      queueName: EXTRACT_QUEUE_NAME,
      prefix: QUEUE_PREFIX,
      concurrency: EXTRACT_QUEUE_CONCURRENCY,
    });
  }
  return extractQueuePromise;
}

export function extractionBudgetExceeded(runStartedAt: number, enqueued: number, now: number = Date.now()): boolean {
  return enqueued >= EXTRACT_RUN_MAX_ARTICLES || now - runStartedAt >= EXTRACT_RUN_BUDGET_MS;
}

export type ArticleExtractionOutcome =
  | "missing"
  | "already-extracted"
  | "skip-no-url"
  | "skip-unsafe-url"
  | "defer-transient"
  | "fetch";

// Decision step of the extract job, split out so the SSRF skip (article
// URLs are feed data) is unit-testable without a database. Transient DNS
// failures defer ('' would be terminal; NULL lets a later run backfill).
export async function articleExtractionOutcome(
  article: { url: string } | undefined,
  contentExtracted: string | null,
): Promise<ArticleExtractionOutcome> {
  if (!article) return "missing";
  if (contentExtracted !== null) return "already-extracted";
  if (!article.url) return "skip-no-url";
  try {
    await assertSafeFeedUrl(article.url);
  } catch (error) {
    if (isTransientFeedUrlError(error)) {
      return "defer-transient";
    }
    return "skip-unsafe-url";
  }
  return "fetch";
}

async function storeExtraction(db: Database, articleId: string, contentExtracted: string): Promise<void> {
  await db
    .update(articles)
    .set({ contentExtracted, updatedAt: new Date() })
    .where(and(eq(articles.id, articleId), isNull(articles.contentExtracted)));
}

// Enqueues extraction jobs for the feed's pending articles (contentExtracted
// NULL, non-empty URL): the run's new articles first (most recent
// publishedAt), bounded by the per-run budget; the rest defer to later runs.
// The budget clock starts INSIDE this step — time spent fetching and
// inserting articles must not consume the extraction budget, or slow feeds
// would never enqueue any extraction at all.
export async function enqueuePendingExtractions(db: Database, feed: FeedRow): Promise<number> {
  const runStartedAt = Date.now();
  const candidates = await db
    .select({ id: articles.id })
    .from(articles)
    .where(
      and(
        eq(articles.feedId, feed.id),
        isNull(articles.contentExtracted),
        ne(articles.url, ""),
      ),
    )
    .orderBy(desc(articles.publishedAt))
    .limit(EXTRACT_RUN_MAX_ARTICLES);

  if (candidates.length === 0) return 0;

  const queue = await getExtractQueue();
  let enqueued = 0;
  for (const candidate of candidates) {
    if (extractionBudgetExceeded(runStartedAt, enqueued)) {
      break;
    }
    await queue.add(EXTRACT_ARTICLE_JOB, { articleId: candidate.id });
    enqueued++;
  }
  return enqueued;
}

export async function processExtractArticle(articleId: string): Promise<{ articleId: string; status: ArticleExtractionOutcome | string }> {
  const db = await getDb();

  // Single query: article fields plus the feed's bring-your-own-subscription
  // headers and URL (join, no second roundtrip).
  const [article] = await db
    .select({ id: articles.id, url: articles.url, contentExtracted: articles.contentExtracted, httpHeaders: feeds.httpHeaders, feedUrl: feeds.url })
    .from(articles)
    .innerJoin(feeds, eq(articles.feedId, feeds.id))
    .where(eq(articles.id, articleId))
    .limit(1);

  const outcome = await articleExtractionOutcome(
    article ? { url: article.url } : undefined,
    article?.contentExtracted ?? null,
  );

  if (outcome === "missing" || outcome === "already-extracted") {
    return { articleId, status: outcome };
  }
  if (outcome === "defer-transient") {
    // DNS-transient: leave contentExtracted NULL so a later run's backfill
    // retries it ('' would be terminal under fetch-once semantics).
    console.warn(`Extraction deferred (transient DNS) for article ${articleId}: ${article!.url}`);
    return { articleId, status: "deferred-transient" };
  }
  if (outcome === "skip-no-url" || outcome === "skip-unsafe-url") {
    console.warn(`Extraction job skipping article ${articleId}: ${outcome}`);
    await storeExtraction(db, articleId, "");
    return { articleId, status: outcome };
  }

  const url = article!.url;

  try {
    // Bring-your-own-subscription headers only ride the article fetch when
    // the article URL is on the feed's own site (sameSiteHost: naive
    // registrable-domain match, exact for IP literals) — item links can
    // point anywhere and must never receive the owner's cookies or
    // authorization.
    const articleHeaders =
      article!.httpHeaders && sameSiteHost(article!.feedUrl, url)
        ? article!.httpHeaders
        : undefined;
    const doc = await fetchDocument(url, undefined, articleHeaders);
    if (doc.status !== 200 || !doc.body) {
      // Transient upstream statuses stay NULL so a later run backfills
      // them; only genuinely terminal outcomes (404/410/…) store ''.
      if (RETRYABLE_EXTRACTION_STATUSES.has(doc.status)) {
        console.warn(`Extraction deferred (transient HTTP ${doc.status}) for ${url}`);
        return { articleId, status: `deferred-http-${doc.status}` };
      }
      await storeExtraction(db, articleId, "");
      return { articleId, status: `http-${doc.status}` };
    }
    const html = decodeBody(doc.body, doc.contentType);
    const extracted = extractArticle(html, doc.finalUrl || url);
    await storeExtraction(db, articleId, extracted.contentHtml);
    return { articleId, status: `ok-${extracted.method}` };
  } catch (error) {
    if (isTransientFeedUrlError(error)) {
      console.warn(`Extraction deferred (transient DNS) for ${url}:`, error);
      return { articleId, status: "deferred-transient" };
    }
    if (error instanceof AppError) {
      console.warn(`Extraction failed (terminal, not re-fetched) for ${url}:`, error);
      await storeExtraction(db, articleId, "");
      return { articleId, status: "error" };
    }
    // Timeouts and network errors are transient upstream conditions —
    // leave NULL so the backfill retries them.
    console.warn(`Extraction deferred (transient network) for ${url}:`, error);
    return { articleId, status: "deferred-transient" };
  }
}

export function createPageFeedStore(db: Database): PageFeedStore {
  return {
    insertItems: async (feedId, items, pageUrl) => {
      if (items.length === 0) return 0;
      const rows = await db
        .insert(articles)
        .values(
          items.map((item) => ({
            feedId,
            guid: item.guid,
            url: item.link ?? pageUrl,
            title: item.title,
            contentExtracted: item.contentHtml,
            publishedAt: new Date(),
          })),
        )
        .onConflictDoNothing({ target: [articles.feedId, articles.guid] })
        .returning({ id: articles.id });
      return rows.length;
    },
    markSuccess: async (feedId, settingsPatch) => {
      await db
        .update(feeds)
        .set({
          lastFetchedAt: new Date(),
          lastFetchError: null,
          errorCount: 0,
          updatedAt: new Date(),
          settings: sql`COALESCE(${feeds.settings}, '{}'::jsonb) || ${JSON.stringify(settingsPatch)}::jsonb`,
        })
        .where(eq(feeds.id, feedId));
    },
    markSelectorMiss: async (feedId, message) => {
      await db
        .update(feeds)
        .set({
          lastFetchedAt: new Date(),
          lastFetchError: message,
          errorCount: sql`${feeds.errorCount} + 1`,
          updatedAt: new Date(),
          settings: sql`COALESCE(${feeds.settings}, '{}'::jsonb) || '{"pageStatus":"selector-miss"}'::jsonb`,
        })
        .where(eq(feeds.id, feedId));
    },
  };
}

// Page-feed update with a single-flight claim so overlapping polls of the
// same feed never double-fetch. Fetch errors propagate to the shared
// update-single catch (feed error flag); selector misses keep the last
// good items instead of zeroing the feed.
async function processPageFeedSingle(feed: FeedRow): Promise<{ feedId: string; newArticles: number }> {
  if (pageFeedInFlight.has(feed.id)) {
    console.info(`Page feed ${feed.id} update already in flight — skipping duplicate poll`);
    return { feedId: feed.id, newArticles: 0 };
  }
  pageFeedInFlight.add(feed.id);
  try {
    const db = await getDb();
    // The feed's bring-your-own-subscription headers ride along on every
    // page-feed poll fetch.
    const result = await runPageFeedUpdate(feed, (url, conditional) => fetchDocument(url, conditional, feed.httpHeaders ?? undefined), createPageFeedStore(db));
    if (result.newItems > 0) {
      console.info(`Page feed ${feed.title} added ${result.newItems} items (${result.status})`);
    }
    return { feedId: feed.id, newArticles: result.newItems };
  } finally {
    pageFeedInFlight.delete(feed.id);
  }
}

const FEED_UPDATE_CRON = "*/5 * * * *";
const CLEANUP_CRON = "0 3 * * *";
const ANALYTICS_CRON = "0 * * * *";
// Metadata cache entries live 24h; re-warm every 6h so the discover
// endpoints always find warm enrichment data.
const DISCOVERY_WARM_CRON = "0 */6 * * *";
// A failed SMTP delivery is retried in-process (the neutron-data
// QueueDriver.add carries no BullMQ job options, so queue-level
// attempts/backoff are not expressible).
const EMAIL_SEND_ATTEMPTS = 3;
const EMAIL_SEND_RETRY_DELAY_MS = 5000;
const RETRYABLE_EXTRACTION_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504]);
const FEED_TITLE_MAX_CHARS = 500;
const ARTICLE_AUTHOR_MAX_CHARS = 255;

const parser = new Parser({
  customFields: {
    feed: ["subtitle", "image"],
    item: ["image", "enclosure", "media:content", "content:encoded", "description", "author"],
  },
});

interface FeedDueInput {
  isActive: boolean;
  lastFetchedAt: Date | null;
  updateInterval: number | null;
}

// Due-filter extracted from the Express update-all SQL so it stays unit
// testable: a feed is due when it is active and either never fetched or
// fetched longer than updateInterval minutes ago. A NULL interval never
// becomes due on its own (NULL interval arithmetic in SQL), which matches.
export function isFeedDue(feed: FeedDueInput, now: Date = new Date()): boolean {
  if (!feed.isActive) {
    return false;
  }
  if (feed.lastFetchedAt === null) {
    return true;
  }
  if (feed.updateInterval === null) {
    return false;
  }
  return now.getTime() - feed.lastFetchedAt.getTime() > feed.updateInterval * 60 * 1000;
}

async function processUpdateAll(): Promise<void> {
  console.info("Starting scheduled feed update");

  const db = await getDb();

  const activeFeeds = await db
    .select()
    .from(feeds)
    .where(eq(feeds.isActive, true));

  const dueFeeds = activeFeeds.filter((feed) =>
    isFeedDue({
      isActive: feed.isActive,
      lastFetchedAt: feed.lastFetchedAt,
      updateInterval: feed.updateInterval,
    })
  );

  console.info(`Found ${dueFeeds.length} feeds to update`);

  const runtime = await getDataRuntime();
  const results = await Promise.allSettled(
    dueFeeds.map((feed) => runtime.queue.add(FEED_UPDATE_SINGLE_JOB, { feedId: feed.id })),
  );

  const successful = results.filter((r) => r.status === "fulfilled").length;
  const failed = results.filter((r) => r.status === "rejected").length;

  console.info(`Feed update completed: ${successful} successful, ${failed} failed`);
}

// Feed items may carry site-relative links; resolve them against the feed's
// site URL (or feed URL) at insert so extraction's assertSafeFeedUrl never
// terminal-skips them. Absolute links and unresolvable values pass through.
export function resolveArticleUrl(link: string | undefined, base: string | null | undefined): string {
  if (!link) return "";
  try {
    return new URL(link, base || undefined).href;
  } catch {
    return link;
  }
}

// Publisher-controlled text is clamped to column limits (codepoint-safe —
// never splits a surrogate pair) and unparseable dates fall back to arrival
// time, so one malformed item cannot abort ingestion of every later item in
// the feed on every refresh.
export function publisherText(value: unknown, limit: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const chars = Array.from(value);
  return chars.length > limit ? chars.slice(0, limit).join("") : value;
}

export function publisherDate(value: unknown): Date {
  const date = value instanceof Date ? value : new Date(value as string | number);
  if (!Number.isNaN(date.getTime())) return date;
  return new Date();
}

async function processUpdateSingle(feedId: string): Promise<{ feedId: string; newArticles: number }> {
  try {
    const db = await getDb();

    const [feed] = await db
      .select()
      .from(feeds)
      .where(eq(feeds.id, feedId))
      .limit(1);

    if (!feed) {
      throw new Error(`Feed ${feedId} not found`);
    }

    if (feed.sourceType === "page") {
      return await processPageFeedSingle(feed);
    }

    console.info(`Updating feed: ${feed.title} (${feed.url})`);

    console.info(`Updating feed: ${feed.title} (${feed.url})`);

    const feedXml = await withHostGate(feed.url, () => fetchFeedXml(feed.url, feed.httpHeaders ?? undefined));
    const feedData = await parser.parseString(feedXml);

    await db
      .update(feeds)
      .set({
        title: publisherText(feedData.title, FEED_TITLE_MAX_CHARS) || feed.title,
        description: feedData.description || feed.description,
        siteUrl: feedData.link || feed.siteUrl,
        imageUrl: extractImageUrl(feedData) || feed.imageUrl,
        lastFetchedAt: new Date(),
        lastFetchError: null,
        errorCount: 0,
      })
      .where(eq(feeds.id, feedId));

    const newArticles = [];

    for (const item of feedData.items) {
      const guid =
        item.guid ||
        item.link ||
        crypto.createHash("md5").update((item.title || "") + (item.pubDate || "")).digest("hex");

      // Conflict-tolerant insert: a duplicate guid appearing between the
      // pre-check and the insert (concurrent update run) is skipped per
      // item instead of killing the whole feed update. Publisher-controlled
      // strings/dates are clamped first — an unparseable pubDate or an
      // oversized author must not poison every later item of the feed.
      const insertedArticles = await db
        .insert(articles)
        .values({
          feedId,
          guid,
          url: resolveArticleUrl(item.link, feed.siteUrl || feed.url),
          title: item.title || "Untitled",
          author: publisherText(item.creator || (item as { author?: string }).author, ARTICLE_AUTHOR_MAX_CHARS),
          content: (item as { "content:encoded"?: string })["content:encoded"] || item.content,
          summary: item.summary || (item as { description?: string }).description,
          imageUrl: extractItemImageUrl(item),
          publishedAt: publisherDate(item.pubDate),
          categories: item.categories || [],
          enclosures: (item as { enclosure?: unknown }).enclosure
            ? [(item as { enclosure: unknown }).enclosure]
            : [],
          metadata: {
            originalItem: item,
          },
        })
        .onConflictDoNothing({ target: [articles.feedId, articles.guid] })
        .returning();

      if (insertedArticles.length > 0) {
        newArticles.push(insertedArticles[0]);
      }
    }

    if (newArticles.length > 0) {
      console.info(`Added ${newArticles.length} new articles for feed ${feed.title}`);
    }

    if (feed.fullTextEnabled) {
      const enqueued = await enqueuePendingExtractions(db, feed);
      if (enqueued > 0) {
        console.info(`Enqueued ${enqueued} extraction jobs for feed ${feed.title}`);
      }
    }

    return { feedId, newArticles: newArticles.length };
  } catch (error) {
    console.error(`Failed to update feed ${feedId}:`, error);

    const db = await getDb();
    const [failedFeed] = await db
      .select({ sourceType: feeds.sourceType })
      .from(feeds)
      .where(eq(feeds.id, feedId))
      .limit(1);
    await db
      .update(feeds)
      .set({
        lastFetchError: error instanceof Error ? error.message : String(error),
        errorCount: sql`${feeds.errorCount} + 1`,
        lastFetchedAt: new Date(),
        // Page feeds carry a structured status so the webui never
        // string-matches lastFetchError.
        ...(failedFeed?.sourceType === "page" && {
          settings: sql`COALESCE(${feeds.settings}, '{}'::jsonb) || '{"pageStatus":"fetch-error"}'::jsonb`,
        }),
      })
      .where(eq(feeds.id, feedId));

    throw error;
  }
}

// Retention cutoff with validation: garbage ARTICLE_RETENTION_DAYS must
// fail the job instead of computing a destructive (or no-op) date.
export function articleRetentionCutoff(raw: string | undefined, now: Date = new Date()): Date {
  const days = Number(raw && raw.trim() ? raw : "90");
  if (!Number.isInteger(days) || days < 1 || days > 36500) {
    throw new Error(`Invalid ARTICLE_RETENTION_DAYS: ${raw ?? "(unset)"}`);
  }
  return new Date(now.getTime() - days * 24 * 60 * 60 * 1000);
}

// Nightly retention: deletes articles past the cutoff EXCEPT starred ones.
// Pausing a feed only stops fetching — it never deletes the library.
export async function processCleanup(): Promise<{ expired: number }> {
  const cutoff = articleRetentionCutoff(process.env.ARTICLE_RETENTION_DAYS);
  const db = await getDb();

  const expired = await db
    .delete(articles)
    .where(
      and(
        sql`COALESCE(${articles.publishedAt}, ${articles.createdAt}) < ${cutoff}`,
        sql`NOT EXISTS (
          SELECT 1 FROM ${userArticleStates}
          WHERE ${userArticleStates.articleId} = ${articles.id}
          AND ${userArticleStates.isStarred} = true
        )`,
      ),
    )
    .returning({ id: articles.id });

  console.info(`Cleanup complete: ${expired.length} articles past retention (starred excluded)`);

  return { expired: expired.length };
}

// Ported verbatim from Express workers/analytics.worker.ts — the
// MERGE-not-clobber version. Incremental writers (analytics service, stats
// routes) only ever add to these counters, so reconcile with GREATEST
// instead of overwriting the accumulated values; hourlyDistribution merges
// per-key with GREATEST.
async function processAnalyticsAggregate(): Promise<{ users: number }> {
  const db = await getDb();
  const day = new Date();
  day.setHours(0, 0, 0, 0);

  const rows = await db
    .select({
      userId: userArticleStates.userId,
      articleId: userArticleStates.articleId,
      readingTime: userArticleStates.readingTime,
      readAt: userArticleStates.readAt,
      words: sql<number>`
        ARRAY_LENGTH(REGEXP_SPLIT_TO_ARRAY(COALESCE(${articles.content}, ''), '\\s+'), 1)
      `,
      categories: articles.categories,
      feedId: articles.feedId,
    })
    .from(userArticleStates)
    .innerJoin(articles, eq(articles.id, userArticleStates.articleId))
    .where(
      and(
        eq(userArticleStates.isRead, true),
        gte(userArticleStates.readAt, day),
      ),
    );

  const byUser = new Map<
    string,
    {
      articlesRead: number;
      readingTime: number;
      wordsRead: number;
      feedsVisited: Set<string>;
      categories: Record<string, number>;
      hourlyDistribution: Record<string, number>;
    }
  >();

  for (const row of rows) {
    const entry = byUser.get(row.userId) || {
      articlesRead: 0,
      readingTime: 0,
      wordsRead: 0,
      feedsVisited: new Set<string>(),
      categories: {},
      hourlyDistribution: {},
    };

    entry.articlesRead++;
    entry.readingTime += row.readingTime || 0;
    entry.wordsRead += Number(row.words || 0);
    if (row.feedId) entry.feedsVisited.add(row.feedId);

    if (Array.isArray(row.categories)) {
      for (const category of row.categories as string[]) {
        entry.categories[category] = (entry.categories[category] || 0) + 1;
      }
    }

    if (row.readAt) {
      const hour = new Date(row.readAt).getHours().toString();
      entry.hourlyDistribution[hour] = (entry.hourlyDistribution[hour] || 0) + 1;
    }

    byUser.set(row.userId, entry);
  }

  const now = new Date();
  let upserted = 0;

  for (const [userId, entry] of byUser) {
    await db
      .insert(readingStats)
      .values({
        userId,
        date: day,
        articlesRead: entry.articlesRead,
        readingTime: entry.readingTime,
        wordsRead: entry.wordsRead,
        feedsVisited: Array.from(entry.feedsVisited),
        categories: entry.categories,
        hourlyDistribution: entry.hourlyDistribution,
      })
      .onConflictDoUpdate({
        target: [readingStats.userId, readingStats.date],
        set: {
          articlesRead: sql`GREATEST(${readingStats.articlesRead}, ${entry.articlesRead})`,
          readingTime: sql`GREATEST(${readingStats.readingTime}, ${entry.readingTime})`,
          wordsRead: entry.wordsRead,
          feedsVisited: Array.from(entry.feedsVisited),
          categories: entry.categories,
          hourlyDistribution: sql`
            (
              SELECT COALESCE(jsonb_object_agg(key, to_jsonb(max_count)), '{}'::jsonb)
              FROM (
                SELECT COALESCE(e.key, c.key) AS key,
                       GREATEST(COALESCE(e.value::int, 0), COALESCE(c.value::int, 0)) AS max_count
                FROM jsonb_each(${JSON.stringify(entry.hourlyDistribution)}::jsonb) c
                FULL JOIN jsonb_each(COALESCE(${readingStats.hourlyDistribution}, '{}'::jsonb)) e
                  ON e.key = c.key
              ) merged
            )
          `,
          updatedAt: now,
        },
      });
    upserted++;
  }

  console.info(`Analytics aggregation complete: ${upserted} users updated`);

  return { users: upserted };
}

// Ported from Express workers/notification.worker.ts — the honest
// version: every send is recorded as sent/failed/skipped from the actual
// delivery result, never fabricated.
interface SendEmailJobData {
  userId: string;
  email: string;
  subject: string;
  body?: string;
  template?: string;
  data?: Record<string, unknown>;
}

async function processSendEmail(jobData: SendEmailJobData): Promise<{ success: boolean; status: string }> {
  const { userId, email, subject, body, template, data } = jobData;

  try {
    console.info(`Processing email job for user ${userId}: ${subject}`);

    const db = await getDb();

    if (!isEmailConfigured()) {
      await db
        .insert(notifications)
        .values({
          userId,
          type: "email",
          title: subject,
          body: body || "Email notification",
          data: { email, template, ...data },
          channels: ["email"],
          status: "skipped",
        });

      console.warn(`Email skipped (SMTP not configured) for user ${userId}: ${subject}`);
      return { success: true, status: "skipped" };
    }

    // A failed delivery is retried before being recorded as failed; the
    // throw after recording surfaces the failure on the queue too.
    let sent = false;
    for (let attempt = 1; attempt <= EMAIL_SEND_ATTEMPTS; attempt++) {
      sent = await sendEmail({
        to: email,
        subject,
        text: body,
        template,
        data,
      });
      if (sent) break;
      if (attempt < EMAIL_SEND_ATTEMPTS) {
        console.warn(`Email delivery attempt ${attempt}/${EMAIL_SEND_ATTEMPTS} failed for user ${userId}: ${subject}`);
        await new Promise((resolve) => setTimeout(resolve, EMAIL_SEND_RETRY_DELAY_MS));
      }
    }

    if (!sent) {
      await db
        .insert(notifications)
        .values({
          userId,
          type: "email",
          title: subject,
          body: body || "Email notification",
          data: { email, template, ...data },
          channels: ["email"],
          status: "failed",
          failedAt: new Date(),
        });

      console.error(`Email delivery failed for user ${userId}: ${subject}`);
      throw new Error(`Email delivery failed after ${EMAIL_SEND_ATTEMPTS} attempts: ${subject}`);
    }

    await db
      .insert(notifications)
      .values({
        userId,
        type: "email",
        title: subject,
        body: body || "Email notification",
        data: { email, template, ...data },
        channels: ["email"],
        status: "sent",
        sentAt: new Date(),
      });

    console.info(`Email sent to user ${userId}: ${subject}`);
    return { success: true, status: "sent" };
  } catch (error) {
    console.error("Email job failed:", error);
    throw error;
  }
}

async function processMarkRead(jobData: { notificationId: string; userId: string }): Promise<{ success: boolean }> {
  const { notificationId, userId } = jobData;

  try {
    const db = await getDb();

    await db
      .update(notifications)
      .set({ readAt: new Date() })
      .where(
        and(
          eq(notifications.id, notificationId),
          eq(notifications.userId, userId),
        ),
      );

    return { success: true };
  } catch (error) {
    console.error("Mark read job failed:", error);
    throw error;
  }
}

function extractItemImageUrl(item: any): string | null {
  if (typeof item.image === "string") return item.image;
  const mediaContent = item["media:content"] as { $?: { url?: string } } | undefined;
  if (mediaContent?.$?.url) return mediaContent.$.url;
  const enclosure = item.enclosure as { url?: string; type?: string } | undefined;
  if (enclosure?.type?.startsWith("image/")) return enclosure.url ?? null;

  const content = item.content;
  if (typeof content === "string") {
    const imgMatch = content.match(/<img[^>]+src="([^">]+)"/);
    if (imgMatch) return imgMatch[1];
  }

  return null;
}

function extractImageUrl(feedData: any): string | null {
  const { image } = feedData;
  if (typeof image === "string") return image;
  if (image && typeof image === "object" && "url" in image) {
    const url = (image as { url?: unknown }).url;
    if (typeof url === "string") return url;
  }
  for (const item of feedData.items || []) {
    const itemImage = extractItemImageUrl(item);
    if (itemImage) return itemImage;
  }
  return null;
}

export async function run(context: WorkerContext): Promise<() => Promise<void>> {
  validateAuthBootEnv();

  const runtime = await getDataRuntime();

  await initializeEmailService();

  await runtime.queue.process(FEED_UPDATE_ALL_JOB, async () => {
    await processUpdateAll();
  });

  await runtime.queue.process(FEED_UPDATE_SINGLE_JOB, async (job) => {
    await processUpdateSingle((job.payload as { feedId: string }).feedId);
  });

  await runtime.queue.process(CLEANUP_JOB, async () => {
    await processCleanup();
  });

  await runtime.queue.process(ANALYTICS_JOB, async () => {
    await processAnalyticsAggregate();
  });

  await runtime.queue.process(NOTIFICATION_SEND_EMAIL_JOB, async (job) => {
    await processSendEmail(job.payload as SendEmailJobData);
  });

  await runtime.queue.process(NOTIFICATION_MARK_READ_JOB, async (job) => {
    await processMarkRead(job.payload as { notificationId: string; userId: string });
  });

  await runtime.queue.process(DISCOVERY_WARM_JOB, async () => {
    await warmDiscoveryCatalog();
  });

  // Extraction jobs run on a dedicated lower-concurrency queue in this same
  // worker process (see EXTRACT_QUEUE_NAME above).
  const extractQueue = await getExtractQueue();
  await extractQueue.process(EXTRACT_ARTICLE_JOB, async (job) => {
    await processExtractArticle((job.payload as { articleId: string }).articleId);
  });

  // neutron-data's QueueDriver has no repeatable-job API, so the cron
  // registration goes straight to BullMQ on the same prefixed queue. The
  // neutron-data worker above still consumes the jobs it produces.
  const scheduler = new Queue(QUEUE_NAME, {
    prefix: QUEUE_PREFIX,
    connection: { url: process.env.REDIS_URL || "redis://localhost:6380" },
  });
  await scheduler.add(FEED_UPDATE_ALL_JOB, {}, { repeat: { pattern: FEED_UPDATE_CRON } });
  await scheduler.add(CLEANUP_JOB, {}, { repeat: { pattern: CLEANUP_CRON } });
  await scheduler.add(ANALYTICS_JOB, {}, { repeat: { pattern: ANALYTICS_CRON } });
  await scheduler.add(DISCOVERY_WARM_JOB, {}, { repeat: { pattern: DISCOVERY_WARM_CRON } });
  context.log(
    `repeatable jobs registered: ${FEED_UPDATE_ALL_JOB}='${FEED_UPDATE_CRON}' ${CLEANUP_JOB}='${CLEANUP_CRON}' ` +
      `${ANALYTICS_JOB}='${ANALYTICS_CRON}' ${DISCOVERY_WARM_JOB}='${DISCOVERY_WARM_CRON}' queue=${QUEUE_PREFIX}:${QUEUE_NAME}`
  );

  // Warm the discovery catalog immediately at boot (fire-and-forget — the
  // API serves curated data instantly either way, this fills enrichment).
  void warmDiscoveryCatalog();

  context.log(
    `ready database=${runtime.drivers.database} queue=${runtime.drivers.queue} mode=${context.mode}`
  );

  return async () => {
    await scheduler.close();
    if (extractQueuePromise) {
      await (await extractQueuePromise).close();
    }
    await runtime.close();
    context.log("shutdown complete");
  };
}
