import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_glassmorphism_reader/core/api/api_config.dart';
import 'package:rss_glassmorphism_reader/core/api/api_interceptors.dart';

final apiClientProvider = Provider((ref) => ApiClient());

class ApiClient {
  late final Dio _dio;
  
  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
    
    // Add interceptors
    _dio.interceptors.addAll([
      AuthInterceptor(),
      LoggingInterceptor(),
      RetryInterceptor(_dio),
      CacheInterceptor(),
    ]);
  }
  
  // Auth endpoints
  Future<ApiResponse<AuthResponse>> login(String email, String password) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      return ApiResponse.success(AuthResponse.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<AuthResponse>> register(
    String email,
    String password,
    String name,
  ) async {
    try {
      final response = await _dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'name': name,
      });
      return ApiResponse.success(AuthResponse.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> logout() async {
    try {
      await _dio.post('/auth/logout');
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<AuthResponse>> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post('/auth/refresh', data: {
        'refresh_token': refreshToken,
      });
      return ApiResponse.success(AuthResponse.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // User endpoints
  Future<ApiResponse<User>> getProfile() async {
    try {
      final response = await _dio.get('/user/profile');
      return ApiResponse.success(User.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<User>> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/user/profile', data: data);
      return ApiResponse.success(User.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> deleteAccount() async {
    try {
      await _dio.delete('/user/account');
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Feed endpoints
  Future<ApiResponse<List<Feed>>> getFeeds() async {
    try {
      final response = await _dio.get('/feeds');
      final feeds = (response.data as List)
          .map((json) => Feed.fromJson(json))
          .toList();
      return ApiResponse.success(feeds);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<Feed>> addFeed(String url, {String? categoryId}) async {
    try {
      final response = await _dio.post('/feeds', data: {
        'url': url,
        'category_id': categoryId,
      });
      return ApiResponse.success(Feed.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<Feed>> updateFeed(String feedId, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/feeds/$feedId', data: data);
      return ApiResponse.success(Feed.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> deleteFeed(String feedId) async {
    try {
      await _dio.delete('/feeds/$feedId');
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> refreshFeed(String feedId) async {
    try {
      await _dio.post('/feeds/$feedId/refresh');
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Article endpoints
  Future<ApiResponse<List<Article>>> getArticles({
    String? feedId,
    String? categoryId,
    bool? unreadOnly,
    bool? savedOnly,
    String? search,
    int? limit,
    int? offset,
  }) async {
    try {
      final response = await _dio.get('/articles', queryParameters: {
        if (feedId != null) 'feed_id': feedId,
        if (categoryId != null) 'category_id': categoryId,
        if (unreadOnly != null) 'unread_only': unreadOnly,
        if (savedOnly != null) 'saved_only': savedOnly,
        if (search != null) 'search': search,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      });
      final articles = (response.data as List)
          .map((json) => Article.fromJson(json))
          .toList();
      return ApiResponse.success(articles);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<Article>> getArticle(String articleId) async {
    try {
      final response = await _dio.get('/articles/$articleId');
      return ApiResponse.success(Article.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> markAsRead(String articleId) async {
    try {
      await _dio.post('/articles/$articleId/read');
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> markAsUnread(String articleId) async {
    try {
      await _dio.delete('/articles/$articleId/read');
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> saveArticle(String articleId) async {
    try {
      await _dio.post('/articles/$articleId/save');
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> unsaveArticle(String articleId) async {
    try {
      await _dio.delete('/articles/$articleId/save');
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> markAllAsRead({String? feedId, String? categoryId}) async {
    try {
      await _dio.post('/articles/mark-all-read', data: {
        if (feedId != null) 'feed_id': feedId,
        if (categoryId != null) 'category_id': categoryId,
      });
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Category endpoints
  Future<ApiResponse<List<Category>>> getCategories() async {
    try {
      final response = await _dio.get('/categories');
      final categories = (response.data as List)
          .map((json) => Category.fromJson(json))
          .toList();
      return ApiResponse.success(categories);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<Category>> createCategory(String name, {String? icon}) async {
    try {
      final response = await _dio.post('/categories', data: {
        'name': name,
        if (icon != null) 'icon': icon,
      });
      return ApiResponse.success(Category.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<Category>> updateCategory(
    String categoryId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.put('/categories/$categoryId', data: data);
      return ApiResponse.success(Category.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<void>> deleteCategory(String categoryId) async {
    try {
      await _dio.delete('/categories/$categoryId');
      return ApiResponse.success(null);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // AI endpoints
  Future<ApiResponse<AiAnalysis>> analyzeArticle(String articleId) async {
    try {
      final response = await _dio.post('/ai/analyze/$articleId');
      return ApiResponse.success(AiAnalysis.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<List<String>>> generateSummary(String articleId) async {
    try {
      final response = await _dio.post('/ai/summarize/$articleId');
      return ApiResponse.success(List<String>.from(response.data['summary']));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<List<Perspective>>> getPerspectives(String articleId) async {
    try {
      final response = await _dio.get('/ai/perspectives/$articleId');
      final perspectives = (response.data as List)
          .map((json) => Perspective.fromJson(json))
          .toList();
      return ApiResponse.success(perspectives);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Full text extraction
  Future<ApiResponse<String>> extractFullText(String url) async {
    try {
      final response = await _dio.post('/extract', data: {
        'url': url,
      });
      return ApiResponse.success(response.data['content']);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Feed generation
  Future<ApiResponse<GeneratedFeed>> generateFeed(String url) async {
    try {
      final response = await _dio.post('/generate', data: {
        'url': url,
      });
      return ApiResponse.success(GeneratedFeed.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Statistics
  Future<ApiResponse<Statistics>> getStatistics() async {
    try {
      final response = await _dio.get('/statistics');
      return ApiResponse.success(Statistics.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<FeedStatistics>> getFeedStatistics(String feedId) async {
    try {
      final response = await _dio.get('/statistics/feed/$feedId');
      return ApiResponse.success(FeedStatistics.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Search
  Future<ApiResponse<SearchResults>> search(String query, {
    List<String>? types,
    int? limit,
  }) async {
    try {
      final response = await _dio.get('/search', queryParameters: {
        'q': query,
        if (types != null) 'types': types.join(','),
        if (limit != null) 'limit': limit,
      });
      return ApiResponse.success(SearchResults.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Export/Import
  Future<ApiResponse<String>> exportData(ExportFormat format) async {
    try {
      final response = await _dio.get('/export', queryParameters: {
        'format': format.name,
      });
      return ApiResponse.success(response.data['url']);
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<ImportResult>> importData(String fileUrl, ImportFormat format) async {
    try {
      final response = await _dio.post('/import', data: {
        'url': fileUrl,
        'format': format.name,
      });
      return ApiResponse.success(ImportResult.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Settings
  Future<ApiResponse<UserSettings>> getSettings() async {
    try {
      final response = await _dio.get('/settings');
      return ApiResponse.success(UserSettings.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  Future<ApiResponse<UserSettings>> updateSettings(Map<String, dynamic> settings) async {
    try {
      final response = await _dio.put('/settings', data: settings);
      return ApiResponse.success(UserSettings.fromJson(response.data));
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }
  
  // Error handling
  String _handleError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timeout. Please check your internet connection.';
        case DioExceptionType.connectionError:
          return 'Unable to connect to server. Please check your internet connection.';
        case DioExceptionType.badCertificate:
          return 'Security certificate error. Please try again later.';
        case DioExceptionType.cancel:
          return 'Request cancelled.';
        case DioExceptionType.unknown:
          if (error.response?.statusCode != null) {
            return _handleStatusCode(error.response!.statusCode!, error.response?.data);
          }
          return 'An unknown error occurred.';
        default:
          return 'An error occurred. Please try again.';
      }
    }
    return error.toString();
  }
  
  String _handleStatusCode(int statusCode, dynamic data) {
    final message = data?['message'] ?? data?['error'];
    
    switch (statusCode) {
      case 400:
        return message ?? 'Invalid request. Please check your input.';
      case 401:
        return message ?? 'Authentication required. Please log in.';
      case 403:
        return message ?? 'Access denied. You don\'t have permission to perform this action.';
      case 404:
        return message ?? 'Resource not found.';
      case 422:
        return message ?? 'Invalid data provided.';
      case 429:
        return message ?? 'Too many requests. Please try again later.';
      case 500:
        return message ?? 'Server error. Please try again later.';
      case 503:
        return message ?? 'Service temporarily unavailable. Please try again later.';
      default:
        return message ?? 'An error occurred (Code: $statusCode).';
    }
  }
}

// Response wrapper
class ApiResponse<T> {
  final T? data;
  final String? error;
  final bool isSuccess;
  
  ApiResponse._({this.data, this.error, required this.isSuccess});
  
  factory ApiResponse.success(T? data) => ApiResponse._(
    data: data,
    isSuccess: true,
  );
  
  factory ApiResponse.error(String error) => ApiResponse._(
    error: error,
    isSuccess: false,
  );
}

// Enums
enum ExportFormat { opml, json, csv }
enum ImportFormat { opml, json }