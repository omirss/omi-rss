import 'package:flutter/foundation.dart';
import 'analytics_service.dart';

class AnalyticsProvider extends ChangeNotifier {
  final AnalyticsService _analyticsService = AnalyticsService();

  UserAnalytics? _analytics;
  List<Recommendation> _recommendations = [];
  List<Insight> _insights = [];
  bool _isLoading = false;
  String? _error;

  UserAnalytics? get analytics => _analytics;
  List<Recommendation> get recommendations => _recommendations;
  List<Insight> get insights => _insights;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Reading streak data
  ReadingStreak? get currentStreak => _analytics?.readingPatterns?.currentStreak;
  ReadingStreak? get longestStreak => _analytics?.readingPatterns?.longestStreak;
  
  // Chart data
  List<ChartDataPoint> get readingTimeChart {
    if (_analytics?.readingTime == null) return [];
    
    final data = _analytics!.readingTime!;
    return [
      ChartDataPoint('Articles', data.articlesRead.toDouble()),
      ChartDataPoint('Hours', data.totalTimeHours),
      ChartDataPoint('Avg Minutes', data.averageTimeMinutes),
    ];
  }

  List<ChartDataPoint> get categoryChart {
    if (_analytics?.contentPreferences?.topCategories == null) return [];
    
    return _analytics!.contentPreferences!.topCategories
        .take(5)
        .map((cat) => ChartDataPoint(cat.name, cat.count.toDouble()))
        .toList();
  }

  List<ChartDataPoint> get hourlyActivityChart {
    if (_analytics?.readingPatterns?.hourlyDistribution == null) return [];
    
    return _analytics!.readingPatterns!.hourlyDistribution.entries
        .map((entry) => ChartDataPoint('${entry.key}:00', entry.value.toDouble()))
        .toList();
  }

  List<ChartDataPoint> get weeklyActivityChart {
    if (_analytics?.readingPatterns?.weeklyDistribution == null) return [];
    
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return _analytics!.readingPatterns!.weeklyDistribution.entries
        .map((entry) => ChartDataPoint(
              days[int.parse(entry.key) - 1],
              entry.value.toDouble(),
            ))
        .toList();
  }

  // Load analytics data
  Future<void> loadAnalytics({String timeframe = 'month'}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _analytics = await _analyticsService.getUserAnalytics(timeframe);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load recommendations
  Future<void> loadRecommendations({
    String type = 'mixed',
    int limit = 10,
  }) async {
    try {
      _recommendations = await _analyticsService.getPersonalizedRecommendations(
        type: type,
        limit: limit,
      );
      notifyListeners();
    } catch (e) {
      print('Failed to load recommendations: $e');
    }
  }

  // Load insights
  Future<void> loadInsights({String category = 'all'}) async {
    try {
      _insights = await _analyticsService.getInsights(category: category);
      notifyListeners();
    } catch (e) {
      print('Failed to load insights: $e');
    }
  }

  // Track article read
  Future<void> trackArticleRead({
    required String articleId,
    required double scrollDepth,
    required int interactionTime,
    required bool completed,
  }) async {
    try {
      await _analyticsService.trackArticleRead(
        articleId: articleId,
        scrollDepth: scrollDepth,
        interactionTime: interactionTime,
        completed: completed,
      );
      
      // Refresh analytics after tracking
      await loadAnalytics();
    } catch (e) {
      print('Failed to track article read: $e');
    }
  }

  // Track feed interaction
  Future<void> trackFeedInteraction({
    required String feedId,
    required String action,
  }) async {
    try {
      await _analyticsService.trackFeedInteraction(
        feedId: feedId,
        action: action,
      );
    } catch (e) {
      print('Failed to track feed interaction: $e');
    }
  }

  // Track AI usage
  Future<void> trackAIUsage({
    required String feature,
    required String provider,
    required int responseTime,
    int? tokensUsed,
  }) async {
    try {
      await _analyticsService.trackAIUsage(
        feature: feature,
        provider: provider,
        responseTime: responseTime,
        tokensUsed: tokensUsed,
      );
    } catch (e) {
      print('Failed to track AI usage: $e');
    }
  }

  // Export analytics data
  Future<String?> exportAnalytics() async {
    try {
      return await _analyticsService.exportUserData();
    } catch (e) {
      print('Failed to export analytics: $e');
      return null;
    }
  }

  // Get reading streaks
  Future<Map<String, dynamic>?> getReadingStreaks() async {
    try {
      return await _analyticsService.getReadingStreaks();
    } catch (e) {
      print('Failed to get reading streaks: $e');
      return null;
    }
  }

  // Compare with other users
  Future<Map<String, dynamic>?> compareWithOthers() async {
    try {
      return await _analyticsService.compareWithOthers();
    } catch (e) {
      print('Failed to compare with others: $e');
      return null;
    }
  }

  // Refresh all data
  Future<void> refreshAll() async {
    await Future.wait([
      loadAnalytics(),
      loadRecommendations(),
      loadInsights(),
    ]);
  }
}

// Chart data point model
class ChartDataPoint {
  final String label;
  final double value;

  ChartDataPoint(this.label, this.value);
}