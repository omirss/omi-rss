import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/analytics/analytics_service.dart';

// Analytics service provider
final analyticsServiceProvider = Provider((ref) => AnalyticsService());

// Current analytics data
final userAnalyticsProvider = FutureProvider.family<UserAnalytics, String>((ref, timeframe) async {
  final service = ref.watch(analyticsServiceProvider);
  return service.getUserAnalytics(timeframe);
});

// Recommendations
final recommendationsProvider = FutureProvider.family<List<Recommendation>, RecommendationQuery>((ref, query) async {
  final service = ref.watch(analyticsServiceProvider);
  return service.getPersonalizedRecommendations(
    type: query.type,
    limit: query.limit,
  );
});

// Insights
final insightsProvider = FutureProvider.family<List<Insight>, String>((ref, category) async {
  final service = ref.watch(analyticsServiceProvider);
  return service.getInsights(category: category);
});

// Reading streaks
final readingStreaksProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return service.getReadingStreaks();
});

// Comparison with others
final comparisonProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return service.compareWithOthers();
});

// Selected timeframe state
final selectedTimeframeProvider = StateProvider<String>((ref) => 'month');

// Track article read
final trackArticleReadProvider = Provider((ref) {
  final service = ref.watch(analyticsServiceProvider);
  
  return (String articleId, double scrollDepth, int interactionTime, bool completed) async {
    await service.trackArticleRead(
      articleId: articleId,
      scrollDepth: scrollDepth,
      interactionTime: interactionTime,
      completed: completed,
    );
    
    // Invalidate analytics to refresh data
    ref.invalidate(userAnalyticsProvider);
  };
});

// Track feed interaction
final trackFeedInteractionProvider = Provider((ref) {
  final service = ref.watch(analyticsServiceProvider);
  
  return (String feedId, String action) async {
    await service.trackFeedInteraction(
      feedId: feedId,
      action: action,
    );
  };
});

// Track AI usage
final trackAIUsageProvider = Provider((ref) {
  final service = ref.watch(analyticsServiceProvider);
  
  return (String feature, String provider, int responseTime, {int? tokensUsed}) async {
    await service.trackAIUsage(
      feature: feature,
      provider: provider,
      responseTime: responseTime,
      tokensUsed: tokensUsed,
    );
  };
});

// Export analytics
final exportAnalyticsProvider = FutureProvider<String>((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return service.exportUserData();
});

// Chart data providers
final readingTimeChartProvider = Provider.family<List<ChartDataPoint>, UserAnalytics?>((ref, analytics) {
  if (analytics?.readingTime == null) return [];
  
  final data = analytics!.readingTime!;
  return [
    ChartDataPoint('Articles', data.articlesRead.toDouble()),
    ChartDataPoint('Hours', data.totalTimeHours),
    ChartDataPoint('Avg Minutes', data.averageTimeMinutes),
  ];
});

final categoryChartProvider = Provider.family<List<ChartDataPoint>, UserAnalytics?>((ref, analytics) {
  if (analytics?.contentPreferences?.topCategories == null) return [];
  
  return analytics!.contentPreferences!.topCategories
      .take(5)
      .map((cat) => ChartDataPoint(cat.name, cat.count.toDouble()))
      .toList();
});

final hourlyActivityChartProvider = Provider.family<List<ChartDataPoint>, UserAnalytics?>((ref, analytics) {
  if (analytics?.readingPatterns?.hourlyDistribution == null) return [];
  
  return analytics!.readingPatterns!.hourlyDistribution.entries
      .map((entry) => ChartDataPoint('${entry.key}:00', entry.value.toDouble()))
      .toList();
});

final weeklyActivityChartProvider = Provider.family<List<ChartDataPoint>, UserAnalytics?>((ref, analytics) {
  if (analytics?.readingPatterns?.weeklyDistribution == null) return [];
  
  final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return analytics!.readingPatterns!.weeklyDistribution.entries
      .map((entry) => ChartDataPoint(
            days[int.parse(entry.key) - 1],
            entry.value.toDouble(),
          ))
      .toList();
});

// Helper classes
class RecommendationQuery {
  final String type;
  final int limit;

  RecommendationQuery({
    this.type = 'mixed',
    this.limit = 10,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecommendationQuery &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          limit == other.limit;

  @override
  int get hashCode => type.hashCode ^ limit.hashCode;
}

class ChartDataPoint {
  final String label;
  final double value;

  ChartDataPoint(this.label, this.value);
}