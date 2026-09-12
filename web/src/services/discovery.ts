// Ported from Express services/discovery/index.ts (v0.2.1). Curated-only,
// honest: search/discover return curated feeds (optionally enriched with
// live feed metadata), never fabricated results. Redis usage maps onto the
// runtime cache client.

import { eq, and, desc } from "drizzle-orm";
import Parser from "rss-parser";
import { DOMParser } from "linkedom";
import { feeds, articles, folders, userArticleStates, readingStats } from "../data/db/schema.js";
import { getDb, type Database } from "../lib/api/db.js";
import { AppError } from "../lib/api/errors.js";
import { getDataRuntime } from "../data/runtime.js";
import { assertSafeFeedUrl, fetchFeedXml } from "./feed-fetch.js";

interface FeedSuggestion {
  url: string;
  title: string;
  description?: string;
  category?: string;
  language?: string;
  popularity?: number;
  relevanceScore?: number;
  reason?: string;
  favicon?: string;
  lastUpdated?: Date;
}

interface FeedCategory {
  id: string;
  name: string;
  description: string;
  feeds: FeedSuggestion[];
}

// Category ids are the authoritative wire identifiers (GET /api/discovery/
// categories returns {id, name, description}); callers may also pass the
// exact display name for back-compat.
export function categoryMatchesFilter(filters: string[], category: Pick<FeedCategory, "id" | "name">): boolean {
  const normalized = filters.map(f => f.trim().toLowerCase());
  return normalized.some(
    f => f === category.id.toLowerCase() || f === category.name.toLowerCase(),
  );
}

export const DISCOVERY_CATEGORIES = () =>
  CURATED_FEEDS.map(({ id, name, description }) => ({ id, name, description }));

export function curatedFeedUrls(): string[] {
  const urls = new Set<string>();
  for (const category of CURATED_FEEDS) {
    for (const feed of category.feeds) {
      urls.add(feed.url);
    }
  }
  return [...urls];
}

// Request-path warm trigger: at most one warm pass per cooldown window so
// feeds that never enrich (paywalled/blocked — no cached metadata) don't
// re-trigger a full live pass on every request. The worker cron calls
// warmDiscoveryCatalog directly and bypasses this.
const WARM_TRIGGER_COOLDOWN_MS = 10 * 60 * 1000;
let lastWarmTriggerAt = 0;

function triggerCatalogWarm(): void {
  if (Date.now() - lastWarmTriggerAt < WARM_TRIGGER_COOLDOWN_MS) {
    return;
  }
  lastWarmTriggerAt = Date.now();
  void warmDiscoveryCatalog();
}

// Single-flight catalog warm: populates the feed:metadata:* cache for the
// whole curated catalog. Concurrent callers share one pass; a completed
// warm clears the slot so the worker cron keeps re-refreshing TTLs.
let catalogWarm: Promise<void> | null = null;

export function warmDiscoveryCatalog(): Promise<void> {
  if (!catalogWarm) {
    catalogWarm = (async () => {
      const urls = curatedFeedUrls();
      await Promise.all(urls.map((url) => feedDiscoveryService.fetchFeedMetadata(url)));
      console.info(`Discovery catalog warm complete: ${urls.length} feeds checked`);
    })()
      .catch((error) => {
        console.error("Discovery catalog warm failed:", error);
      })
      .finally(() => {
        catalogWarm = null;
      });
  }
  return catalogWarm;
}

interface UserInterests {
  categories: Map<string, number>;
  keywords: Map<string, number>;
  authors: Map<string, number>;
  sources: Map<string, number>;
  readingTimes: Map<number, number>;
  contentLength: { short: number; medium: number; long: number };
}

