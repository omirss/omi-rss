import { getDb } from '../../database';
import { 
  feeds, 
  articles, 
  userArticleStates,
  aiAnalysis,
  users,
  readingStats,
} from '../../database/schema';
import { eq, and, gt, sql, desc, asc, inArray, like, notInArray } from 'drizzle-orm';
import { logger } from '../../utils/logger';
import { getRedis } from '../redis';
import { aiService } from '../ai';
import axios from 'axios';
import Parser from 'rss-parser';
import { v4 as uuidv4 } from 'uuid';

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
  readingTimes: Map<number, number>; // hour -> count
  contentLength: { short: number; medium: number; long: number };
}

export class FeedDiscoveryService {
  private redis = getRedis();
  private db = getDb();
  private parser = new Parser();
  
  // Curated feed collections
  private curatedFeeds: FeedCategory[] = [
    {
      name: 'Technology',
      description: 'Latest tech news and developments',
      feeds: [
        { url: 'https://techcrunch.com/feed/', title: 'TechCrunch', category: 'Technology' },
        { url: 'https://www.theverge.com/rss/index.xml', title: 'The Verge', category: 'Technology' },
        { url: 'https://feeds.arstechnica.com/arstechnica/index', title: 'Ars Technica', category: 'Technology' },
        { url: 'https://www.wired.com/feed/rss', title: 'Wired', category: 'Technology' },
        { url: 'https://rss.slashdot.org/Slashdot/slashdotMain', title: 'Slashdot', category: 'Technology' },
        { url: 'https://news.ycombinator.com/rss', title: 'Hacker News', category: 'Technology' },
        { url: 'https://feeds.feedburner.com/TechCrunch/startups', title: 'TechCrunch Startups', category: 'Technology' },
        { url: 'https://www.reddit.com/r/technology/.rss', title: 'Reddit Technology', category: 'Technology' },
      ],
    },
    {
      name: 'Science',
      description: 'Scientific discoveries and research',
      feeds: [
        { url: 'https://www.nature.com/nature.rss', title: 'Nature', category: 'Science' },
        { url: 'https://www.science.org/rss/news_current.xml', title: 'Science Magazine', category: 'Science' },
        { url: 'https://feeds.sciencedaily.com/sciencedaily', title: 'ScienceDaily', category: 'Science' },
        { url: 'https://www.newscientist.com/feed/home', title: 'New Scientist', category: 'Science' },
        { url: 'https://phys.org/rss-feed/', title: 'Phys.org', category: 'Science' },
        { url: 'https://www.scientificamerican.com/feed/rss/', title: 'Scientific American', category: 'Science' },
      ],
    },
    {
      name: 'Business & Finance',
      description: 'Business news and market analysis',
      feeds: [
        { url: 'https://feeds.bloomberg.com/markets/news.rss', title: 'Bloomberg Markets', category: 'Business' },
        { url: 'https://www.ft.com/?format=rss', title: 'Financial Times', category: 'Business' },
        { url: 'https://feeds.wsj.com/xml/rss/3_7085.xml', title: 'WSJ Business', category: 'Business' },
        { url: 'https://fortune.com/feed/', title: 'Fortune', category: 'Business' },
        { url: 'https://www.economist.com/feeds/print-sections/77/business.xml', title: 'The Economist Business', category: 'Business' },
        { url: 'https://www.cnbc.com/id/100003114/device/rss/rss.html', title: 'CNBC', category: 'Business' },
      ],
    },
    {
      name: 'Programming & Development',
      description: 'Software development and programming',
      feeds: [
        { url: 'https://dev.to/feed', title: 'DEV Community', category: 'Programming' },
        { url: 'https://css-tricks.com/feed/', title: 'CSS-Tricks', category: 'Programming' },
        { url: 'https://www.smashingmagazine.com/feed', title: 'Smashing Magazine', category: 'Programming' },
        { url: 'https://stackoverflow.blog/feed/', title: 'Stack Overflow Blog', category: 'Programming' },
        { url: 'https://github.blog/feed/', title: 'GitHub Blog', category: 'Programming' },
        { url: 'https://blog.codinghorror.com/rss/', title: 'Coding Horror', category: 'Programming' },
      ],
    },
    {
      name: 'AI & Machine Learning',
      description: 'Artificial Intelligence and ML news',
      feeds: [
        { url: 'https://openai.com/blog/rss.xml', title: 'OpenAI Blog', category: 'AI' },
        { url: 'https://deepmind.com/blog/feed/basic/', title: 'DeepMind Blog', category: 'AI' },
        { url: 'https://ai.googleblog.com/feeds/posts/default', title: 'Google AI Blog', category: 'AI' },
        { url: 'https://blogs.microsoft.com/ai/feed/', title: 'Microsoft AI Blog', category: 'AI' },
        { url: 'https://machinelearningmastery.com/blog/feed/', title: 'Machine Learning Mastery', category: 'AI' },
        { url: 'https://towardsdatascience.com/feed', title: 'Towards Data Science', category: 'AI' },
      ],
    },
    {
      name: 'World News',
      description: 'Global news and current events',
      feeds: [
        { url: 'https://feeds.bbci.co.uk/news/world/rss.xml', title: 'BBC World News', category: 'News' },
        { url: 'https://rss.cnn.com/rss/cnn_world.rss', title: 'CNN World', category: 'News' },
        { url: 'https://www.theguardian.com/world/rss', title: 'The Guardian World', category: 'News' },
        { url: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml', title: 'NY Times World', category: 'News' },
        { url: 'https://feeds.reuters.com/reuters/worldNews', title: 'Reuters World News', category: 'News' },
      ],
    },
  ];

  async discoverFeeds(userId: string, options?: {
    categories?: string[];
    limit?: number;
    language?: string;
  }): Promise<FeedSuggestion[]> {
    try {
      // Get user interests
      const userInterests = await this.analyzeUserInterests(userId);
      
      // Get already subscribed feeds
      const subscribedFeeds = await this.getUserSubscribedFeeds(userId);
      const subscribedUrls = new Set(subscribedFeeds.map(f => f.url));

      // Filter curated feeds
      let suggestions: FeedSuggestion[] = [];
      
      for (const category of this.curatedFeeds) {
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

      // Sort by relevance score
      suggestions.sort((a, b) => (b.relevanceScore || 0) - (a.relevanceScore || 0));

      // Apply limit
      if (options?.limit) {
        suggestions = suggestions.slice(0, options.limit);
      }

      // Enhance with additional metadata
      const enhanced = await Promise.all(
        suggestions.map(async (suggestion) => {
          const metadata = await this.fetchFeedMetadata(suggestion.url);
          return { ...suggestion, ...metadata };
        })
      );

      // Cache results
      await this.redis.set(
        `discovery:suggestions:${userId}`,
        JSON.stringify(enhanced),
        'EX',
        3600 // 1 hour
      );

      return enhanced;
    } catch (error) {
      logger.error('Failed to discover feeds:', error);
      throw error;
    }
  }

  async generateCustomFeed(userId: string, prompt: string): Promise<FeedSuggestion[]> {
    try {
      // Use AI to understand the prompt and generate feed suggestions
      const analysis = await aiService.generateContent(userId, {
        prompt: `Based on this user request: "${prompt}", suggest 5-10 RSS feeds that would match their interests. 
        Format the response as a JSON array with objects containing: url, title, description, category, and reason.
        Focus on active, high-quality feeds that publish regularly.`,
        temperature: 0.7,
        maxTokens: 1000,
      });

      let suggestions: FeedSuggestion[] = [];
      
      try {
        // Parse AI response
        const jsonMatch = analysis.text.match(/\[[\s\S]*\]/);
        if (jsonMatch) {
          suggestions = JSON.parse(jsonMatch[0]);
        }
      } catch (parseError) {
        logger.error('Failed to parse AI response:', parseError);
        
        // Fallback to keyword-based search
        suggestions = await this.searchFeedsByKeywords(prompt);
      }

      // Validate and enhance suggestions
      const validated = await Promise.all(
        suggestions.map(async (suggestion) => {
          const isValid = await this.validateFeedUrl(suggestion.url);
          if (isValid) {
            const metadata = await this.fetchFeedMetadata(suggestion.url);
            return { ...suggestion, ...metadata };
          }
          return null;
        })
      );

      return validated.filter((s): s is FeedSuggestion => s !== null);
    } catch (error) {
      logger.error('Failed to generate custom feed:', error);
      throw error;
    }
  }

  async searchPublicFeeds(query: string, options?: {
    category?: string;
    language?: string;
    limit?: number;
  }): Promise<FeedSuggestion[]> {
    try {
      // Search in our curated database first
      const results: FeedSuggestion[] = [];
      const queryLower = query.toLowerCase();

      for (const category of this.curatedFeeds) {
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

      // Search using external feed search APIs
      const externalResults = await this.searchExternalFeedDirectories(query, options);
      results.push(...externalResults);

      // Remove duplicates
      const uniqueResults = Array.from(
        new Map(results.map(r => [r.url, r])).values()
      );

      // Sort by relevance
      uniqueResults.sort((a, b) => {
        const aScore = this.calculateSearchRelevance(a, query);
        const bScore = this.calculateSearchRelevance(b, query);
        return bScore - aScore;
      });

      // Apply limit
      const limited = options?.limit 
        ? uniqueResults.slice(0, options.limit)
        : uniqueResults;

      // Enhance with metadata
      return Promise.all(
        limited.map(async (result) => {
          const metadata = await this.fetchFeedMetadata(result.url);
          return { ...result, ...metadata };
        })
      );
    } catch (error) {
      logger.error('Failed to search feeds:', error);
      throw error;
    }
  }

  async getTrendingFeeds(options?: {
    timeframe?: 'day' | 'week' | 'month';
    category?: string;
    limit?: number;
  }): Promise<FeedSuggestion[]> {
    try {
      // Get trending feeds based on global usage
      const timeframe = options?.timeframe || 'week';
      const limit = options?.limit || 20;

      // This would typically query a global analytics database
      // For now, we'll return popular feeds with simulated popularity scores
      const trendingFeeds = this.curatedFeeds
        .flatMap(category => {
          if (options?.category && category.name !== options.category) {
            return [];
          }
          return category.feeds.map(feed => ({
            ...feed,
            popularity: Math.random() * 1000, // Simulated popularity
          }));
        })
        .sort((a, b) => (b.popularity || 0) - (a.popularity || 0))
        .slice(0, limit);

      // Enhance with metadata
      return Promise.all(
        trendingFeeds.map(async (feed) => {
          const metadata = await this.fetchFeedMetadata(feed.url);
          return { ...feed, ...metadata };
        })
      );
    } catch (error) {
      logger.error('Failed to get trending feeds:', error);
      throw error;
    }
  }

  async getRelatedFeeds(feedId: string, limit: number = 10): Promise<FeedSuggestion[]> {
    try {
      // Get the feed details
      const [feed] = await this.db
        .select()
        .from(feeds)
        .where(eq(feeds.id, feedId))
        .limit(1);

      if (!feed) {
        throw new Error('Feed not found');
      }

      // Get recent articles from this feed
      const recentArticles = await this.db
        .select()
        .from(articles)
        .where(eq(articles.feedId, feedId))
        .orderBy(desc(articles.publishedAt))
        .limit(20);

      // Analyze content to find related topics
      const topics = await this.extractTopicsFromArticles(recentArticles);
      
      // Find feeds with similar topics
      const relatedFeeds: FeedSuggestion[] = [];
      
      for (const category of this.curatedFeeds) {
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

      // Sort by similarity and limit
      return relatedFeeds
        .sort((a, b) => (b.relevanceScore || 0) - (a.relevanceScore || 0))
        .slice(0, limit);
    } catch (error) {
      logger.error('Failed to get related feeds:', error);
      throw error;
    }
  }

  async recommendFeedsBasedOnReadingHistory(userId: string, limit: number = 20): Promise<FeedSuggestion[]> {
    try {
      // Analyze user's reading patterns
      const interests = await this.analyzeUserInterests(userId);
      
      // Get collaborative filtering recommendations
      const collaborativeRecs = await this.getCollaborativeRecommendations(userId);
      
      // Get content-based recommendations
      const contentRecs = await this.getContentBasedRecommendations(userId, interests);
      
      // Merge and deduplicate recommendations
      const allRecs = [...collaborativeRecs, ...contentRecs];
      const uniqueRecs = Array.from(
        new Map(allRecs.map(r => [r.url, r])).values()
      );

      // Sort by combined score
      uniqueRecs.sort((a, b) => (b.relevanceScore || 0) - (a.relevanceScore || 0));

      // Apply limit and enhance
      const limited = uniqueRecs.slice(0, limit);
      
      return Promise.all(
        limited.map(async (rec) => {
          const metadata = await this.fetchFeedMetadata(rec.url);
          return { ...rec, ...metadata };
        })
      );
    } catch (error) {
      logger.error('Failed to recommend feeds:', error);
      throw error;
    }
  }

  private async analyzeUserInterests(userId: string): Promise<UserInterests> {
    // Get user's reading history
    const readArticles = await this.db
      .select({
        article: articles,
        state: userArticleStates,
      })
      .from(userArticleStates)
      .innerJoin(articles, eq(articles.id, userArticleStates.articleId))
      .where(
        and(
          eq(userArticleStates.userId, userId),
          eq(userArticleStates.isRead, true)
        )
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

    // Analyze categories
    for (const { article } of readArticles) {
      // Categories
      if (article.categories && Array.isArray(article.categories)) {
        for (const category of article.categories) {
          interests.categories.set(
            category,
            (interests.categories.get(category) || 0) + 1
          );
        }
      }

      // Authors
      if (article.author) {
        interests.authors.set(
          article.author,
          (interests.authors.get(article.author) || 0) + 1
        );
      }

      // Content length preferences
      const wordCount = (article.content || '').split(/\s+/).length;
      if (wordCount < 500) {
        interests.contentLength.short++;
      } else if (wordCount < 1500) {
        interests.contentLength.medium++;
      } else {
        interests.contentLength.long++;
      }
    }

    // Get reading time patterns
    const readingStats = await this.db
      .select()
      .from(readingStats)
      .where(eq(readingStats.userId, userId))
      .orderBy(desc(readingStats.date))
      .limit(30);

    for (const stat of readingStats) {
      if (stat.hourlyDistribution) {
        Object.entries(stat.hourlyDistribution).forEach(([hour, count]) => {
          const h = parseInt(hour);
          interests.readingTimes.set(h, (interests.readingTimes.get(h) || 0) + count as number);
        });
      }
    }

    return interests;
  }

  private calculateRelevanceScore(feed: FeedSuggestion, interests: UserInterests): number {
    let score = 0;

    // Category match
    if (feed.category && interests.categories.has(feed.category)) {
      score += interests.categories.get(feed.category)! * 0.3;
    }

    // Keyword match in title/description
    const feedText = `${feed.title} ${feed.description || ''}`.toLowerCase();
    for (const [keyword, count] of interests.keywords) {
      if (feedText.includes(keyword.toLowerCase())) {
        score += count * 0.1;
      }
    }

    // Normalize score to 0-1 range
    return Math.min(score / 100, 1);
  }

  private async fetchFeedMetadata(url: string): Promise<Partial<FeedSuggestion>> {
    try {
      // Check cache first
      const cached = await this.redis.get(`feed:metadata:${url}`);
      if (cached) {
        return JSON.parse(cached);
      }

      // Parse feed
      const feed = await this.parser.parseURL(url);
      
      const metadata: Partial<FeedSuggestion> = {
        title: feed.title || 'Unknown Feed',
        description: feed.description,
        language: feed.language,
        lastUpdated: feed.lastBuildDate ? new Date(feed.lastBuildDate) : undefined,
        favicon: feed.image?.url,
      };

      // Cache metadata
      await this.redis.set(
        `feed:metadata:${url}`,
        JSON.stringify(metadata),
        'EX',
        86400 // 24 hours
      );

      return metadata;
    } catch (error) {
      logger.error(`Failed to fetch metadata for ${url}:`, error);
      return {};
    }
  }

  private async validateFeedUrl(url: string): Promise<boolean> {
    try {
      const response = await axios.head(url, { timeout: 5000 });
      return response.status === 200;
    } catch {
      return false;
    }
  }

  private async searchFeedsByKeywords(keywords: string): Promise<FeedSuggestion[]> {
    const keywordList = keywords.toLowerCase().split(/\s+/);
    const results: FeedSuggestion[] = [];

    for (const category of this.curatedFeeds) {
      for (const feed of category.feeds) {
        const feedText = `${feed.title} ${feed.description || ''} ${feed.category || ''}`.toLowerCase();
        const matches = keywordList.filter(kw => feedText.includes(kw)).length;
        
        if (matches > 0) {
          results.push({
            ...feed,
            relevanceScore: matches / keywordList.length,
          });
        }
      }
    }

    return results.sort((a, b) => (b.relevanceScore || 0) - (a.relevanceScore || 0));
  }

  private async searchExternalFeedDirectories(
    query: string,
    options?: { category?: string; language?: string }
  ): Promise<FeedSuggestion[]> {
    // This would integrate with external feed directories
    // For now, return empty array
    return [];
  }

  private calculateSearchRelevance(feed: FeedSuggestion, query: string): number {
    const queryLower = query.toLowerCase();
    const titleMatch = feed.title.toLowerCase().includes(queryLower) ? 0.5 : 0;
    const descMatch = (feed.description || '').toLowerCase().includes(queryLower) ? 0.3 : 0;
    const categoryMatch = (feed.category || '').toLowerCase().includes(queryLower) ? 0.2 : 0;
    
    return titleMatch + descMatch + categoryMatch;
  }

  private async getUserSubscribedFeeds(userId: string) {
    return this.db
      .select()
      .from(feeds)
      .where(eq(feeds.userId, userId));
  }

  private async extractTopicsFromArticles(articles: any[]): Promise<string[]> {
    const topics = new Set<string>();
    
    for (const article of articles) {
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

  private async getCollaborativeRecommendations(userId: string): Promise<FeedSuggestion[]> {
    // Find users with similar reading patterns
    const similarUsers = await this.findSimilarUsers(userId);
    
    // Get feeds that similar users subscribe to
    const recommendations: Map<string, number> = new Map();
    
    for (const similarUser of similarUsers) {
      const userFeeds = await this.getUserSubscribedFeeds(similarUser.userId);
      
      for (const feed of userFeeds) {
        const score = recommendations.get(feed.url) || 0;
        recommendations.set(feed.url, score + similarUser.similarity);
      }
    }

    // Convert to suggestions
    const suggestions: FeedSuggestion[] = [];
    for (const [url, score] of recommendations) {
      // Skip if user already subscribes
      const userFeeds = await this.getUserSubscribedFeeds(userId);
      if (userFeeds.some(f => f.url === url)) continue;

      suggestions.push({
        url,
        title: 'Unknown', // Will be enhanced later
        relevanceScore: score,
        reason: 'Popular with similar users',
      });
    }

    return suggestions;
  }

  private async getContentBasedRecommendations(
    userId: string,
    interests: UserInterests
  ): Promise<FeedSuggestion[]> {
    const recommendations: FeedSuggestion[] = [];

    // Recommend based on top categories
    const topCategories = Array.from(interests.categories.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([cat]) => cat);

    for (const category of this.curatedFeeds) {
      if (topCategories.some(tc => category.name.toLowerCase().includes(tc.toLowerCase()))) {
        for (const feed of category.feeds) {
          recommendations.push({
            ...feed,
            relevanceScore: 0.8,
            reason: `Based on your interest in ${category.name}`,
          });
        }
      }
    }

    return recommendations;
  }

  private async findSimilarUsers(userId: string, limit: number = 10): Promise<Array<{ userId: string; similarity: number }>> {
    // This would implement collaborative filtering
    // For now, return empty array
    return [];
  }

  async importOPML(userId: string, opmlContent: string): Promise<{ imported: number; failed: number; errors: string[] }> {
    try {
      const parser = new (require('opml-parser'))();
      const feeds: any[] = [];
      const errors: string[] = [];

      parser.on('feed', (feed: any) => {
        feeds.push(feed);
      });

      parser.on('error', (error: any) => {
        errors.push(error.message);
      });

      // Parse OPML
      await new Promise((resolve, reject) => {
        parser.on('end', resolve);
        parser.on('error', reject);
        parser.write(opmlContent);
        parser.end();
      });

      let imported = 0;
      let failed = 0;

      // Import feeds
      for (const feed of feeds) {
        try {
          await this.db.insert(feeds).values({
            userId,
            url: feed.xmlUrl || feed.url,
            title: feed.title || 'Imported Feed',
            description: feed.description,
            siteUrl: feed.htmlUrl,
            createdAt: new Date(),
            updatedAt: new Date(),
          });
          imported++;
        } catch (error) {
          failed++;
          errors.push(`Failed to import ${feed.title}: ${error}`);
        }
      }

      return { imported, failed, errors };
    } catch (error) {
      logger.error('Failed to import OPML:', error);
      throw error;
    }
  }

  async exportOPML(userId: string): Promise<string> {
    try {
      const userFeeds = await this.db
        .select()
        .from(feeds)
        .where(eq(feeds.userId, userId));

      let opml = `<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>Omi RSS Feed Export</title>
    <dateCreated>${new Date().toISOString()}</dateCreated>
  </head>
  <body>`;

      // Group feeds by folder
      const feedsByFolder = new Map<string, typeof userFeeds>();
      
      for (const feed of userFeeds) {
        const folder = feed.folderId || 'Uncategorized';
        if (!feedsByFolder.has(folder)) {
          feedsByFolder.set(folder, []);
        }
        feedsByFolder.get(folder)!.push(feed);
      }

      // Generate OPML
      for (const [folder, folderFeeds] of feedsByFolder) {
        opml += `\n    <outline text="${folder}" title="${folder}">`;
        
        for (const feed of folderFeeds) {
          opml += `\n      <outline type="rss" text="${this.escapeXml(feed.title)}" title="${this.escapeXml(feed.title)}" xmlUrl="${this.escapeXml(feed.url)}" htmlUrl="${this.escapeXml(feed.siteUrl || '')}" />`;
        }
        
        opml += '\n    </outline>';
      }

      opml += '\n  </body>\n</opml>';

      return opml;
    } catch (error) {
      logger.error('Failed to export OPML:', error);
      throw error;
    }
  }

  private escapeXml(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  }
}

// Export singleton instance
export const feedDiscoveryService = new FeedDiscoveryService();