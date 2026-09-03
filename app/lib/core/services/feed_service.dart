import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';
import 'package:flutter/foundation.dart';
import '../models/feed.dart';
import '../models/article.dart';
import '../parsers/rss_parser.dart';
import '../parsers/atom_parser.dart';
import '../parsers/json_feed_parser.dart';
import '../database/database.dart';
import 'feed_discovery_service.dart';
import '../../services/feed_parser_service.dart';

/// Feed service for managing RSS/Atom/JSON feeds with FreshRSS features
class FeedService {
  final Dio _dio;
  final RssParser _rssParser;
  final AtomParser _atomParser;
  final JsonFeedParser _jsonFeedParser;
  final FeedParserService _feedParserService;
  final AppDatabase? _database;
  final FeedDiscoveryService? _discoveryService;
  
  // Cache for ETags and Last-Modified headers
  final Map<String, String> _etagCache = {};
  final Map<String, String> _lastModifiedCache = {};
  
  // Feed health monitoring
  final Map<String, FeedHealth> _feedHealth = {};
  
  // Progress callbacks for batch operations
  void Function(int current, int total)? onBatchProgress;
  void Function(String feedId, String message)? onFeedLog;
  
  FeedService({
    Dio? dio,
    AppDatabase? database,
    FeedDiscoveryService? discoveryService,
    FeedParserService? feedParserService,
  }) : _dio = dio ?? Dio(),
        _rssParser = RssParser(),
        _atomParser = AtomParser(),
        _jsonFeedParser = JsonFeedParser(),
        _feedParserService = feedParserService ?? FeedParserService(dio: dio),
        _database = database,
        _discoveryService = discoveryService {
    // Configure Dio
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers = {
      'User-Agent': 'RSS Glassmorphism Reader/1.0 (+https://github.com/yourusername/rss-reader)',
      'Accept': 'application/rss+xml, application/atom+xml, application/json, application/xml, text/xml, */*',
    };
  }
  
  /// Subscribe to a new feed
  Future<Feed> subscribeFeed(String url) async {
    try {
      // Use the new FeedParserService to parse the feed
      final parsedFeed = await _feedParserService.parseFeed(url);
      
      // Generate unique ID for the feed
      final feedId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Fetch favicon
      final faviconUrl = await _feedParserService.getFeedFavicon(parsedFeed.siteUrl) ??
                         await _fetchFavicon(parsedFeed.siteUrl);
      
      // Map FeedType from parser to model
      FeedType feedType;
      switch (parsedFeed.type) {
        case FeedParserService.FeedType.rss:
          feedType = FeedType.rss;
          break;
        case FeedParserService.FeedType.atom:
          feedType = FeedType.atom;
          break;
        case FeedParserService.FeedType.json:
          feedType = FeedType.json;
          break;
        default:
          feedType = FeedType.unknown;
      }
      
      // Convert ParsedFeed to Feed model
      final feed = Feed(
        id: feedId,
        url: parsedFeed.url,
        title: parsedFeed.title,
        description: parsedFeed.description,
        link: parsedFeed.siteUrl,
        siteUrl: parsedFeed.siteUrl,
        faviconUrl: faviconUrl,
        language: parsedFeed.language,
        lastFetched: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        etag: null,
        lastModified: null,
        updateFrequency: 3600, // 1 hour default
        successfulFetches: 1,
        failedFetches: 0,
        successRate: 1.0,
        type: feedType,
        imageUrl: parsedFeed.imageUrl,
      );
      
      return feed;
    } catch (e) {
      throw FeedServiceException('Failed to subscribe to feed: $e');
    }
  }
  
