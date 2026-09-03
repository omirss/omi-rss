import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/feed.dart';
import '../core/models/article.dart';
import '../core/models/user.dart';
import '../core/models/folder.dart';
import '../providers/auth_provider.dart';
import '../config/api_config.dart';

class ApiService {
  late final Dio _dio;
  final Ref _ref;

  ApiService(this._ref) {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectionTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add interceptors
    _dio.interceptors.add(AuthInterceptor(_ref));
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
    ));
  }

  // Authentication endpoints
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> register(String email, String password, String name) async {
    try {
      final response = await _dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'name': name,
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // User endpoints
  Future<User> getCurrentUser() async {
    try {
      final response = await _dio.get('/user/me');
      return User.fromJson(response.data['user']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<User> updateUser(Map<String, dynamic> updates) async {
    try {
      final response = await _dio.put('/user/me', data: updates);
      return User.fromJson(response.data['user']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Feed endpoints
  Future<List<Feed>> getFeeds() async {
    try {
      final response = await _dio.get('/feeds');
      return (response.data['feeds'] as List)
          .map((json) => Feed.fromJson(json))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Feed> getFeed(int feedId) async {
    try {
      final response = await _dio.get('/feeds/$feedId');
      return Feed.fromJson(response.data['feed']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Feed> createFeed(String url, {int? folderId}) async {
    try {
      final response = await _dio.post('/feeds', data: {
        'url': url,
        if (folderId != null) 'folderId': folderId,
      });
      return Feed.fromJson(response.data['feed']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Feed> updateFeed(int feedId, Map<String, dynamic> updates) async {
    try {
      final response = await _dio.put('/feeds/$feedId', data: updates);
      return Feed.fromJson(response.data['feed']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteFeed(int feedId) async {
    try {
      await _dio.delete('/feeds/$feedId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> refreshFeed(int feedId) async {
    try {
      await _dio.post('/feeds/$feedId/refresh');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Article endpoints
  Future<List<Article>> getArticles({
    int? feedId,
    int? folderId,
    bool? unreadOnly,
    int? limit,
    int? offset,
    String? search,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (feedId != null) queryParams['feedId'] = feedId;
      if (folderId != null) queryParams['folderId'] = folderId;
      if (unreadOnly != null) queryParams['unreadOnly'] = unreadOnly;
      if (limit != null) queryParams['limit'] = limit;
      if (offset != null) queryParams['offset'] = offset;
      if (search != null) queryParams['search'] = search;

      final response = await _dio.get('/articles', queryParameters: queryParams);
      return (response.data['articles'] as List)
          .map((json) => Article.fromJson(json))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Article> getArticle(int articleId) async {
    try {
      final response = await _dio.get('/articles/$articleId');
      return Article.fromJson(response.data['article']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> markArticleRead(int articleId, bool isRead) async {
    try {
      await _dio.put('/articles/$articleId/read', data: {
        'isRead': isRead,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> markArticleSaved(int articleId, bool isSaved) async {
    try {
      await _dio.put('/articles/$articleId/saved', data: {
        'isSaved': isSaved,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> markAllRead({int? feedId, int? folderId}) async {
    try {
      final data = <String, dynamic>{};
      if (feedId != null) data['feedId'] = feedId;
      if (folderId != null) data['folderId'] = folderId;
      
      await _dio.post('/articles/mark-all-read', data: data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Folder endpoints
  Future<List<Folder>> getFolders() async {
    try {
      final response = await _dio.get('/folders');
      return (response.data['folders'] as List)
          .map((json) => Folder.fromJson(json))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Folder> createFolder(String name) async {
    try {
      final response = await _dio.post('/folders', data: {
        'name': name,
      });
      return Folder.fromJson(response.data['folder']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Folder> updateFolder(int folderId, String name) async {
    try {
      final response = await _dio.put('/folders/$folderId', data: {
        'name': name,
      });
      return Folder.fromJson(response.data['folder']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteFolder(int folderId) async {
    try {
      await _dio.delete('/folders/$folderId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // OPML endpoints
  Future<void> importOpml(String opmlContent) async {
    try {
      await _dio.post('/feeds/import-opml', data: {
        'opmlContent': opmlContent,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<String> exportOpml() async {
    try {
      final response = await _dio.get('/feeds/export-opml');
      return response.data['opml'];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Analytics endpoints
  Future<Map<String, dynamic>> getAnalytics() async {
    try {
      final response = await _dio.get('/analytics');
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Error handling
  String _handleError(DioException error) {
    if (error.response != null) {
      final data = error.response!.data;
      if (data is Map && data.containsKey('message')) {
        return data['message'];
      }
      
      switch (error.response!.statusCode) {
        case 400:
          return 'Bad request. Please check your input.';
        case 401:
          return 'Unauthorized. Please login again.';
        case 403:
          return 'Forbidden. You don\'t have permission to perform this action.';
        case 404:
          return 'Resource not found.';
        case 500:
          return 'Server error. Please try again later.';
        default:
          return 'An error occurred. Please try again.';
      }
    }
    
    if (error.type == DioExceptionType.connectionTimeout) {
      return 'Connection timeout. Please check your internet connection.';
    }
    
    if (error.type == DioExceptionType.receiveTimeout) {
      return 'Server took too long to respond. Please try again.';
    }
    
    return 'Network error. Please check your connection.';
  }
}

// Auth interceptor to add JWT token to requests
class AuthInterceptor extends Interceptor {
  final Ref ref;

  AuthInterceptor(this.ref);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Skip auth for login/register endpoints
    if (options.path.contains('/auth/login') || 
        options.path.contains('/auth/register')) {
      return handler.next(options);
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Token might be expired, try to refresh
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');

      if (refreshToken != null) {
        try {
          // Create new Dio instance to avoid interceptor loop
          final dio = Dio(BaseOptions(baseUrl: err.requestOptions.baseUrl));
          final response = await dio.post('/auth/refresh', data: {
            'refreshToken': refreshToken,
          });

          final newToken = response.data['accessToken'];
          final newRefreshToken = response.data['refreshToken'];

          // Save new tokens
          await prefs.setString('access_token', newToken);
          await prefs.setString('refresh_token', newRefreshToken);

          // Retry original request with new token
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          final cloneReq = await dio.fetch(err.requestOptions);
          return handler.resolve(cloneReq);
        } catch (e) {
          // Refresh failed, logout user
          ref.read(authProvider.notifier).logout();
        }
      }
    }

    handler.next(err);
  }
}

// Provider for API service
final apiServiceProvider = Provider<ApiService>((ref) => ApiService(ref));