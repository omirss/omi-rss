import 'dart:async';
import 'package:dio/dio.dart';
import 'package:synchronized/synchronized.dart';

/// Parser for robots.txt files
class RobotsParser {
  final Dio _dio;
  final Map<String, RobotsRules> _cache = {};
  final Lock _lock = Lock();
  final Duration _cacheExpiry;
  final String _userAgent;
  
  RobotsParser({
    Dio? dio,
    Duration cacheExpiry = const Duration(hours: 24),
    String userAgent = 'RSSGenerator',
  }) : _dio = dio ?? Dio(),
        _cacheExpiry = cacheExpiry,
        _userAgent = userAgent {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
  }
  
  /// Check if URL is allowed according to robots.txt
  Future<bool> isAllowed(String url) async {
    final uri = Uri.parse(url);
    final robotsUrl = '${uri.scheme}://${uri.host}/robots.txt';
    
    try {
      final rules = await _getRobotsRules(robotsUrl);
      return rules.isAllowed(uri.path, _userAgent);
    } catch (e) {
      // If we can't fetch robots.txt, assume allowed
      print('Failed to fetch robots.txt from ${uri.host}: $e');
      return true;
    }
  }
  
  /// Get crawl delay for domain
  Future<Duration?> getCrawlDelay(String url) async {
    final uri = Uri.parse(url);
    final robotsUrl = '${uri.scheme}://${uri.host}/robots.txt';
    
    try {
      final rules = await _getRobotsRules(robotsUrl);
      return rules.getCrawlDelay(_userAgent);
    } catch (e) {
      return null;
    }
  }
  
  /// Get sitemap URLs from robots.txt
  Future<List<String>> getSitemaps(String url) async {
    final uri = Uri.parse(url);
    final robotsUrl = '${uri.scheme}://${uri.host}/robots.txt';
    
    try {
      final rules = await _getRobotsRules(robotsUrl);
      return rules.sitemaps;
    } catch (e) {
      return [];
    }
  }
  
  Future<RobotsRules> _getRobotsRules(String robotsUrl) async {
    return await _lock.synchronized(() async {
      // Check cache
      final cached = _cache[robotsUrl];
      if (cached != null && !cached.isExpired(_cacheExpiry)) {
        return cached;
      }
      
      // Fetch and parse robots.txt
      final response = await _dio.get(robotsUrl);
      final rules = _parseRobotsTxt(response.data.toString());
      
      // Cache the result
      _cache[robotsUrl] = rules;
      
      return rules;
    });
  }
  
  RobotsRules _parseRobotsTxt(String content) {
    final rules = RobotsRules();
    final lines = content.split('\n');
    
    String? currentUserAgent;
    final userAgentRules = <String, List<RobotsRule>>{};
    final crawlDelays = <String, int>{};
    
    for (final line in lines) {
      final trimmed = line.trim();
      
      // Skip comments and empty lines
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      
      // Remove inline comments
      final parts = trimmed.split('#');
      final directive = parts[0].trim();
      
      if (directive.isEmpty) continue;
      
      // Parse directive
      final colonIndex = directive.indexOf(':');
      if (colonIndex == -1) continue;
      
      final key = directive.substring(0, colonIndex).trim().toLowerCase();
      final value = directive.substring(colonIndex + 1).trim();
      
      switch (key) {
        case 'user-agent':
          currentUserAgent = value.toLowerCase();
          userAgentRules.putIfAbsent(currentUserAgent, () => []);
          break;
          
        case 'disallow':
          if (currentUserAgent != null && value.isNotEmpty) {
            userAgentRules[currentUserAgent]!.add(
              RobotsRule(pattern: value, allowed: false),
            );
          }
          break;
          
        case 'allow':
          if (currentUserAgent != null && value.isNotEmpty) {
            userAgentRules[currentUserAgent]!.add(
              RobotsRule(pattern: value, allowed: true),
            );
          }
          break;
          
        case 'crawl-delay':
          if (currentUserAgent != null) {
            final delay = int.tryParse(value);
            if (delay != null) {
              crawlDelays[currentUserAgent] = delay;
            }
          }
          break;
          
        case 'sitemap':
          rules.sitemaps.add(value);
          break;
      }
    }
    
    rules.userAgentRules = userAgentRules;
    rules.crawlDelays = crawlDelays;
    rules.fetchTime = DateTime.now();
    
    return rules;
  }
}

