import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';

class AnalyticsService {
  String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Get user analytics
  Future<UserAnalytics> getUserAnalytics(String timeframe) async {
    if (!ApiConfig.hasServer) throw Exception('No server configured');
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/analytics?timeframe=$timeframe'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return UserAnalytics.fromJson(data);
    } else {
      throw Exception('Failed to load analytics');
    }
  }

  // Track article read
  Future<void> trackArticleRead({
    required String articleId,
    required double scrollDepth,
    required int interactionTime,
    required bool completed,
  }) async {
    if (!ApiConfig.hasServer) return;
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/analytics/article-read'),
      headers: headers,
      body: json.encode({
        'articleId': articleId,
        'scrollDepth': scrollDepth,
        'interactionTime': interactionTime,
        'completed': completed,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to track article read');
    }
  }

  // Track feed interaction
  Future<void> trackFeedInteraction({
    required String feedId,
    required String action,
  }) async {
    if (!ApiConfig.hasServer) return;
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/analytics/feed-interaction'),
      headers: headers,
      body: json.encode({
        'feedId': feedId,
        'action': action,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to track feed interaction');
    }
  }

  // Export user data
  Future<String> exportUserData() async {
    if (!ApiConfig.hasServer) throw Exception('No server configured');
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/analytics/export'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to export data');
    }
  }
}

// Models matching the server response from
// Express services/analytics/index.ts getUserAnalytics().
class UserAnalytics {
  final String timeframe;
  final ReadingAnalytics? reading;
  final ContentPreferences? preferences;
  final ReadingPatternsData? patterns;
  final EngagementMetrics? engagement;
  final List<String> insights;

  UserAnalytics({
    required this.timeframe,
    this.reading,
    this.preferences,
    this.patterns,
    this.engagement,
    this.insights = const [],
  });

