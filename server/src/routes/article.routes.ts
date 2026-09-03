import { Router } from 'express';
import { z } from 'zod';
import { getDb } from '../database';
import { articles, userArticleStates, feeds } from '../database/schema';
import { eq, and, desc, asc, sql, inArray, or, ilike } from 'drizzle-orm';
import { AppError } from '../middleware/errorHandler';

const router = Router();

// Validation schemas
const paginationSchema = z.object({
  page: z.string().transform(Number).default('1'),
  limit: z.string().transform(Number).default('20'),
  sortBy: z.enum(['publishedAt', 'title', 'feedTitle']).default('publishedAt'),
  sortOrder: z.enum(['asc', 'desc']).default('desc'),
});

const filterSchema = z.object({
  feedId: z.string().uuid().optional(),
  folderId: z.string().uuid().optional(),
  isRead: z.string().transform(val => val === 'true').optional(),
  isStarred: z.string().transform(val => val === 'true').optional(),
  search: z.string().optional(),
  tags: z.string().transform(val => val.split(',')).optional(),
});

const updateArticleStateSchema = z.object({
  isRead: z.boolean().optional(),
  isStarred: z.boolean().optional(),
  tags: z.array(z.string()).optional(),
});

const batchUpdateSchema = z.object({
  articleIds: z.array(z.string().uuid()),
  updates: updateArticleStateSchema,
});

// Get articles with filters and pagination
router.get('/', async (req, res, next) => {
  try {
    const pagination = paginationSchema.parse(req.query);
    const filters = filterSchema.parse(req.query);
    const db = getDb();

    // Build query
    let query = db
      .select({
        id: articles.id,
        feedId: articles.feedId,
        title: articles.title,
        link: articles.link,
        description: articles.description,
        content: articles.content,
        author: articles.author,
        publishedAt: articles.publishedAt,
        imageUrl: articles.imageUrl,
        enclosures: articles.enclosures,
        isRead: userArticleStates.isRead,
        isStarred: userArticleStates.isStarred,
        readAt: userArticleStates.readAt,
        tags: userArticleStates.tags,
        feedTitle: feeds.title,
        feedFavicon: feeds.favicon,
      })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .leftJoin(
        userArticleStates,
        and(
          eq(userArticleStates.articleId, articles.id),
          eq(userArticleStates.userId, req.user!.id)
        )
      )
      .where(eq(feeds.userId, req.user!.id));

    // Apply filters
    const conditions = [];

    if (filters.feedId) {
      conditions.push(eq(articles.feedId, filters.feedId));
    }

    if (filters.folderId) {
      conditions.push(eq(feeds.folderId, filters.folderId));
    }

    if (filters.isRead !== undefined) {
      if (filters.isRead) {
        conditions.push(eq(userArticleStates.isRead, true));
      } else {
        conditions.push(
          or(
            eq(userArticleStates.isRead, false),
            sql`${userArticleStates.isRead} IS NULL`
          )
        );
      }
    }

    if (filters.isStarred !== undefined) {
      conditions.push(eq(userArticleStates.isStarred, filters.isStarred));
    }

    if (filters.search) {
      conditions.push(
        or(
          ilike(articles.title, `%${filters.search}%`),
          ilike(articles.description, `%${filters.search}%`),
          ilike(articles.content, `%${filters.search}%`)
        )
      );
    }

    if (conditions.length > 0) {
      query = query.where(and(...conditions));
    }

    // Apply sorting
    const sortColumn = {
      publishedAt: articles.publishedAt,
      title: articles.title,
      feedTitle: feeds.title,
    }[pagination.sortBy];

    if (pagination.sortOrder === 'desc') {
      query = query.orderBy(desc(sortColumn));
    } else {
      query = query.orderBy(asc(sortColumn));
    }

    // Apply pagination
    const offset = (pagination.page - 1) * pagination.limit;
    query = query.limit(pagination.limit).offset(offset);

    const articleList = await query;

    // Get total count
    const [{ count }] = await db
      .select({ count: sql<number>`COUNT(*)` })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .where(eq(feeds.userId, req.user!.id));

    res.json({
      articles: articleList.map(article => ({
        ...article,
        isRead: article.isRead || false,
        isStarred: article.isStarred || false,
        tags: article.tags || [],
      })),
      pagination: {
        page: pagination.page,
        limit: pagination.limit,
        total: Number(count),
        totalPages: Math.ceil(Number(count) / pagination.limit),
      },
    });
  } catch (error) {
    next(error);
  }
});