/// Robots.txt rules for a domain
class RobotsRules {
  Map<String, List<RobotsRule>> userAgentRules = {};
  Map<String, int> crawlDelays = {};
  List<String> sitemaps = [];
  DateTime fetchTime = DateTime.now();
  
  bool isExpired(Duration expiry) {
    return DateTime.now().difference(fetchTime) > expiry;
  }
  
  bool isAllowed(String path, String userAgent) {
    final ua = userAgent.toLowerCase();
    
    // Find matching rules
    List<RobotsRule>? rules;
    
    // Check for exact user agent match
    rules = userAgentRules[ua];
    
    // Check for wildcard match
    if (rules == null) {
      rules = userAgentRules['*'];
    }
    
    // Check for partial match
    if (rules == null) {
      for (final entry in userAgentRules.entries) {
        if (ua.contains(entry.key) || entry.key.contains(ua)) {
          rules = entry.value;
          break;
        }
      }
    }
    
    // If no rules found, allow by default
    if (rules == null || rules.isEmpty) {
      return true;
    }
    
    // Check rules in order (more specific rules should come first)
    // Sort by specificity (longer patterns first)
    final sortedRules = List<RobotsRule>.from(rules)
      ..sort((a, b) => b.pattern.length.compareTo(a.pattern.length));
    
    for (final rule in sortedRules) {
      if (rule.matches(path)) {
        return rule.allowed;
      }
    }
    
    // Default to allow
    return true;
  }
  
  Duration? getCrawlDelay(String userAgent) {
    final ua = userAgent.toLowerCase();
    
    // Check exact match
    final delay = crawlDelays[ua] ?? crawlDelays['*'];
    
    if (delay != null) {
      return Duration(seconds: delay);
    }
    
    // Check partial match
    for (final entry in crawlDelays.entries) {
      if (ua.contains(entry.key) || entry.key.contains(ua)) {
        return Duration(seconds: entry.value);
      }
    }
    
    return null;
  }
}

/// Individual robots.txt rule
class RobotsRule {
  final String pattern;
  final bool allowed;
  
  RobotsRule({required this.pattern, required this.allowed});
  
  bool matches(String path) {
    // Convert pattern to regex
    String regexPattern = pattern;
    
    // Escape special regex characters except * and $
    regexPattern = regexPattern.replaceAllMapped(
      RegExp(r'[.+?^{}()|[\]\\]'),
      (match) => '\\${match.group(0)}',
    );
    
    // Convert * to .*
    regexPattern = regexPattern.replaceAll('*', '.*');
    
    // If pattern doesn't end with *, match prefix only
    if (!pattern.endsWith('*') && !pattern.endsWith('\$')) {
      regexPattern = '$regexPattern.*';
    }
    
    // Anchor to start
    regexPattern = '^$regexPattern';
    
    try {
      final regex = RegExp(regexPattern);
      return regex.hasMatch(path);
    } catch (e) {
      // If regex is invalid, do simple string matching
      return path.startsWith(pattern);
    }
  }
}

/// Global robots parser instance
class GlobalRobotsParser {
  static final GlobalRobotsParser _instance = GlobalRobotsParser._internal();
  factory GlobalRobotsParser() => _instance;
  GlobalRobotsParser._internal();
  
  final RobotsParser parser = RobotsParser(
    userAgent: 'RSSGenerator/1.0 (+https://github.com/yourusername/rss-reader)',
  );
}

/// Robots.txt respectful interceptor for Dio
class RobotsInterceptor extends Interceptor {
  final RobotsParser robotsParser;
  
  RobotsInterceptor({RobotsParser? parser})
      : robotsParser = parser ?? GlobalRobotsParser().parser;
  
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Check if URL is allowed
    final isAllowed = await robotsParser.isAllowed(options.uri.toString());
    
    if (!isAllowed) {
      handler.reject(
        DioError(
          requestOptions: options,
          error: 'URL disallowed by robots.txt',
          type: DioErrorType.cancel,
        ),
      );
      return;
    }
    
    // Check for crawl delay
    final crawlDelay = await robotsParser.getCrawlDelay(options.uri.toString());
    if (crawlDelay != null && crawlDelay.inMilliseconds > 0) {
      await Future.delayed(crawlDelay);
    }
    
    handler.next(options);
  }
}