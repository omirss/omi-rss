// Ported from Express services/discovery/index.ts (v0.2.1). Curated-only,
// honest: search/discover return curated feeds (optionally enriched with
// live feed metadata), never fabricated results. Redis usage maps onto the
// runtime cache client.

import { eq, and, desc } from "drizzle-orm";
import Parser from "rss-parser";
import { feeds, articles, folders, userArticleStates, readingStats } from "../data/db/schema.js";
import { getDb } from "../lib/api/db.js";
import { getDataRuntime } from "../data/runtime.js";
import { fetchFeedXml } from "./feed-fetch.js";

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
  name: string;
  description: string;
  feeds: FeedSuggestion[];
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

export class FeedDiscoveryService {
  async discoverFeeds(userId: string, options?: {
    categories?: string[];
    limit?: number;
    language?: string;
  }): Promise<FeedSuggestion[]> {
    try {
      const userInterests = await this.analyzeUserInterests(userId);

      const subscribedFeeds = await this.getUserSubscribedFeeds(userId);
      const subscribedUrls = new Set(subscribedFeeds.map(f => f.url));

      let suggestions: FeedSuggestion[] = [];

      for (const category of CURATED_FEEDS) {
        if (options?.categories && !options.categories.includes(category.name)) {
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

      const enhanced = await Promise.all(
        suggestions.map(async (suggestion) => {
          const metadata = await this.fetchFeedMetadata(suggestion.url);
          return { ...suggestion, ...metadata };
        }),
      );

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
    language?: string;
    limit?: number;
  }): Promise<FeedSuggestion[]> {
    try {
      const results: FeedSuggestion[] = [];
      const queryLower = query.toLowerCase();

      for (const category of CURATED_FEEDS) {
        if (options?.category && category.name !== options.category) {
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

      return Promise.all(
        limited.map(async (result) => {
          const metadata = await this.fetchFeedMetadata(result.url);
          return { ...result, ...metadata };
        }),
      );
    } catch (error) {
      console.error("Failed to search feeds:", error);
      throw error;
    }
  }

  async getRelatedFeeds(feedId: string, limit: number = 10): Promise<FeedSuggestion[]> {
    try {
      const db = await getDb();

      const [feed] = await db
        .select()
        .from(feeds)
        .where(eq(feeds.id, feedId))
        .limit(1);

      if (!feed) {
        throw new Error("Feed not found");
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
  ): Promise<{ imported: number; failed: number; errors: string[] }> {
    try {
      const entries = this.parseOPML(opmlContent);
      const errors: string[] = [];
      let imported = 0;
      let failed = 0;

      const db = await getDb();
      const subscribed = await db
        .select()
        .from(feeds)
        .where(eq(feeds.userId, userId));
      const knownUrls = new Set(subscribed.map(f => f.url));

      for (const entry of entries) {
        if (knownUrls.has(entry.url)) {
          continue;
        }

        try {
          await db.insert(feeds).values({
            userId,
            url: entry.url,
            title: entry.title || "Imported Feed",
            siteUrl: entry.siteUrl || null,
          });
          knownUrls.add(entry.url);
          imported++;
        } catch (error) {
          failed++;
          errors.push(`Failed to import ${entry.title || entry.url}`);
        }
      }

      return { imported, failed, errors };
    } catch (error) {
      console.error("Failed to import OPML:", error);
      throw error;
    }
  }

  private parseOPML(opmlContent: string): Array<{ url: string; title?: string; siteUrl?: string }> {
    const results: Array<{ url: string; title?: string; siteUrl?: string }> = [];
    const outlineRegex = /<outline\b[^>]*>/gi;
    let match: RegExpExecArray | null;

    while ((match = outlineRegex.exec(opmlContent)) !== null) {
      const tag = match[0];
      const xmlUrl = this.getXmlAttribute(tag, "xmlUrl");
      if (!xmlUrl) continue;

      const title = this.getXmlAttribute(tag, "title") || this.getXmlAttribute(tag, "text");
      const htmlUrl = this.getXmlAttribute(tag, "htmlUrl");

      results.push({
        url: this.unescapeXml(xmlUrl),
        title: title ? this.unescapeXml(title) : undefined,
        siteUrl: htmlUrl ? this.unescapeXml(htmlUrl) : undefined,
      });
    }

    return results;
  }

  private getXmlAttribute(tag: string, name: string): string | null {
    const doubleQuoted = tag.match(new RegExp(`${name}\\s*=\\s*"([^"]*)"`, "i"));
    if (doubleQuoted) return doubleQuoted[1];
    const singleQuoted = tag.match(new RegExp(`${name}\\s*=\\s*'([^']*)'`, "i"));
    if (singleQuoted) return singleQuoted[1];
    return null;
  }

  private unescapeXml(text: string): string {
    return text
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'");
  }

  async exportOPML(userId: string): Promise<string> {
    try {
      const db = await getDb();

      const userFeeds = await db
        .select()
        .from(feeds)
        .where(eq(feeds.userId, userId));

      const userFolders = await db
        .select({ id: folders.id, name: folders.name })
        .from(folders)
        .where(eq(folders.userId, userId));

      const folderNamesById = new Map(userFolders.map((folder) => [folder.id, folder.name]));

      let opml = `<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>Omi RSS Feed Export</title>
    <dateCreated>${new Date().toISOString()}</dateCreated>
  </head>
  <body>`;

      const feedsByFolder = new Map<string, typeof userFeeds>();

      for (const feed of userFeeds) {
        const folder = (feed.folderId ? folderNamesById.get(feed.folderId) : undefined) || "Uncategorized";
        if (!feedsByFolder.has(folder)) {
          feedsByFolder.set(folder, []);
        }
        feedsByFolder.get(folder)!.push(feed);
      }

      for (const [folder, folderFeeds] of feedsByFolder) {
        opml += `\n    <outline text="${this.escapeXml(folder)}" title="${this.escapeXml(folder)}">`;

        for (const feed of folderFeeds) {
          opml += `\n      <outline type="rss" text="${this.escapeXml(feed.title)}" title="${this.escapeXml(feed.title)}" xmlUrl="${this.escapeXml(feed.url)}" htmlUrl="${this.escapeXml(feed.siteUrl || "")}" />`;
        }

        opml += "\n    </outline>";
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
