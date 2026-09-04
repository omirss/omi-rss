import { Router } from 'express';
import { z } from 'zod';
import { validateRequest } from '../middleware/validation';
import { analyticsService } from '../services/analytics';

const router = Router();

// Get user analytics
const getUserAnalyticsSchema = z.object({
  query: z.object({
    timeframe: z.enum(['day', 'week', 'month', 'year', 'all']).default('month'),
  }),
});

router.get(
  '/',
  validateRequest(getUserAnalyticsSchema),
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const { timeframe } = req.query as unknown as { timeframe: 'day' | 'week' | 'month' | 'year' | 'all' };

      const analytics = await analyticsService.getUserAnalytics(userId, timeframe);
      res.json(analytics);
    } catch (error) {
      next(error);
    }
  },
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
  validateRequest(trackArticleReadSchema),
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const body = req.body as z.infer<typeof trackArticleReadSchema>['body'];
      await analyticsService.trackArticleRead(userId, body);
      res.json({ success: true });
    } catch (error) {
      next(error);
    }
  },
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
  validateRequest(trackFeedInteractionSchema),
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const body = req.body as z.infer<typeof trackFeedInteractionSchema>['body'];
      await analyticsService.trackFeedInteraction(userId, body);
      res.json({ success: true });
    } catch (error) {
      next(error);
    }
  },
);

// Export analytics data
router.get(
  '/export',
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const exportData = await analyticsService.exportUserData(userId);

      res.setHeader('Content-Type', 'application/json');
      res.setHeader(
        'Content-Disposition',
        `attachment; filename="omi-rss-analytics-${new Date().toISOString().split('T')[0]}.json"`,
      );
      res.json(exportData);
    } catch (error) {
      next(error);
    }
  },
);

// Get reading streaks
router.get(
  '/streaks',
  async (req, res, next) => {
    try {
      const userId = req.user!.id;
      const streaks = await analyticsService.getReadingStreaks(userId);
      res.json(streaks);
    } catch (error) {
      next(error);
    }
  },
);

export default router;