  /// Refresh a feed with smart caching
  Future<RefreshResult> refreshFeed(Feed feed) async {
    final startTime = DateTime.now();
    
    try {
      // Use the new FeedParserService to parse the feed
      final parsedFeed = await _feedParserService.parseFeed(feed.url);
      final responseTime = DateTime.now().difference(startTime);
      
      // Convert parsed articles to Article models
      final articles = parsedFeed.items.map((parsedArticle) => 
        _convertParsedArticleToArticle(parsedArticle, feed.id)
      ).toList();
      
      // Get existing articles to find new ones
      List<Article> newArticles = [];
      if (_database != null) {
        final existingArticles = await _database!.articleDao.getArticlesByFeed(feed.id);
        final existingGuids = existingArticles.map((a) => a.guid).toSet();
        newArticles = articles.where((a) => !existingGuids.contains(a.guid)).toList();
      } else {
        newArticles = articles;
      }
      
      _updateFeedHealth(feed.id, true, responseTime, null);
      
      // Update feed favicon if changed
      final newFaviconUrl = await _feedParserService.getFeedFavicon(parsedFeed.siteUrl);
      
      return RefreshResult(
        feed: feed.copyWith(
          title: parsedFeed.title,
          description: parsedFeed.description,
          lastFetched: DateTime.now(),
          faviconUrl: newFaviconUrl ?? feed.faviconUrl,
          imageUrl: parsedFeed.imageUrl ?? feed.imageUrl,
          successfulFetches: feed.successfulFetches + 1,
          successRate: (feed.successfulFetches + 1) / (feed.successfulFetches + feed.failedFetches + 1),
        ),
        newArticles: newArticles,
        wasModified: true,
      );
    } catch (e) {
      final responseTime = DateTime.now().difference(startTime);
      _updateFeedHealth(feed.id, false, responseTime, e.toString());
      
      // Update error statistics
      return RefreshResult(
        feed: feed.copyWith(
          lastFetched: DateTime.now(),
          failedFetches: feed.failedFetches + 1,
          successRate: feed.successfulFetches / (feed.successfulFetches + feed.failedFetches + 1),
          lastError: e.toString(),
          lastErrorAt: DateTime.now(),
        ),
        newArticles: [],
        wasModified: false,
        error: e.toString(),
      );
    }
  }
  
  /// Convert ParsedArticle to Article model
  Article _convertParsedArticleToArticle(ParsedArticle parsedArticle, String feedId) {
    return Article(
      feedId: feedId,
      guid: parsedArticle.guid,
      title: parsedArticle.title,
      content: parsedArticle.content,
      summary: parsedArticle.description,
      author: parsedArticle.author,
      publishedAt: parsedArticle.publishedAt,
      url: parsedArticle.link,
      imageUrl: parsedArticle.thumbnail,
      categories: parsedArticle.categories,
    );
  }
  
  /// Discover feeds from a URL
  Future<List<DiscoveredFeed>> discoverFeeds(String url) async {
    try {
      url = _normalizeUrl(url);
      final discoveries = <DiscoveredFeed>[];
      
      // First, try the URL as a direct feed
      try {
        final response = await _fetchFeed(url);
        final feedType = _detectFeedType(response.data);
        if (feedType != FeedType.unknown) {
          final feed = await _parseFeed(response.data, url, feedType);
          discoveries.add(DiscoveredFeed(
            url: url,
            title: feed.title,
            type: feedType,
            isDirect: true,
          ));
          return discoveries;
        }
      } catch (e) {
        // Not a direct feed, continue to discovery
      }
      
      // Fetch the HTML page
      final response = await _dio.get(url);
      final document = html_parser.parse(response.data);
      
      // Look for feed links in HTML
      final feedLinks = document.querySelectorAll('link[rel="alternate"]');
      for (final link in feedLinks) {
        final type = link.attributes['type'];
        final href = link.attributes['href'];
        final title = link.attributes['title'];
        
        if (href != null && _isFeedType(type)) {
          final feedUrl = _resolveUrl(href, url);
          discoveries.add(DiscoveredFeed(
            url: feedUrl,
            title: title ?? 'Feed',
            type: _getFeedTypeFromMime(type),
            isDirect: false,
          ));
        }
      }
      
      // Try common feed paths
      final commonPaths = [
        '/feed',
        '/feed.xml',
        '/rss',
        '/rss.xml',
        '/atom',
        '/atom.xml',
        '/feed.json',
        '/index.xml',
        '/blog/feed',
        '/news/feed',
      ];
      
      for (final path in commonPaths) {
        final feedUrl = _resolveUrl(path, url);
        try {
          final response = await _fetchFeed(feedUrl);
          final feedType = _detectFeedType(response.data);
          if (feedType != FeedType.unknown) {
            final feed = await _parseFeed(response.data, feedUrl, feedType);
            discoveries.add(DiscoveredFeed(
              url: feedUrl,
              title: feed.title,
              type: feedType,
              isDirect: false,
            ));
          }
        } catch (e) {
          // Skip if not found
        }
      }
      
      return discoveries;
    } catch (e) {
      throw FeedServiceException('Failed to discover feeds: $e');
    }
  }
  
