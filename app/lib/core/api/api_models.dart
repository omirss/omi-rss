import 'package:freezed_annotation/freezed_annotation.dart';

part 'api_models.freezed.dart';
part 'api_models.g.dart';

// Auth models
@freezed
class AuthResponse with _$AuthResponse {
  const factory AuthResponse({
    required String accessToken,
    required String refreshToken,
    required User user,
    required DateTime expiresAt,
  }) = _AuthResponse;

  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);
}

@freezed
class User with _$User {
  const factory User({
    required String id,
    required String email,
    required String name,
    String? avatarUrl,
    required DateTime createdAt,
    required DateTime updatedAt,
    required UserSettings settings,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}

@freezed
class UserSettings with _$UserSettings {
  const factory UserSettings({
    required String theme,
    required String language,
    required bool enableNotifications,
    required bool enableAI,
    required int refreshInterval,
    required int articlesPerPage,
    required bool showImages,
    required bool enableBypass,
    required Map<String, dynamic> customSettings,
  }) = _UserSettings;

  factory UserSettings.fromJson(Map<String, dynamic> json) =>
      _$UserSettingsFromJson(json);
}

// Feed models
@freezed
class Feed with _$Feed {
  const factory Feed({
    required String id,
    required String url,
    required String title,
    String? description,
    String? siteUrl,
    String? iconUrl,
    String? categoryId,
    required int unreadCount,
    required DateTime lastFetched,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Feed;

  factory Feed.fromJson(Map<String, dynamic> json) => _$FeedFromJson(json);
}

@freezed
class Category with _$Category {
  const factory Category({
    required String id,
    required String name,
    String? icon,
    required int feedCount,
    required int unreadCount,
    required DateTime createdAt,
  }) = _Category;

  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);
}

// Article models
@freezed
class Article with _$Article {
  const factory Article({
    required String id,
    required String feedId,
    required String title,
    String? author,
    required String url,
    String? content,
    String? summary,
    String? imageUrl,
    required bool isRead,
    required bool isSaved,
    required DateTime publishedAt,
    required DateTime createdAt,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) = _Article;

  factory Article.fromJson(Map<String, dynamic> json) =>
      _$ArticleFromJson(json);
}

// AI models
@freezed
class AiAnalysis with _$AiAnalysis {
  const factory AiAnalysis({
    required String articleId,
    required SentimentAnalysis sentiment,
    required BiasAnalysis bias,
    required List<String> topics,
    required Map<String, double> entities,
    required double readability,
    required DateTime analyzedAt,
  }) = _AiAnalysis;

  factory AiAnalysis.fromJson(Map<String, dynamic> json) =>
      _$AiAnalysisFromJson(json);
}

@freezed
class SentimentAnalysis with _$SentimentAnalysis {
  const factory SentimentAnalysis({
    required double positive,
    required double negative,
    required double neutral,
    required String overall,
  }) = _SentimentAnalysis;

  factory SentimentAnalysis.fromJson(Map<String, dynamic> json) =>
      _$SentimentAnalysisFromJson(json);
}

@freezed
class BiasAnalysis with _$BiasAnalysis {
  const factory BiasAnalysis({
    required double political,
    required double commercial,
    required double sensational,
    required String direction,
    required double confidence,
  }) = _BiasAnalysis;

  factory BiasAnalysis.fromJson(Map<String, dynamic> json) =>
      _$BiasAnalysisFromJson(json);
}

@freezed
class Perspective with _$Perspective {
  const factory Perspective({
    required String viewpoint,
    required String summary,
    required List<String> keyPoints,
    required double confidence,
  }) = _Perspective;

  factory Perspective.fromJson(Map<String, dynamic> json) =>
      _$PerspectiveFromJson(json);
}

// Statistics models
@freezed
class Statistics with _$Statistics {
  const factory Statistics({
    required int totalFeeds,
    required int totalArticles,
    required int readArticles,
    required int savedArticles,
    required Map<String, int> articlesByDay,
    required Map<String, int> articlesByFeed,
    required Map<String, int> articlesByCategory,
    required double readRate,
    required double averageReadTime,
  }) = _Statistics;

  factory Statistics.fromJson(Map<String, dynamic> json) =>
      _$StatisticsFromJson(json);
}

@freezed
class FeedStatistics with _$FeedStatistics {
  const factory FeedStatistics({
    required String feedId,
    required int totalArticles,
    required int readArticles,
    required int savedArticles,
    required double articlesPerDay,
    required double readRate,
    required Map<String, int> articlesByDay,
    required Map<String, int> articlesByHour,
    required List<String> topAuthors,
    required List<String> topTags,
  }) = _FeedStatistics;

  factory FeedStatistics.fromJson(Map<String, dynamic> json) =>
      _$FeedStatisticsFromJson(json);
}

// Search models
@freezed
class SearchResults with _$SearchResults {
  const factory SearchResults({
    required List<Article> articles,
    required List<Feed> feeds,
    required List<Category> categories,
    required int totalResults,
    required String query,
  }) = _SearchResults;

  factory SearchResults.fromJson(Map<String, dynamic> json) =>
      _$SearchResultsFromJson(json);
}

// Generated feed models
@freezed
class GeneratedFeed with _$GeneratedFeed {
  const factory GeneratedFeed({
    required String url,
    required String feedUrl,
    required String title,
    String? description,
    required List<String> selectors,
    required DateTime generatedAt,
  }) = _GeneratedFeed;

  factory GeneratedFeed.fromJson(Map<String, dynamic> json) =>
      _$GeneratedFeedFromJson(json);
}

// Import/Export models
@freezed
class ImportResult with _$ImportResult {
  const factory ImportResult({
    required int feedsImported,
    required int categoriesImported,
    required List<String> errors,
    required DateTime importedAt,
  }) = _ImportResult;

  factory ImportResult.fromJson(Map<String, dynamic> json) =>
      _$ImportResultFromJson(json);
}