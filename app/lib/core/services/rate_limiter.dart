import 'dart:async';
import 'dart:collection';
import 'package:synchronized/synchronized.dart';

/// Rate limiter for controlling request frequency
class RateLimiter {
  final Map<String, DomainRateLimit> _domainLimits = {};
  final Map<String, Queue<DateTime>> _requestQueues = {};
  final Lock _lock = Lock();
  
  /// Set rate limit for a domain
  void setDomainLimit(String domain, {
    required int requestsPerMinute,
    int? burstSize,
    Duration? minDelay,
  }) {
    _domainLimits[domain] = DomainRateLimit(
      requestsPerMinute: requestsPerMinute,
      burstSize: burstSize ?? requestsPerMinute,
      minDelay: minDelay ?? Duration(milliseconds: 60000 ~/ requestsPerMinute),
    );
  }
  
  /// Check if request can proceed immediately
  Future<bool> canProceed(String domain) async {
    return await _lock.synchronized(() {
      final limit = _getDomainLimit(domain);
      final queue = _getOrCreateQueue(domain);
      
      _cleanOldRequests(queue);
      
      return queue.length < limit.burstSize;
    });
  }
  
  /// Wait for rate limit if necessary, then proceed
  Future<void> waitForSlot(String domain) async {
    final limit = _getDomainLimit(domain);
    
    while (true) {
      final delay = await _lock.synchronized(() {
        final queue = _getOrCreateQueue(domain);
        _cleanOldRequests(queue);
        
        if (queue.length < limit.burstSize) {
          // Can proceed immediately
          queue.add(DateTime.now());
          return Duration.zero;
        }
        
        // Need to wait
        final oldestRequest = queue.first;
        final timeSinceOldest = DateTime.now().difference(oldestRequest);
        final windowDuration = const Duration(minutes: 1);
        
        if (timeSinceOldest >= windowDuration) {
          // Window has passed, can proceed
          queue.removeFirst();
          queue.add(DateTime.now());
          return Duration.zero;
        }
        
        // Calculate wait time
        final waitTime = windowDuration - timeSinceOldest;
        
        // Also consider minimum delay between requests
        if (queue.isNotEmpty) {
          final lastRequest = queue.last;
          final timeSinceLast = DateTime.now().difference(lastRequest);
          if (timeSinceLast < limit.minDelay) {
            final minWait = limit.minDelay - timeSinceLast;
            return minWait > waitTime ? minWait : waitTime;
          }
        }
        
        return waitTime;
      });
      
      if (delay == Duration.zero) {
        break;
      }
      
      // Wait for the calculated delay
      await Future.delayed(delay);
    }
  }
  
  /// Record a request
  Future<void> recordRequest(String domain) async {
    await _lock.synchronized(() {
      final queue = _getOrCreateQueue(domain);
      queue.add(DateTime.now());
    });
  }
  
  /// Get current request count for domain
  Future<int> getRequestCount(String domain) async {
    return await _lock.synchronized(() {
      final queue = _getOrCreateQueue(domain);
      _cleanOldRequests(queue);
      return queue.length;
    });
  }
  
  /// Reset rate limit for domain
  Future<void> reset(String domain) async {
    await _lock.synchronized(() {
      _requestQueues[domain]?.clear();
    });
  }
  
  /// Reset all rate limits
  Future<void> resetAll() async {
    await _lock.synchronized(() {
      _requestQueues.clear();
    });
  }
  
  DomainRateLimit _getDomainLimit(String domain) {
    // Check for exact domain match
    if (_domainLimits.containsKey(domain)) {
      return _domainLimits[domain]!;
    }
    
    // Check for wildcard matches
    for (final entry in _domainLimits.entries) {
      if (entry.key.contains('*')) {
        final pattern = entry.key.replaceAll('*', '.*');
        if (RegExp(pattern).hasMatch(domain)) {
          return entry.value;
        }
      }
    }
    
    // Return default limit
    return DomainRateLimit(
      requestsPerMinute: 60,
      burstSize: 60,
      minDelay: const Duration(seconds: 1),
    );
  }
  