const CURATED_FEEDS: FeedCategory[] = [
  {
    id: "technology",
    name: "Technology",
    description: "Latest tech news and developments",
    feeds: [
      { url: "https://techcrunch.com/feed/", title: "TechCrunch", category: "Technology" },
      { url: "https://www.theverge.com/rss/index.xml", title: "The Verge", category: "Technology" },
      { url: "https://feeds.arstechnica.com/arstechnica/index", title: "Ars Technica", category: "Technology" },
      { url: "https://www.wired.com/feed/rss", title: "Wired", category: "Technology" },
      { url: "https://rss.slashdot.org/Slashdot/slashdotMain", title: "Slashdot", category: "Technology" },
      { url: "https://news.ycombinator.com/rss", title: "Hacker News", category: "Technology" },
      { url: "https://feeds.feedburner.com/TechCrunch/startups", title: "TechCrunch Startups", category: "Technology" },
      { url: "https://www.reddit.com/r/technology/.rss", title: "Reddit Technology", category: "Technology" },
    ],
  },
  {
    id: "science",
    name: "Science",
    description: "Scientific discoveries and research",
    feeds: [
      { url: "https://www.nature.com/nature.rss", title: "Nature", category: "Science" },
      { url: "https://www.science.org/rss/news_current.xml", title: "Science Magazine", category: "Science" },
      { url: "https://feeds.sciencedaily.com/sciencedaily", title: "ScienceDaily", category: "Science" },
      { url: "https://www.newscientist.com/feed/home", title: "New Scientist", category: "Science" },
      { url: "https://phys.org/rss-feed/", title: "Phys.org", category: "Science" },
      { url: "https://www.scientificamerican.com/feed/rss/", title: "Scientific American", category: "Science" },
    ],
  },
  {
    id: "business",
    name: "Business & Finance",
    description: "Business news and market analysis",
    feeds: [
      { url: "https://feeds.bloomberg.com/markets/news.rss", title: "Bloomberg Markets", category: "Business" },
      { url: "https://www.ft.com/?format=rss", title: "Financial Times", category: "Business" },
      { url: "https://feeds.wsj.com/xml/rss/3_7085.xml", title: "WSJ Business", category: "Business" },
      { url: "https://fortune.com/feed/", title: "Fortune", category: "Business" },
      { url: "https://www.economist.com/feeds/print-sections/77/business.xml", title: "The Economist Business", category: "Business" },
      { url: "https://www.cnbc.com/id/100003114/device/rss/rss.html", title: "CNBC", category: "Business" },
    ],
  },
  {
    id: "programming",
    name: "Programming & Development",
    description: "Software development and programming",
    feeds: [
      { url: "https://dev.to/feed", title: "DEV Community", category: "Programming" },
      { url: "https://css-tricks.com/feed/", title: "CSS-Tricks", category: "Programming" },
      { url: "https://www.smashingmagazine.com/feed", title: "Smashing Magazine", category: "Programming" },
      { url: "https://stackoverflow.blog/feed/", title: "Stack Overflow Blog", category: "Programming" },
      { url: "https://github.blog/feed/", title: "GitHub Blog", category: "Programming" },
      { url: "https://blog.codinghorror.com/rss/", title: "Coding Horror", category: "Programming" },
    ],
  },
  {
    id: "ai",
    name: "AI & Machine Learning",
    description: "Artificial Intelligence and ML news",
    feeds: [
      { url: "https://openai.com/blog/rss.xml", title: "OpenAI Blog", category: "AI" },
      { url: "https://deepmind.com/blog/feed/basic/", title: "DeepMind Blog", category: "AI" },
      { url: "https://ai.googleblog.com/feeds/posts/default", title: "Google AI Blog", category: "AI" },
      { url: "https://blogs.microsoft.com/ai/feed/", title: "Microsoft AI Blog", category: "AI" },
      { url: "https://machinelearningmastery.com/blog/feed/", title: "Machine Learning Mastery", category: "AI" },
      { url: "https://towardsdatascience.com/feed", title: "Towards Data Science", category: "AI" },
    ],
  },
  {
    id: "news",
    name: "World News",
    description: "Global news and current events",
    feeds: [
      { url: "https://feeds.bbci.co.uk/news/world/rss.xml", title: "BBC World News", category: "News" },
      { url: "https://rss.cnn.com/rss/cnn_world.rss", title: "CNN World", category: "News" },
      { url: "https://www.theguardian.com/world/rss", title: "The Guardian World", category: "News" },
      { url: "https://rss.nytimes.com/services/xml/rss/nyt/World.xml", title: "NY Times World", category: "News" },
      { url: "https://feeds.reuters.com/reuters/worldNews", title: "Reuters World News", category: "News" },
    ],
  },
];

const parser = new Parser();

export interface OpmlImportOutcome {
  imported: number;
  failed: number;
  skipped: number;
  capped: boolean;
  reasons: { invalidUrl: number; duplicate: number; overLimit: number };
  errors: string[];
}

