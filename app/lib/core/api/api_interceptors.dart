import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:rss_glassmorphism_reader/core/api/api_config.dart';

// Auth Interceptor
class AuthInterceptor extends Interceptor {
  final _storage = const FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Add auth token to headers
    final token = await _storage.read(key: _tokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    
    // Add API key
    options.headers['X-API-Key'] = ApiConfig.apiKey;
    
    handler.next(options);
  }
  
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      // Token expired, try to refresh
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      if (refreshToken != null) {
        try {
          // Refresh token logic
          final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
          final response = await dio.post('/auth/refresh', data: {
            'refresh_token': refreshToken,
          });
          
          // Save new tokens
          await _storage.write(
            key: _tokenKey,
            value: response.data['access_token'],
          );
          await _storage.write(
            key: _refreshTokenKey,
            value: response.data['refresh_token'],
          );
          
          // Retry original request
          final options = err.requestOptions;
          options.headers['Authorization'] = 'Bearer ${response.data['access_token']}';
          
          final clonedRequest = await dio.fetch(options);
          return handler.resolve(clonedRequest);
        } catch (e) {
          // Refresh failed, clear tokens
          await _storage.delete(key: _tokenKey);
          await _storage.delete(key: _refreshTokenKey);
        }
      }
    }
    
    handler.next(err);
  }
  
  static Future<void> saveTokens(String accessToken, String refreshToken) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: _tokenKey, value: accessToken);
    await storage.write(key: _refreshTokenKey, value: refreshToken);
  }
  
  static Future<void> clearTokens() async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: _tokenKey);
    await storage.delete(key: _refreshTokenKey);
  }
}

// Logging Interceptor
class LoggingInterceptor extends Interceptor {
  final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 100,
      colors: true,
      printEmojis: true,
    ),
  );
  
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (ApiConfig.enableLogging) {
      _logger.i('🔵 REQUEST[${options.method}] => PATH: ${options.path}');
      _logger.i('Headers: ${options.headers}');
      if (options.data != null) {
        _logger.i('Data: ${_formatJson(options.data)}');
      }
    }
    handler.next(options);
  }
  
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (ApiConfig.enableLogging) {
      _logger.i('🟢 RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}');
      _logger.i('Data: ${_formatJson(response.data)}');
    }
    handler.next(response);
  }
  
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (ApiConfig.enableLogging) {
      _logger.e('🔴 ERROR[${err.response?.statusCode}] => PATH: ${err.requestOptions.path}');
      _logger.e('Error: ${err.message}');
      if (err.response?.data != null) {
        _logger.e('Response: ${_formatJson(err.response!.data)}');
      }
    }
    handler.next(err);
  }
  
  String _formatJson(dynamic data) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (e) {
      return data.toString();
    }
  }
}

// Retry Interceptor
class RetryInterceptor extends Interceptor {
  final Dio dio;
  int _retryCount = 0;
  
  RetryInterceptor(this.dio);
  
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!ApiConfig.enableRetry) {
      return handler.next(err);
    }
    
    // Check if we should retry
    if (_shouldRetry(err) && _retryCount < ApiConfig.maxRetries) {
      _retryCount++;
      
      // Wait before retrying
      await Future.delayed(
        ApiConfig.retryDelay * _retryCount,
      );
      
      try {
        // Retry the request
        final response = await dio.fetch(err.requestOptions);
        _retryCount = 0; // Reset retry count on success
        return handler.resolve(response);
      } catch (e) {
        // Retry failed
        if (_retryCount >= ApiConfig.maxRetries) {
          _retryCount = 0; // Reset for next request
          return handler.next(err);
        }
        // Continue retrying
        return onError(e as DioException, handler);
      }
    }
    
    _retryCount = 0; // Reset for next request
    handler.next(err);
  }
  
  bool _shouldRetry(DioException err) {
    // Retry on network errors
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    
    // Retry on specific status codes
    final statusCode = err.response?.statusCode;
    if (statusCode != null) {
      return statusCode == 408 || // Request Timeout
             statusCode == 429 || // Too Many Requests
             statusCode == 500 || // Internal Server Error
             statusCode == 502 || // Bad Gateway
             statusCode == 503 || // Service Unavailable
             statusCode == 504;   // Gateway Timeout
    }
    
    return false;
  }
}

// Cache Interceptor
class CacheInterceptor extends Interceptor {
  final Map<String, CachedResponse> _cache = {};
  
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!ApiConfig.enableCache || options.method != 'GET') {
      return handler.next(options);
    }
    
    final key = _getCacheKey(options);
    final cached = _cache[key];
    
    if (cached != null && !cached.isExpired) {
      // Return cached response
      return handler.resolve(
        Response(
          requestOptions: options,
          data: cached.data,
          statusCode: 200,
          extra: {'cached': true},
        ),
      );
    }
    
    handler.next(options);
  }
  
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!ApiConfig.enableCache || response.requestOptions.method != 'GET') {
      return handler.next(response);
    }
    
    // Don't cache if it's already cached
    if (response.extra['cached'] == true) {
      return handler.next(response);
    }
    
    // Cache successful responses
    if (response.statusCode == 200) {
      final key = _getCacheKey(response.requestOptions);
      _cache[key] = CachedResponse(
        data: response.data,
        timestamp: DateTime.now(),
      );
      
      // Clean old cache entries
      _cleanCache();
    }
    
    handler.next(response);
  }
  
  String _getCacheKey(RequestOptions options) {
    final queryParams = options.queryParameters.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return '${options.path}?$queryParams';
  }
  
  void _cleanCache() {
    _cache.removeWhere((key, value) => value.isExpired);
    
    // Remove oldest entries if cache is too large
    if (_cache.length > 100) {
      final entries = _cache.entries.toList()
        ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
      
      for (int i = 0; i < 20; i++) {
        _cache.remove(entries[i].key);
      }
    }
  }
  
  void clearCache() {
    _cache.clear();
  }
}

class CachedResponse {
  final dynamic data;
  final DateTime timestamp;
  
  CachedResponse({
    required this.data,
    required this.timestamp,
  });
  
  bool get isExpired => 
      DateTime.now().difference(timestamp) > ApiConfig.cacheMaxAge;
}