  /// Fetch feed content
  Future<Response> _fetchFeed(String url, {Map<String, String>? headers}) async {
    final options = Options(
      headers: headers,
      validateStatus: (status) => status != null && status < 500,
    );
    
    return await _dio.get(url, options: options);
  }
  
  /// Detect feed type from content
  FeedType _detectFeedType(String content) {
    // Try JSON first (fastest check)
    try {
      final json = jsonDecode(content);
      if (json is Map && json['version'] != null && 
          json['version'].toString().startsWith('https://jsonfeed.org/version/')) {
        return FeedType.json;
      }
    } catch (e) {
      // Not JSON
    }
    
    // Try XML
    try {
      final document = XmlDocument.parse(content);
      
      // Check for RSS
      if (document.findElements('rss').isNotEmpty ||
          document.findElements('channel').isNotEmpty) {
        return FeedType.rss;
      }
      
      // Check for Atom
      if (document.findElements('feed').isNotEmpty) {
        // Check if it has Atom namespace
        final feed = document.findElements('feed').first;
        final xmlns = feed.getAttribute('xmlns');
        if (xmlns == 'http://www.w3.org/2005/Atom' || 
            xmlns == 'http://purl.org/atom/ns#') {
          return FeedType.atom;
        }
        // Even without namespace, if it has entry elements, it's likely Atom
        if (feed.findElements('entry').isNotEmpty) {
          return FeedType.atom;
        }
      }
    } catch (e) {
      // Not valid XML
    }
    
    return FeedType.unknown;
  }
  
  /// Parse feed based on type
  Future<Feed> _parseFeed(String content, String url, FeedType type) async {
    switch (type) {
      case FeedType.rss:
        return await _rssParser.parseFeed(content, url);
      case FeedType.atom:
        return await _atomParser.parseFeed(content, url);
      case FeedType.json:
        return await _jsonFeedParser.parseFeed(content, url);
      case FeedType.unknown:
        throw FeedServiceException('Unknown feed type');
    }
  }
  
  /// Parse articles based on feed type
  Future<List<Article>> _parseArticles(String content, String feedId, FeedType type) async {
    switch (type) {
      case FeedType.rss:
        return await _rssParser.parseArticles(content, feedId);
      case FeedType.atom:
        return await _atomParser.parseArticles(content, feedId);
      case FeedType.json:
        return await _jsonFeedParser.parseArticles(content, feedId);
      case FeedType.unknown:
        return [];
    }
  }
  
