import 'package:serverpod/serverpod.dart';
import '../generated/protocol.dart';

class AnalyticsEndpoint extends Endpoint {
  // Get reading analytics for the current user
  Future<ReadingAnalytics> getReadingAnalytics(
    Session session,
    DateTime startDate,
    DateTime endDate,
  ) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      // Validate date range
      if (endDate.isBefore(startDate)) {
        throw Exception('End date must be after start date');
      }
      
      if (endDate.difference(startDate).inDays > 365) {
        throw Exception('Date range cannot exceed 365 days');
      }
      
      // Get reading activity
      final readHistory = await ReadHistory.find(
        session,
        where: (t) => t.userId.equals(userId) & 
                     t.readAt.afterOrEqualTo(startDate) & 
                     t.readAt.beforeOrEqualTo(endDate),
        orderBy: (t) => t.readAt,
      );
      
      // Calculate daily stats
      final dailyStats = _calculateDailyStats(readHistory);
      
      // Get top sources
      final topSources = await _getTopSources(session, userId, startDate, endDate);
      
      // Get reading time distribution
      final timeDistribution = _calculateTimeDistribution(readHistory);
      
      // Get category breakdown
      final categoryBreakdown = await _getCategoryBreakdown(session, userId, startDate, endDate);
      
      return ReadingAnalytics(
        startDate: startDate,
        endDate: endDate,
        totalArticlesRead: readHistory.length,
        averageArticlesPerDay: readHistory.isEmpty ? 0 : readHistory.length / endDate.difference(startDate).inDays,
        dailyStats: dailyStats,
        topSources: topSources,
        timeDistribution: timeDistribution,
        categoryBreakdown: categoryBreakdown,
        readingStreak: await _calculateDetailedStreak(session, userId),
      );
    } catch (e) {
      session.log('Error fetching reading analytics: $e', level: LogLevel.error);
      throw Exception('Failed to fetch analytics');
    }
  }
  
  // Get feed performance metrics
  Future<List<FeedPerformance>> getFeedPerformance(
    Session session,
    int? limit,
  ) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      // Get all user subscriptions
      final subscriptions = await FeedSubscription.find(
        session,
        where: (t) => t.userId.equals(userId),
        include: FeedSubscription.include(
          feed: Feed.include(),
        ),
      );
      
      final performances = <FeedPerformance>[];
      
      for (final subscription in subscriptions) {
        if (subscription.feed == null) continue;
        
        // Calculate metrics for each feed
        final metrics = await _calculateFeedMetrics(
          session,
          userId,
          subscription.feedId,
          subscription.feed!,
        );
        
        performances.add(metrics);
      }
      
      // Sort by engagement rate
      performances.sort((a, b) => b.engagementRate.compareTo(a.engagementRate));
      
      // Apply limit if specified
      if (limit != null && limit > 0 && performances.length > limit) {
        return performances.take(limit).toList();
      }
      
      return performances;
    } catch (e) {
      session.log('Error fetching feed performance: $e', level: LogLevel.error);
      throw Exception('Failed to fetch feed performance');
    }
  }
  
  // Track user event
  Future<bool> trackEvent(
    Session session,
    String eventName,
    Map<String, dynamic> properties,
  ) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      // Validate event name
      if (!_isValidEventName(eventName)) {
        throw Exception('Invalid event name');
      }
      
      // Create analytics event
      final event = AnalyticsEvent(
        userId: userId,
        eventName: eventName,
        properties: properties,
        timestamp: DateTime.now(),
        sessionId: session.sessionId,
        userAgent: session.httpRequest?.headers.value('user-agent'),
        ipAddress: session.httpRequest?.connectionInfo?.remoteAddress.address,
      );
      
      await event.insert(session);
      
      // Process event for real-time analytics if needed
      await _processRealtimeEvent(session, event);
      
      return true;
    } catch (e) {
      session.log('Error tracking event: $e', level: LogLevel.error);
      throw Exception('Failed to track event');
    }
  }
  
  // Get user engagement metrics
  Future<EngagementMetrics> getEngagementMetrics(Session session) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(Duration(days: 30));
      
      // Get session data
      final sessions = await _getUserSessions(session, userId, thirtyDaysAgo, now);
      
      // Calculate metrics
      final dailyActiveUsers = _calculateDAU(sessions);
      final weeklyActiveUsers = _calculateWAU(sessions);
      final monthlyActiveUsers = _calculateMAU(sessions);
      
      // Get feature usage
      final featureUsage = await _getFeatureUsage(session, userId, thirtyDaysAgo, now);
      
      // Get retention metrics
      final retention = await _calculateRetention(session, userId);
      
      return EngagementMetrics(
        dailyActiveUsers: dailyActiveUsers,
        weeklyActiveUsers: weeklyActiveUsers,
        monthlyActiveUsers: monthlyActiveUsers,
        averageSessionDuration: _calculateAverageSessionDuration(sessions),
        bounceRate: _calculateBounceRate(sessions),
        featureUsage: featureUsage,
        retentionRate: retention,
      );
    } catch (e) {
      session.log('Error fetching engagement metrics: $e', level: LogLevel.error);
      throw Exception('Failed to fetch engagement metrics');
    }
  }
  
  // Get content insights
  Future<ContentInsights> getContentInsights(
    Session session,
    int? feedId,
  ) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      // Get articles based on feed filter
      final articles = await _getArticlesForInsights(session, userId, feedId);
      
      // Analyze content
      final topKeywords = await _extractTopKeywords(articles);
      final readingTimeStats = _calculateReadingTimeStats(articles);
      final popularTopics = await _identifyPopularTopics(articles);
      final contentLength = _analyzeContentLength(articles);
      
      return ContentInsights(
        totalArticles: articles.length,
        topKeywords: topKeywords,
        averageReadingTime: readingTimeStats['average'] ?? 0,
        readingTimeDistribution: readingTimeStats['distribution'] ?? {},
        popularTopics: popularTopics,
        contentLengthDistribution: contentLength,
        engagementByLength: await _calculateEngagementByLength(session, userId, articles),
      );
    } catch (e) {
      session.log('Error fetching content insights: $e', level: LogLevel.error);
      throw Exception('Failed to fetch content insights');
    }
  }
  
  // Helper methods
  
  Map<String, int> _calculateDailyStats(List<ReadHistory> readHistory) {
    final dailyStats = <String, int>{};
    
    for (final entry in readHistory) {
      final dateKey = '${entry.readAt.year}-${entry.readAt.month.toString().padLeft(2, '0')}-${entry.readAt.day.toString().padLeft(2, '0')}';
      dailyStats[dateKey] = (dailyStats[dateKey] ?? 0) + 1;
    }
    
    return dailyStats;
  }
  
  Future<List<TopSource>> _getTopSources(
    Session session,
    int userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    // This would typically use a more efficient query with grouping
    // For now, we'll do it in memory
    final readHistory = await ReadHistory.find(
      session,
      where: (t) => t.userId.equals(userId) & 
                   t.readAt.afterOrEqualTo(startDate) & 
                   t.readAt.beforeOrEqualTo(endDate),
      include: ReadHistory.include(
        article: Article.include(
          feed: Feed.include(),
        ),
      ),
    );
    
    final sourceCount = <String, int>{};
    
    for (final entry in readHistory) {
      if (entry.article?.feed != null) {
        final feedTitle = entry.article!.feed!.title;
        sourceCount[feedTitle] = (sourceCount[feedTitle] ?? 0) + 1;
      }
    }
    
    // Convert to list and sort
    final topSources = sourceCount.entries
        .map((e) => TopSource(name: e.key, articleCount: e.value))
        .toList()
      ..sort((a, b) => b.articleCount.compareTo(a.articleCount));
    
    return topSources.take(10).toList();
  }
  
  Map<String, double> _calculateTimeDistribution(List<ReadHistory> readHistory) {
    final hourCounts = List.filled(24, 0);
    
    for (final entry in readHistory) {
      hourCounts[entry.readAt.hour]++;
    }
    
    final total = readHistory.length;
    final distribution = <String, double>{};
    
    for (int i = 0; i < 24; i++) {
      distribution['$i:00'] = total > 0 ? (hourCounts[i] / total) * 100 : 0;
    }
    
    return distribution;
  }
  
  Future<Map<String, int>> _getCategoryBreakdown(
    Session session,
    int userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    // This would typically categorize based on feed categories or tags
    // For now, returning a placeholder
    return {
      'Technology': 45,
      'Business': 30,
      'Science': 15,
      'Entertainment': 10,
    };
  }
  
  Future<int> _calculateDetailedStreak(Session session, int userId) async {
    // Reuse the streak calculation from user endpoint
    final thirtyDaysAgo = DateTime.now().subtract(Duration(days: 30));
    
    final readHistory = await ReadHistory.find(
      session,
      where: (t) => t.userId.equals(userId) & t.readAt.afterOrEqualTo(thirtyDaysAgo),
      orderBy: (t) => t.readAt,
      orderDescending: true,
    );
    
    if (readHistory.isEmpty) return 0;
    
    int streak = 0;
    DateTime? lastDate;
    
    for (final entry in readHistory) {
      final entryDate = DateTime(entry.readAt.year, entry.readAt.month, entry.readAt.day);
      
      if (lastDate == null) {
        final today = DateTime.now();
        final daysDiff = today.difference(entryDate).inDays;
        
        if (daysDiff > 1) return 0;
        
        streak = 1;
        lastDate = entryDate;
      } else {
        final daysDiff = lastDate.difference(entryDate).inDays;
        
        if (daysDiff == 1) {
          streak++;
          lastDate = entryDate;
        } else if (daysDiff > 1) {
          break;
        }
      }
    }
    
    return streak;
  }
  
  Future<FeedPerformance> _calculateFeedMetrics(
    Session session,
    int userId,
    int feedId,
    Feed feed,
  ) async {
    // Get read history for this feed
    final readCount = await ReadHistory.count(
      session,
      where: (t) => t.userId.equals(userId) & t.article.feedId.equals(feedId),
    );
    
    // Get total articles from this feed
    final totalArticles = await Article.count(
      session,
      where: (t) => t.feedId.equals(feedId),
    );
    
    // Get saved articles from this feed
    final savedCount = await SavedArticle.count(
      session,
      where: (t) => t.userId.equals(userId) & t.article.feedId.equals(feedId),
    );
    
    // Calculate engagement rate
    final engagementRate = totalArticles > 0 ? (readCount / totalArticles) * 100 : 0;
    
    return FeedPerformance(
      feedId: feedId,
      feedTitle: feed.title,
      totalArticles: totalArticles,
      readArticles: readCount,
      savedArticles: savedCount,
      engagementRate: engagementRate,
      lastRead: DateTime.now(), // Would get actual last read time
    );
  }
  
  bool _isValidEventName(String eventName) {
    const validEvents = [
      'article_read',
      'article_saved',
      'article_shared',
      'feed_subscribed',
      'feed_unsubscribed',
      'folder_created',
      'search_performed',
      'settings_changed',
      'export_requested',
    ];
    
    return validEvents.contains(eventName);
  }
  
  Future<void> _processRealtimeEvent(Session session, AnalyticsEvent event) async {
    // This would typically send to a real-time analytics service
    // or update real-time dashboards
    session.log('Analytics event: ${event.eventName} for user ${event.userId}');
  }
  
  Future<List<SessionData>> _getUserSessions(
    Session session,
    int userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    // This would typically track actual user sessions
    // For now, returning mock data
    return [];
  }
  
  int _calculateDAU(List<SessionData> sessions) {
    // Calculate daily active users from session data
    return 1; // Placeholder
  }
  
  int _calculateWAU(List<SessionData> sessions) {
    // Calculate weekly active users from session data
    return 1; // Placeholder
  }
  
  int _calculateMAU(List<SessionData> sessions) {
    // Calculate monthly active users from session data
    return 1; // Placeholder
  }
  
  double _calculateAverageSessionDuration(List<SessionData> sessions) {
    // Calculate average session duration in minutes
    return 15.5; // Placeholder
  }
  
  double _calculateBounceRate(List<SessionData> sessions) {
    // Calculate bounce rate percentage
    return 25.0; // Placeholder
  }
  
  Future<Map<String, int>> _getFeatureUsage(
    Session session,
    int userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    // Track feature usage from analytics events
    return {
      'search': 45,
      'save_article': 128,
      'share': 23,
      'export': 5,
    };
  }
  
  Future<double> _calculateRetention(Session session, int userId) async {
    // Calculate user retention rate
    return 75.0; // Placeholder
  }
  
  Future<List<Article>> _getArticlesForInsights(
    Session session,
    int userId,
    int? feedId,
  ) async {
    if (feedId != null) {
      return await Article.find(
        session,
        where: (t) => t.feedId.equals(feedId),
        limit: 1000,
      );
    } else {
      // Get articles from user's subscribed feeds
      final subscriptions = await FeedSubscription.find(
        session,
        where: (t) => t.userId.equals(userId),
      );
      
      final feedIds = subscriptions.map((s) => s.feedId).toList();
      
      if (feedIds.isEmpty) return [];
      
      return await Article.find(
        session,
        where: (t) => t.feedId.inSet(feedIds),
        limit: 1000,
      );
    }
  }
  
  Future<List<String>> _extractTopKeywords(List<Article> articles) async {
    // This would use NLP to extract keywords
    // For now, returning placeholder
    return ['technology', 'innovation', 'startup', 'AI', 'development'];
  }
  
  Map<String, dynamic> _calculateReadingTimeStats(List<Article> articles) {
    // Calculate reading time statistics based on content length
    return {
      'average': 5.2,
      'distribution': {
        '0-2 min': 20,
        '2-5 min': 45,
        '5-10 min': 25,
        '10+ min': 10,
      },
    };
  }
  
  Future<List<String>> _identifyPopularTopics(List<Article> articles) async {
    // This would use topic modeling or categorization
    return ['AI & Machine Learning', 'Web Development', 'Cloud Computing'];
  }
  
  Map<String, int> _analyzeContentLength(List<Article> articles) {
    // Analyze distribution of content lengths
    return {
      'short': 30,
      'medium': 50,
      'long': 20,
    };
  }
  
  Future<Map<String, double>> _calculateEngagementByLength(
    Session session,
    int userId,
    List<Article> articles,
  ) async {
    // Calculate engagement rates by content length
    return {
      'short': 65.0,
      'medium': 80.0,
      'long': 45.0,
    };
  }
}