  factory UserAnalytics.fromJson(Map<String, dynamic> json) {
    return UserAnalytics(
      timeframe: (json['timeframe'] as String?) ?? '',
      reading: json['reading'] != null
          ? ReadingAnalytics.fromJson(json['reading'])
          : null,
      preferences: json['preferences'] != null
          ? ContentPreferences.fromJson(json['preferences'])
          : null,
      patterns: json['patterns'] != null
          ? ReadingPatternsData.fromJson(json['patterns'])
          : null,
      engagement: json['engagement'] != null
          ? EngagementMetrics.fromJson(json['engagement'])
          : null,
      insights: (json['insights'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
    );
  }
}

class ReadingAnalytics {
  final int totalArticlesRead;
  final int totalReadingTime; // minutes
  final int averageReadingTime; // minutes
  final double articlesPerDay;
  final int mostActiveHour;
  final String mostActiveDay;
  final int readingStreak;
  final int longestStreak;

  ReadingAnalytics({
    required this.totalArticlesRead,
    required this.totalReadingTime,
    required this.averageReadingTime,
    required this.articlesPerDay,
    required this.mostActiveHour,
    required this.mostActiveDay,
    required this.readingStreak,
    required this.longestStreak,
  });

  factory ReadingAnalytics.fromJson(Map<String, dynamic> json) {
    return ReadingAnalytics(
      totalArticlesRead: (json['totalArticlesRead'] as num?)?.toInt() ?? 0,
      totalReadingTime: (json['totalReadingTime'] as num?)?.toInt() ?? 0,
      averageReadingTime: (json['averageReadingTime'] as num?)?.toInt() ?? 0,
      articlesPerDay: (json['articlesPerDay'] as num?)?.toDouble() ?? 0,
      mostActiveHour: (json['mostActiveHour'] as num?)?.toInt() ?? 0,
      mostActiveDay: (json['mostActiveDay'] as String?) ?? '',
      readingStreak: (json['readingStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longestStreak'] as num?)?.toInt() ?? 0,
    );
  }
}

class ContentPreferences {
  final List<CategoryCount> topCategories;
  final List<AuthorCount> topAuthors;
  final List<SourceCount> topSources;
  final String preferredLength;
  final int readingSpeed;

  ContentPreferences({
    required this.topCategories,
    required this.topAuthors,
    required this.topSources,
    required this.preferredLength,
    required this.readingSpeed,
  });

  factory ContentPreferences.fromJson(Map<String, dynamic> json) {
    return ContentPreferences(
      topCategories: (json['topCategories'] as List? ?? [])
          .map((item) => CategoryCount.fromJson(item))
          .toList(),
      topAuthors: (json['topAuthors'] as List? ?? [])
          .map((item) => AuthorCount.fromJson(item))
          .toList(),
      topSources: (json['topSources'] as List? ?? [])
          .map((item) => SourceCount.fromJson(item))
          .toList(),
      preferredLength: (json['preferredLength'] as String?) ?? '',
      readingSpeed: (json['readingSpeed'] as num?)?.toInt() ?? 0,
    );
  }
}

class CategoryCount {
  final String name;
  final int count;
  final double percentage;

  CategoryCount({
    required this.name,
    required this.count,
    required this.percentage,
  });

  factory CategoryCount.fromJson(Map<String, dynamic> json) {
    return CategoryCount(
      name: (json['category'] ?? json['name'] ?? '') as String,
      count: (json['count'] as num?)?.toInt() ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AuthorCount {
  final String name;
  final int count;

  AuthorCount({required this.name, required this.count});

  factory AuthorCount.fromJson(Map<String, dynamic> json) {
    return AuthorCount(
      name: (json['author'] ?? json['name'] ?? '') as String,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class SourceCount {
  final String name;
  final int count;

  SourceCount({required this.name, required this.count});

  factory SourceCount.fromJson(Map<String, dynamic> json) {
    return SourceCount(
      name: (json['source'] ?? json['name'] ?? '') as String,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReadingPatternsData {
  final List<HourCount> dailyDistribution;
  final List<DayCount> weeklyDistribution;
  final List<DateCount> monthlyTrend;

  ReadingPatternsData({
    required this.dailyDistribution,
    required this.weeklyDistribution,
    required this.monthlyTrend,
  });

  factory ReadingPatternsData.fromJson(Map<String, dynamic> json) {
    return ReadingPatternsData(
      dailyDistribution: (json['dailyDistribution'] as List? ?? [])
          .map((item) => HourCount.fromJson(item))
          .toList(),
      weeklyDistribution: (json['weeklyDistribution'] as List? ?? [])
          .map((item) => DayCount.fromJson(item))
          .toList(),
      monthlyTrend: (json['monthlyTrend'] as List? ?? [])
          .map((item) => DateCount.fromJson(item))
          .toList(),
    );
  }
}

class HourCount {
  final int hour;
  final int count;

  HourCount({required this.hour, required this.count});

  factory HourCount.fromJson(Map<String, dynamic> json) {
    return HourCount(
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class DayCount {
  final String day;
  final int count;

  DayCount({required this.day, required this.count});

  factory DayCount.fromJson(Map<String, dynamic> json) {
    return DayCount(
      day: (json['day'] ?? '') as String,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class DateCount {
  final String date;
  final int count;

  DateCount({required this.date, required this.count});

  factory DateCount.fromJson(Map<String, dynamic> json) {
    return DateCount(
      date: (json['date'] ?? '') as String,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class EngagementMetrics {
  final double averageTimePerParagraph; // minutes
  final double bookmarkRate; // 0-100
  final double interactionScore; // 0-100

  EngagementMetrics({
    required this.averageTimePerParagraph,
    required this.bookmarkRate,
    required this.interactionScore,
  });

  factory EngagementMetrics.fromJson(Map<String, dynamic> json) {
    return EngagementMetrics(
      averageTimePerParagraph:
          (json['averageTimePerParagraph'] as num?)?.toDouble() ?? 0,
      bookmarkRate: (json['bookmarkRate'] as num?)?.toDouble() ?? 0,
      interactionScore: (json['interactionScore'] as num?)?.toDouble() ?? 0,
    );
  }
}