  /// Fetch favicon for a website
  Future<String?> _fetchFavicon(String url) async {
    try {
      final uri = Uri.parse(url);
      final baseUrl = '${uri.scheme}://${uri.host}';
      
      // Try common favicon locations
      final faviconUrls = [
        '$baseUrl/favicon.ico',
        '$baseUrl/favicon.png',
        '$baseUrl/apple-touch-icon.png',
      ];
      
      for (final faviconUrl in faviconUrls) {
        try {
          final response = await _dio.head(faviconUrl);
          if (response.statusCode == 200) {
            return faviconUrl;
          }
        } catch (e) {
          // Continue to next URL
        }
      }
      
      // Try to extract from HTML
      try {
        final response = await _dio.get(baseUrl);
        final document = html_parser.parse(response.data);
        
        // Look for favicon links
        final iconLinks = document.querySelectorAll('link[rel*="icon"]');
        for (final link in iconLinks) {
          final href = link.attributes['href'];
          if (href != null) {
            return _resolveUrl(href, baseUrl);
          }
        }
      } catch (e) {
        // Failed to fetch HTML
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// Normalize URL
  String _normalizeUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
  }
  
  /// Resolve relative URL
  String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    final baseUri = Uri.parse(baseUrl);
    final resolved = baseUri.resolve(url);
    return resolved.toString();
  }
  
  /// Check if MIME type is a feed type
  bool _isFeedType(String? mimeType) {
    if (mimeType == null) return false;
    
    final feedTypes = [
      'application/rss+xml',
      'application/atom+xml',
      'application/json',
      'application/feed+json',
      'text/xml',
      'application/xml',
    ];
    
    return feedTypes.contains(mimeType.toLowerCase());
  }
  
  /// Get feed type from MIME type
  FeedType _getFeedTypeFromMime(String? mimeType) {
    if (mimeType == null) return FeedType.unknown;
    
    if (mimeType.contains('rss')) return FeedType.rss;
    if (mimeType.contains('atom')) return FeedType.atom;
    if (mimeType.contains('json')) return FeedType.json;
    
    return FeedType.unknown;
  }
  
  /// Batch refresh multiple feeds
  Future<BatchRefreshResult> batchRefresh(List<Feed> feeds, {
    int concurrency = 3,
    bool continueOnError = true,
  }) async {
    final results = <String, RefreshResult>{};
    final errors = <String, String>{};
    int completed = 0;
    
    // Create a queue of feeds to process
    final queue = List<Feed>.from(feeds);
    final active = <Future<void>>[];
    
    while (queue.isNotEmpty || active.isNotEmpty) {
      // Start new tasks up to concurrency limit
      while (active.length < concurrency && queue.isNotEmpty) {
        final feed = queue.removeAt(0);
        final task = _processFeedInBatch(feed, results, errors).then((_) {
          completed++;
          onBatchProgress?.call(completed, feeds.length);
        });
        active.add(task);
      }
      
      // Wait for at least one task to complete
      if (active.isNotEmpty) {
        await Future.any(active);
        active.removeWhere((task) => task.isCompleted);
      }
    }
    
    return BatchRefreshResult(
      results: results,
      errors: errors,
      totalFeeds: feeds.length,
      successfulFeeds: results.values.where((r) => r.wasModified || !r.wasModified && r.error == null).length,
      failedFeeds: errors.length,
    );
  }
  
  Future<void> _processFeedInBatch(
    Feed feed,
    Map<String, RefreshResult> results,
    Map<String, String> errors,
  ) async {
    try {
      onFeedLog?.call(feed.id, 'Refreshing ${feed.title}...');
      final result = await refreshFeed(feed);
      results[feed.id] = result;
      
      if (result.error != null) {
        errors[feed.id] = result.error!;
        onFeedLog?.call(feed.id, 'Error: ${result.error}');
      } else {
        onFeedLog?.call(feed.id, 'Success: ${result.newArticles.length} new articles');
      }
    } catch (e) {
      errors[feed.id] = e.toString();
      onFeedLog?.call(feed.id, 'Fatal error: $e');
    }
  }
  
  /// Get feed health statistics
  FeedHealth getFeedHealth(String feedId) {
    return _feedHealth[feedId] ?? FeedHealth(
      feedId: feedId,
      totalFetches: 0,
      successfulFetches: 0,
      failedFetches: 0,
      successRate: 0,
      averageResponseTime: Duration.zero,
      recentEvents: [],
    );
  }
  
  /// Update feed health after refresh
  void _updateFeedHealth(String feedId, bool success, Duration responseTime, String? error) {
    final health = getFeedHealth(feedId);
    final events = List<FeedHealthEvent>.from(health.recentEvents);
    
    // Add new event
    events.add(FeedHealthEvent(
      timestamp: DateTime.now(),
      success: success,
      responseTime: responseTime,
      error: error,
    ));
    
    // Keep only last 100 events
    if (events.length > 100) {
      events.removeRange(0, events.length - 100);
    }
    
    // Calculate statistics
    final totalFetches = health.totalFetches + 1;
    final successfulFetches = health.successfulFetches + (success ? 1 : 0);
    final failedFetches = health.failedFetches + (success ? 0 : 1);
    final successRate = successfulFetches / totalFetches;
    
    // Calculate average response time
    final totalResponseTime = events
        .map((e) => e.responseTime.inMilliseconds)
        .reduce((a, b) => a + b);
    final averageResponseTime = Duration(
      milliseconds: totalResponseTime ~/ events.length,
    );
    
    _feedHealth[feedId] = FeedHealth(
      feedId: feedId,
      totalFetches: totalFetches,
      successfulFetches: successfulFetches,
      failedFetches: failedFetches,
      successRate: successRate,
      averageResponseTime: averageResponseTime,
      lastSuccessAt: success ? DateTime.now() : health.lastSuccessAt,
      lastFailureAt: success ? health.lastFailureAt : DateTime.now(),
      lastError: error ?? health.lastError,
      recentEvents: events,
    );
  }
  
  /// Mark all articles as read for a feed
  Future<void> markFeedAsRead(String feedId) async {
    if (_database != null) {
      await _database!.markFeedAsRead(feedId);
    }
  }
  
  /// Mark all articles as read for multiple feeds
  Future<void> markFeedsAsRead(List<String> feedIds) async {
    if (_database != null) {
      await _database!.markFeedsAsRead(feedIds);
    }
  }
  
  /// Get feed statistics
  Future<FeedStatistics> getFeedStatistics(String feedId) async {
    if (_database == null) {
      return FeedStatistics.empty(feedId);
    }
    
    final articles = await _database!.getArticlesByFeed(feedId);
    final health = getFeedHealth(feedId);
    
    return FeedStatistics(
      feedId: feedId,
      totalArticles: articles.length,
      readArticles: articles.where((a) => a.isRead).length,
      starredArticles: articles.where((a) => a.isStarred).length,
      articlesPerDay: _calculateArticlesPerDay(articles),
      mostActiveHours: _calculateMostActiveHours(articles),
      health: health,
    );
  }
  
  double _calculateArticlesPerDay(List<Article> articles) {
    if (articles.isEmpty) return 0;
    
    final sortedArticles = articles.toList()
      ..sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
    
    final firstArticle = sortedArticles.first;
    final lastArticle = sortedArticles.last;
    final daysDiff = lastArticle.publishedAt.difference(firstArticle.publishedAt).inDays;
    
    if (daysDiff == 0) return articles.length.toDouble();
    return articles.length / daysDiff;
  }
  
  List<int> _calculateMostActiveHours(List<Article> articles) {
    final hourCounts = List<int>.filled(24, 0);
    
    for (final article in articles) {
      hourCounts[article.publishedAt.hour]++;
    }
    
    // Get top 3 most active hours
    final hoursWithCounts = hourCounts.asMap().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return hoursWithCounts.take(3).map((e) => e.key).toList();
  }
  
  /// Clean up old articles based on retention settings
  Future<int> cleanupOldArticles({
    Duration? keepUnreadFor,
    Duration? keepReadFor,
    Duration? keepStarredFor,
    int? maxArticlesPerFeed,
  }) async {
    if (_database == null) return 0;
    
    int deletedCount = 0;
    final now = DateTime.now();
    
    // Get all feeds
    final feeds = await _database!.getAllFeeds();
    
    for (final feed in feeds) {
      final articles = await _database!.getArticlesByFeed(feed.id);
      final toDelete = <String>[];
      
      for (final article in articles) {
        // Skip starred articles if they have special retention
        if (article.isStarred && keepStarredFor != null) {
          if (now.difference(article.publishedAt) > keepStarredFor) {
            toDelete.add(article.id);
          }
          continue;
        }
        
        // Check read articles
        if (article.isRead && keepReadFor != null) {
          if (now.difference(article.publishedAt) > keepReadFor) {
            toDelete.add(article.id);
          }
          continue;
        }
        
        // Check unread articles
        if (!article.isRead && keepUnreadFor != null) {
          if (now.difference(article.publishedAt) > keepUnreadFor) {
            toDelete.add(article.id);
          }
        }
      }
      
      // Apply max articles per feed limit
      if (maxArticlesPerFeed != null && articles.length > maxArticlesPerFeed) {
        final sortedArticles = articles.toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
        
        for (int i = maxArticlesPerFeed; i < sortedArticles.length; i++) {
          if (!sortedArticles[i].isStarred) {
            toDelete.add(sortedArticles[i].id);
          }
        }
      }
      
      // Delete articles
      if (toDelete.isNotEmpty) {
        await _database!.deleteArticles(toDelete);
        deletedCount += toDelete.length;
      }
    }
    
    return deletedCount;
  }
}

/// Batch refresh result
class BatchRefreshResult {
  final Map<String, RefreshResult> results;
  final Map<String, String> errors;
  final int totalFeeds;
  final int successfulFeeds;
  final int failedFeeds;
  