const MAX_OPML_ENTRIES = 500;
const OPML_INSERT_CHUNK = 100;
const OPML_MAX_DEPTH = 32;
const FEED_TITLE_MAX_CHARS = 500;

interface OpmlEntry {
  url: string;
  title?: string;
  siteUrl?: string;
  folderPath: string[];
}

function clampFeedTitle(value: string | undefined): string {
  const source = value && value.trim() ? value : "Imported Feed";
  const chars = Array.from(source);
  return chars.length > FEED_TITLE_MAX_CHARS ? chars.slice(0, FEED_TITLE_MAX_CHARS).join("") : source;
}

export class FeedDiscoveryService {
  async discoverFeeds(userId: string, options?: {
    categories?: string[];
    limit?: number;
  }): Promise<FeedSuggestion[]> {
    try {
      const userInterests = await this.analyzeUserInterests(userId);

      const subscribedFeeds = await this.getUserSubscribedFeeds(userId);
      const subscribedUrls = new Set(subscribedFeeds.map(f => f.url));

      let suggestions: FeedSuggestion[] = [];

      for (const category of CURATED_FEEDS) {
        if (options?.categories && !categoryMatchesFilter(options.categories, category)) {
          continue;
        }

        for (const feed of category.feeds) {
          if (!subscribedUrls.has(feed.url)) {
            suggestions.push({
              ...feed,
              relevanceScore: this.calculateRelevanceScore(feed, userInterests),
            });
          }
        }
      }

      suggestions.sort((a, b) => (b.relevanceScore || 0) - (a.relevanceScore || 0));

      if (options?.limit) {
        suggestions = suggestions.slice(0, options.limit);
      }

      // Request-path enrichment is cache-only (R7 perf): the catalog must
      // respond instantly with curated data. A cache miss kicks off the
      // background warm instead of blocking on a live fetch.
      let coldMetadata = false;
      const enhanced = await Promise.all(
        suggestions.map(async (suggestion) => {
          const metadata = await this.getCachedFeedMetadata(suggestion.url);
          if (Object.keys(metadata).length === 0) coldMetadata = true;
          return { ...suggestion, ...metadata };
        }),
      );

      if (coldMetadata) {
        triggerCatalogWarm();
      }

      const runtime = await getDataRuntime();
      await runtime.cache.set(
        `discovery:suggestions:${userId}`,
        JSON.stringify(enhanced),
        3600,
      );

      return enhanced;
    } catch (error) {
      console.error("Failed to discover feeds:", error);
      throw error;
    }
  }

  async searchPublicFeeds(query: string, options?: {
    category?: string;
    limit?: number;
  }): Promise<FeedSuggestion[]> {
    try {
      const results: FeedSuggestion[] = [];
      const queryLower = query.toLowerCase();

      for (const category of CURATED_FEEDS) {
        if (options?.category && !categoryMatchesFilter([options.category], category)) {
          continue;
        }

        for (const feed of category.feeds) {
          if (
            feed.title.toLowerCase().includes(queryLower) ||
            feed.description?.toLowerCase().includes(queryLower) ||
            feed.category?.toLowerCase().includes(queryLower)
          ) {
            results.push(feed);
          }
        }
      }

      const uniqueResults = Array.from(
        new Map(results.map(r => [r.url, r])).values(),
      );

      uniqueResults.sort((a, b) => {
        const aScore = this.calculateSearchRelevance(a, query);
        const bScore = this.calculateSearchRelevance(b, query);
        return bScore - aScore;
      });

      const limited = options?.limit
        ? uniqueResults.slice(0, options.limit)
        : uniqueResults;

      let coldMetadata = false;
      const enriched = await Promise.all(
        limited.map(async (result) => {
          const metadata = await this.getCachedFeedMetadata(result.url);
          if (Object.keys(metadata).length === 0) coldMetadata = true;
          return { ...result, ...metadata };
        }),
      );

      if (coldMetadata) {
        triggerCatalogWarm();
      }

      return enriched;
    } catch (error) {
      console.error("Failed to search feeds:", error);
      throw error;
    }
  }

