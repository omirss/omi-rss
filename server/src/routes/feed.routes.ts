import { Router } from 'express';
import { z } from 'zod';
import { getDb } from '../database';
import { feeds, folders, articles, userArticleStates } from '../database/schema';
import { eq, and, desc, sql } from 'drizzle-orm';
import { AppError } from '../middleware/errorHandler';
import { feedUpdateQueue } from '../workers';
import { logger } from '../utils/logger';
import Parser from 'rss-parser';

const router = Router();
const parser = new Parser();

// Validation schemas
const createFeedSchema = z.object({
  url: z.string().url(),
  folderId: z.string().uuid().optional(),
  customTitle: z.string().optional(),
  updateInterval: z.number().min(5).max(1440).optional(),
});

const updateFeedSchema = z.object({
  customTitle: z.string().optional(),
  folderId: z.string().uuid().nullable().optional(),
  updateInterval: z.number().min(5).max(1440).optional(),
  isActive: z.boolean().optional(),
});

// Get all feeds for user
router.get('/', async (req, res, next) => {
  try {
    const db = getDb();
    
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
        createdAt: feeds.createdAt,
        updatedAt: feeds.updatedAt,
        unreadCount: sql<number>`
          COUNT(DISTINCT ${articles.id}) FILTER (
            WHERE ${articles.id} IS NOT NULL 
            AND NOT EXISTS (
              SELECT 1 FROM ${userArticleStates} 
              WHERE ${userArticleStates.articleId} = ${articles.id} 
              AND ${userArticleStates.userId} = ${req.user!.id}
              AND ${userArticleStates.isRead} = true
            )
          )
        `.as('unreadCount'),
      })
      .from(feeds)
      .leftJoin(articles, eq(articles.feedId, feeds.id))
      .where(eq(feeds.userId, req.user!.id))
      .groupBy(feeds.id)
      .orderBy(feeds.customTitle, feeds.title);

    res.json({ feeds: userFeeds });
  } catch (error) {
    next(error);
  }
});

// Get single feed
router.get('/:feedId', async (req, res, next) => {
  try {
    const { feedId } = req.params;
    const db = getDb();
    
    const [feed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.id, feedId),
        eq(feeds.userId, req.user!.id)
      ))
      .limit(1);

    if (!feed) {
      throw new AppError('Feed not found', 404);
    }

    // Get article count
    const [stats] = await db
      .select({
        totalArticles: sql<number>`COUNT(*)`,
        unreadArticles: sql<number>`
          COUNT(*) FILTER (
            WHERE NOT EXISTS (
              SELECT 1 FROM ${userArticleStates} 
              WHERE ${userArticleStates.articleId} = ${articles.id} 
              AND ${userArticleStates.userId} = ${req.user!.id}
              AND ${userArticleStates.isRead} = true
            )
          )
        `,
      })
      .from(articles)
      .where(eq(articles.feedId, feedId));

    res.json({ 
      feed,
      stats: stats || { totalArticles: 0, unreadArticles: 0 }
    });
  } catch (error) {
    next(error);
  }
});

// Subscribe to new feed
router.post('/', async (req, res, next) => {
  try {
    const data = createFeedSchema.parse(req.body);
    const db = getDb();

    // Check if user already subscribed to this feed
    const [existingFeed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.url, data.url),
        eq(feeds.userId, req.user!.id)
      ))
      .limit(1);

    if (existingFeed) {
      throw new AppError('Already subscribed to this feed', 409);
    }

    // Validate feed URL by parsing it
    let feedData;
    try {
      feedData = await parser.parseURL(data.url);
    } catch (parseError) {
      throw new AppError('Invalid feed URL or unable to parse feed', 400);
    }

    // Create feed
    const [newFeed] = await db
      .insert(feeds)
      .values({
        userId: req.user!.id,
        url: data.url,
        title: feedData.title || 'Untitled Feed',
        description: feedData.description,
        siteUrl: feedData.link,
        imageUrl: feedData.image?.url || feedData.image,
        customTitle: data.customTitle,
        folderId: data.folderId,
        updateInterval: data.updateInterval || 30,
        favicon: await extractFavicon(feedData.link),
      })
      .returning();

    // Queue immediate feed update
    await feedUpdateQueue.add('update-single-feed', { 
      feedId: newFeed.id 
    });

    logger.info(`User ${req.user!.id} subscribed to feed: ${newFeed.title}`);

    res.status(201).json({ feed: newFeed });
  } catch (error) {
    next(error);
  }
});

