import { Router } from 'express';
import { body, query } from 'express-validator';
import { authenticate } from '../middleware/authentication';
import { validate } from '../middleware/validation';
import { asyncHandler } from '../middleware/asyncHandler';
import { feedDiscoveryService } from '../services/discovery';
import { logger } from '../utils/logger';
import multer from 'multer';

const router = Router();
const upload = multer({ 
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB limit
});

// Discover feeds based on user interests
router.get(
  '/discover',
  authenticate,
  [
    query('categories').optional().isString(),
    query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
    query('language').optional().isString(),
  ],
  validate,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { categories, limit, language } = req.query;

    const suggestions = await feedDiscoveryService.discoverFeeds(userId, {
      categories: categories ? (categories as string).split(',') : undefined,
      limit: limit as number,
      language: language as string,
    });

    res.json({
      success: true,
      data: suggestions,
    });
  })
);

// Generate custom feed based on prompt
router.post(
  '/generate',
  authenticate,
  [
    body('prompt').isString().isLength({ min: 3, max: 500 }).withMessage('Prompt must be between 3 and 500 characters'),
  ],
  validate,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { prompt } = req.body;

    const suggestions = await feedDiscoveryService.generateCustomFeed(userId, prompt);

    res.json({
      success: true,
      data: suggestions,
    });
  })
);

// Search public feeds
router.get(
  '/search',
  authenticate,
  [
    query('q').isString().isLength({ min: 2 }).withMessage('Query must be at least 2 characters'),
    query('category').optional().isString(),
    query('language').optional().isString(),
    query('limit').optional().isInt({ min: 1, max: 50 }).toInt(),
  ],
  validate,
  asyncHandler(async (req, res) => {
    const { q, category, language, limit } = req.query;

    const results = await feedDiscoveryService.searchPublicFeeds(q as string, {
      category: category as string,
      language: language as string,
      limit: limit as number,
    });

    res.json({
      success: true,
      data: results,
    });
  })
);

// Get trending feeds
router.get(
  '/trending',
  authenticate,
  [
    query('timeframe').optional().isIn(['day', 'week', 'month']),
    query('category').optional().isString(),
    query('limit').optional().isInt({ min: 1, max: 50 }).toInt(),
  ],
  validate,
  asyncHandler(async (req, res) => {
    const { timeframe, category, limit } = req.query;

    const trending = await feedDiscoveryService.getTrendingFeeds({
      timeframe: timeframe as 'day' | 'week' | 'month',
      category: category as string,
      limit: limit as number,
    });

    res.json({
      success: true,
      data: trending,
    });
  })
);

// Get related feeds
router.get(
  '/related/:feedId',
  authenticate,
  [
    query('limit').optional().isInt({ min: 1, max: 20 }).toInt(),
  ],
  validate,
  asyncHandler(async (req, res) => {
    const { feedId } = req.params;
    const { limit } = req.query;

    const related = await feedDiscoveryService.getRelatedFeeds(
      feedId,
      limit as number
    );

    res.json({
      success: true,
      data: related,
    });
  })
);

// Get personalized recommendations
router.get(
  '/recommendations',
  authenticate,
  [
    query('limit').optional().isInt({ min: 1, max: 50 }).toInt(),
  ],
  validate,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const { limit } = req.query;

    const recommendations = await feedDiscoveryService.recommendFeedsBasedOnReadingHistory(
      userId,
      limit as number
    );

    res.json({
      success: true,
      data: recommendations,
    });
  })
);

// Import OPML
router.post(
  '/import/opml',
  authenticate,
  upload.single('file'),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No file uploaded',
      });
    }

    const opmlContent = req.file.buffer.toString('utf-8');
    const result = await feedDiscoveryService.importOPML(userId, opmlContent);

    res.json({
      success: true,
      data: result,
    });
  })
);

// Export OPML
router.get(
  '/export/opml',
  authenticate,
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    
    const opmlContent = await feedDiscoveryService.exportOPML(userId);

    res.setHeader('Content-Type', 'application/xml');
    res.setHeader('Content-Disposition', 'attachment; filename="omi-rss-feeds.opml"');
    res.send(opmlContent);
  })
);

// Get feed categories
router.get(
  '/categories',
  authenticate,
  asyncHandler(async (req, res) => {
    // Return available feed categories
    const categories = [
      { id: 'technology', name: 'Technology', description: 'Latest tech news and developments' },
      { id: 'science', name: 'Science', description: 'Scientific discoveries and research' },
      { id: 'business', name: 'Business & Finance', description: 'Business news and market analysis' },
      { id: 'programming', name: 'Programming & Development', description: 'Software development and programming' },
      { id: 'ai', name: 'AI & Machine Learning', description: 'Artificial Intelligence and ML news' },
      { id: 'news', name: 'World News', description: 'Global news and current events' },
      { id: 'health', name: 'Health & Medicine', description: 'Health, wellness, and medical news' },
      { id: 'entertainment', name: 'Entertainment', description: 'Movies, music, and pop culture' },
      { id: 'sports', name: 'Sports', description: 'Sports news and updates' },
      { id: 'politics', name: 'Politics', description: 'Political news and analysis' },
    ];

    res.json({
      success: true,
      data: categories,
    });
  })
);

// Validate feed URL
router.post(
  '/validate',
  authenticate,
  [
    body('url').isURL().withMessage('Invalid URL format'),
  ],
  validate,
  asyncHandler(async (req, res) => {
    const { url } = req.body;

    try {
      const metadata = await feedDiscoveryService['fetchFeedMetadata'](url);
      const isValid = !!metadata.title;

      res.json({
        success: true,
        data: {
          valid: isValid,
          metadata: isValid ? metadata : null,
        },
      });
    } catch (error) {
      res.json({
        success: true,
        data: {
          valid: false,
          error: 'Unable to parse feed',
        },
      });
    }
  })
);

export default router;