  async getRelatedFeeds(userId: string, feedId: string, limit: number = 10): Promise<FeedSuggestion[]> {
    try {
      const db = await getDb();

      const [feed] = await db
        .select()
        .from(feeds)
        .where(
          and(
            eq(feeds.id, feedId),
            eq(feeds.userId, userId),
          ),
        )
        .limit(1);

      if (!feed) {
        throw new AppError("Feed not found", 404);
      }

      const recentArticles = await db
        .select()
        .from(articles)
        .where(eq(articles.feedId, feedId))
        .orderBy(desc(articles.publishedAt))
        .limit(20);

      const topics = this.extractTopicsFromArticles(recentArticles);

      const relatedFeeds: FeedSuggestion[] = [];

      for (const category of CURATED_FEEDS) {
        for (const candidateFeed of category.feeds) {
          if (candidateFeed.url === feed.url) continue;

          const similarity = this.calculateTopicSimilarity(topics, candidateFeed);
          if (similarity > 0.5) {
            relatedFeeds.push({
              ...candidateFeed,
              relevanceScore: similarity,
              reason: `Similar to ${feed.title}`,
            });
          }
        }
      }

      return relatedFeeds
        .sort((a, b) => (b.relevanceScore || 0) - (a.relevanceScore || 0))
        .slice(0, limit);
    } catch (error) {
      console.error("Failed to get related feeds:", error);
      throw error;
    }
  }

  private async analyzeUserInterests(userId: string): Promise<UserInterests> {
    const db = await getDb();

    const readArticles = await db
      .select({
        article: articles,
      })
      .from(userArticleStates)
      .innerJoin(articles, eq(articles.id, userArticleStates.articleId))
      .where(
        and(
          eq(userArticleStates.userId, userId),
          eq(userArticleStates.isRead, true),
        ),
      )
      .limit(1000);

    const interests: UserInterests = {
      categories: new Map(),
      keywords: new Map(),
      authors: new Map(),
      sources: new Map(),
      readingTimes: new Map(),
      contentLength: { short: 0, medium: 0, long: 0 },
    };

    for (const { article } of readArticles) {
      if (article.categories && Array.isArray(article.categories)) {
        for (const category of article.categories as string[]) {
          interests.categories.set(
            category,
            (interests.categories.get(category) || 0) + 1,
          );
        }
      }

      if (article.author) {
        interests.authors.set(
          article.author,
          (interests.authors.get(article.author) || 0) + 1,
        );
      }

      const wordCount = (article.content || "").split(/\s+/).length;
      if (wordCount < 500) {
        interests.contentLength.short++;
      } else if (wordCount < 1500) {
        interests.contentLength.medium++;
      } else {
        interests.contentLength.long++;
      }
    }

    const stats = await db
      .select()
      .from(readingStats)
      .where(eq(readingStats.userId, userId))
      .orderBy(desc(readingStats.date))
      .limit(30);

    for (const stat of stats) {
      const distribution = stat.hourlyDistribution as Record<string, number> | null;
      if (distribution) {
        Object.entries(distribution).forEach(([hour, count]) => {
          const h = parseInt(hour);
          interests.readingTimes.set(h, (interests.readingTimes.get(h) || 0) + count);
        });
      }
    }

    return interests;
  }

  private calculateRelevanceScore(feed: FeedSuggestion, interests: UserInterests): number {
    let score = 0;

    if (feed.category && interests.categories.has(feed.category)) {
      score += interests.categories.get(feed.category)! * 0.3;
    }

    const feedText = `${feed.title} ${feed.description || ""}`.toLowerCase();
    for (const [keyword, count] of interests.keywords) {
      if (feedText.includes(keyword.toLowerCase())) {
        score += count * 0.1;
      }
    }

    return Math.min(score / 100, 1);
  }

  // Cache-only variant for the request path: never fetches live. A cache
  // miss returns {} so the curated fields survive untouched, and a cache
  // outage degrades to the curated catalog instead of failing the request.
  private async getCachedFeedMetadata(url: string): Promise<Partial<FeedSuggestion>> {
    try {
      const runtime = await getDataRuntime();
      const cached = await runtime.cache.get(`feed:metadata:${url}`);
      return cached ? (JSON.parse(cached) as Partial<FeedSuggestion>) : {};
    } catch {
      return {};
    }
  }