// Update feed
router.put('/:feedId', async (req, res, next) => {
  try {
    const { feedId } = req.params;
    const data = updateFeedSchema.parse(req.body);
    const db = getDb();

    // Check ownership
    const [existingFeed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.id, feedId),
        eq(feeds.userId, req.user!.id)
      ))
      .limit(1);

    if (!existingFeed) {
      throw new AppError('Feed not found', 404);
    }

    // Update feed
    const [updatedFeed] = await db
      .update(feeds)
      .set({
        ...data,
        updatedAt: new Date(),
      })
      .where(eq(feeds.id, feedId))
      .returning();

    res.json({ feed: updatedFeed });
  } catch (error) {
    next(error);
  }
});

// Delete feed
router.delete('/:feedId', async (req, res, next) => {
  try {
    const { feedId } = req.params;
    const db = getDb();

    // Check ownership
    const [existingFeed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.id, feedId),
        eq(feeds.userId, req.user!.id)
      ))
      .limit(1);

    if (!existingFeed) {
      throw new AppError('Feed not found', 404);
    }

    // Delete feed (articles will cascade)
    await db
      .delete(feeds)
      .where(eq(feeds.id, feedId));

    logger.info(`User ${req.user!.id} deleted feed: ${existingFeed.title}`);

    res.status(204).send();
  } catch (error) {
    next(error);
  }
});

// Refresh feed
router.post('/:feedId/refresh', async (req, res, next) => {
  try {
    const { feedId } = req.params;
    const db = getDb();

    // Check ownership
    const [feed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.id, feedId),
        eq(feeds.userId, req.user!.id)
      ))
      .limit(1);

    if (!feed) {
      throw new AppError('Feed not found', 404);
    }

    // Queue feed update
    await feedUpdateQueue.add('update-single-feed', { 
      feedId 
    }, {
      priority: 1, // Higher priority for manual refresh
    });

    res.json({ message: 'Feed refresh queued' });
  } catch (error) {
    next(error);
  }
});

// Mark all articles in feed as read
router.post('/:feedId/mark-all-read', async (req, res, next) => {
  try {
    const { feedId } = req.params;
    const db = getDb();

    // Check ownership
    const [feed] = await db
      .select()
      .from(feeds)
      .where(and(
        eq(feeds.id, feedId),
        eq(feeds.userId, req.user!.id)
      ))
      .limit(1);

    if (!feed) {
      throw new AppError('Feed not found', 404);
    }

    // Get all articles in feed
    const feedArticles = await db
      .select({ id: articles.id })
      .from(articles)
      .where(eq(articles.feedId, feedId));

    // Mark all as read
    for (const article of feedArticles) {
      await db
        .insert(userArticleStates)
        .values({
          userId: req.user!.id,
          articleId: article.id,
          isRead: true,
          readAt: new Date(),
        })
        .onConflictDoUpdate({
          target: [userArticleStates.userId, userArticleStates.articleId],
          set: {
            isRead: true,
            readAt: new Date(),
            updatedAt: new Date(),
          },
        });
    }

    res.json({ 
      message: 'All articles marked as read',
      count: feedArticles.length 
    });
  } catch (error) {
    next(error);
  }
});

// Helper function to extract favicon
async function extractFavicon(siteUrl?: string): Promise<string | null> {
  if (!siteUrl) return null;
  
  try {
    const url = new URL(siteUrl);
    return `https://www.google.com/s2/favicons?domain=${url.hostname}&sz=64`;
  } catch {
    return null;
  }
}

export default router;