  BatchRefreshResult({
    required this.results,
    required this.errors,
    required this.totalFeeds,
    required this.successfulFeeds,
    required this.failedFeeds,
  });
}

/// Feed statistics
class FeedStatistics {
  final String feedId;
  final int totalArticles;
  final int readArticles;
  final int starredArticles;
  final double articlesPerDay;
  final List<int> mostActiveHours;
  final FeedHealth health;
  
  FeedStatistics({
    required this.feedId,
    required this.totalArticles,
    required this.readArticles,
    required this.starredArticles,
    required this.articlesPerDay,
    required this.mostActiveHours,
    required this.health,
  });
  
  factory FeedStatistics.empty(String feedId) => FeedStatistics(
    feedId: feedId,
    totalArticles: 0,
    readArticles: 0,
    starredArticles: 0,
    articlesPerDay: 0,
    mostActiveHours: [],
    health: FeedHealth(
      feedId: feedId,
      totalFetches: 0,
      successfulFetches: 0,
      failedFetches: 0,
      successRate: 0,
      averageResponseTime: Duration.zero,
      recentEvents: [],
    ),
  );
}

/// Result of a feed refresh operation
class RefreshResult {
  final Feed feed;
  final List<Article> newArticles;
  final bool wasModified;
  final String? error;
  