  async fetchFeedMetadata(url: string): Promise<Partial<FeedSuggestion>> {
    try {
      const runtime = await getDataRuntime();
      const cached = await runtime.cache.get(`feed:metadata:${url}`);
      if (cached) {
        return JSON.parse(cached) as Partial<FeedSuggestion>;
      }

      const xml = await fetchFeedXml(url);
      const feed = (await parser.parseString(xml)) as {
        title?: string;
        description?: string;
        language?: string;
        lastBuildDate?: Date;
      };

      const metadata: Partial<FeedSuggestion> = {
        title: feed.title || "Unknown Feed",
        description: feed.description,
        language: feed.language,
        lastUpdated: feed.lastBuildDate ? new Date(feed.lastBuildDate) : undefined,
      };

      await runtime.cache.set(
        `feed:metadata:${url}`,
        JSON.stringify(metadata),
        86400,
      );

      return metadata;
    } catch (error) {
      console.error(`Failed to fetch metadata for ${url}:`, error);
      return {};
    }
  }

  private calculateSearchRelevance(feed: FeedSuggestion, query: string): number {
    const queryLower = query.toLowerCase();
    const titleMatch = feed.title.toLowerCase().includes(queryLower) ? 0.5 : 0;
    const descMatch = (feed.description || "").toLowerCase().includes(queryLower) ? 0.3 : 0;
    const categoryMatch = (feed.category || "").toLowerCase().includes(queryLower) ? 0.2 : 0;

    return titleMatch + descMatch + categoryMatch;
  }

  private getUserSubscribedFeeds(userId: string) {
    return getDb()
      .then(db =>
        db
          .select()
          .from(feeds)
          .where(eq(feeds.userId, userId)),
      );
  }

  private extractTopicsFromArticles(articleList: Array<{ categories: unknown }>): string[] {
    const topics = new Set<string>();

    for (const article of articleList) {
      if (article.categories && Array.isArray(article.categories)) {
        article.categories.forEach((cat: string) => topics.add(cat));
      }
    }

    return Array.from(topics);
  }

  private calculateTopicSimilarity(topics: string[], feed: FeedSuggestion): number {
    if (!feed.category) return 0;

    const feedTopics = feed.category.toLowerCase().split(/[,\s]+/);
    const topicsLower = topics.map(t => t.toLowerCase());

    let matches = 0;
    for (const feedTopic of feedTopics) {
      if (topicsLower.some(t => t.includes(feedTopic) || feedTopic.includes(t))) {
        matches++;
      }
    }

    return matches / Math.max(feedTopics.length, topics.length);
  }

  async importOPML(
    userId: string,
    opmlContent: string,
  ): Promise<OpmlImportOutcome> {
    const entries = this.parseOPML(opmlContent);
    const capped = entries.length > MAX_OPML_ENTRIES;

    const reasons = { invalidUrl: 0, duplicate: 0, overLimit: 0 };
    const errors: string[] = [];
    let failed = 0;

    const db = await getDb();
    const subscribed = await db
      .select({ url: feeds.url })
      .from(feeds)
      .where(eq(feeds.userId, userId));
    const knownUrls = new Set(subscribed.map(f => f.url));

    const toInsert: Array<{ row: typeof feeds.$inferInsert; folderPath: string[] }> = [];
    const usedFolderPaths = new Set<string>();

    for (let index = 0; index < entries.length; index++) {
      const entry = entries[index];

      if (index >= MAX_OPML_ENTRIES) {
        reasons.overLimit++;
        continue;
      }

      if (knownUrls.has(entry.url)) {
        reasons.duplicate++;
        continue;
      }

      try {
        await assertSafeFeedUrl(entry.url);
      } catch {
        reasons.invalidUrl++;
        errors.push(`Skipped unsafe or invalid URL: ${entry.title || entry.url}`);
        continue;
      }

      knownUrls.add(entry.url);
      if (entry.folderPath.length > 0) {
        usedFolderPaths.add(entry.folderPath.join("\u0000"));
      }
      toInsert.push({
        row: {
          userId,
          url: entry.url,
          title: clampFeedTitle(entry.title),
          siteUrl: entry.siteUrl || null,
        },
        folderPath: entry.folderPath,
      });
    }

    let imported = 0;

    if (toInsert.length > 0) {
      await db.transaction(async (tx) => {
        // Folder chains are created first, reusing existing folders by
        // (parent, name) so re-imports never duplicate labels.
        const folderIdByPath = await this.ensureFolderPaths(
          tx,
          userId,
          [...usedFolderPaths].map((joined) => joined.split("\u0000")),
        );

        for (let i = 0; i < toInsert.length; i += OPML_INSERT_CHUNK) {
          const chunk = toInsert.slice(i, i + OPML_INSERT_CHUNK);
          try {
            // Per-chunk SAVEPOINT: one bad chunk fails independently and
            // the earlier chunks still commit — a failure inside the outer
            // transaction no longer rolls back everything while the counter
            // still reported it imported.
            const inserted = await tx.transaction(async (sp) =>
              sp
                .insert(feeds)
                .values(
                  chunk.map(({ row, folderPath }) => ({
                    ...row,
                    folderId:
                      folderPath.length > 0 ? folderIdByPath.get(folderPath.join("\u0000")) : undefined,
                  })),
                )
                .onConflictDoNothing({ target: [feeds.userId, feeds.url] })
                .returning({ id: feeds.id }),
            );
            imported += inserted.length;
          } catch (error) {
            failed += chunk.length;
            console.error("Failed to import OPML chunk:", error);
            errors.push(`Failed to import ${chunk.length} feed(s) in batch ${Math.floor(i / OPML_INSERT_CHUNK) + 1}`);
          }
        }
      });
    }

    return {
      imported,
      failed,
      skipped: reasons.invalidUrl + reasons.duplicate + reasons.overLimit,
      capped,
      reasons,
      errors,
    };
  }