// Data classes for analytics
class ReadingAnalytics {
  final DateTime startDate;
  final DateTime endDate;
  final int totalArticlesRead;
  final double averageArticlesPerDay;
  final Map<String, int> dailyStats;
  final List<TopSource> topSources;
  final Map<String, double> timeDistribution;
  final Map<String, int> categoryBreakdown;
  final int readingStreak;
  
  ReadingAnalytics({
    required this.startDate,
    required this.endDate,
    required this.totalArticlesRead,
    required this.averageArticlesPerDay,
    required this.dailyStats,
    required this.topSources,
    required this.timeDistribution,
    required this.categoryBreakdown,
    required this.readingStreak,
  });
  
  Map<String, dynamic> toJson() => {
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'totalArticlesRead': totalArticlesRead,
    'averageArticlesPerDay': averageArticlesPerDay,
    'dailyStats': dailyStats,
    'topSources': topSources.map((s) => s.toJson()).toList(),
    'timeDistribution': timeDistribution,
    'categoryBreakdown': categoryBreakdown,
    'readingStreak': readingStreak,
  };
}

class TopSource {
  final String name;
  final int articleCount;
  
  TopSource({required this.name, required this.articleCount});
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'articleCount': articleCount,
  };
}

class FeedPerformance {
  final int feedId;
  final String feedTitle;
  final int totalArticles;
  final int readArticles;
  final int savedArticles;
  final double engagementRate;
  final DateTime lastRead;
  