// Get single article
router.get('/:articleId', async (req, res, next) => {
  try {
    const { articleId } = req.params;
    const db = getDb();

    const [article] = await db
      .select({
        id: articles.id,
        feedId: articles.feedId,
        title: articles.title,
        link: articles.link,
        description: articles.description,
        content: articles.content,
        author: articles.author,
        publishedAt: articles.publishedAt,
        imageUrl: articles.imageUrl,
        enclosures: articles.enclosures,
        isRead: userArticleStates.isRead,
        isStarred: userArticleStates.isStarred,
        readAt: userArticleStates.readAt,
        tags: userArticleStates.tags,
        feedTitle: feeds.title,
        feedFavicon: feeds.favicon,
      })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .leftJoin(
        userArticleStates,
        and(
          eq(userArticleStates.articleId, articles.id),
          eq(userArticleStates.userId, req.user!.id)
        )
      )
      .where(
        and(
          eq(articles.id, articleId),
          eq(feeds.userId, req.user!.id)
        )
      )
      .limit(1);

    if (!article) {
      throw new AppError('Article not found', 404);
    }

    // Mark as read automatically when fetching
    if (!article.isRead) {
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
      article: {
        ...article,
        isRead: true,
        isStarred: article.isStarred || false,
        tags: article.tags || [],
      },
    });
  } catch (error) {
    next(error);
  }
});

// Update article state
router.put('/:articleId/state', async (req, res, next) => {
  try {
    const { articleId } = req.params;
    const updates = updateArticleStateSchema.parse(req.body);
    const db = getDb();

    // Verify article ownership
    const [article] = await db
      .select({ id: articles.id })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .where(
        and(
          eq(articles.id, articleId),
          eq(feeds.userId, req.user!.id)
        )
      )
      .limit(1);

    if (!article) {
      throw new AppError('Article not found', 404);
    }

    // Update or create user article state
    const stateData: any = {
      userId: req.user!.id,
      articleId,
      updatedAt: new Date(),
    };

    if (updates.isRead !== undefined) {
      stateData.isRead = updates.isRead;
      if (updates.isRead) {
        stateData.readAt = new Date();
      }
    }

    if (updates.isStarred !== undefined) {
      stateData.isStarred = updates.isStarred;
    }

    if (updates.tags !== undefined) {
      stateData.tags = updates.tags;
    }

    await db
      .insert(userArticleStates)
      .values(stateData)
      .onConflictDoUpdate({
        target: [userArticleStates.userId, userArticleStates.articleId],
        set: stateData,
      });

    res.json({ message: 'Article state updated' });
  } catch (error) {
    next(error);
  }
});

// Batch update articles
router.post('/batch-update', async (req, res, next) => {
  try {
    const { articleIds, updates } = batchUpdateSchema.parse(req.body);
    const db = getDb();

    // Verify ownership of all articles
    const ownedArticles = await db
      .select({ id: articles.id })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .where(
        and(
          inArray(articles.id, articleIds),
          eq(feeds.userId, req.user!.id)
        )
      );

    const ownedArticleIds = ownedArticles.map(a => a.id);
    
    if (ownedArticleIds.length === 0) {
      throw new AppError('No valid articles found', 404);
    }

    // Update each article state
    for (const articleId of ownedArticleIds) {
      const stateData: any = {
        userId: req.user!.id,
        articleId,
        updatedAt: new Date(),
      };

      if (updates.isRead !== undefined) {
        stateData.isRead = updates.isRead;
        if (updates.isRead) {
          stateData.readAt = new Date();
        }
      }

      if (updates.isStarred !== undefined) {
        stateData.isStarred = updates.isStarred;
      }

      if (updates.tags !== undefined) {
        stateData.tags = updates.tags;
      }

      await db
        .insert(userArticleStates)
        .values(stateData)
        .onConflictDoUpdate({
          target: [userArticleStates.userId, userArticleStates.articleId],
          set: stateData,
        });
    }

    res.json({
      message: 'Articles updated',
      updatedCount: ownedArticleIds.length,
    });
  } catch (error) {
    next(error);
  }
});

// Mark all articles as read
router.post('/mark-all-read', async (req, res, next) => {
  try {
    const filters = filterSchema.parse(req.query);
    const db = getDb();

    // Build query to find articles
    let query = db
      .select({ id: articles.id })
      .from(articles)
      .innerJoin(feeds, eq(articles.feedId, feeds.id))
      .leftJoin(
        userArticleStates,
        and(
          eq(userArticleStates.articleId, articles.id),
          eq(userArticleStates.userId, req.user!.id)
        )
      )
      .where(eq(feeds.userId, req.user!.id));

    // Apply filters
    const conditions = [];

    if (filters.feedId) {
      conditions.push(eq(articles.feedId, filters.feedId));
    }

    if (filters.folderId) {
      conditions.push(eq(feeds.folderId, filters.folderId));
    }

    // Only unread articles
    conditions.push(
      or(
        eq(userArticleStates.isRead, false),
        sql`${userArticleStates.isRead} IS NULL`
      )
    );

    if (conditions.length > 0) {
      query = query.where(and(...conditions));
    }

    const unreadArticles = await query;

    // Mark all as read
    for (const article of unreadArticles) {
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
      count: unreadArticles.length,
    });
  } catch (error) {
    next(error);
  }
});

export default router;