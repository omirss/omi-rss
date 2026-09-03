import { getDb } from '../../database';
import {
  users,
  articles,
  feeds,
  userArticleStates,
  readingStats,
  aiAnalysis,
  folders,
} from '../../database/schema';
import { eq, and, gte, lte, sql, desc, asc, inArray } from 'drizzle-orm';
import { logger } from '../../utils/logger';
import { getRedis } from '../redis';
import { aiService } from '../ai';
import { v4 as uuidv4 } from 'uuid';
import { startOfDay, startOfWeek, startOfMonth, subDays, subMonths } from 'date-fns';

interface ReadingAnalytics {
  totalArticlesRead: number;
  totalReadingTime: number; // minutes
  averageReadingTime: number; // minutes per article
  articlesPerDay: number;
  mostActiveHour: number;
  mostActiveDay: string;
  readingStreak: number;
  longestStreak: number;
  completionRate: number; // percentage of started articles that were finished
}

interface ContentPreferences {
  topCategories: Array<{ category: string; count: number; percentage: number }>;
  topAuthors: Array<{ author: string; count: number; articles: number }>;
  topSources: Array<{ source: string; feedId: string; count: number }>;
  preferredLength: 'short' | 'medium' | 'long';
  readingSpeed: number; // words per minute
  topKeywords: Array<{ keyword: string; frequency: number }>;
}

interface ReadingPatterns {
  dailyDistribution: Array<{ hour: number; count: number }>;
  weeklyDistribution: Array<{ day: string; count: number }>;
  monthlyTrend: Array<{ date: string; count: number }>;
  categoryTrends: Array<{ category: string; trend: 'rising' | 'falling' | 'stable'; change: number }>;
  velocityTrend: 'increasing' | 'decreasing' | 'stable';
}

interface PersonalizedRecommendations {
  articles: Array<{
    articleId: string;
    score: number;
    reasons: string[];
  }>;
  feeds: Array<{
    feedId: string;
    score: number;
    reasons: string[];
  }>;
  categories: string[];
  readingGoals: {
    daily: number;
    weekly: number;
    suggestions: string[];
  };
}

interface EngagementMetrics {
  averageScrollDepth: number;
  averageTimePerParagraph: number;
  shareRate: number;
  bookmarkRate: number;
  annotationRate: number;
  interactionScore: number; // 0-100
}

export class AnalyticsService {
  private redis = getRedis();
  private db = getDb();

  async getUserAnalytics(userId: string, timeframe: 'week' | 'month' | 'year' = 'month'): Promise<{
    reading: ReadingAnalytics;
    preferences: ContentPreferences;
    patterns: ReadingPatterns;
    engagement: EngagementMetrics;
    insights: string[];
  }> {
    const startDate = this.getStartDate(timeframe);
    
    // Fetch reading analytics
    const reading = await this.calculateReadingAnalytics(userId, startDate);
    
    // Fetch content preferences
    const preferences = await this.analyzeContentPreferences(userId, startDate);
    
    // Analyze reading patterns
    const patterns = await this.analyzeReadingPatterns(userId, startDate);
    
    // Calculate engagement metrics
    const engagement = await this.calculateEngagementMetrics(userId, startDate);
    
    // Generate insights
    const insights = await this.generateInsights(userId, { reading, preferences, patterns, engagement });

    // Cache results
    await this.redis.set(
      `analytics:${userId}:${timeframe}`,
      JSON.stringify({ reading, preferences, patterns, engagement, insights }),
      'EX',
      3600 // 1 hour cache
    );

    return { reading, preferences, patterns, engagement, insights };
  }

