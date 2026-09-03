import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';

class AnalyticsService {
  final String baseUrl = ApiConfig.baseUrl;

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

  // Track AI usage
  Future<void> trackAIUsage({
    required String feature,
    required String provider,
    required int responseTime,
    int? tokensUsed,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/analytics/ai-usage'),
      headers: headers,
      body: json.encode({
        'feature': feature,
        'provider': provider,
        'responseTime': responseTime,
        if (tokensUsed != null) 'tokensUsed': tokensUsed,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to track AI usage');
    }
  }

  // Get personalized recommendations
  Future<List<Recommendation>> getPersonalizedRecommendations({
    String type = 'mixed',
    int limit = 10,
  }) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/analytics/recommendations?type=$type&limit=$limit'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;
      return data.map((item) => Recommendation.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load recommendations');
    }
  }

  // Get insights
  Future<List<Insight>> getInsights({String category = 'all'}) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/analytics/insights?category=$category'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;
      return data.map((item) => Insight.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load insights');
    }
  }

  // Export user data
  Future<String> exportUserData() async {
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

  // Get reading streaks
  Future<Map<String, dynamic>> getReadingStreaks() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/analytics/streaks'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load streaks');
    }
  }

  // Compare with others
  Future<Map<String, dynamic>> compareWithOthers() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/analytics/compare'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load comparison');
    }
  }
}

// Models
class UserAnalytics {
  final String userId;
  final String timeframe;
  final ReadingTime? readingTime;
  final ContentPreferences? contentPreferences;
  final ReadingPatterns? readingPatterns;
  final EngagementMetrics? engagementMetrics;
  final Map<String, dynamic>? aiUsage;

  UserAnalytics({
    required this.userId,
    required this.timeframe,
    this.readingTime,
    this.contentPreferences,
    this.readingPatterns,
    this.engagementMetrics,
    this.aiUsage,
  });

  factory UserAnalytics.fromJson(Map<String, dynamic> json) {
    return UserAnalytics(
      userId: json['userId'],
      timeframe: json['timeframe'],
      readingTime: json['readingTime'] != null
          ? ReadingTime.fromJson(json['readingTime'])
          : null,
      contentPreferences: json['contentPreferences'] != null
          ? ContentPreferences.fromJson(json['contentPreferences'])
          : null,
      readingPatterns: json['readingPatterns'] != null
          ? ReadingPatterns.fromJson(json['readingPatterns'])
          : null,
      engagementMetrics: json['engagementMetrics'] != null
          ? EngagementMetrics.fromJson(json['engagementMetrics'])
          : null,
      aiUsage: json['aiUsage'],
    );
  }
}

class ReadingTime {
  final int articlesRead;
  final double totalTimeHours;
  final double averageTimeMinutes;
  final Map<String, int> dailyReading;

  ReadingTime({
    required this.articlesRead,
    required this.totalTimeHours,
    required this.averageTimeMinutes,
    required this.dailyReading,
  });

  factory ReadingTime.fromJson(Map<String, dynamic> json) {
    return ReadingTime(
      articlesRead: json['articlesRead'],
      totalTimeHours: json['totalTimeHours'].toDouble(),
      averageTimeMinutes: json['averageTimeMinutes'].toDouble(),
      dailyReading: Map<String, int>.from(json['dailyReading']),
    );
  }
}

class ContentPreferences {
  final List<CategoryCount> topCategories;
  final List<AuthorCount> topAuthors;
  final List<SourceCount> topSources;
  final List<String> preferredLanguages;

  ContentPreferences({
    required this.topCategories,
    required this.topAuthors,
    required this.topSources,
    required this.preferredLanguages,
  });

  factory ContentPreferences.fromJson(Map<String, dynamic> json) {
    return ContentPreferences(
      topCategories: (json['topCategories'] as List)
          .map((item) => CategoryCount.fromJson(item))
          .toList(),
      topAuthors: (json['topAuthors'] as List)
          .map((item) => AuthorCount.fromJson(item))
          .toList(),
      topSources: (json['topSources'] as List)
          .map((item) => SourceCount.fromJson(item))
          .toList(),
      preferredLanguages: List<String>.from(json['preferredLanguages']),
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
      name: json['name'],
      count: json['count'],
      percentage: json['percentage'].toDouble(),
    );
  }
}

