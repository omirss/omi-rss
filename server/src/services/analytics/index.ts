import { getDb } from '../../database';
import {
  articles,
  feeds,
  userArticleStates,
  readingStats,
} from '../../database/schema';
import { eq, and, gte, sql, desc } from 'drizzle-orm';
import { logger } from '../../utils/logger';
import { getRedis } from '../redis';

interface ReadingAnalytics {
  totalArticlesRead: number;
  totalReadingTime: number;
  averageReadingTime: number;
  articlesPerDay: number;
  mostActiveHour: number;
  mostActiveDay: string;
  readingStreak: number;
  longestStreak: number;
  completionRate: number;
}

interface ContentPreferences {
  topCategories: Array<{ category: string; count: number; percentage: number }>;
  topAuthors: Array<{ author: string; count: number; articles: number }>;
  topSources: Array<{ source: string; feedId: string; count: number }>;
  preferredLength: 'short' | 'medium' | 'long';
  readingSpeed: number;
  topKeywords: Array<{ keyword: string; frequency: number }>;
}

interface ReadingPatterns {
  dailyDistribution: Array<{ hour: number; count: number }>;
  weeklyDistribution: Array<{ day: string; count: number }>;
  monthlyTrend: Array<{ date: string; count: number }>;
  categoryTrends: Array<{ category: string; trend: 'rising' | 'falling' | 'stable'; change: number }>;
  velocityTrend: 'increasing' | 'decreasing' | 'stable';
}

interface EngagementMetrics {
  averageScrollDepth: number;
  averageTimePerParagraph: number;
  shareRate: number;
  bookmarkRate: number;
  annotationRate: number;
  interactionScore: number;
}

export type AnalyticsTimeframe = 'day' | 'week' | 'month' | 'year' | 'all';

export class AnalyticsService {
  private get redis() {
    return getRedis();
  }
  private get db() {
    return getDb();
  }

  async getUserAnalytics(userId: string, timeframe: AnalyticsTimeframe = 'month'): Promise<{
    reading: ReadingAnalytics;
    preferences: ContentPreferences;
    patterns: ReadingPatterns;
    engagement: EngagementMetrics;
    insights: string[];
  }> {
    const startDate = this.getStartDate(timeframe);

    const reading = await this.calculateReadingAnalytics(userId, startDate);
    const preferences = await this.analyzeContentPreferences(userId, startDate);
    const patterns = await this.analyzeReadingPatterns(userId, startDate);
    const engagement = await this.calculateEngagementMetrics(userId, startDate);
    const insights = this.generateInsights({ reading, preferences, patterns, engagement });

    await this.redis.set(
      `analytics:${userId}:${timeframe}`,
      JSON.stringify({ reading, preferences, patterns, engagement, insights }),
      'EX',
      3600,
    );

    return { reading, preferences, patterns, engagement, insights };
  }

  async trackArticleRead(
    userId: string,
    data: {
      articleId: string;
      scrollDepth: number;
      interactionTime: number;
      completed: boolean;
    },
  ): Promise<void> {
    const now = new Date();

    await this.db
      .insert(userArticleStates)
      .values({
        userId,
        articleId: data.articleId,
        isRead: data.completed,
        readAt: data.completed ? now : null,
        readingTime: data.interactionTime,
        scrollPosition: Math.round(data.scrollDepth),
        updatedAt: now,
      })
      .onConflictDoUpdate({
        target: [userArticleStates.userId, userArticleStates.articleId],
        set: {
          readingTime: sql`COALESCE(${userArticleStates.readingTime}, 0) + ${data.interactionTime}`,
          scrollPosition: Math.round(data.scrollDepth),
          updatedAt: now,
          ...(data.completed && {
            isRead: true,
            readAt: now,
          }),
        },
      });

    const day = startOfDay(now);
    const hour = now.getHours().toString();

    await this.db
      .insert(readingStats)
      .values({
        userId,
        date: day,
        articlesRead: data.completed ? 1 : 0,
        readingTime: data.interactionTime,
        hourlyDistribution: { [hour]: 1 },
      })
      .onConflictDoUpdate({
        target: [readingStats.userId, readingStats.date],
        set: {
          articlesRead: data.completed
            ? sql`${readingStats.articlesRead} + 1`
            : sql`${readingStats.articlesRead}`,
          readingTime: sql`${readingStats.readingTime} + ${data.interactionTime}`,
          hourlyDistribution: sql`jsonb_set(
            COALESCE(${readingStats.hourlyDistribution}, '{}'::jsonb),
            ARRAY[${hour}],
            to_jsonb(COALESCE((${readingStats.hourlyDistribution} ->> ${hour})::int, 0) + 1)
          )`,
          updatedAt: now,
        },
      });
  }

