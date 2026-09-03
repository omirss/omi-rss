import 'dart:async';
import 'dart:math' as math;
import 'package:collection/collection.dart';
import '../models/feed.dart';
import '../models/article.dart';
import '../models/feed_statistics.dart';
import '../database/database.dart';

/// Service for tracking and calculating feed statistics
class StatisticsService {
  final AppDatabase _database;
  final Map<String, FeedStatistics> _cache = {};
  Timer? _updateTimer;
  
  StatisticsService(this._database) {
    // Update statistics every hour
    _updateTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => updateAllStatistics(),
    );
  }
  
  void dispose() {
    _updateTimer?.cancel();
  }
  
  /// Get statistics for a specific feed
  Future<FeedStatistics> getFeedStatistics(String feedId) async {
    // Check cache first
    if (_cache.containsKey(feedId)) {
      final cached = _cache[feedId]!;
      // Return cached if less than 30 minutes old
      if (DateTime.now().difference(cached.lastUpdated).inMinutes < 30) {
        return cached;
      }
    }
    
    // Calculate fresh statistics
    final stats = await _calculateFeedStatistics(feedId);
    _cache[feedId] = stats;
    return stats;
  }
  
  /// Get aggregated statistics for all feeds
  Future<AggregatedStatistics> getAggregatedStatistics({
    String? categoryId,
  }) async {
    final feeds = await _database.feedDao.getAllFeeds();
    final filteredFeeds = categoryId != null
        ? feeds.where((f) => f.categoryId == categoryId).toList()
        : feeds;
    
    if (filteredFeeds.isEmpty) {
      return _createEmptyAggregatedStatistics();
    }
    
    // Calculate statistics for each feed
    final feedStats = await Future.wait(
      filteredFeeds.map((feed) => getFeedStatistics(feed.id)),
    );
    
    // Aggregate the statistics
    return _aggregateStatistics(filteredFeeds, feedStats);
  }
  
  /// Get reading statistics for the user
  Future<ReadingStatistics> getReadingStatistics() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);
    
    // Get read articles
    final readArticles = await _database.articleDao.getReadArticles();
    
    // Calculate statistics
    final articlesReadToday = readArticles.where((a) {
      final readDate = a.readAt;
      return readDate != null && readDate.isAfter(today);
    }).length;
    
    final articlesReadThisWeek = readArticles.where((a) {
      final readDate = a.readAt;
      return readDate != null && readDate.isAfter(weekStart);
    }).length;
    
    final articlesReadThisMonth = readArticles.where((a) {
      final readDate = a.readAt;
      return readDate != null && readDate.isAfter(monthStart);
    }).length;
    
    // Calculate reading time
    final totalReadingTimeToday = _calculateReadingTime(
      readArticles.where((a) {
        final readDate = a.readAt;
        return readDate != null && readDate.isAfter(today);
      }).toList(),
    );
    
    final totalReadingTimeThisWeek = _calculateReadingTime(
      readArticles.where((a) {
        final readDate = a.readAt;
        return readDate != null && readDate.isAfter(weekStart);
      }).toList(),
    );
    
    final totalReadingTimeThisMonth = _calculateReadingTime(
      readArticles.where((a) {
        final readDate = a.readAt;
        return readDate != null && readDate.isAfter(monthStart);
      }).toList(),
    );
    
    // Calculate reading speed (words per minute)
    final averageReadingSpeed = _calculateAverageReadingSpeed(readArticles);
    
    // Reading time by category
    final readingTimeByCategory = await _calculateReadingTimeByCategory(readArticles);
    
    // Reading time by hour
    final readingTimeByHour = _calculateReadingTimeByHour(readArticles);
    
    // Calculate streaks
    final streaks = _calculateReadingStreaks(readArticles);
    
    return ReadingStatistics(
      articlesReadToday: articlesReadToday,
      articlesReadThisWeek: articlesReadThisWeek,
      articlesReadThisMonth: articlesReadThisMonth,
      totalReadingTimeToday: totalReadingTimeToday,
      totalReadingTimeThisWeek: totalReadingTimeThisWeek,
      totalReadingTimeThisMonth: totalReadingTimeThisMonth,
      averageReadingSpeed: averageReadingSpeed,
      readingTimeByCategory: readingTimeByCategory,
      readingTimeByHour: readingTimeByHour,
      streaks: streaks,
      lastUpdated: DateTime.now(),
    );
  }
  
  /// Update statistics for all feeds
  Future<void> updateAllStatistics() async {
    final feeds = await _database.feedDao.getAllFeeds();
    
    for (final feed in feeds) {
      try {
        final stats = await _calculateFeedStatistics(feed.id);
        _cache[feed.id] = stats;
        
        // Store in database if needed
        await _storeFeedStatistics(stats);
      } catch (e) {
        // Log error but continue with other feeds
        print('Failed to update statistics for feed ${feed.id}: $e');
      }
    }
  }
  
  /// Calculate statistics for a specific feed
  Future<FeedStatistics> _calculateFeedStatistics(String feedId) async {
    final articles = await _database.articleDao.getArticlesByFeed(feedId);
    
    if (articles.isEmpty) {
      return FeedStatistics.empty(feedId);
    }
    
    // Basic counts
    final totalArticles = articles.length;
    final unreadArticles = articles.where((a) => !a.isRead).length;
    final starredArticles = articles.where((a) => a.isStarred).length;
    
    // Date ranges
    final publishedDates = articles
        .map((a) => a.publishedAt)
        .whereNotNull()
        .toList()
      ..sort();
    
    final lastArticleDate = publishedDates.isNotEmpty ? publishedDates.last : null;
    final oldestArticleDate = publishedDates.isNotEmpty ? publishedDates.first : null;
    
    // Articles per day
    final daysSinceFirst = oldestArticleDate != null
        ? DateTime.now().difference(oldestArticleDate).inDays
        : 0;
    final articlesPerDay = daysSinceFirst > 0 ? totalArticles / daysSinceFirst : 0.0;
    
    // Read rate
    final readRate = totalArticles > 0
        ? (totalArticles - unreadArticles) / totalArticles
        : 0.0;
    
    // Average article length
    final lengths = articles
        .map((a) => a.content?.length ?? 0)
        .where((l) => l > 0)
        .toList();
    final averageArticleLength = lengths.isNotEmpty
        ? lengths.reduce((a, b) => a + b) ~/ lengths.length
        : 0;
    
    // Articles by hour
    final articlesByHour = <String, int>{};
    for (final article in articles) {
      if (article.publishedAt != null) {
        final hour = article.publishedAt!.hour.toString().padLeft(2, '0');
        articlesByHour[hour] = (articlesByHour[hour] ?? 0) + 1;
      }
    }
    
    // Articles by day of week
    final articlesByDayOfWeek = <String, int>{};
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (final article in articles) {
      if (article.publishedAt != null) {
        final dayName = dayNames[article.publishedAt!.weekday - 1];
        articlesByDayOfWeek[dayName] = (articlesByDayOfWeek[dayName] ?? 0) + 1;
      }
    }
    
    // Articles by month
    final articlesByMonth = <String, int>{};
    for (final article in articles) {
      if (article.publishedAt != null) {
        final monthKey = '${article.publishedAt!.year}-${article.publishedAt!.month.toString().padLeft(2, '0')}';
        articlesByMonth[monthKey] = (articlesByMonth[monthKey] ?? 0) + 1;
      }
    }
    
    // Top keywords (simplified - would need NLP for better results)
    final topKeywords = await _extractTopKeywords(articles);
    
    // Top authors
    final authorCounts = <String, int>{};
    for (final article in articles) {
      if (article.author != null && article.author!.isNotEmpty) {
        authorCounts[article.author!] = (authorCounts[article.author!] ?? 0) + 1;
      }
    }
    final topAuthors = authorCounts.entries
        .sorted((a, b) => b.value.compareTo(a.value))
        .take(5)
        .map((e) => e.key)
        .toList();
    
    // Total reading time
    final totalReadingTimeMinutes = _calculateReadingTime(articles);
    
    return FeedStatistics(
      feedId: feedId,
      totalArticles: totalArticles,
      unreadArticles: unreadArticles,
      starredArticles: starredArticles,
      articlesPerDay: articlesPerDay,
      readRate: readRate,
      lastArticleDate: lastArticleDate,
      oldestArticleDate: oldestArticleDate,
      averageArticleLength: averageArticleLength,
      articlesByHour: articlesByHour,
      articlesByDayOfWeek: articlesByDayOfWeek,
      articlesByMonth: articlesByMonth,
      topKeywords: topKeywords,
      topAuthors: topAuthors,
      totalReadingTimeMinutes: totalReadingTimeMinutes,
      lastUpdated: DateTime.now(),
    );
  }
  
  /// Extract top keywords from articles
  Future<List<String>> _extractTopKeywords(List<Article> articles) async {
    final wordCounts = <String, int>{};
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'been',
      'be', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
      'could', 'should', 'may', 'might', 'must', 'can', 'this', 'that',
      'these', 'those', 'i', 'you', 'he', 'she', 'it', 'we', 'they',
    };
    
    for (final article in articles) {
      final text = '${article.title} ${article.content ?? ''}'.toLowerCase();
      final words = text.split(RegExp(r'[^a-z0-9]+'))
          .where((w) => w.length > 3 && !stopWords.contains(w));
      
      for (final word in words) {
        wordCounts[word] = (wordCounts[word] ?? 0) + 1;
      }
    }
    
    return wordCounts.entries
        .sorted((a, b) => b.value.compareTo(a.value))
        .take(10)
        .map((e) => e.key)
        .toList();
  }
  
  /// Calculate total reading time in minutes
  int _calculateReadingTime(List<Article> articles) {
    const averageReadingSpeed = 200; // words per minute
    var totalWords = 0;
    
    for (final article in articles) {
      final content = article.content ?? '';
      totalWords += content.split(RegExp(r'\s+')).length;
    }
    
    return (totalWords / averageReadingSpeed).ceil();
  }
  
  /// Calculate average reading speed
  double _calculateAverageReadingSpeed(List<Article> articles) {
    final readArticles = articles.where((a) => a.isRead && a.readingTimeSeconds != null);
    if (readArticles.isEmpty) return 200.0; // Default WPM
    
    var totalWords = 0;
    var totalSeconds = 0;
    
    for (final article in readArticles) {
      final content = article.content ?? '';
      totalWords += content.split(RegExp(r'\s+')).length;
      totalSeconds += article.readingTimeSeconds!;
    }
    
    if (totalSeconds == 0) return 200.0;
    
    return (totalWords / totalSeconds) * 60; // Convert to WPM
  }
  
  /// Calculate reading time by category
  Future<Map<String, int>> _calculateReadingTimeByCategory(List<Article> articles) async {
    final feeds = await _database.feedDao.getAllFeeds();
    final feedCategoryMap = {
      for (final feed in feeds) feed.id: feed.categoryId
    };
    
    final categories = await _database.categoryDao.getAllCategories();
    final categoryNameMap = {
      for (final category in categories) category.id: category.name
    };
    
    final result = <String, int>{};
    
    for (final article in articles) {
      final categoryId = feedCategoryMap[article.feedId];
      if (categoryId != null) {
        final categoryName = categoryNameMap[categoryId] ?? 'Uncategorized';
        final readingTime = _calculateArticleReadingTime(article);
        result[categoryName] = (result[categoryName] ?? 0) + readingTime;
      }
    }
    
    return result;
  }
  
  /// Calculate reading time by hour
  Map<int, int> _calculateReadingTimeByHour(List<Article> articles) {
    final result = <int, int>{};
    
    for (final article in articles.where((a) => a.readAt != null)) {
      final hour = article.readAt!.hour;
      final readingTime = _calculateArticleReadingTime(article);
      result[hour] = (result[hour] ?? 0) + readingTime;
    }
    
    return result;
  }
  
  /// Calculate reading time for a single article
  int _calculateArticleReadingTime(Article article) {
    if (article.readingTimeSeconds != null) {
      return article.readingTimeSeconds! ~/ 60; // Convert to minutes
    }
    
    const averageReadingSpeed = 200; // words per minute
    final content = article.content ?? '';
    final wordCount = content.split(RegExp(r'\s+')).length;
    return (wordCount / averageReadingSpeed).ceil();
  }
  
  /// Calculate reading streaks
  List<ReadingStreak> _calculateReadingStreaks(List<Article> articles) {
    final readArticles = articles.where((a) => a.readAt != null).toList()
      ..sort((a, b) => a.readAt!.compareTo(b.readAt!));
    
    if (readArticles.isEmpty) return [];
    
    final streaks = <ReadingStreak>[];
    var currentStreakStart = readArticles.first.readAt!;
    var currentStreakEnd = currentStreakStart;
    var currentStreakArticles = 1;
    var lastDate = DateTime(
      currentStreakStart.year,
      currentStreakStart.month,
      currentStreakStart.day,
    );
    
    for (int i = 1; i < readArticles.length; i++) {
      final articleDate = readArticles[i].readAt!;
      final date = DateTime(articleDate.year, articleDate.month, articleDate.day);
      
      if (date.difference(lastDate).inDays <= 1) {
        // Continue streak
        currentStreakEnd = articleDate;
        currentStreakArticles++;
        if (date.isAfter(lastDate)) {
          lastDate = date;
        }
      } else {
        // Break streak
        streaks.add(ReadingStreak(
          startDate: currentStreakStart,
          endDate: currentStreakEnd,
          daysCount: currentStreakEnd.difference(currentStreakStart).inDays + 1,
          articlesRead: currentStreakArticles,
          isCurrent: false,
        ));
        
        currentStreakStart = articleDate;
        currentStreakEnd = articleDate;
        currentStreakArticles = 1;
        lastDate = date;
      }
    }
    
    // Add final streak
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isCurrent = today.difference(lastDate).inDays <= 1;
    
    streaks.add(ReadingStreak(
      startDate: currentStreakStart,
      endDate: currentStreakEnd,
      daysCount: currentStreakEnd.difference(currentStreakStart).inDays + 1,
      articlesRead: currentStreakArticles,
      isCurrent: isCurrent,
    ));
    
    return streaks;
  }
  
  /// Aggregate statistics from multiple feeds
  Future<AggregatedStatistics> _aggregateStatistics(
    List<Feed> feeds,
    List<FeedStatistics> feedStats,
  ) async {
    final activeFeeds = feeds.where((f) => f.isActive).length;
    final totalArticles = feedStats.fold(0, (sum, stat) => sum + stat.totalArticles);
    final unreadArticles = feedStats.fold(0, (sum, stat) => sum + stat.unreadArticles);
    final starredArticles = feedStats.fold(0, (sum, stat) => sum + stat.starredArticles);
    
    // Average articles per day
    final averageArticlesPerDay = feedStats.isNotEmpty
        ? feedStats.map((s) => s.articlesPerDay).reduce((a, b) => a + b) / feedStats.length
        : 0.0;
    
    // Average read rate
    final averageReadRate = feedStats.isNotEmpty
        ? feedStats.map((s) => s.readRate).reduce((a, b) => a + b) / feedStats.length
        : 0.0;
    
    // Articles by category
    final articlesByCategory = await _calculateArticlesByCategory(feeds, feedStats);
    
    // Health by category
    final healthByCategory = await _calculateHealthByCategory(feeds);
    
    // Top and worst performing feeds
    final performances = await _calculateFeedPerformances(feeds, feedStats);
    final topPerformingFeeds = performances
        .sorted((a, b) => b.healthScore.compareTo(a.healthScore))
        .take(5)
        .toList();
    final worstPerformingFeeds = performances
        .sorted((a, b) => a.healthScore.compareTo(b.healthScore))
        .take(5)
        .toList();
    
    // Articles over time
    final articlesOverTime = await _calculateArticlesOverTime();
    
    // Total reading time
    final totalReadingTimeMinutes = feedStats.fold(
      0,
      (sum, stat) => sum + stat.totalReadingTimeMinutes,
    );
    
    return AggregatedStatistics(
      totalFeeds: feeds.length,
      activeFeeds: activeFeeds,
      totalArticles: totalArticles,
      unreadArticles: unreadArticles,
      starredArticles: starredArticles,
      averageArticlesPerDay: averageArticlesPerDay,
      averageReadRate: averageReadRate,
      articlesByCategory: articlesByCategory,
      healthByCategory: healthByCategory,
      topPerformingFeeds: topPerformingFeeds,
      worstPerformingFeeds: worstPerformingFeeds,
      articlesOverTime: articlesOverTime,
      totalReadingTimeMinutes: totalReadingTimeMinutes,
      lastUpdated: DateTime.now(),
    );
  }
  
  Future<Map<String, int>> _calculateArticlesByCategory(
    List<Feed> feeds,
    List<FeedStatistics> feedStats,
  ) async {
    final categories = await _database.categoryDao.getAllCategories();
    final categoryNameMap = {
      for (final category in categories) category.id: category.name
    };
    
    final result = <String, int>{};
    
    for (int i = 0; i < feeds.length; i++) {
      final feed = feeds[i];
      final stats = feedStats[i];
      final categoryName = feed.categoryId != null
          ? categoryNameMap[feed.categoryId] ?? 'Uncategorized'
          : 'Uncategorized';
      
      result[categoryName] = (result[categoryName] ?? 0) + stats.totalArticles;
    }
    
    return result;
  }
  
  Future<Map<String, double>> _calculateHealthByCategory(List<Feed> feeds) async {
    final categories = await _database.categoryDao.getAllCategories();
    final categoryNameMap = {
      for (final category in categories) category.id: category.name
    };
    
    final healthSums = <String, double>{};
    final healthCounts = <String, int>{};
    
    for (final feed in feeds) {
      final categoryName = feed.categoryId != null
          ? categoryNameMap[feed.categoryId] ?? 'Uncategorized'
          : 'Uncategorized';
      
      healthSums[categoryName] = (healthSums[categoryName] ?? 0) + feed.successRate;
      healthCounts[categoryName] = (healthCounts[categoryName] ?? 0) + 1;
    }
    
    return {
      for (final entry in healthSums.entries)
        entry.key: entry.value / healthCounts[entry.key]!
    };
  }
  
  Future<List<FeedPerformance>> _calculateFeedPerformances(
    List<Feed> feeds,
    List<FeedStatistics> feedStats,
  ) async {
    final performances = <FeedPerformance>[];
    
    for (int i = 0; i < feeds.length; i++) {
      final feed = feeds[i];
      final stats = feedStats[i];
      
      performances.add(FeedPerformance(
        feedId: feed.id,
        feedTitle: feed.title,
        healthScore: feed.successRate,
        articlesPerDay: stats.articlesPerDay,
        readRate: stats.readRate,
        errorCount: 0, // TODO: Get from feed health monitoring
        lastSuccessfulUpdate: feed.lastFetched,
        averageUpdateTime: const Duration(seconds: 5), // TODO: Track actual update times
      ));
    }
    
    return performances;
  }
  
  Future<Map<DateTime, int>> _calculateArticlesOverTime() async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    
    final articles = await _database.articleDao.getArticlesAfter(thirtyDaysAgo);
    final result = <DateTime, int>{};
    
    for (final article in articles) {
      if (article.publishedAt != null) {
        final date = DateTime(
          article.publishedAt!.year,
          article.publishedAt!.month,
          article.publishedAt!.day,
        );
        result[date] = (result[date] ?? 0) + 1;
      }
    }
    
    return result;
  }
  
  AggregatedStatistics _createEmptyAggregatedStatistics() {
    return AggregatedStatistics(
      totalFeeds: 0,
      activeFeeds: 0,
      totalArticles: 0,
      unreadArticles: 0,
      starredArticles: 0,
      averageArticlesPerDay: 0.0,
      averageReadRate: 0.0,
      articlesByCategory: {},
      healthByCategory: {},
      topPerformingFeeds: [],
      worstPerformingFeeds: [],
      articlesOverTime: {},
      totalReadingTimeMinutes: 0,
      lastUpdated: DateTime.now(),
    );
  }
  
  Future<void> _storeFeedStatistics(FeedStatistics stats) async {
    // TODO: Store statistics in database if needed
  }
}