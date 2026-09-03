/// Feed statistics model
class FeedStatistics {
  final String feedId;
  final int totalArticles;
  final int unreadArticles;
  final int starredArticles;
  final double articlesPerDay;
  final double readRate;
  final DateTime? lastArticleDate;
  final DateTime? oldestArticleDate;
  final int averageArticleLength;
  final Map<String, int> articlesByHour;
  final Map<String, int> articlesByDayOfWeek;
  final Map<String, int> articlesByMonth;
  final List<String> topKeywords;
  final List<String> topAuthors;
  final int totalReadingTimeMinutes;
  final DateTime lastUpdated;

  const FeedStatistics({
    required this.feedId,
    required this.totalArticles,
    required this.unreadArticles,
    required this.starredArticles,
    required this.articlesPerDay,
    required this.readRate,
    required this.lastArticleDate,
    required this.oldestArticleDate,
    required this.averageArticleLength,
    required this.articlesByHour,
    required this.articlesByDayOfWeek,
    required this.articlesByMonth,
    required this.topKeywords,
    required this.topAuthors,
    required this.totalReadingTimeMinutes,
    required this.lastUpdated,
  });

  factory FeedStatistics.empty(String feedId) => FeedStatistics(
    feedId: feedId,
    totalArticles: 0,
    unreadArticles: 0,
    starredArticles: 0,
    articlesPerDay: 0.0,
    readRate: 0.0,
    lastArticleDate: null,
    oldestArticleDate: null,
    averageArticleLength: 0,
    articlesByHour: {},
    articlesByDayOfWeek: {},
    articlesByMonth: {},
    topKeywords: [],
    topAuthors: [],
    totalReadingTimeMinutes: 0,
    lastUpdated: DateTime.now(),
  );
}

/// Aggregated statistics for multiple feeds
class AggregatedStatistics {
  final int totalFeeds;
  final int activeFeeds;
  final int totalArticles;
  final int unreadArticles;
  final int starredArticles;
  final double averageArticlesPerDay;
  final double averageReadRate;
  final Map<String, int> articlesByCategory;
  final Map<String, double> healthByCategory;
  final List<FeedPerformance> topPerformingFeeds;
  final List<FeedPerformance> worstPerformingFeeds;
  final Map<DateTime, int> articlesOverTime;
  final int totalReadingTimeMinutes;
  final DateTime lastUpdated;

  const AggregatedStatistics({
    required this.totalFeeds,
    required this.activeFeeds,
    required this.totalArticles,
    required this.unreadArticles,
    required this.starredArticles,
    required this.averageArticlesPerDay,
    required this.averageReadRate,
    required this.articlesByCategory,
    required this.healthByCategory,
    required this.topPerformingFeeds,
    required this.worstPerformingFeeds,
    required this.articlesOverTime,
    required this.totalReadingTimeMinutes,
    required this.lastUpdated,
  });
}

/// Feed performance metrics
class FeedPerformance {
  final String feedId;
  final String feedTitle;
  final double healthScore;
  final double articlesPerDay;
  final double readRate;
  final int errorCount;
  final DateTime? lastSuccessfulUpdate;
  final Duration averageUpdateTime;

  const FeedPerformance({
    required this.feedId,
    required this.feedTitle,
    required this.healthScore,
    required this.articlesPerDay,
    required this.readRate,
    required this.errorCount,
    required this.lastSuccessfulUpdate,
    required this.averageUpdateTime,
  });
}

/// Reading statistics
class ReadingStatistics {
  final int articlesReadToday;
  final int articlesReadThisWeek;
  final int articlesReadThisMonth;
  final int totalReadingTimeToday;
  final int totalReadingTimeThisWeek;
  final int totalReadingTimeThisMonth;
  final double averageReadingSpeed;
  final Map<String, int> readingTimeByCategory;
  final Map<int, int> readingTimeByHour;
  final List<ReadingStreak> streaks;
  final DateTime lastUpdated;

  const ReadingStatistics({
    required this.articlesReadToday,
    required this.articlesReadThisWeek,
    required this.articlesReadThisMonth,
    required this.totalReadingTimeToday,
    required this.totalReadingTimeThisWeek,
    required this.totalReadingTimeThisMonth,
    required this.averageReadingSpeed,
    required this.readingTimeByCategory,
    required this.readingTimeByHour,
    required this.streaks,
    required this.lastUpdated,
  });
}

/// Reading streak
class ReadingStreak {
  final DateTime startDate;
  final DateTime endDate;
  final int daysCount;
  final int articlesRead;
  final bool isCurrent;

  const ReadingStreak({
    required this.startDate,
    required this.endDate,
    required this.daysCount,
    required this.articlesRead,
    required this.isCurrent,
  });
}
