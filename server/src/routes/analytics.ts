import { Router } from 'express';
import { z } from 'zod';
import { authenticateToken } from '../middleware/auth';
import { validateRequest } from '../middleware/validation';
import { AnalyticsService } from '../services/analytics';

const router = Router();
const analyticsService = new AnalyticsService();

// Get user analytics
const getUserAnalyticsSchema = z.object({
  query: z.object({
    timeframe: z.enum(['day', 'week', 'month', 'year', 'all']).default('month'),
  }),
});

router.get(
  '/',
  authenticateToken,
  validateRequest(getUserAnalyticsSchema),
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const { timeframe } = req.query as { timeframe: string };

      const analytics = await analyticsService.getUserAnalytics(userId, timeframe);
      res.json(analytics);
    } catch (error) {
      next(error);
    }
  }
);

// Track article read
const trackArticleReadSchema = z.object({
  body: z.object({
    articleId: z.string(),
    scrollDepth: z.number().min(0).max(100),
    interactionTime: z.number().positive(),
    completed: z.boolean(),
  }),
});

router.post(
  '/article-read',
  authenticateToken,
  validateRequest(trackArticleReadSchema),
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      await analyticsService.trackArticleRead(userId, req.body);
      res.json({ success: true });
    } catch (error) {
      next(error);
    }
  }
);

// Track feed interaction
const trackFeedInteractionSchema = z.object({
  body: z.object({
    feedId: z.string(),
    action: z.enum(['subscribe', 'unsubscribe', 'mute', 'favorite']),
  }),
});

router.post(
  '/feed-interaction',
  authenticateToken,
  validateRequest(trackFeedInteractionSchema),
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      await analyticsService.trackFeedInteraction(userId, req.body);
      res.json({ success: true });
    } catch (error) {
      next(error);
    }
  }
);

// Track AI feature usage
const trackAIUsageSchema = z.object({
  body: z.object({
    feature: z.enum(['summarize', 'analyze', 'generate', 'chat', 'translate']),
    provider: z.string(),
    responseTime: z.number().positive(),
    tokensUsed: z.number().positive().optional(),
  }),
});

router.post(
  '/ai-usage',
  authenticateToken,
  validateRequest(trackAIUsageSchema),
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      await analyticsService.trackAIUsage(userId, req.body);
      res.json({ success: true });
    } catch (error) {
      next(error);
    }
  }
);

// Get personalized recommendations
const getRecommendationsSchema = z.object({
  query: z.object({
    type: z.enum(['articles', 'feeds', 'mixed']).default('mixed'),
    limit: z.string().regex(/^\d+$/).transform(Number).default('10'),
  }),
});

router.get(
  '/recommendations',
  authenticateToken,
  validateRequest(getRecommendationsSchema),
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const { type, limit } = req.query as { type: string; limit: number };

      const recommendations = await analyticsService.getPersonalizedRecommendations(
        userId,
        type,
        limit
      );
      res.json(recommendations);
    } catch (error) {
      next(error);
    }
  }
);

// Get insights
const getInsightsSchema = z.object({
  query: z.object({
    category: z.enum(['reading', 'preferences', 'trends', 'all']).default('all'),
  }),
});

router.get(
  '/insights',
  authenticateToken,
  validateRequest(getInsightsSchema),
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const { category } = req.query as { category: string };

      const insights = await analyticsService.getInsights(userId, category);
      res.json(insights);
    } catch (error) {
      next(error);
    }
  }
);

// Export analytics data
router.get(
  '/export',
  authenticateToken,
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const exportData = await analyticsService.exportUserData(userId);

      res.setHeader('Content-Type', 'application/json');
      res.setHeader(
        'Content-Disposition',
        `attachment; filename="omi-rss-analytics-${new Date().toISOString().split('T')[0]}.json"`
      );
      res.json(exportData);
    } catch (error) {
      next(error);
    }
  }
);

// Get reading streaks
router.get(
  '/streaks',
  authenticateToken,
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const streaks = await analyticsService.getReadingStreaks(userId);
      res.json(streaks);
    } catch (error) {
      next(error);
    }
  }
);

// Compare with other users
router.get(
  '/compare',
  authenticateToken,
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const comparison = await analyticsService.compareWithOthers(userId);
      res.json(comparison);
    } catch (error) {
      next(error);
    }
  }
);

export default router;