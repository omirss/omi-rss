import Queue from 'bull';
import { getDb } from '../database';
import { feeds, articles, userArticleStates } from '../database/schema';
import { eq, and, gt, sql } from 'drizzle-orm';
import { logger } from '../utils/logger';
import { broadcastFeedUpdate } from '../services/socket.service';
import axios from 'axios';
import Parser from 'rss-parser';
import crypto from 'crypto';

const parser = new Parser({
  customFields: {
    feed: ['subtitle', 'image'],
    item: ['image', 'enclosure', 'media:content'],
  },
});

export function feedUpdateWorker(queue: Queue.Queue) {
  queue.process('update-all-feeds', async (job) => {
    logger.info('Starting scheduled feed update');
    
    const db = getDb();
    
    // Get all active feeds that need updating
    const activeFeeds = await db
      .select()
      .from(feeds)
      .where(
        and(
          eq(feeds.isActive, true),
          sql`${feeds.lastFetchedAt} IS NULL OR ${feeds.lastFetchedAt} < NOW() - INTERVAL '1 minute' * ${feeds.updateInterval}`
        )
      );

    logger.info(`Found ${activeFeeds.length} feeds to update`);

    // Update feeds in parallel (with concurrency limit)
    const results = await Promise.allSettled(
      activeFeeds.map((feed) =>
        queue.add('update-single-feed', { feedId: feed.id }, { delay: 0 })
      )
    );

    const successful = results.filter((r) => r.status === 'fulfilled').length;
    const failed = results.filter((r) => r.status === 'rejected').length;

    logger.info(`Feed update completed: ${successful} successful, ${failed} failed`);
  });

  queue.process('update-single-feed', async (job) => {
    const { feedId } = job.data;
    
    try {
      const db = getDb();
      
      // Get feed details
      const [feed] = await db
        .select()
        .from(feeds)
        .where(eq(feeds.id, feedId))
        .limit(1);

      if (!feed) {
        throw new Error(`Feed ${feedId} not found`);
      }

      logger.info(`Updating feed: ${feed.title} (${feed.url})`);

      // Fetch and parse feed
      const feedData = await parser.parseURL(feed.url);

      // Update feed metadata
      await db
        .update(feeds)
        .set({
          title: feedData.title || feed.title,
          description: feedData.description || feed.description,
          siteUrl: feedData.link || feed.siteUrl,
          imageUrl: feedData.image?.url || feedData.image || feed.imageUrl,
          lastFetchedAt: new Date(),
          lastFetchError: null,
          errorCount: 0,
        })
        .where(eq(feeds.id, feedId));

      // Process articles
      const newArticles = [];
      
      for (const item of feedData.items) {
        // Generate unique GUID
        const guid = item.guid || item.link || crypto.createHash('md5').update(item.title + item.pubDate).digest('hex');
        
        // Check if article already exists
        const [existingArticle] = await db
          .select()
          .from(articles)
          .where(and(eq(articles.feedId, feedId), eq(articles.guid, guid)))
          .limit(1);

        if (!existingArticle) {
          // Extract article data
          const articleData = {
            feedId,
            guid,
            url: item.link || '',
            title: item.title || 'Untitled',
            author: item.creator || item.author,
            content: item['content:encoded'] || item.content,
            summary: item.summary || item.description,
            imageUrl: extractImageUrl(item),
            publishedAt: item.pubDate ? new Date(item.pubDate) : new Date(),
            categories: item.categories || [],
            enclosures: item.enclosure ? [item.enclosure] : [],
            metadata: {
              originalItem: item,
            },
          };

          // Insert article
          const [newArticle] = await db
            .insert(articles)
            .values(articleData)
            .returning();

          newArticles.push(newArticle);
        }
      }

      if (newArticles.length > 0) {
        logger.info(`Added ${newArticles.length} new articles for feed ${feed.title}`);
        
        // Broadcast updates to connected clients
        await broadcastFeedUpdate(feedId, newArticles);
        
        // Queue notifications for users
        await queue.add('send-new-article-notifications', {
          feedId,
          articleCount: newArticles.length,
          articles: newArticles.slice(0, 5), // First 5 articles
        });
      }

      return { feedId, newArticles: newArticles.length };
    } catch (error) {
      logger.error(`Failed to update feed ${feedId}:`, error);
      
      // Update error count
      const db = getDb();
      await db
        .update(feeds)
        .set({
          lastFetchError: error.message,
          errorCount: sql`${feeds.errorCount} + 1`,
          lastFetchedAt: new Date(),
        })
        .where(eq(feeds.id, feedId));

      throw error;
    }
  });

  queue.process('send-new-article-notifications', async (job) => {
    const { feedId, articleCount, articles } = job.data;
    
    // This would be implemented to send notifications
    // For now, just log
    logger.info(`Would send notifications for ${articleCount} new articles in feed ${feedId}`);
  });
}

function extractImageUrl(item: any): string | null {
  // Try various image sources
  if (item.image) return item.image;
  if (item['media:content']?.$ ?.url) return item['media:content'].$.url;
  if (item.enclosure?.type?.startsWith('image/')) return item.enclosure.url;
  
  // Extract from content
  const imgMatch = item.content?.match(/<img[^>]+src="([^">]+)"/);
  if (imgMatch) return imgMatch[1];
  
  return null;
}