  RefreshResult({
    required this.feed,
    required this.newArticles,
    required this.wasModified,
    this.error,
  });
}

/// Discovered feed information
class DiscoveredFeed {
  final String url;
  final String title;
  final FeedType type;
  final bool isDirect;
  
  DiscoveredFeed({
    required this.url,
    required this.title,
    required this.type,
    required this.isDirect,
  });
}

/// Feed service exception
class FeedServiceException implements Exception {
  final String message;
  
  FeedServiceException(this.message);
  
  @override
  String toString() => message;
}

/// Feed health status
class FeedHealth {
  final String feedId;
  final int totalFetches;
  final int successfulFetches;
  final int failedFetches;
  final double successRate;
  final Duration averageResponseTime;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? lastError;
  final List<FeedHealthEvent> recentEvents;
  
  FeedHealth({
    required this.feedId,
    required this.totalFetches,
    required this.successfulFetches,
    required this.failedFetches,
    required this.successRate,
    required this.averageResponseTime,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastError,
    required this.recentEvents,
  });
  
  bool get isHealthy => successRate > 0.8 && lastFailureAt == null ||
      (lastFailureAt != null && lastSuccessAt != null && lastSuccessAt!.isAfter(lastFailureAt!));
}

/// Feed health event
class FeedHealthEvent {
  final DateTime timestamp;
  final bool isSuccess;
  final String? error;
  final Duration responseTime;
  
  FeedHealthEvent({
    required this.timestamp,
    required this.isSuccess,
    this.error,
    required this.responseTime,
  });
}

extension FeedServiceBatchOperations on FeedService {
  /// Batch refresh multiple feeds
  Future<void> batchRefresh(
    List<Feed> feeds, {
    Function(int current, int total)? onProgress,
  }) async {
    for (int i = 0; i < feeds.length; i++) {
      onProgress?.call(i + 1, feeds.length);
      
      try {
        await refreshFeed(feeds[i]);
      } catch (e) {
        onFeedLog?.call(feeds[i].id, 'Failed to refresh: $e');
      }
    }
  }
  
  /// Mark all articles in feeds as read
  Future<void> markFeedsAsRead(List<String> feedIds) async {
    if (_database == null) return;
    
    for (final feedId in feedIds) {
      await _database!.articleDao.markAllAsRead(feedId);
    }
  }
  
  /// Mark single feed as read
  Future<void> markFeedAsRead(String feedId) async {
    await markFeedsAsRead([feedId]);
  }
  
  /// Clean up old articles
  Future<void> cleanupOldArticles({
    required List<String> feedIds,
    required int olderThanDays,
  }) async {
    if (_database == null) return;
    
    final cutoffDate = DateTime.now().subtract(Duration(days: olderThanDays));
    
    for (final feedId in feedIds) {
      await _database!.articleDao.deleteOldArticles(feedId, cutoffDate);
    }
  }
}