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

/// One page of the server's paginated article list.
class ArticlePage {
  final List<Article> articles;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  const ArticlePage({
    required this.articles,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });
}

class ApiService {
  late final Dio _dio;
  final Ref _ref;

  int _authGeneration = 0;
  ({String refreshToken, String baseUrl, int generation,
     Future<Map<String, dynamic>?> future})? _refreshFlight;

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
    _dio.interceptors.add(AuthInterceptor(_ref, api: this));
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
    _refreshFlight = null;
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
    final existing = _refreshFlight;
    if (existing != null &&
        existing.refreshToken == refreshToken &&
        existing.baseUrl == baseUrl &&
        existing.generation == _authGeneration) {
      return existing.future;
    }

    final generation = _authGeneration;
    late final Future<Map<String, dynamic>?> future;
    future = _performTokenRefresh(refreshToken, baseUrl)
        .then((tokens) async {
      if (generation != _authGeneration) return null;
      final token = tokens['token'];
      if (token is! String || token.isEmpty) {
        throw const ApiException('Invalid refresh response');
      }
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('refresh_token') != refreshToken) return null;
      await prefs.setString('access_token', token);
      // The guards above ran BEFORE this write; a logout or newer login
      // may have interleaved on the platform-channel await and this
      // write may have landed AFTER it cleared or replaced the key.
      // Re-verify before issuing the second write, and roll this one
      // back when ownership was lost: a stale refresh must never
      // resurrect or overwrite credentials (rotateAuthSession's
      // contract). The rollback removes the key only while it holds
      // this flight's value or no value at all — a newer session's
      // credential always survives.
      if (generation != _authGeneration) {
        final currentAccess = prefs.getString('access_token');
        if (currentAccess == token || currentAccess == null) {
          await prefs.remove('access_token');
        }
        return null;
      }
      final newRefreshToken = tokens['refreshToken'];
      if (newRefreshToken is String) {
        await prefs.setString('refresh_token', newRefreshToken);
      }
      // Same re-verification for the second write's await.
      final ownedRefreshToken =
          newRefreshToken is String ? newRefreshToken : refreshToken;
      if (generation != _authGeneration ||
          prefs.getString('refresh_token') != ownedRefreshToken) {
        final currentAccess = prefs.getString('access_token');
        if (currentAccess == token || currentAccess == null) {
          await prefs.remove('access_token');
        }
        final currentRefresh = prefs.getString('refresh_token');
        if (currentRefresh == ownedRefreshToken || currentRefresh == null) {
          await prefs.remove('refresh_token');
        }
        return null;
      }
      // Publish the rotation to the in-memory auth state so
      // getAuthHeaders() and the UI observe the new token before a
      // restart. A stale notifier (disposed container) is skipped.
      final notifier = _tryAuthNotifier();
      if (notifier != null) {
        notifier.applyRotatedTokens(
          token: token,
          refreshToken: newRefreshToken is String ? newRefreshToken : null,
        );
      }
      return tokens;
    }).whenComplete(() {
      if (identical(_refreshFlight?.future, future)) _refreshFlight = null;
    });
    _refreshFlight = (
      refreshToken: refreshToken,
      baseUrl: baseUrl,
      generation: generation,
      future: future,
    );
    return future;
  }

  AuthNotifier? _tryAuthNotifier() {
    try {
      return _ref.read(authProvider.notifier);
    } catch (_) {
      // The provider (or its container) is gone; nothing to publish to.
      return null;
    }
  }

  Future<Map<String, dynamic>> _performTokenRefresh(
    String refreshToken,
    String baseUrl,
  ) async {
    // Bare dio without interceptors to avoid a refresh loop. Timeouts
    // keep a hung server from pinning the flight forever, and the
    // client is always closed so sockets do not leak per rotation.
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: ApiConfig.connectionTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
    try {
      final response = await dio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const ApiException('Invalid refresh response');
      }
      return data;
    } finally {
      dio.close();
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } on DioException catch (_) {
      // Logout is a no-op server-side; stored auth is cleared regardless
    }
  }

  /// Best-effort server logout for credentials captured before the
  /// local session was rotated. Uses exactly the captured token and
  /// origin so clearing a session can never invalidate a newer one.
  Future<void> logoutWithToken(String token, String baseUrl) async {
    if (token.isEmpty || baseUrl.isEmpty) return;
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: ApiConfig.connectionTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
    try {
      await dio.post('/auth/logout',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
    } on DioException catch (_) {
      // Server-side logout is best-effort by design.
    } finally {
      dio.close();
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

  Future<Feed> createFeed(String url, {String? folderId, int? updateInterval}) async {
    try {
      final response = await _dio.post('/feeds', data: {
        'url': url,
        if (folderId != null) 'folderId': folderId,
        if (updateInterval != null) 'updateInterval': updateInterval,
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

  /// Paginated article fetch. The server caps pages at 200 items; use
  /// [totalPages] to walk an account completely.
  Future<ArticlePage> getArticlePage({
    String? feedId,
    String? folderId,
    bool? unreadOnly,
    bool? starredOnly,
    int page = 1,
    int limit = 200,
    String? search,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (feedId != null) 'feedId': feedId,
        if (folderId != null) 'folderId': folderId,
        if (unreadOnly == true) 'isRead': 'false',
        if (starredOnly == true) 'isStarred': 'true',
        if (search != null) 'search': search,
      };

      final response =
          await _dio.get('/articles', queryParameters: queryParams);
      final pagination = response.data['pagination'];
      final pageJson = pagination is Map ? pagination : const <String, dynamic>{};
      return ArticlePage(
        articles: (response.data['articles'] as List)
            .map((json) => Article.fromJson(json))
            .toList(),
        page: (pageJson['page'] as num?)?.toInt() ?? page,
        limit: (pageJson['limit'] as num?)?.toInt() ?? limit,
        total: (pageJson['total'] as num?)?.toInt() ?? 0,
        totalPages: (pageJson['totalPages'] as num?)?.toInt() ?? page,
      );
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
      return _flattenFolders(response.data['folders'] as List);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// The server returns a tree of root folders with nested children;
  /// sync consumers want the flattened list, parents before children.
  static List<Folder> _flattenFolders(List<dynamic> nodes) {
    final out = <Folder>[];
    void visit(dynamic raw) {
      final json = Map<String, dynamic>.from(raw as Map);
      out.add(Folder.fromJson(json));
      final children = json['children'];
      if (children is List) {
        for (final child in children) {
          visit(child);
        }
      }
    }
    for (final node in nodes) {
      visit(node);
    }
    return out;
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

  /// The ApiService that owns the Dio instance this interceptor is
  /// attached to. Resolving it through [ref] would read the provider
  /// from its own Ref ("a provider cannot depend on itself"), so the
  /// instance is bound directly at construction — including to test
  /// subclasses.
  final ApiService api;

  AuthInterceptor(this.ref, {required this.api});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Skip auth for public auth endpoints
    if (options.path.contains('/auth/login') ||
        options.path.contains('/auth/register') ||
        options.path.contains('/auth/refresh') ||
        options.path.contains('/auth/forgot-password')) {
      handler.next(options);
      return;
    }

    // One snapshot of the session at dispatch time: generation, origin
    // and both tokens are read together and travel with the request.
    // The 401 handler may only act inside this snapshot — a response
    // that lands after a login/logout/server switch must never send
    // the CURRENT session's credentials to the OLD origin.
    final prefs = await SharedPreferences.getInstance();
    final snapshot = (
      generation: api._authGeneration,
      baseUrl: options.baseUrl,
      token: prefs.getString('access_token'),
      refreshToken: prefs.getString('refresh_token'),
    );
    options.extra['authDispatch'] = snapshot;

    if (snapshot.token != null) {
      options.headers['Authorization'] = 'Bearer ${snapshot.token}';
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final snapshot = err.requestOptions.extra['authDispatch'];
    if (err.response?.statusCode == 401 &&
        !err.requestOptions.path.contains('/auth/') &&
        snapshot is ({
          int generation,
          String baseUrl,
          String? token,
          String? refreshToken,
        })) {
      // Checks BEFORE issuing a refresh: the session that dispatched
      // this request must still be the current one, and its refresh
      // token must still be the stored one. Otherwise the request is
      // stale and surfacing the 401 is the only safe action.
      final prefs = await SharedPreferences.getInstance();
      final stillCurrent = api._authGeneration == snapshot.generation &&
          snapshot.refreshToken != null &&
          prefs.getString('refresh_token') == snapshot.refreshToken &&
          snapshot.baseUrl == api._dio.options.baseUrl;

      if (stillCurrent) {
        Map<String, dynamic>? tokens;
        var refreshRejected = false;
        try {
          // Refresh posts only to the captured origin with the
          // captured credential.
          tokens = await api.refreshTokensSingleFlight(
              snapshot.refreshToken!, snapshot.baseUrl);
        } on DioException catch (e) {
          if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
            refreshRejected = true;
          }
          // Network and 5xx failures keep stored credentials.
        } on ApiException {
          // Malformed refresh payload: surface the original 401 and
          // keep stored credentials.
        }

        if (refreshRejected) {
          // The refresh credential was definitively rejected — but it
          // may have been rotated while the refresh was in flight, so
          // only clear when this snapshot still owns the session.
          final stillOwner = api._authGeneration == snapshot.generation &&
              prefs.getString('refresh_token') == snapshot.refreshToken;
          if (stillOwner) {
            unawaited(ref.read(authProvider.notifier).clearLocalSession());
          }
          return handler.next(err);
        }

        final newToken = tokens?['token'];
        if (tokens != null &&
            newToken is String &&
            newToken.isNotEmpty &&
            api._authGeneration == snapshot.generation &&
            prefs.getString('refresh_token') ==
                (tokens['refreshToken'] is String
                    ? tokens['refreshToken']
                    : snapshot.refreshToken)) {
          err.requestOptions.extra['authRetried'] = true;
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          // The retry runs OUTSIDE the refresh-rejection handling: a
          // resource-level 403 here is a permission answer, not proof
          // that the refresh credential was rejected.
          final dio = Dio(BaseOptions(
            baseUrl: snapshot.baseUrl,
            connectTimeout: ApiConfig.connectionTimeout,
            receiveTimeout: ApiConfig.receiveTimeout,
          ));
          try {
            final cloneReq = await dio.fetch(err.requestOptions);
            return handler.resolve(cloneReq);
          } on DioException catch (retryError) {
            return handler.next(retryError);
          } finally {
            dio.close();
          }
        }
      }
    }

    handler.next(err);
  }
}

// Provider for API service
final apiServiceProvider = Provider<ApiService>((ref) => ApiService(ref));