  // Tree-walking OPML parse (linkedom): enclosing folder outlines become a
  // folderPath per feed, so hierarchy round-trips instead of being discarded
  // by the old flat <outline> regex. DOCTYPE is rejected (entity expansion)
  // and depth is capped.
  private parseOPML(opmlContent: string): OpmlEntry[] {
    if (/<!DOCTYPE/i.test(opmlContent)) {
      throw new AppError("OPML with a DOCTYPE declaration is not accepted", 400);
    }

    // XML parsing (not HTML): the HTML parser re-nests unknown elements
    // like <opml> and silently re-parents the outlines.
    const document = new DOMParser().parseFromString(opmlContent, "text/xml");
    const results: OpmlEntry[] = [];

    const walk = (element: unknown, path: string[], depth: number): void => {
      if (depth > OPML_MAX_DEPTH) {
        throw new AppError(`OPML nested deeper than ${OPML_MAX_DEPTH} levels`, 400);
      }
      for (const child of (element as { children: Iterable<unknown> }).children) {
        const node = child as {
          tagName?: string;
          getAttribute?: (name: string) => string | null;
          children?: Iterable<unknown>;
        };
        if (node.tagName?.toLowerCase() !== "outline") continue;

        const xmlUrl = node.getAttribute?.("xmlUrl");
        if (xmlUrl) {
          const title = node.getAttribute?.("title") || node.getAttribute?.("text");
          const htmlUrl = node.getAttribute?.("htmlUrl");
          results.push({
            url: xmlUrl,
            title: title || undefined,
            siteUrl: htmlUrl || undefined,
            folderPath: [...path],
          });
          continue;
        }

        const name = (node.getAttribute?.("title") || node.getAttribute?.("text") || "").trim();
        walk(node, name ? [...path, name] : path, depth + 1);
      }
    };

    walk(document.querySelector("body") ?? document, [], 0);
    return results;
  }

  // Creates the folder chains referenced by the import inside the caller's
  // transaction, reusing existing folders by (parent, name). Returns a map
  // of "\u0000"-joined path → folder id.
  private async ensureFolderPaths(
    tx: Parameters<Parameters<Database["transaction"]>[0]>[0],
    userId: string,
    paths: string[][],
  ): Promise<Map<string, string>> {
    const existing = await tx
      .select({ id: folders.id, name: folders.name, parentId: folders.parentId })
      .from(folders)
      .where(eq(folders.userId, userId));

    const byParentName = new Map<string, string>();
    for (const folder of existing) {
      byParentName.set(`${folder.parentId ?? ""}\u0000${folder.name}`, folder.id);
    }

    let nextPosition = existing.length + 1;
    const idByPath = new Map<string, string>();
    const sortedPaths = [...paths].sort((a, b) => a.length - b.length);

    for (const path of sortedPaths) {
      let parentId: string | null = null;
      let partial: string[] = [];
      for (const segment of path) {
        partial = [...partial, segment];
        const key: string = partial.join("\u0000");
        const parentKey: string = `${parentId ?? ""}\u0000${segment}`;
        let folderId: string | undefined = byParentName.get(parentKey) ?? idByPath.get(key);
        if (!folderId) {
          const created: Array<{ id: string }> = await tx
            .insert(folders)
            .values({ userId, name: segment, parentId: parentId ?? undefined, position: nextPosition++ })
            .returning({ id: folders.id });
          folderId = created[0]?.id;
        }
        if (!folderId) continue;
        idByPath.set(key, folderId);
        parentId = folderId;
      }
    }

    return idByPath;
  }