  Queue<DateTime> _getOrCreateQueue(String domain) {
    return _requestQueues.putIfAbsent(domain, () => Queue<DateTime>());
  }
  
  void _cleanOldRequests(Queue<DateTime> queue) {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    while (queue.isNotEmpty && queue.first.isBefore(cutoff)) {
      queue.removeFirst();
    }
  }
}

/// Domain-specific rate limit configuration
class DomainRateLimit {
  final int requestsPerMinute;
  final int burstSize;
  final Duration minDelay;
  
  const DomainRateLimit({
    required this.requestsPerMinute,
    required this.burstSize,
    required this.minDelay,
  });
}

/// Global rate limiter instance
class GlobalRateLimiter {
  static final GlobalRateLimiter _instance = GlobalRateLimiter._internal();
  factory GlobalRateLimiter() => _instance;
  GlobalRateLimiter._internal();
  
  final RateLimiter _rateLimiter = RateLimiter();
  
  /// Initialize with default limits
  void initialize() {
    // Financial sites - stricter limits
    _rateLimiter.setDomainLimit('bloomberg.com', 
      requestsPerMinute: 30, 
      minDelay: const Duration(seconds: 2),
    );
    _rateLimiter.setDomainLimit('wsj.com', 
      requestsPerMinute: 20, 
      minDelay: const Duration(seconds: 3),
    );
    _rateLimiter.setDomainLimit('ft.com', 
      requestsPerMinute: 20, 
      minDelay: const Duration(seconds: 3),
    );
    
    // News sites - moderate limits
    _rateLimiter.setDomainLimit('*.bbc.com', 
      requestsPerMinute: 60,
      minDelay: const Duration(seconds: 1),
    );
    _rateLimiter.setDomainLimit('cnn.com', 
      requestsPerMinute: 60,
      minDelay: const Duration(seconds: 1),
    );
    _rateLimiter.setDomainLimit('theguardian.com', 
      requestsPerMinute: 60,
      minDelay: const Duration(seconds: 1),
    );
    
    // Tech sites - relaxed limits
    _rateLimiter.setDomainLimit('techcrunch.com', 
      requestsPerMinute: 120,
      minDelay: const Duration(milliseconds: 500),
    );
    _rateLimiter.setDomainLimit('theverge.com', 
      requestsPerMinute: 120,
      minDelay: const Duration(milliseconds: 500),
    );
    
    // Social media - very strict
    _rateLimiter.setDomainLimit('twitter.com', 
      requestsPerMinute: 15,
      minDelay: const Duration(seconds: 4),
    );
    _rateLimiter.setDomainLimit('reddit.com', 
      requestsPerMinute: 30,
      minDelay: const Duration(seconds: 2),
    );
    
    // Academic sites - moderate
    _rateLimiter.setDomainLimit('arxiv.org', 
      requestsPerMinute: 30,
      minDelay: const Duration(seconds: 2),
    );
    _rateLimiter.setDomainLimit('pubmed.ncbi.nlm.nih.gov', 
      requestsPerMinute: 20,
      minDelay: const Duration(seconds: 3),
    );
  }
  
  /// Get the rate limiter instance
  RateLimiter get limiter => _rateLimiter;
}

/// Rate limit interceptor for Dio
class RateLimitInterceptor extends Interceptor {
  final RateLimiter rateLimiter;
  
  RateLimitInterceptor({RateLimiter? rateLimiter})
      : rateLimiter = rateLimiter ?? GlobalRateLimiter().limiter;
  
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final domain = Uri.parse(options.uri.toString()).host;
    
    // Wait for rate limit slot
    await rateLimiter.waitForSlot(domain);
    
    handler.next(options);
  }
  
  @override
  void onError(
    DioError err,
    ErrorInterceptorHandler handler,
  ) {
    // Check for rate limit errors
    if (err.response?.statusCode == 429) {
      // Too Many Requests
      final retryAfter = err.response?.headers['retry-after']?.first;
      if (retryAfter != null) {
        final delay = int.tryParse(retryAfter) ?? 60;
        print('Rate limited by server. Retry after $delay seconds');
      }
    }
    
    handler.next(err);
  }
}