  FeedPerformance({
    required this.feedId,
    required this.feedTitle,
    required this.totalArticles,
    required this.readArticles,
    required this.savedArticles,
    required this.engagementRate,
    required this.lastRead,
  });
  
  Map<String, dynamic> toJson() => {
    'feedId': feedId,
    'feedTitle': feedTitle,
    'totalArticles': totalArticles,
    'readArticles': readArticles,
    'savedArticles': savedArticles,
    'engagementRate': engagementRate,
    'lastRead': lastRead.toIso8601String(),
  };
}

class EngagementMetrics {
  final int dailyActiveUsers;
  final int weeklyActiveUsers;
  final int monthlyActiveUsers;
  final double averageSessionDuration;
  final double bounceRate;
  final Map<String, int> featureUsage;
  final double retentionRate;
  
  EngagementMetrics({
    required this.dailyActiveUsers,
    required this.weeklyActiveUsers,
    required this.monthlyActiveUsers,
    required this.averageSessionDuration,
    required this.bounceRate,
    required this.featureUsage,
    required this.retentionRate,
  });
  
  Map<String, dynamic> toJson() => {
    'dailyActiveUsers': dailyActiveUsers,
    'weeklyActiveUsers': weeklyActiveUsers,
    'monthlyActiveUsers': monthlyActiveUsers,
    'averageSessionDuration': averageSessionDuration,
    'bounceRate': bounceRate,
    'featureUsage': featureUsage,
    'retentionRate': retentionRate,
  };
}

class ContentInsights {
  final int totalArticles;
  final List<String> topKeywords;
  final double averageReadingTime;
  final Map<String, int> readingTimeDistribution;
  final List<String> popularTopics;
  final Map<String, int> contentLengthDistribution;
  final Map<String, double> engagementByLength;
  
  ContentInsights({
    required this.totalArticles,
    required this.topKeywords,
    required this.averageReadingTime,
    required this.readingTimeDistribution,
    required this.popularTopics,
    required this.contentLengthDistribution,
    required this.engagementByLength,
  });
  
  Map<String, dynamic> toJson() => {
    'totalArticles': totalArticles,
    'topKeywords': topKeywords,
    'averageReadingTime': averageReadingTime,
    'readingTimeDistribution': readingTimeDistribution,
    'popularTopics': popularTopics,
    'contentLengthDistribution': contentLengthDistribution,
    'engagementByLength': engagementByLength,
  };
}

class SessionData {
  final String sessionId;
  final DateTime startTime;
  final DateTime? endTime;
  final int pageViews;
  
  SessionData({
    required this.sessionId,
    required this.startTime,
    this.endTime,
    required this.pageViews,
  });
}