class AuthorCount {
  final String name;
  final int count;

  AuthorCount({required this.name, required this.count});

  factory AuthorCount.fromJson(Map<String, dynamic> json) {
    return AuthorCount(
      name: json['name'],
      count: json['count'],
    );
  }
}

class SourceCount {
  final String name;
  final String url;
  final int count;

  SourceCount({
    required this.name,
    required this.url,
    required this.count,
  });

  factory SourceCount.fromJson(Map<String, dynamic> json) {
    return SourceCount(
      name: json['name'],
      url: json['url'],
      count: json['count'],
    );
  }
}

class ReadingPatterns {
  final Map<String, int> hourlyDistribution;
  final Map<String, int> weeklyDistribution;
  final List<String> peakHours;
  final List<String> peakDays;
  final Map<String, double> trends;
  final ReadingStreak? currentStreak;
  final ReadingStreak? longestStreak;

  ReadingPatterns({
    required this.hourlyDistribution,
    required this.weeklyDistribution,
    required this.peakHours,
    required this.peakDays,
    required this.trends,
    this.currentStreak,
    this.longestStreak,
  });

  factory ReadingPatterns.fromJson(Map<String, dynamic> json) {
    return ReadingPatterns(
      hourlyDistribution: Map<String, int>.from(json['hourlyDistribution']),
      weeklyDistribution: Map<String, int>.from(json['weeklyDistribution']),
      peakHours: List<String>.from(json['peakHours']),
      peakDays: List<String>.from(json['peakDays']),
      trends: Map<String, double>.from(json['trends']),
      currentStreak: json['currentStreak'] != null
          ? ReadingStreak.fromJson(json['currentStreak'])
          : null,
      longestStreak: json['longestStreak'] != null
          ? ReadingStreak.fromJson(json['longestStreak'])
          : null,
    );
  }
}

class ReadingStreak {
  final int days;
  final DateTime startDate;
  final DateTime? endDate;

  ReadingStreak({
    required this.days,
    required this.startDate,
    this.endDate,
  });

  factory ReadingStreak.fromJson(Map<String, dynamic> json) {
    return ReadingStreak(
      days: json['days'],
      startDate: DateTime.parse(json['startDate']),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
    );
  }
}

class EngagementMetrics {
  final double averageScrollDepth;
  final double bookmarkRate;
  final double shareRate;
  final double completionRate;
  final Map<String, double> engagementByCategory;

  EngagementMetrics({
    required this.averageScrollDepth,
    required this.bookmarkRate,
    required this.shareRate,
    required this.completionRate,
    required this.engagementByCategory,
  });

  factory EngagementMetrics.fromJson(Map<String, dynamic> json) {
    return EngagementMetrics(
      averageScrollDepth: json['averageScrollDepth'].toDouble(),
      bookmarkRate: json['bookmarkRate'].toDouble(),
      shareRate: json['shareRate'].toDouble(),
      completionRate: json['completionRate'].toDouble(),
      engagementByCategory: Map<String, double>.from(json['engagementByCategory']),
    );
  }
}

class Recommendation {
  final String id;
  final String type;
  final String title;
  final String? description;
  final String? url;
  final double score;
  final String reason;
  final Map<String, dynamic>? metadata;

  Recommendation({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.url,
    required this.score,
    required this.reason,
    this.metadata,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      id: json['id'],
      type: json['type'],
      title: json['title'],
      description: json['description'],
      url: json['url'],
      score: json['score'].toDouble(),
      reason: json['reason'],
      metadata: json['metadata'],
    );
  }
}

class Insight {
  final String id;
  final String category;
  final String type;
  final String title;
  final String description;
  final Map<String, dynamic>? data;
  final String? actionUrl;
  final DateTime createdAt;

  Insight({
    required this.id,
    required this.category,
    required this.type,
    required this.title,
    required this.description,
    this.data,
    this.actionUrl,
    required this.createdAt,
  });

  factory Insight.fromJson(Map<String, dynamic> json) {
    return Insight(
      id: json['id'],
      category: json['category'],
      type: json['type'],
      title: json['title'],
      description: json['description'],
      data: json['data'],
      actionUrl: json['actionUrl'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}