  async trackFeedInteraction(
    userId: string,
    data: { feedId: string; action: 'subscribe' | 'unsubscribe' | 'mute' | 'favorite' },
  ): Promise<void> {
    try {
      await this.redis.hincrby(
        `analytics:feed-interactions:${userId}`,
        `${data.action}:${data.feedId}`,
        1,
      );
    } catch (error) {
      logger.error('Failed to track feed interaction:', error);
    }
  }

  async getReadingStreaks(userId: string): Promise<{
    currentStreak: number;
    longestStreak: number;
    dailyHistory: Array<{ date: string; articlesRead: number }>;
  }> {
    const stats = await this.db
      .select()
      .from(readingStats)
      .where(eq(readingStats.userId, userId))
      .orderBy(desc(readingStats.date))
      .limit(60);

    const { currentStreak, longestStreak } = this.calculateReadingStreaks(
      stats.slice().reverse(),
    );

    return {
      currentStreak,
      longestStreak,
      dailyHistory: stats.map((s) => ({
        date: s.date.toISOString().split('T')[0],
        articlesRead: s.articlesRead,
      })),
    };
  }

  async exportUserData(userId: string): Promise<{
    userId: string;
    exportedAt: string;
    totals: { articlesRead: number; articlesStarred: number; totalReadingTime: number };
    readingStats: Array<{
      date: string;
      articlesRead: number;
      readingTime: number;
      wordsRead: number;
    }>;
  }> {
    const [totals] = await this.db
      .select({
        articlesRead: sql<number>`COUNT(*) FILTER (WHERE ${userArticleStates.isRead} = true)`,
        articlesStarred: sql<number>`COUNT(*) FILTER (WHERE ${userArticleStates.isStarred} = true)`,
        totalReadingTime: sql<number>`COALESCE(SUM(${userArticleStates.readingTime}), 0)`,
      })
      .from(userArticleStates)
      .where(eq(userArticleStates.userId, userId));

    const stats = await this.db
      .select({
        date: readingStats.date,
        articlesRead: readingStats.articlesRead,
        readingTime: readingStats.readingTime,
        wordsRead: readingStats.wordsRead,
      })
      .from(readingStats)
      .where(eq(readingStats.userId, userId))
      .orderBy(desc(readingStats.date));

    return {
      userId,
      exportedAt: new Date().toISOString(),
      totals: {
        articlesRead: Number(totals?.articlesRead || 0),
        articlesStarred: Number(totals?.articlesStarred || 0),
        totalReadingTime: Number(totals?.totalReadingTime || 0),
      },
      readingStats: stats.map((s) => ({
        date: s.date.toISOString().split('T')[0],
        articlesRead: s.articlesRead,
        readingTime: s.readingTime,
        wordsRead: s.wordsRead,
      })),
    };
  }

