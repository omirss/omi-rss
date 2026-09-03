import 'dart:async';
import 'dart:io';
import 'package:serverpod/serverpod.dart';
import '../config/server_config.dart';

class RateLimitMiddleware extends Middleware {
  final RateLimitConfig config;
  final Map<String, RateLimitBucket> _buckets = {};
  Timer? _cleanupTimer;

  RateLimitMiddleware(this.config) {
    // Start cleanup timer to remove old buckets
    _cleanupTimer = Timer.periodic(Duration(minutes: 5), (_) => _cleanup());
  }

  @override
  Future<bool> handle(Session session, HttpRequest request) async {
    // Generate key based on configuration
    final key = _generateKey(request);
    
    // Get or create bucket
    final bucket = _buckets.putIfAbsent(key, () => RateLimitBucket(
      maxRequests: config.maxRequests,
      windowMs: config.windowMs,
    ));
    
    // Check if request is allowed
    if (!bucket.allowRequest()) {
      await _sendRateLimitExceeded(request, bucket);
      return false;
    }
    
    // Add rate limit headers
    request.response.headers
      ..add('X-RateLimit-Limit', config.maxRequests.toString())
      ..add('X-RateLimit-Remaining', bucket.remainingRequests.toString())
      ..add('X-RateLimit-Reset', bucket.resetTime.millisecondsSinceEpoch.toString());
    
    // Continue if successful requests should skip counting
    if (config.skipSuccessfulRequests) {
      // Store bucket reference to potentially restore the request later
      request.headers.add('X-RateLimit-Bucket-Key', key);
    }
    
    return true;
  }
  
  String _generateKey(HttpRequest request) {
    switch (config.keyGenerator) {
      case 'ip':
        return request.connectionInfo?.remoteAddress.address ?? 'unknown';
      case 'user':
        return request.headers.value('X-User-Id') ?? 
               request.connectionInfo?.remoteAddress.address ?? 'unknown';
      case 'ip+path':
        final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';
        return '$ip:${request.uri.path}';
      default:
        return request.connectionInfo?.remoteAddress.address ?? 'unknown';
    }
  }
  
  Future<void> _sendRateLimitExceeded(HttpRequest request, RateLimitBucket bucket) async {
    request.response
      ..statusCode = 429
      ..headers.contentType = ContentType.json
      ..headers.add('Retry-After', ((bucket.resetTime.millisecondsSinceEpoch - 
                    DateTime.now().millisecondsSinceEpoch) / 1000).ceil().toString())
      ..write('''
        {
          "error": "Too many requests",
          "message": "Rate limit exceeded. Please retry after ${bucket.resetTime.toIso8601String()}",
          "retryAfter": ${bucket.resetTime.millisecondsSinceEpoch}
        }
      ''');
    await request.response.close();
  }
  
  void _cleanup() {
    final now = DateTime.now();
    _buckets.removeWhere((key, bucket) => 
      now.difference(bucket.lastRequest).inMilliseconds > config.windowMs * 2);
  }
  
  void restoreRequest(String key) {
    // Called when skipSuccessfulRequests is true and request was successful
    final bucket = _buckets[key];
    if (bucket != null && config.skipSuccessfulRequests) {
      bucket.restoreRequest();
    }
  }
  
  void dispose() {
    _cleanupTimer?.cancel();
  }
}

class RateLimitBucket {
  final int maxRequests;
  final int windowMs;
  final List<DateTime> _requests = [];
  DateTime lastRequest = DateTime.now();
  
  RateLimitBucket({
    required this.maxRequests,
    required this.windowMs,
  });
  
  bool allowRequest() {
    final now = DateTime.now();
    lastRequest = now;
    
    // Remove old requests outside the window
    _requests.removeWhere((time) => 
      now.difference(time).inMilliseconds > windowMs);
    
    // Check if limit exceeded
    if (_requests.length >= maxRequests) {
      return false;
    }
    
    // Add current request
    _requests.add(now);
    return true;
  }
  
  void restoreRequest() {
    // Remove the last request if it was counted
    if (_requests.isNotEmpty) {
      _requests.removeLast();
    }
  }
  
  int get remainingRequests => maxRequests - _requests.length;
  
  DateTime get resetTime {
    if (_requests.isEmpty) {
      return DateTime.now();
    }
    return _requests.first.add(Duration(milliseconds: windowMs));
  }
}

// Rate limit configurations for different endpoint types
class EndpointRateLimits {
  static final Map<String, RateLimitConfig> configs = {
    // Strict limits for auth endpoints
    '/auth/login': RateLimitConfig(
      windowMs: 300000, // 5 minutes
      maxRequests: 5,
      skipSuccessfulRequests: false,
      keyGenerator: 'ip',
    ),
    '/auth/register': RateLimitConfig(
      windowMs: 3600000, // 1 hour
      maxRequests: 3,
      skipSuccessfulRequests: false,
      keyGenerator: 'ip',
    ),
    '/auth/forgot-password': RateLimitConfig(
      windowMs: 3600000, // 1 hour
      maxRequests: 3,
      skipSuccessfulRequests: false,
      keyGenerator: 'ip',
    ),
    
    // Moderate limits for API endpoints
    '/api/feeds': RateLimitConfig(
      windowMs: 60000, // 1 minute
      maxRequests: 60,
      skipSuccessfulRequests: true,
      keyGenerator: 'user',
    ),
    '/api/articles': RateLimitConfig(
      windowMs: 60000, // 1 minute
      maxRequests: 100,
      skipSuccessfulRequests: true,
      keyGenerator: 'user',
    ),
    
    // Strict limits for AI endpoints
    '/api/ai': RateLimitConfig(
      windowMs: 60000, // 1 minute
      maxRequests: 10,
      skipSuccessfulRequests: false,
      keyGenerator: 'user',
    ),
    
    // Very strict limits for expensive operations
    '/api/feeds/import': RateLimitConfig(
      windowMs: 3600000, // 1 hour
      maxRequests: 5,
      skipSuccessfulRequests: false,
      keyGenerator: 'user',
    ),
  };
  
  static RateLimitConfig? getConfig(String path) {
    // Find the most specific matching config
    for (final entry in configs.entries) {
      if (path.startsWith(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
}

// Advanced rate limiter with multiple strategies
class AdvancedRateLimitMiddleware extends Middleware {
  final RateLimitConfig defaultConfig;
  final Map<String, RateLimitMiddleware> _limiters = {};
  
  AdvancedRateLimitMiddleware(this.defaultConfig);
  
  @override
  Future<bool> handle(Session session, HttpRequest request) async {
    // Get endpoint-specific config or use default
    final config = EndpointRateLimits.getConfig(request.uri.path) ?? defaultConfig;
    
    // Get or create limiter for this config
    final key = '${config.windowMs}:${config.maxRequests}:${config.keyGenerator}';
    final limiter = _limiters.putIfAbsent(key, () => RateLimitMiddleware(config));
    
    return limiter.handle(session, request);
  }
  
  void dispose() {
    for (final limiter in _limiters.values) {
      limiter.dispose();
    }
  }
}