  async exportOPML(userId: string): Promise<string> {
    try {
      const db = await getDb();

      const userFeeds = await db
        .select()
        .from(feeds)
        .where(eq(feeds.userId, userId));

      const userFolders = await db
        .select({ id: folders.id, name: folders.name, parentId: folders.parentId })
        .from(folders)
        .where(eq(folders.userId, userId));

      const folderById = new Map(userFolders.map((folder) => [folder.id, folder]));

      const feedsByFolder = new Map<string | null, typeof userFeeds>();
      const childFoldersByParent = new Map<string | null, typeof userFolders>();
      for (const folder of userFolders) {
        const siblings = childFoldersByParent.get(folder.parentId) ?? [];
        siblings.push(folder);
        childFoldersByParent.set(folder.parentId, siblings);
      }

      // Folders orphaned by a dangling parentId export as roots instead of
      // disappearing.
      const rootFolders: typeof userFolders = [
        ...(childFoldersByParent.get(null) ?? []),
      ];
      for (const folder of userFolders) {
        if (folder.parentId !== null && !folderById.has(folder.parentId)) {
          rootFolders.push(folder);
        }
      }

      // Page feeds are excluded: they scrape a selector, not an RSS URL,
      // and do not round-trip as xmlUrl outlines (v0.4.1 audit).
      for (const feed of userFeeds) {
        if (feed.sourceType === "page") continue;
        const list = feedsByFolder.get(feed.folderId ?? null) ?? [];
        list.push(feed);
        feedsByFolder.set(feed.folderId ?? null, list);
      }

      const outlineForFeed = (feed: (typeof userFeeds)[number], indent: string): string => {
        // customTitle wins: it is the name the user actually chose.
        const title = feed.customTitle || feed.title;
        return `\n${indent}<outline type="rss" text="${this.escapeXml(title)}" title="${this.escapeXml(title)}" xmlUrl="${this.escapeXml(feed.url)}" htmlUrl="${this.escapeXml(feed.siteUrl || "")}" />`;
      };

      const outlineForFolder = (folder: (typeof userFolders)[number], indent: string, ancestors: Set<string>): string => {
        let opml = `\n${indent}<outline text="${this.escapeXml(folder.name)}" title="${this.escapeXml(folder.name)}">`;
        for (const feed of feedsByFolder.get(folder.id) ?? []) {
          opml += outlineForFeed(feed, `${indent}  `);
        }
        // Cycle guard: a folder never recurses into its own ancestry.
        const nextAncestors = new Set([...ancestors, folder.id]);
        for (const child of childFoldersByParent.get(folder.id) ?? []) {
          if (nextAncestors.has(child.id)) continue;
          opml += outlineForFolder(child, `${indent}  `, nextAncestors);
        }
        return `${opml}\n${indent}</outline>`;
      };

      let opml = `<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>Omi RSS Feed Export</title>
    <dateCreated>${new Date().toISOString()}</dateCreated>
  </head>
  <body>`;

      // Root feeds sit directly in <body> — no synthetic "Uncategorized".
      for (const feed of feedsByFolder.get(null) ?? []) {
        opml += outlineForFeed(feed, "    ");
      }

      for (const folder of rootFolders) {
        opml += outlineForFolder(folder, "    ", new Set());
      }

      opml += "\n  </body>\n</opml>";

      return opml;
    } catch (error) {
      console.error("Failed to export OPML:", error);
      throw error;
    }
  }

  private escapeXml(text: string): string {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&apos;");
  }
}

export const feedDiscoveryService = new FeedDiscoveryService();