  async getPersonalizedRecommendations(userId: string): Promise<PersonalizedRecommendations> {
    try {
      // Get user's reading history and preferences
      const userPreferences = await this.analyzeContentPreferences(userId, subMonths(new Date(), 3));
      const readingPatterns = await this.analyzeReadingPatterns(userId, subMonths(new Date(), 1));
      
      // Get unread articles from subscribed feeds
      const unreadArticles = await this.getUnreadArticles(userId, 100);
      
      // Score articles based on multiple factors
      const scoredArticles = await this.scoreArticles(userId, unreadArticles, userPreferences, readingPatterns);
      
      // Get feed recommendations
      const feedRecommendations = await this.recommendFeeds(userId, userPreferences);
      
      // Generate category recommendations
      const categoryRecommendations = this.recommendCategories(userPreferences, readingPatterns);
      
      // Calculate reading goals
      const readingGoals = this.calculateReadingGoals(readingPatterns);

      return {
        articles: scoredArticles.slice(0, 20),
        feeds: feedRecommendations.slice(0, 10),
        categories: categoryRecommendations,
        readingGoals,
      };
    } catch (error) {
      logger.error('Failed to generate recommendations:', error);
      throw error;
    }
  }

  private async calculateReadingAnalytics(userId: string, startDate: Date): Promise<ReadingAnalytics> {
    // Get all read articles in timeframe
    const readArticles = await this.db
      .select({
        articleId: userArticleStates.articleId,
        readAt: userArticleStates.readAt,
        readingTime: userArticleStates.readingTime,
        scrollPosition: userArticleStates.scrollPosition,
      })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, userId),
          eq(userArticleStates.isRead, true),
          gte(userArticleStates.readAt, startDate)
        )
      );

    // Get reading stats
    const stats = await this.db
      .select()
      .from(readingStats)
      .where(
        and(
          eq(readingStats.userId, userId),
          gte(readingStats.date, startDate)
        )
      );

    // Calculate metrics
    const totalArticlesRead = readArticles.length;
    const totalReadingTime = readArticles.reduce((sum, a) => sum + (a.readingTime || 0), 0) / 60; // Convert to minutes
    const averageReadingTime = totalArticlesRead > 0 ? totalReadingTime / totalArticlesRead : 0;
    
    // Calculate daily average
    const daysSinceStart = Math.max(1, Math.floor((Date.now() - startDate.getTime()) / (1000 * 60 * 60 * 24)));
    const articlesPerDay = totalArticlesRead / daysSinceStart;

    // Find most active hour
    const hourlyDistribution = new Map<number, number>();
    readArticles.forEach(article => {
      if (article.readAt) {
        const hour = new Date(article.readAt).getHours();
        hourlyDistribution.set(hour, (hourlyDistribution.get(hour) || 0) + 1);
      }
    });
    const mostActiveHour = Array.from(hourlyDistribution.entries())
      .sort((a, b) => b[1] - a[1])[0]?.[0] || 0;

    // Find most active day
    const dailyDistribution = new Map<string, number>();
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    readArticles.forEach(article => {
      if (article.readAt) {
        const day = days[new Date(article.readAt).getDay()];
        dailyDistribution.set(day, (dailyDistribution.get(day) || 0) + 1);
      }
    });
    const mostActiveDay = Array.from(dailyDistribution.entries())
      .sort((a, b) => b[1] - a[1])[0]?.[0] || 'Monday';

    // Calculate streaks
    const { currentStreak, longestStreak } = this.calculateReadingStreaks(stats);

    // Calculate completion rate
    const startedArticles = await this.db
      .select({ count: sql<number>`count(*)` })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, userId),
          gte(userArticleStates.createdAt, startDate),
          sql`${userArticleStates.scrollPosition} > 0`
        )
      );
    
    const completionRate = startedArticles[0]?.count 
      ? (totalArticlesRead / startedArticles[0].count) * 100 
      : 0;

    return {
      totalArticlesRead,
      totalReadingTime: Math.round(totalReadingTime),
      averageReadingTime: Math.round(averageReadingTime),
      articlesPerDay: Math.round(articlesPerDay * 10) / 10,
      mostActiveHour,
      mostActiveDay,
      readingStreak: currentStreak,
      longestStreak,
      completionRate: Math.round(completionRate),
    };
  }

  private async analyzeContentPreferences(userId: string, startDate: Date): Promise<ContentPreferences> {
    // Get read articles with details
    const readArticles = await this.db
      .select({
        article: articles,
        state: userArticleStates,
        feed: feeds,
      })
      .from(userArticleStates)
      .innerJoin(articles, eq(articles.id, userArticleStates.articleId))
      .innerJoin(feeds, eq(feeds.id, articles.feedId))
      .where(
        and(
          eq(userArticleStates.userId, userId),
          eq(userArticleStates.isRead, true),
          gte(userArticleStates.readAt, startDate)
        )
      );

    // Analyze categories
    const categoryCount = new Map<string, number>();
    readArticles.forEach(({ article }) => {
      if (article.categories && Array.isArray(article.categories)) {
        (article.categories as string[]).forEach(category => {
          categoryCount.set(category, (categoryCount.get(category) || 0) + 1);
        });
      }
    });

    const totalCategoryCount = Array.from(categoryCount.values()).reduce((a, b) => a + b, 0);
    const topCategories = Array.from(categoryCount.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([category, count]) => ({
        category,
        count,
        percentage: Math.round((count / totalCategoryCount) * 100),
      }));

    // Analyze authors
    const authorCount = new Map<string, number>();
    readArticles.forEach(({ article }) => {
      if (article.author) {
        authorCount.set(article.author, (authorCount.get(article.author) || 0) + 1);
      }
    });

    const topAuthors = Array.from(authorCount.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([author, count]) => ({
        author,
        count,
        articles: count,
      }));

    // Analyze sources
    const sourceCount = new Map<string, { feedId: string; count: number }>();
    readArticles.forEach(({ feed }) => {
      const current = sourceCount.get(feed.title) || { feedId: feed.id, count: 0 };
      sourceCount.set(feed.title, { ...current, count: current.count + 1 });
    });

    const topSources = Array.from(sourceCount.entries())
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 5)
      .map(([source, data]) => ({
        source,
        feedId: data.feedId,
        count: data.count,
      }));

    // Analyze preferred article length
    const lengthPreferences = { short: 0, medium: 0, long: 0 };
    let totalWords = 0;
    let totalReadingTime = 0;

    readArticles.forEach(({ article, state }) => {
      const wordCount = (article.content || '').split(/\s+/).length;
      if (wordCount < 500) lengthPreferences.short++;
      else if (wordCount < 1500) lengthPreferences.medium++;
      else lengthPreferences.long++;
      
      totalWords += wordCount;
      totalReadingTime += state.readingTime || 0;
    });

    const preferredLength = Object.entries(lengthPreferences)
      .sort((a, b) => b[1] - a[1])[0][0] as 'short' | 'medium' | 'long';

    // Calculate reading speed
    const readingSpeed = totalReadingTime > 0 
      ? Math.round(totalWords / (totalReadingTime / 60)) 
      : 250; // Default WPM

    // Extract top keywords using AI
    const topKeywords = await this.extractTopKeywords(readArticles.slice(0, 50));

    return {
      topCategories,
      topAuthors,
      topSources,
      preferredLength,
      readingSpeed,
      topKeywords,
    };
  }

  private async analyzeReadingPatterns(userId: string, startDate: Date): Promise<ReadingPatterns> {
    const readArticles = await this.db
      .select({
        readAt: userArticleStates.readAt,
        categories: articles.categories,
      })
      .from(userArticleStates)
      .innerJoin(articles, eq(articles.id, userArticleStates.articleId))
      .where(
        and(
          eq(userArticleStates.userId, userId),
          eq(userArticleStates.isRead, true),
          gte(userArticleStates.readAt, startDate)
        )
      );

    // Daily distribution (by hour)
    const hourlyCount = new Array(24).fill(0);
    readArticles.forEach(({ readAt }) => {
      if (readAt) {
        const hour = new Date(readAt).getHours();
        hourlyCount[hour]++;
      }
    });
    const dailyDistribution = hourlyCount.map((count, hour) => ({ hour, count }));

    // Weekly distribution
    const weeklyCount = new Map<string, number>();
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    readArticles.forEach(({ readAt }) => {
      if (readAt) {
        const day = days[new Date(readAt).getDay()];
        weeklyCount.set(day, (weeklyCount.get(day) || 0) + 1);
      }
    });
    const weeklyDistribution = days.map(day => ({
      day,
      count: weeklyCount.get(day) || 0,
    }));

    // Monthly trend
    const dailyCount = new Map<string, number>();
    const today = new Date();
    for (let i = 29; i >= 0; i--) {
      const date = new Date(today);
      date.setDate(date.getDate() - i);
      const dateStr = date.toISOString().split('T')[0];
      dailyCount.set(dateStr, 0);
    }

    readArticles.forEach(({ readAt }) => {
      if (readAt) {
        const dateStr = new Date(readAt).toISOString().split('T')[0];
        if (dailyCount.has(dateStr)) {
          dailyCount.set(dateStr, dailyCount.get(dateStr)! + 1);
        }
      }
    });

    const monthlyTrend = Array.from(dailyCount.entries()).map(([date, count]) => ({ date, count }));

    // Category trends
    const categoryTrends = await this.analyzeCategoryTrends(userId, readArticles);

    // Velocity trend
    const velocityTrend = this.analyzeVelocityTrend(monthlyTrend);

    return {
      dailyDistribution,
      weeklyDistribution,
      monthlyTrend,
      categoryTrends,
      velocityTrend,
    };
  }

  private async calculateEngagementMetrics(userId: string, startDate: Date): Promise<EngagementMetrics> {
    const userStates = await this.db
      .select()
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, userId),
          gte(userArticleStates.createdAt, startDate)
        )
      );

    // Calculate average scroll depth
    const scrollDepths = userStates
      .filter(s => s.scrollPosition !== null)
      .map(s => s.scrollPosition!);
    const averageScrollDepth = scrollDepths.length > 0
      ? scrollDepths.reduce((a, b) => a + b, 0) / scrollDepths.length
      : 0;

    // Calculate average time per paragraph (estimate)
    const readArticlesWithTime = userStates.filter(s => s.isRead && s.readingTime);
    const totalReadingTime = readArticlesWithTime.reduce((sum, s) => sum + s.readingTime!, 0);
    const estimatedParagraphs = readArticlesWithTime.length * 10; // Assume 10 paragraphs per article
    const averageTimePerParagraph = estimatedParagraphs > 0
      ? (totalReadingTime / estimatedParagraphs) / 60 // Convert to minutes
      : 0;

    // Calculate rates
    const totalArticles = userStates.length;
    const starredCount = userStates.filter(s => s.isStarred).length;
    const annotatedCount = userStates.filter(s => s.highlights && s.highlights.length > 0).length;
    const notesCount = userStates.filter(s => s.notes).length;

    const bookmarkRate = totalArticles > 0 ? (starredCount / totalArticles) * 100 : 0;
    const annotationRate = totalArticles > 0 ? (annotatedCount / totalArticles) * 100 : 0;
    const shareRate = 0; // Would need sharing tracking

    // Calculate interaction score
    const interactionScore = Math.min(100, 
      (averageScrollDepth * 0.3) +
      (bookmarkRate * 0.2) +
      (annotationRate * 0.3) +
      (Math.min(averageTimePerParagraph * 10, 20))
    );

    return {
      averageScrollDepth: Math.round(averageScrollDepth),
      averageTimePerParagraph: Math.round(averageTimePerParagraph * 10) / 10,
      shareRate: Math.round(shareRate),
      bookmarkRate: Math.round(bookmarkRate),
      annotationRate: Math.round(annotationRate),
      interactionScore: Math.round(interactionScore),
    };
  }

  private async generateInsights(
    userId: string,
    analytics: {
      reading: ReadingAnalytics;
      preferences: ContentPreferences;
      patterns: ReadingPatterns;
      engagement: EngagementMetrics;
    }
  ): Promise<string[]> {
    const insights: string[] = [];

    // Reading habit insights
    if (analytics.reading.readingStreak > 7) {
      insights.push(`🔥 You're on a ${analytics.reading.readingStreak}-day reading streak! Keep it up!`);
    }

    if (analytics.reading.articlesPerDay > 10) {
      insights.push('📚 You\'re a power reader! You read more than 10 articles per day on average.');
    }

    // Time-based insights
    insights.push(`🕐 You're most active at ${analytics.reading.mostActiveHour}:00. Your peak reading time!`);
    insights.push(`📅 ${analytics.reading.mostActiveDay} is your most active reading day.`);

    // Content preference insights
    if (analytics.preferences.topCategories.length > 0) {
      const topCategory = analytics.preferences.topCategories[0];
      insights.push(`🏷️ ${topCategory.category} makes up ${topCategory.percentage}% of your reading.`);
    }

    if (analytics.preferences.readingSpeed > 300) {
      insights.push(`⚡ You're a fast reader at ${analytics.preferences.readingSpeed} words per minute!`);
    }

    // Engagement insights
    if (analytics.engagement.bookmarkRate > 20) {
      insights.push('⭐ You bookmark frequently! Consider organizing your saved articles into collections.');
    }

    if (analytics.engagement.annotationRate > 15) {
      insights.push('✍️ You\'re an active annotator! Your highlights help you remember key points.');
    }

    // Pattern insights
    if (analytics.patterns.velocityTrend === 'increasing') {
      insights.push('📈 Your reading velocity is increasing! You\'re reading more over time.');
    }

    // Recommendation insights
    const risingCategories = analytics.patterns.categoryTrends
      .filter(c => c.trend === 'rising')
      .slice(0, 2);
    if (risingCategories.length > 0) {
      insights.push(`🆙 You're reading more ${risingCategories.map(c => c.category).join(' and ')} content lately.`);
    }

    return insights;
  }

  private getStartDate(timeframe: 'week' | 'month' | 'year'): Date {
    const now = new Date();
    switch (timeframe) {
      case 'week':
        return subDays(now, 7);
      case 'month':
        return subDays(now, 30);
      case 'year':
        return subDays(now, 365);
    }
  }

  private calculateReadingStreaks(stats: any[]): { currentStreak: number; longestStreak: number } {
    if (stats.length === 0) return { currentStreak: 0, longestStreak: 0 };

    // Sort by date
    const sortedStats = stats.sort((a, b) => 
      new Date(a.date).getTime() - new Date(b.date).getTime()
    );

    let currentStreak = 0;
    let longestStreak = 0;
    let tempStreak = 0;
    let lastDate: Date | null = null;

    for (const stat of sortedStats) {
      const currentDate = new Date(stat.date);
      
      if (stat.articlesRead > 0) {
        if (!lastDate || this.isConsecutiveDay(lastDate, currentDate)) {
          tempStreak++;
        } else {
          tempStreak = 1;
        }
        
        longestStreak = Math.max(longestStreak, tempStreak);
        lastDate = currentDate;
      } else {
        tempStreak = 0;
      }
    }

    // Check if current streak is still active
    const today = new Date();
    if (lastDate && this.isConsecutiveDay(lastDate, today)) {
      currentStreak = tempStreak;
    }

    return { currentStreak, longestStreak };
  }

  private isConsecutiveDay(date1: Date, date2: Date): boolean {
    const diff = Math.abs(date2.getTime() - date1.getTime());
    const dayDiff = Math.floor(diff / (1000 * 60 * 60 * 24));
    return dayDiff === 1;
  }

  private async extractTopKeywords(articles: any[]): Promise<Array<{ keyword: string; frequency: number }>> {
    try {
      // Use AI to extract keywords
      const content = articles
        .slice(0, 20)
        .map(a => a.article.title + ' ' + (a.article.summary || ''))
        .join(' ');

      const analysis = await aiService.analyzeArticles(
        ['dummy-id'], // We're just using the service for keyword extraction
        'system',
        { analysisTypes: ['keywords'] }
      );

      // Simulate keyword extraction
      const commonWords = new Set(['the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for']);
      const wordFreq = new Map<string, number>();
      
      content.toLowerCase().split(/\s+/).forEach(word => {
        word = word.replace(/[^a-z0-9]/g, '');
        if (word.length > 3 && !commonWords.has(word)) {
          wordFreq.set(word, (wordFreq.get(word) || 0) + 1);
        }
      });

      return Array.from(wordFreq.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 10)
        .map(([keyword, frequency]) => ({ keyword, frequency }));
    } catch (error) {
      logger.error('Failed to extract keywords:', error);
      return [];
    }
  }

  private async analyzeCategoryTrends(userId: string, readArticles: any[]): Promise<Array<{
    category: string;
    trend: 'rising' | 'falling' | 'stable';
    change: number;
  }>> {
    // Group articles by week
    const weeklyCategories = new Map<number, Map<string, number>>();
    const now = Date.now();
    
    readArticles.forEach(({ readAt, categories }) => {
      if (readAt && categories) {
        const weekNumber = Math.floor((now - new Date(readAt).getTime()) / (7 * 24 * 60 * 60 * 1000));
        if (!weeklyCategories.has(weekNumber)) {
          weeklyCategories.set(weekNumber, new Map());
        }
        
        const weekMap = weeklyCategories.get(weekNumber)!;
        (categories as string[]).forEach(category => {
          weekMap.set(category, (weekMap.get(category) || 0) + 1);
        });
      }
    });

    // Calculate trends
    const trends: Array<{ category: string; trend: 'rising' | 'falling' | 'stable'; change: number }> = [];
    const allCategories = new Set<string>();
    
    weeklyCategories.forEach(weekMap => {
      weekMap.forEach((_, category) => allCategories.add(category));
    });

    allCategories.forEach(category => {
      const recentCount = weeklyCategories.get(0)?.get(category) || 0;
      const pastCount = weeklyCategories.get(3)?.get(category) || 0;
      
      if (recentCount > 0 || pastCount > 0) {
        const change = pastCount > 0 ? ((recentCount - pastCount) / pastCount) * 100 : 100;
        let trend: 'rising' | 'falling' | 'stable';
        
        if (change > 20) trend = 'rising';
        else if (change < -20) trend = 'falling';
        else trend = 'stable';
        
        trends.push({ category, trend, change: Math.round(change) });
      }
    });

    return trends.sort((a, b) => Math.abs(b.change) - Math.abs(a.change)).slice(0, 5);
  }

  private analyzeVelocityTrend(monthlyTrend: Array<{ date: string; count: number }>): 'increasing' | 'decreasing' | 'stable' {
    if (monthlyTrend.length < 7) return 'stable';

    // Compare recent week average to previous week
    const recentWeek = monthlyTrend.slice(-7).reduce((sum, d) => sum + d.count, 0) / 7;
    const previousWeek = monthlyTrend.slice(-14, -7).reduce((sum, d) => sum + d.count, 0) / 7;

    const change = previousWeek > 0 ? ((recentWeek - previousWeek) / previousWeek) * 100 : 0;

    if (change > 20) return 'increasing';
    if (change < -20) return 'decreasing';
    return 'stable';
  }

  private async getUnreadArticles(userId: string, limit: number) {
    return this.db
      .select({
        article: articles,
        feed: feeds,
      })
      .from(articles)
      .innerJoin(feeds, eq(feeds.id, articles.feedId))
      .leftJoin(
        userArticleStates,
        and(
          eq(userArticleStates.articleId, articles.id),
          eq(userArticleStates.userId, userId)
        )
      )
      .where(
        and(
          eq(feeds.userId, userId),
          sql`${userArticleStates.isRead} IS NULL OR ${userArticleStates.isRead} = false`
        )
      )
      .orderBy(desc(articles.publishedAt))
      .limit(limit);
  }

  private async scoreArticles(
    userId: string,
    articles: any[],
    preferences: ContentPreferences,
    patterns: ReadingPatterns
  ): Promise<Array<{ articleId: string; score: number; reasons: string[] }>> {
    const scoredArticles: Array<{ articleId: string; score: number; reasons: string[] }> = [];

    for (const { article, feed } of articles) {
      let score = 50; // Base score
      const reasons: string[] = [];

      // Category preference scoring
      if (article.categories && Array.isArray(article.categories)) {
        for (const category of article.categories) {
          const categoryPref = preferences.topCategories.find(c => c.category === category);
          if (categoryPref) {
            score += categoryPref.percentage * 0.5;
            reasons.push(`Popular category: ${category}`);
          }
        }
      }

      // Author preference scoring
      if (article.author) {
        const authorPref = preferences.topAuthors.find(a => a.author === article.author);
        if (authorPref) {
          score += 20;
          reasons.push(`Favorite author: ${article.author}`);
        }
      }

      // Source preference scoring
      const sourcePref = preferences.topSources.find(s => s.feedId === feed.id);
      if (sourcePref) {
        score += 15;
        reasons.push(`Favorite source: ${feed.title}`);
      }

      // Length preference scoring
      const wordCount = (article.content || '').split(/\s+/).length;
      let lengthCategory: 'short' | 'medium' | 'long';
      if (wordCount < 500) lengthCategory = 'short';
      else if (wordCount < 1500) lengthCategory = 'medium';
      else lengthCategory = 'long';

      if (lengthCategory === preferences.preferredLength) {
        score += 10;
        reasons.push(`Preferred length: ${lengthCategory}`);
      }

      // Time-based scoring
      const publishHour = new Date(article.publishedAt).getHours();
      const hourPreference = patterns.dailyDistribution.find(d => d.hour === publishHour);
      if (hourPreference && hourPreference.count > 0) {
        score += 5;
        reasons.push('Published during your active hours');
      }

      // Freshness scoring
      const ageInHours = (Date.now() - new Date(article.publishedAt).getTime()) / (1000 * 60 * 60);
      if (ageInHours < 24) {
        score += 10;
        reasons.push('Fresh content');
      }

      // Keyword matching
      const articleText = `${article.title} ${article.summary || ''}`.toLowerCase();
      for (const { keyword } of preferences.topKeywords) {
        if (articleText.includes(keyword.toLowerCase())) {
          score += 5;
          reasons.push(`Contains keyword: ${keyword}`);
          break;
        }
      }

      scoredArticles.push({
        articleId: article.id,
        score: Math.min(100, score),
        reasons,
      });
    }

    return scoredArticles.sort((a, b) => b.score - a.score);
  }

  private async recommendFeeds(userId: string, preferences: ContentPreferences): Promise<Array<{
    feedId: string;
    score: number;
    reasons: string[];
  }>> {
    // This would integrate with the feed discovery service
    // For now, return empty array
    return [];
  }

  private recommendCategories(preferences: ContentPreferences, patterns: ReadingPatterns): string[] {
    const recommendations: string[] = [];

    // Recommend rising categories
    const risingCategories = patterns.categoryTrends
      .filter(c => c.trend === 'rising')
      .map(c => c.category);
    recommendations.push(...risingCategories);

    // Recommend related categories
    const relatedCategories: { [key: string]: string[] } = {
      'Technology': ['AI', 'Programming', 'Startups'],
      'Science': ['Space', 'Health', 'Environment'],
      'Business': ['Finance', 'Economics', 'Entrepreneurship'],
      'Politics': ['World News', 'Policy', 'International Relations'],
    };

    preferences.topCategories.forEach(({ category }) => {
      if (relatedCategories[category]) {
        recommendations.push(...relatedCategories[category]);
      }
    });

    // Remove duplicates and existing preferences
    const existingCategories = new Set(preferences.topCategories.map(c => c.category));
    return [...new Set(recommendations)].filter(c => !existingCategories.has(c)).slice(0, 5);
  }

  private calculateReadingGoals(patterns: ReadingPatterns): {
    daily: number;
    weekly: number;
    suggestions: string[];
  } {
    // Calculate current averages
    const recentDays = patterns.monthlyTrend.slice(-7);
    const currentDailyAverage = recentDays.reduce((sum, d) => sum + d.count, 0) / 7;
    const currentWeeklyTotal = recentDays.reduce((sum, d) => sum + d.count, 0);

    // Set goals based on current performance
    const daily = Math.max(3, Math.ceil(currentDailyAverage * 1.1)); // 10% increase
    const weekly = Math.max(20, Math.ceil(currentWeeklyTotal * 1.1));

    const suggestions: string[] = [];

    if (currentDailyAverage < 5) {
      suggestions.push('Try to read at least 5 articles per day to stay informed');
    }

    if (patterns.velocityTrend === 'decreasing') {
      suggestions.push('Your reading has decreased lately. Set aside dedicated reading time');
    }

    // Suggest optimal reading times
    const peakHours = patterns.dailyDistribution
      .sort((a, b) => b.count - a.count)
      .slice(0, 3)
      .map(d => d.hour);
    suggestions.push(`Your best reading times are around ${peakHours.join(', ')}:00`);

    return { daily, weekly, suggestions };
  }

  async trackReadingProgress(userId: string, articleId: string, progress: number): Promise<void> {
    try {
      await this.db
        .update(userArticleStates)
        .set({
          scrollPosition: progress,
          updatedAt: new Date(),
        })
        .where(
          and(
            eq(userArticleStates.userId, userId),
            eq(userArticleStates.articleId, articleId)
          )
        );

      // Update real-time analytics
      await this.redis.hset(
        `reading:progress:${userId}`,
        articleId,
        progress.toString()
      );
    } catch (error) {
      logger.error('Failed to track reading progress:', error);
    }
  }

  async generateDailyDigest(userId: string): Promise<{
    summary: string;
    recommendations: string[];
    stats: {
      articlesRead: number;
      readingTime: number;
      topCategory: string;
    };
  }> {
    const today = startOfDay(new Date());
    const analytics = await this.getUserAnalytics(userId, 'week');
    const recommendations = await this.getPersonalizedRecommendations(userId);

    // Get today's stats
    const todayStats = await this.db
      .select()
      .from(readingStats)
      .where(
        and(
          eq(readingStats.userId, userId),
          eq(readingStats.date, today)
        )
      )
      .limit(1);

    const stats = todayStats[0] || {
      articlesRead: 0,
      readingTime: 0,
      categories: {},
    };

    const topCategory = Object.entries(stats.categories || {})
      .sort((a, b) => (b[1] as number) - (a[1] as number))[0]?.[0] || 'General';

    // Generate summary using AI
    const summary = await this.generateAISummary(userId, analytics, recommendations);

    return {
      summary,
      recommendations: recommendations.articles.slice(0, 5).map(a => 
        `Article: ${a.articleId} (Score: ${a.score}%)`
      ),
      stats: {
        articlesRead: stats.articlesRead,
        readingTime: Math.round(stats.readingTime / 60), // Convert to minutes
        topCategory,
      },
    };
  }

  private async generateAISummary(
    userId: string,
    analytics: any,
    recommendations: PersonalizedRecommendations
  ): Promise<string> {
    try {
      const prompt = `Generate a brief, friendly daily digest summary for a user with these reading habits:
- Reads ${analytics.reading.articlesPerDay} articles per day
- Favorite categories: ${analytics.preferences.topCategories.map((c: any) => c.category).join(', ')}
- Most active at ${analytics.reading.mostActiveHour}:00
- Current streak: ${analytics.reading.readingStreak} days
- Reading trend: ${analytics.patterns.velocityTrend}

Keep it encouraging and under 3 sentences.`;

      const result = await aiService.generateContent(userId, {
        prompt,
        maxTokens: 150,
        temperature: 0.7,
      });

      return result.text;
    } catch (error) {
      logger.error('Failed to generate AI summary:', error);
      return `Great job maintaining your ${analytics.reading.readingStreak}-day reading streak! You're most active at ${analytics.reading.mostActiveHour}:00, and ${analytics.preferences.topCategories[0]?.category || 'Technology'} remains your favorite topic.`;
    }
  }
}

// Export singleton instance
export const analyticsService = new AnalyticsService();