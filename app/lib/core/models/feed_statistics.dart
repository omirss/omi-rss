import 'package:freezed_annotation/freezed_annotation.dart';

part 'feed_statistics.freezed.dart';
part 'feed_statistics.g.dart';

/// Feed statistics model
@freezed
class FeedStatistics with _$FeedStatistics {
  const factory FeedStatistics({
    required String feedId,
    required int totalArticles,
    required int unreadArticles,
    required int starredArticles,
    required double articlesPerDay,
    required double readRate,
    required DateTime? lastArticleDate,
    required DateTime? oldestArticleDate,
    required int averageArticleLength,
    required Map<String, int> articlesByHour,
    required Map<String, int> articlesByDayOfWeek,
    required Map<String, int> articlesByMonth,
    required List<String> topKeywords,
    required List<String> topAuthors,
    required int totalReadingTimeMinutes,
    required DateTime lastUpdated,
  }) = _FeedStatistics;
  
  factory FeedStatistics.fromJson(Map<String, dynamic> json) =>
      _$FeedStatisticsFromJson(json);
  
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
@freezed
class AggregatedStatistics with _$AggregatedStatistics {
  const factory AggregatedStatistics({
    required int totalFeeds,
    required int activeFeeds,
    required int totalArticles,
    required int unreadArticles,
    required int starredArticles,
    required double averageArticlesPerDay,
    required double averageReadRate,
    required Map<String, int> articlesByCategory,
    required Map<String, double> healthByCategory,
    required List<FeedPerformance> topPerformingFeeds,
    required List<FeedPerformance> worstPerformingFeeds,
    required Map<DateTime, int> articlesOverTime,
    required int totalReadingTimeMinutes,
    required DateTime lastUpdated,
  }) = _AggregatedStatistics;
  
  factory AggregatedStatistics.fromJson(Map<String, dynamic> json) =>
      _$AggregatedStatisticsFromJson(json);
}

/// Feed performance metrics
@freezed
class FeedPerformance with _$FeedPerformance {
  const factory FeedPerformance({
    required String feedId,
    required String feedTitle,
    required double healthScore,
    required double articlesPerDay,
    required double readRate,
    required int errorCount,
    required DateTime? lastSuccessfulUpdate,
    required Duration averageUpdateTime,
  }) = _FeedPerformance;
  
  factory FeedPerformance.fromJson(Map<String, dynamic> json) =>
      _$FeedPerformanceFromJson(json);
}

/// Reading statistics
@freezed
class ReadingStatistics with _$ReadingStatistics {
  const factory ReadingStatistics({
    required int articlesReadToday,
    required int articlesReadThisWeek,
    required int articlesReadThisMonth,
    required int totalReadingTimeToday,
    required int totalReadingTimeThisWeek,
    required int totalReadingTimeThisMonth,
    required double averageReadingSpeed,
    required Map<String, int> readingTimeByCategory,
    required Map<int, int> readingTimeByHour,
    required List<ReadingStreak> streaks,
    required DateTime lastUpdated,
  }) = _ReadingStatistics;
  
  factory ReadingStatistics.fromJson(Map<String, dynamic> json) =>
      _$ReadingStatisticsFromJson(json);
}

/// Reading streak
@freezed
class ReadingStreak with _$ReadingStreak {
  const factory ReadingStreak({
    required DateTime startDate,
    required DateTime endDate,
    required int daysCount,
    required int articlesRead,
    required bool isCurrent,
  }) = _ReadingStreak;
  
  factory ReadingStreak.fromJson(Map<String, dynamic> json) =>
      _$ReadingStreakFromJson(json);
}