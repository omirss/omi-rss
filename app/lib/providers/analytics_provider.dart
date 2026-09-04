import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/analytics/analytics_service.dart';

// Analytics service provider
final analyticsServiceProvider = Provider((ref) => AnalyticsService());

// Current analytics data
final userAnalyticsProvider = FutureProvider.family<UserAnalytics, String>((ref, timeframe) async {
  final service = ref.watch(analyticsServiceProvider);
  return service.getUserAnalytics(timeframe);
});

// Selected timeframe state
final selectedTimeframeProvider = StateProvider<String>((ref) => 'month');

// Track article read
final trackArticleReadProvider = Provider((ref) {
  final service = ref.watch(analyticsServiceProvider);

  return (String articleId, double scrollDepth, int interactionTime, bool completed) async {
    // Best-effort: called fire-and-forget from the reader's dispose
    try {
      await service.trackArticleRead(
        articleId: articleId,
        scrollDepth: scrollDepth,
        interactionTime: interactionTime,
        completed: completed,
      );
    } catch (_) {
      // Analytics is optional; local reading state is unaffected
    }

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

// Export analytics
final exportAnalyticsProvider = FutureProvider<String>((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return service.exportUserData();
});

// Chart data providers
final categoryChartProvider = Provider.family<List<ChartDataPoint>, UserAnalytics?>((ref, analytics) {
  final categories = analytics?.preferences?.topCategories;
  if (categories == null) return [];

  return categories
      .take(5)
      .map((cat) => ChartDataPoint(cat.name, cat.count.toDouble()))
      .toList();
});

final hourlyActivityChartProvider = Provider.family<List<ChartDataPoint>, UserAnalytics?>((ref, analytics) {
  final distribution = analytics?.patterns?.dailyDistribution;
  if (distribution == null) return [];

  return distribution
      .map((entry) => ChartDataPoint('${entry.hour}:00', entry.count.toDouble()))
      .toList();
});

final weeklyActivityChartProvider = Provider.family<List<ChartDataPoint>, UserAnalytics?>((ref, analytics) {
  final distribution = analytics?.patterns?.weeklyDistribution;
  if (distribution == null) return [];

  return distribution
      .map((entry) => ChartDataPoint(
            entry.day.substring(0, entry.day.length >= 3 ? 3 : entry.day.length),
            entry.count.toDouble(),
          ))
      .toList();
});

// Chart data point model
class ChartDataPoint {
  final String label;
  final double value;

  ChartDataPoint(this.label, this.value);
}