  private async calculateReadingAnalytics(userId: string, startDate: Date): Promise<ReadingAnalytics> {
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
          gte(userArticleStates.readAt, startDate),
        ),
      );

    const stats = await this.db
      .select()
      .from(readingStats)
      .where(
        and(
          eq(readingStats.userId, userId),
          gte(readingStats.date, startDate),
        ),
      );

    const totalArticlesRead = readArticles.length;
    const totalReadingTime = readArticles.reduce((sum, a) => sum + (a.readingTime || 0), 0) / 60;
    const averageReadingTime = totalArticlesRead > 0 ? totalReadingTime / totalArticlesRead : 0;

    const daysSinceStart = Math.max(1, Math.floor((Date.now() - startDate.getTime()) / (1000 * 60 * 60 * 24)));
    const articlesPerDay = totalArticlesRead / daysSinceStart;

    const hourlyDistribution = new Map<number, number>();
    readArticles.forEach(article => {
      if (article.readAt) {
        const hour = new Date(article.readAt).getHours();
        hourlyDistribution.set(hour, (hourlyDistribution.get(hour) || 0) + 1);
      }
    });
    const mostActiveHour = Array.from(hourlyDistribution.entries())
      .sort((a, b) => b[1] - a[1])[0]?.[0] || 0;

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

    const { currentStreak, longestStreak } = this.calculateReadingStreaks(
      stats.slice().sort((a, b) => a.date.getTime() - b.date.getTime()),
    );

    const startedArticles = await this.db
      .select({ count: sql<number>`count(*)` })
      .from(userArticleStates)
      .where(
        and(
          eq(userArticleStates.userId, userId),
          gte(userArticleStates.createdAt, startDate),
          sql`${userArticleStates.scrollPosition} > 0`,
        ),
      );

    const completionRate = startedArticles[0]?.count
      ? (totalArticlesRead / Number(startedArticles[0].count)) * 100
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
          gte(userArticleStates.readAt, startDate),
        ),
      );

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
        percentage: Math.round((count / Math.max(1, totalCategoryCount)) * 100),
      }));

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

    const readingSpeed = totalReadingTime > 0
      ? Math.round(totalWords / (totalReadingTime / 60))
      : 250;

    const topKeywords = this.extractTopKeywords(readArticles.slice(0, 50));

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
          gte(userArticleStates.readAt, startDate),
        ),
      );

    const hourlyCount: number[] = Array.from({ length: 24 }, () => 0);
    readArticles.forEach(({ readAt }) => {
      if (readAt) {
        const hour = new Date(readAt).getHours();
        hourlyCount[hour]++;
      }
    });
    const dailyDistribution = hourlyCount.map((count, hour) => ({ hour, count }));

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
          dailyCount.set(dateStr, (dailyCount.get(dateStr)! || 0) + 1);
        }
      }
    });

    const monthlyTrend = Array.from(dailyCount.entries()).map(([date, count]) => ({ date, count }));

    const categoryTrends = this.analyzeCategoryTrends(readArticles);
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
          gte(userArticleStates.createdAt, startDate),
        ),
      );

    const scrollDepths = userStates
      .filter(s => s.scrollPosition !== null)
      .map(s => s.scrollPosition!);
    const averageScrollDepth = scrollDepths.length > 0
      ? scrollDepths.reduce((a, b) => a + b, 0) / scrollDepths.length
      : 0;

    const readArticlesWithTime = userStates.filter(s => s.isRead && s.readingTime);
    const totalReadingTime = readArticlesWithTime.reduce((sum, s) => sum + s.readingTime!, 0);
    const estimatedParagraphs = readArticlesWithTime.length * 10;
    const averageTimePerParagraph = estimatedParagraphs > 0
      ? (totalReadingTime / estimatedParagraphs) / 60
      : 0;

    const totalArticles = userStates.length;
    const starredCount = userStates.filter(s => s.isStarred).length;
    const annotatedCount = userStates.filter(s => s.highlights && (s.highlights as unknown[]).length > 0).length;

    const bookmarkRate = totalArticles > 0 ? (starredCount / totalArticles) * 100 : 0;
    const annotationRate = totalArticles > 0 ? (annotatedCount / totalArticles) * 100 : 0;
    const shareRate = 0;

    const interactionScore = Math.min(100,
      (averageScrollDepth * 0.3) +
      (bookmarkRate * 0.2) +
      (annotationRate * 0.3) +
      (Math.min(averageTimePerParagraph * 10, 20)),
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

  private generateInsights(analytics: {
    reading: ReadingAnalytics;
    preferences: ContentPreferences;
    patterns: ReadingPatterns;
    engagement: EngagementMetrics;
  }): string[] {
    const insights: string[] = [];

    if (analytics.reading.readingStreak > 7) {
      insights.push(`You are on a ${analytics.reading.readingStreak}-day reading streak.`);
    }

    if (analytics.reading.articlesPerDay > 10) {
      insights.push('You read more than 10 articles per day on average.');
    }

    insights.push(`You are most active at ${analytics.reading.mostActiveHour}:00.`);
    insights.push(`${analytics.reading.mostActiveDay} is your most active reading day.`);

    if (analytics.preferences.topCategories.length > 0) {
      const topCategory = analytics.preferences.topCategories[0];
      insights.push(`${topCategory.category} makes up ${topCategory.percentage}% of your reading.`);
    }

    if (analytics.preferences.readingSpeed > 300) {
      insights.push(`You read fast at ${analytics.preferences.readingSpeed} words per minute.`);
    }

    if (analytics.engagement.bookmarkRate > 20) {
      insights.push('You bookmark frequently. Consider organizing saved articles into folders.');
    }

    if (analytics.patterns.velocityTrend === 'increasing') {
      insights.push('Your reading velocity is increasing.');
    }

    const risingCategories = analytics.patterns.categoryTrends
      .filter(c => c.trend === 'rising')
      .slice(0, 2);
    if (risingCategories.length > 0) {
      insights.push(`You are reading more ${risingCategories.map(c => c.category).join(' and ')} content lately.`);
    }

    return insights;
  }

  private getStartDate(timeframe: AnalyticsTimeframe): Date {
    const now = Date.now();
    switch (timeframe) {
      case 'day':
        return new Date(now - 1 * 24 * 60 * 60 * 1000);
      case 'week':
        return new Date(now - 7 * 24 * 60 * 60 * 1000);
      case 'month':
        return new Date(now - 30 * 24 * 60 * 60 * 1000);
      case 'year':
        return new Date(now - 365 * 24 * 60 * 60 * 1000);
      case 'all':
        return new Date(0);
    }
  }

  private calculateReadingStreaks(
    stats: Array<{ date: Date; articlesRead: number }>,
  ): { currentStreak: number; longestStreak: number } {
    if (stats.length === 0) return { currentStreak: 0, longestStreak: 0 };

    const sortedStats = stats.sort((a, b) => a.date.getTime() - b.date.getTime());

    let currentStreak = 0;
    let longestStreak = 0;
    let tempStreak = 0;
    let lastDate: Date | null = null;

    for (const stat of sortedStats) {
      if (stat.articlesRead > 0) {
        if (!lastDate || this.isConsecutiveDay(lastDate, stat.date)) {
          tempStreak++;
        } else {
          tempStreak = 1;
        }

        longestStreak = Math.max(longestStreak, tempStreak);
        lastDate = stat.date;
      } else {
        tempStreak = 0;
      }
    }

    const today = new Date();
    if (lastDate && this.isConsecutiveDay(lastDate, today)) {
      currentStreak = tempStreak;
    } else if (lastDate && this.isSameDay(lastDate, today)) {
      currentStreak = tempStreak;
    }

    return { currentStreak, longestStreak };
  }

  private isSameDay(date1: Date, date2: Date): boolean {
    return date1.toISOString().split('T')[0] === date2.toISOString().split('T')[0];
  }

  private isConsecutiveDay(date1: Date, date2: Date): boolean {
    const diff = Math.abs(date2.getTime() - date1.getTime());
    const dayDiff = Math.floor(diff / (1000 * 60 * 60 * 24));
    return dayDiff === 1;
  }

  private extractTopKeywords(
    readArticles: Array<{ article: { title: string; summary: string | null } }>,
  ): Array<{ keyword: string; frequency: number }> {
    const content = readArticles
      .slice(0, 20)
      .map((a) => `${a.article.title} ${a.article.summary || ''}`)
      .join(' ');

    const commonWords = new Set(['the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'is', 'are', 'was', 'were', 'be', 'been', 'has', 'have', 'had', 'this', 'that', 'from', 'as', 'by', 'it', 'its']);
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
  }

  private analyzeCategoryTrends(readArticles: Array<{ readAt: Date | null; categories: unknown }>): Array<{
    category: string;
    trend: 'rising' | 'falling' | 'stable';
    change: number;
  }> {
    const weeklyCategories = new Map<number, Map<string, number>>();
    const now = Date.now();

    readArticles.forEach(({ readAt, categories }) => {
      if (readAt && Array.isArray(categories)) {
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
    if (monthlyTrend.length < 14) return 'stable';

    const recentWeek = monthlyTrend.slice(-7).reduce((sum, d) => sum + d.count, 0) / 7;
    const previousWeek = monthlyTrend.slice(-14, -7).reduce((sum, d) => sum + d.count, 0) / 7;

    const change = previousWeek > 0 ? ((recentWeek - previousWeek) / previousWeek) * 100 : 0;

    if (change > 20) return 'increasing';
    if (change < -20) return 'decreasing';
    return 'stable';
  }
}

function startOfDay(date: Date): Date {
  const result = new Date(date);
  result.setHours(0, 0, 0, 0);
  return result;
}

export const analyticsService = new AnalyticsService();
