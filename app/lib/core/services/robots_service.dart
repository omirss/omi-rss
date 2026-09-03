import 'dart:async';
import 'package:dio/dio.dart';

/// Service for respecting robots.txt
class RobotsService {
  final Dio _dio;
  final Map<String, RobotsRules> _rulesCache = {};
  final Duration _cacheExpiry = const Duration(hours: 24);
  
  RobotsService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 5);
  }
  
  /// Check if URL is allowed by robots.txt
  Future<bool> isAllowed(String url, {String userAgent = '*'}) async {
    try {
      final uri = Uri.parse(url);
      final robotsUrl = '${uri.scheme}://${uri.host}/robots.txt';
      
      // Get rules from cache or fetch
      final rules = await _getRules(robotsUrl);
      if (rules == null) {
        // No robots.txt means everything is allowed
        return true;
      }
      
      // Check if path is allowed
      return rules.isAllowed(uri.path, userAgent);
    } catch (e) {
      // On error, assume allowed
      return true;
    }
  }
  
  /// Get crawl delay for user agent
  Future<Duration?> getCrawlDelay(String url, {String userAgent = '*'}) async {
    try {
      final uri = Uri.parse(url);
      final robotsUrl = '${uri.scheme}://${uri.host}/robots.txt';
      
      final rules = await _getRules(robotsUrl);
      return rules?.getCrawlDelay(userAgent);
    } catch (e) {
      return null;
    }
  }
  
  /// Get robots.txt rules
  Future<RobotsRules?> _getRules(String robotsUrl) async {
    // Check cache
    if (_rulesCache.containsKey(robotsUrl)) {
      final cached = _rulesCache[robotsUrl]!;
      if (DateTime.now().difference(cached.fetchedAt) < _cacheExpiry) {
        return cached;
      }
    }
    
    try {
      // Fetch robots.txt
      final response = await _dio.get(robotsUrl);
      if (response.statusCode == 200) {
        final rules = RobotsRules.parse(response.data.toString());
        _rulesCache[robotsUrl] = rules;
        return rules;
      }
    } catch (e) {
      // robots.txt not found or error
    }
    
    return null;
  }
  
  /// Clear cache
  void clearCache() {
    _rulesCache.clear();
  }
}

/// Robots.txt rules
class RobotsRules {
  final Map<String, UserAgentRules> agentRules;
  final DateTime fetchedAt;
  
  RobotsRules({
    required this.agentRules,
    required this.fetchedAt,
  });
  
  /// Parse robots.txt content
  factory RobotsRules.parse(String content) {
    final agentRules = <String, UserAgentRules>{};
    String? currentAgent;
    final disallowed = <String>[];
    final allowed = <String>[];
    Duration? crawlDelay;
    
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      
      // Skip comments and empty lines
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      
      // Parse directive
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex == -1) continue;
      
      final directive = trimmed.substring(0, colonIndex).trim().toLowerCase();
      final value = trimmed.substring(colonIndex + 1).trim();
      
      switch (directive) {
        case 'user-agent':
          // Save previous agent rules
          if (currentAgent != null) {
            agentRules[currentAgent] = UserAgentRules(
              userAgent: currentAgent,
              disallowed: List.from(disallowed),
              allowed: List.from(allowed),
              crawlDelay: crawlDelay,
            );
            disallowed.clear();
            allowed.clear();
            crawlDelay = null;
          }
          currentAgent = value.toLowerCase();
          break;
          
        case 'disallow':
          if (value.isNotEmpty) {
            disallowed.add(value);
          }
          break;
          
        case 'allow':
          if (value.isNotEmpty) {
            allowed.add(value);
          }
          break;
          
        case 'crawl-delay':
          final delay = int.tryParse(value);
          if (delay != null) {
            crawlDelay = Duration(seconds: delay);
          }
          break;
      }
    }
    
    // Save last agent rules
    if (currentAgent != null) {
      agentRules[currentAgent] = UserAgentRules(
        userAgent: currentAgent,
        disallowed: disallowed,
        allowed: allowed,
        crawlDelay: crawlDelay,
      );
    }
    
    return RobotsRules(
      agentRules: agentRules,
      fetchedAt: DateTime.now(),
    );
  }
  
  /// Check if path is allowed for user agent
  bool isAllowed(String path, String userAgent) {
    // Find matching rules
    final rules = _findRulesForAgent(userAgent);
    if (rules == null) {
      // No rules means allowed
      return true;
    }
    
    // Check allowed patterns first (they override disallow)
    for (final pattern in rules.allowed) {
      if (_matchesPattern(path, pattern)) {
        return true;
      }
    }
    
    // Check disallowed patterns
    for (final pattern in rules.disallowed) {
      if (_matchesPattern(path, pattern)) {
        return false;
      }
    }
    
    // Default to allowed
    return true;
  }
  
  /// Get crawl delay for user agent
  Duration? getCrawlDelay(String userAgent) {
    final rules = _findRulesForAgent(userAgent);
    return rules?.crawlDelay;
  }
  
  /// Find rules for user agent
  UserAgentRules? _findRulesForAgent(String userAgent) {
    final lowerAgent = userAgent.toLowerCase();
    
    // Exact match
    if (agentRules.containsKey(lowerAgent)) {
      return agentRules[lowerAgent];
    }
    
    // Wildcard match
    if (agentRules.containsKey('*')) {
      return agentRules['*'];
    }
    
    // Partial match (e.g., "googlebot" matches "googlebot-news")
    for (final entry in agentRules.entries) {
      if (lowerAgent.contains(entry.key) || entry.key.contains(lowerAgent)) {
        return entry.value;
      }
    }
    
    return null;
  }
  
  /// Check if path matches pattern
  bool _matchesPattern(String path, String pattern) {
    // Simple pattern matching (not full glob)
    if (pattern == '/') {
      return true; // Matches everything
    }
    
    if (pattern.endsWith('*')) {
      // Prefix match
      final prefix = pattern.substring(0, pattern.length - 1);
      return path.startsWith(prefix);
    }
    
    if (pattern.contains('*')) {
      // Convert to regex
      final regex = pattern
          .replaceAll('*', '.*')
          .replaceAll('?', '.');
      return RegExp('^$regex').hasMatch(path);
    }
    
    // Exact match or prefix
    return path == pattern || path.startsWith(pattern);
  }
}

/// Rules for a specific user agent
class UserAgentRules {
  final String userAgent;
  final List<String> disallowed;
  final List<String> allowed;
  final Duration? crawlDelay;
  
  UserAgentRules({
    required this.userAgent,
    required this.disallowed,
    required this.allowed,
    this.crawlDelay,
  });
}

/// Rate limiter for respecting crawl delays
class RateLimiter {
  final Map<String, DateTime> _lastRequestTime = {};
  final Duration _defaultDelay;
  
  RateLimiter({
    Duration defaultDelay = const Duration(seconds: 1),
  }) : _defaultDelay = defaultDelay;
  
  /// Wait if necessary before making request
  Future<void> waitIfNeeded(String host, {Duration? customDelay}) async {
    final lastRequest = _lastRequestTime[host];
    if (lastRequest == null) {
      _lastRequestTime[host] = DateTime.now();
      return;
    }
    
    final delay = customDelay ?? _defaultDelay;
    final elapsed = DateTime.now().difference(lastRequest);
    
    if (elapsed < delay) {
      await Future.delayed(delay - elapsed);
    }
    
    _lastRequestTime[host] = DateTime.now();
  }
  
  /// Clear rate limit history
  void clear() {
    _lastRequestTime.clear();
  }
}