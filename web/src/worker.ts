import { Queue } from "bullmq";
import crypto from "node:crypto";
import Parser from "rss-parser";
import { eq, and, sql, gte, inArray } from "drizzle-orm";
import { getDataRuntime, QUEUE_NAME, QUEUE_PREFIX } from "./data/runtime.js";
import { getDb } from "./lib/api/db.js";
import { feeds, articles, userArticleStates, readingStats, notifications } from "./data/db/schema.js";
import { fetchFeedXml } from "./services/feed-fetch.js";
import { initializeEmailService, isEmailConfigured, sendEmail } from "./services/email.js";

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

const FEED_UPDATE_CRON = "*/5 * * * *";
const CLEANUP_CRON = "0 3 * * *";
const ANALYTICS_CRON = "0 * * * *";

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

    console.info(`Updating feed: ${feed.title} (${feed.url})`);

    const feedXml = await fetchFeedXml(feed.url);
    const feedData = await parser.parseString(feedXml);

    await db
      .update(feeds)
      .set({
        title: feedData.title || feed.title,
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

      const [existingArticle] = await db
        .select()
        .from(articles)
        .where(and(eq(articles.feedId, feedId), eq(articles.guid, guid)))
        .limit(1);

      if (!existingArticle) {
        const articleData = {
          feedId,
          guid,
          url: item.link || "",
          title: item.title || "Untitled",
          author: item.creator || (item as { author?: string }).author,
          content: (item as { "content:encoded"?: string })["content:encoded"] || item.content,
          summary: item.summary || (item as { description?: string }).description,
          imageUrl: extractItemImageUrl(item),
          publishedAt: item.pubDate ? new Date(item.pubDate) : new Date(),
          categories: item.categories || [],
          enclosures: (item as { enclosure?: unknown }).enclosure
            ? [(item as { enclosure: unknown }).enclosure]
            : [],
          metadata: {
            originalItem: item,
          },
        };

        const [newArticle] = await db
          .insert(articles)
          .values(articleData)
          .returning();

        newArticles.push(newArticle);
      }
    }

    if (newArticles.length > 0) {
      console.info(`Added ${newArticles.length} new articles for feed ${feed.title}`);
    }

    return { feedId, newArticles: newArticles.length };
  } catch (error) {
    console.error(`Failed to update feed ${feedId}:`, error);

    const db = await getDb();
    await db
      .update(feeds)
      .set({
        lastFetchError: error instanceof Error ? error.message : String(error),
        errorCount: sql`${feeds.errorCount} + 1`,
        lastFetchedAt: new Date(),
      })
      .where(eq(feeds.id, feedId));

    throw error;
  }
}

async function processCleanup(): Promise<{ expired: number; inactive: number }> {
  const retentionDays = parseInt(process.env.ARTICLE_RETENTION_DAYS || "90", 10);
  const cutoff = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000);
  const db = await getDb();

  const inactiveFeeds = await db
    .select({ id: feeds.id })
    .from(feeds)
    .where(eq(feeds.isActive, false));

  let inactiveDeleted = 0;
  if (inactiveFeeds.length > 0) {
    const inactiveIds = inactiveFeeds.map((f) => f.id);
    const removed = await db
      .delete(articles)
      .where(inArray(articles.feedId, inactiveIds))
      .returning({ id: articles.id });
    inactiveDeleted = removed.length;
  }

  const expired = await db
    .delete(articles)
    .where(
      sql`COALESCE(${articles.publishedAt}, ${articles.createdAt}) < ${cutoff}`,
    )
    .returning({ id: articles.id });

  console.info(
    `Cleanup complete: ${expired.length} articles past ${retentionDays}-day retention, ` +
      `${inactiveDeleted} from inactive feeds`,
  );

  return { expired: expired.length, inactive: inactiveDeleted };
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
    console.info(`Processing email job for ${email}: ${subject}`);

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

      console.warn(`Email skipped (SMTP not configured) for ${email}: ${subject}`);
      return { success: true, status: "skipped" };
    }

    const sent = await sendEmail({
      to: email,
      subject,
      text: body,
      template,
      data,
    });

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

      console.error(`Email delivery failed for ${email}: ${subject}`);
      return { success: false, status: "failed" };
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

    console.info(`Email sent to ${email}: ${subject}`);
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
  context.log(
    `repeatable jobs registered: ${FEED_UPDATE_ALL_JOB}='${FEED_UPDATE_CRON}' ${CLEANUP_JOB}='${CLEANUP_CRON}' ${ANALYTICS_JOB}='${ANALYTICS_CRON}' queue=${QUEUE_PREFIX}:${QUEUE_NAME}`
  );

  context.log(
    `ready database=${runtime.drivers.database} queue=${runtime.drivers.queue} mode=${context.mode}`
  );

  return async () => {
    await scheduler.close();
    await runtime.close();
    context.log("shutdown complete");
  };
}
