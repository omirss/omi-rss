import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/feed.dart';
import '../core/models/article.dart';
import '../core/models/user.dart';
import '../core/models/folder.dart';
import '../providers/auth_provider.dart';
import '../config/api_config.dart';

/// API error carrying the HTTP status so callers can distinguish auth
/// rejections from transient network/server failures.
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  late final Dio _dio;
  final Ref _ref;

  int _authGeneration = 0;
  Future<Map<String, dynamic>?>? _refreshInFlight;

  ApiService(this._ref) {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.apiBaseUrl,
      connectTimeout: ApiConfig.connectionTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add interceptors
    _dio.interceptors.add(AuthInterceptor(_ref));
    if (kDebugMode) {
      // Never log request/response bodies: they can contain passwords,
      // tokens, and private payloads.
      _dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        error: true,
      ));
    }
  }

  /// Invalidate outstanding auth work. Callers must rotate on login,
  /// logout, credential changes, and server switches so a stale refresh
  /// cannot resurrect or overwrite credentials.
  void rotateAuthSession() {
    _authGeneration++;
    _refreshInFlight = null;
  }

  void updateBaseUrl(String url) {
    rotateAuthSession();
    _dio.options.baseUrl = url.isEmpty ? '' : '${ApiConfig.normalizeUrl(url)}/api';
  }

  String get baseUrl => _dio.options.baseUrl;

  Dio get dio => _dio;

  // Authentication endpoints
  Future<Map<String, dynamic>> login(String emailOrUsername, String password) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'emailOrUsername': emailOrUsername,
        'password': password,
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> register({
    required String username,
    String? email,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/auth/register', data: {
        'username': username,
        if (email != null && email.isNotEmpty) 'email': email,
        'password': password,
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> requestPasswordReset(String email) async {
    try {
      await _dio.post('/auth/forgot-password', data: {'email': email});
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

  /// Refresh tokens once for all concurrent 401s. The result is written to
  /// preferences only when the auth session, the stored refresh token, and
  /// the base URL are all unchanged since the refresh started; otherwise
  /// null is returned and nothing is written.
  Future<Map<String, dynamic>?> refreshTokensSingleFlight(
    String refreshToken,
    String baseUrl,
  ) {
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final generation = _authGeneration;
    late final Future<Map<String, dynamic>?> future;
    future = _performTokenRefresh(refreshToken, baseUrl)
        .then((tokens) async {
      if (generation != _authGeneration) return null;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('refresh_token') != refreshToken) return null;
      await prefs.setString('access_token', tokens['token'] as String);
      final newRefreshToken = tokens['refreshToken'];
      if (newRefreshToken is String) {
        await prefs.setString('refresh_token', newRefreshToken);
      }
      return tokens;
    }).whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
    _refreshInFlight = future;
    return future;
  }

  Future<Map<String, dynamic>> _performTokenRefresh(
    String refreshToken,
    String baseUrl,
  ) async {
    // Bare dio without interceptors to avoid a refresh loop.
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    final response = await dio.post('/auth/refresh', data: {
      'refreshToken': refreshToken,
    });
    return response.data;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } on DioException catch (_) {
      // Logout is a no-op server-side; stored auth is cleared regardless
    }
  }

  // User endpoints
  Future<User> getCurrentUser() async {
    try {
      final response = await _dio.get('/users/me');
      return User.fromJson(response.data['user']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<User> updateUser(Map<String, dynamic> updates) async {
    try {
      final response = await _dio.put('/users/me', data: updates);
      return User.fromJson(response.data['user']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.put('/users/me/password', data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<User> uploadAvatar(String filePath, String filename) async {
    try {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(filePath, filename: filename),
      });
      final response = await _dio.post('/users/me/avatar', data: formData);
      return User.fromJson(response.data['user']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<User> uploadAvatarBytes(List<int> bytes, String filename) async {
    try {
      final formData = FormData.fromMap({
        'avatar': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final response = await _dio.post('/users/me/avatar', data: formData);
      return User.fromJson(response.data['user']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteAccount(String password) async {
    try {
      await _dio.delete('/users/me', data: {'password': password});
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

  Future<Feed> getFeed(String feedId) async {
    try {
      final response = await _dio.get('/feeds/$feedId');
      return Feed.fromJson(response.data['feed']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Feed> createFeed(String url, {String? folderId}) async {
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

  Future<Feed> updateFeed(String feedId, Map<String, dynamic> updates) async {
    try {
      final response = await _dio.put('/feeds/$feedId', data: updates);
      return Feed.fromJson(response.data['feed']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteFeed(String feedId) async {
    try {
      await _dio.delete('/feeds/$feedId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> refreshFeed(String feedId) async {
    try {
      await _dio.post('/feeds/$feedId/refresh');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Article endpoints
  Future<List<Article>> getArticles({
    String? feedId,
    String? folderId,
    bool? unreadOnly,
    bool? starredOnly,
    int? limit,
    int? offset,
    String? search,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (feedId != null) queryParams['feedId'] = feedId;
      if (folderId != null) queryParams['folderId'] = folderId;
      if (unreadOnly == true) queryParams['isRead'] = 'false';
      if (starredOnly == true) queryParams['isStarred'] = 'true';
      if (limit != null) queryParams['limit'] = limit;
      if (offset != null) {
        queryParams['page'] = (offset ~/ (limit ?? 20)) + 1;
      }
      if (search != null) queryParams['search'] = search;

      final response = await _dio.get('/articles', queryParameters: queryParams);
      return (response.data['articles'] as List)
          .map((json) => Article.fromJson(json))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Article> getArticle(String articleId) async {
    try {
      final response = await _dio.get('/articles/$articleId');
      return Article.fromJson(response.data['article']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateArticleState(
    String articleId, {
    bool? isRead,
    bool? isStarred,
  }) async {
    try {
      await _dio.put('/articles/$articleId/state', data: {
        if (isRead != null) 'isRead': isRead,
        if (isStarred != null) 'isStarred': isStarred,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> markAllRead({String? feedId, String? folderId}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (feedId != null) queryParams['feedId'] = feedId;
      if (folderId != null) queryParams['folderId'] = folderId;

      await _dio.post('/articles/mark-all-read', queryParameters: queryParams);
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

  Future<Folder> updateFolder(String folderId, String name) async {
    try {
      final response = await _dio.put('/folders/$folderId', data: {
        'name': name,
      });
      return Folder.fromJson(response.data['folder']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteFolder(String folderId) async {
    try {
      await _dio.delete('/folders/$folderId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // OPML endpoints
  Future<void> importOpml(String opmlContent) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromString(
          opmlContent,
          filename: 'import.opml',
          contentType: DioMediaType('application', 'xml'),
        ),
      });
      await _dio.post('/discovery/import/opml', data: formData);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<String> exportOpml() async {
    try {
      final response = await _dio.get(
        '/discovery/export/opml',
        options: Options(responseType: ResponseType.plain),
      );
      return response.data as String;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Error handling
  ApiException _handleError(DioException error) {
    if (error.response != null) {
      final statusCode = error.response!.statusCode;
      final data = error.response!.data;
      if (data is Map) {
        final serverError = data['error'] ?? data['message'];
        if (serverError is String && serverError.isNotEmpty) {
          return ApiException(serverError, statusCode: statusCode);
        }
      }

      switch (statusCode) {
        case 400:
          return ApiException('Bad request. Please check your input.',
              statusCode: statusCode);
        case 401:
          return ApiException('Unauthorized. Please login again.',
              statusCode: statusCode);
        case 403:
          return ApiException(
              'Forbidden. You don\'t have permission to perform this action.',
              statusCode: statusCode);
        case 404:
          return ApiException('Resource not found.', statusCode: statusCode);
        case 500:
          return ApiException('Server error. Please try again later.',
              statusCode: statusCode);
        default:
          return ApiException('An error occurred. Please try again.',
              statusCode: statusCode);
      }
    }

    if (error.type == DioExceptionType.connectionTimeout) {
      return ApiException(
          'Connection timeout. Please check your internet connection.');
    }

    if (error.type == DioExceptionType.receiveTimeout) {
      return ApiException('Server took too long to respond. Please try again.');
    }

    return ApiException('Network error. Please check your connection.');
  }
}

// Auth interceptor to add JWT token to requests
class AuthInterceptor extends Interceptor {
  final Ref ref;

  AuthInterceptor(this.ref);

  ApiService _api() => ref.read(apiServiceProvider);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Skip auth for public auth endpoints
    if (options.path.contains('/auth/login') ||
        options.path.contains('/auth/register') ||
        options.path.contains('/auth/refresh') ||
        options.path.contains('/auth/forgot-password')) {
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
    if (err.response?.statusCode == 401 && !err.requestOptions.path.contains('/auth/')) {
      // Token might be expired, try to refresh. The refresh is single-flight
      // and bound to the session that started it: if the user logs out,
      // logs in as someone else, or switches server origin while the
      // refresh is in flight, its result is discarded instead of being
      // written back to preferences.
      final api = _api();
      final generation = api._authGeneration;
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');

      if (refreshToken != null) {
        try {
          final tokens =
              await api.refreshTokensSingleFlight(refreshToken, err.requestOptions.baseUrl);
          if (tokens != null && generation == api._authGeneration) {
            final newToken = tokens['token'] as String;
            // Retry original request with new token
            err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            // Bare dio avoids the interceptor loop on retry.
            final dio = Dio(BaseOptions(baseUrl: err.requestOptions.baseUrl));
            final cloneReq = await dio.fetch(err.requestOptions);
            return handler.resolve(cloneReq);
          }
        } on DioException catch (e) {
          if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
            // Refresh token rejected: clear the session locally. Network
          // and 5xx failures keep stored credentials.
            unawaited(ref.read(authProvider.notifier).clearLocalSession());
          }
        }
      }
    }

    handler.next(err);
  }
}

// Provider for API service
final apiServiceProvider = Provider<ApiService>((ref) => ApiService(ref));
