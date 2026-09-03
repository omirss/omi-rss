import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:serverpod/serverpod.dart';
import 'package:webfeed_revised/webfeed_revised.dart';
import 'package:html/parser.dart' as html_parser;
import '../protocol/protocol.dart';

class FeedService {
  final Session session;
  final Dio _dio;
  final Map<int, DateTime> _feedLastCheck = {};
  final Map<int, String?> _feedEtags = {};
  final Map<int, DateTime?> _feedLastModified = {};
  
  FeedService(this.session) : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
    maxRedirects: 5,
    headers: {
      'User-Agent': 'OmiRSS/1.0 (https://github.com/omi-rss)',
      'Accept': 'application/rss+xml, application/atom+xml, application/json, application/xml, text/xml',
    },
  ));

  // Parse feed from URL
  Future<ParsedFeed> parseFeed(String url) async {
    try {
      final response = await _dio.get(url);
      final contentType = response.headers.value('content-type') ?? '';
      final content = response.data.toString();
      
      // Try to detect feed type
      if (content.contains('<rss') || content.contains('<channel>')) {
        return _parseRssFeed(content, url);
      } else if (content.contains('<feed') || content.contains('xmlns="http://www.w3.org/2005/Atom"')) {
        return _parseAtomFeed(content, url);
      } else if (contentType.contains('json') || content.trim().startsWith('{')) {
        return _parseJsonFeed(content, url);
      } else {
        throw Exception('Unknown feed format');
      }
    } catch (e) {
      session.log('Feed parsing error for $url: $e');
      rethrow;
    }
  }

  // Update feed with smart refresh
  Future<FeedUpdateResult> updateFeed(Feed feed) async {
    try {
      final feedId = feed.id!;
      final headers = <String, String>{};
      
      // Add conditional request headers
      if (_feedEtags.containsKey(feedId)) {
        headers['If-None-Match'] = _feedEtags[feedId]!;
      }
      if (_feedLastModified.containsKey(feedId)) {
        final lastMod = _feedLastModified[feedId];
        if (lastMod != null) {
          headers['If-Modified-Since'] = _formatHttpDate(lastMod);
        }
      }
      
      final startTime = DateTime.now();
      final response = await _dio.get(
        feed.feedUrl,
        options: Options(
          headers: headers,
          validateStatus: (status) => status! < 500,
        ),
      );
      final responseTime = DateTime.now().difference(startTime).inMilliseconds;
      
      // Handle 304 Not Modified
      if (response.statusCode == 304) {
        // Update health metrics
        await _updateFeedHealth(feed, true, responseTime, 0);
        return FeedUpdateResult(
          feedId: feedId,
          newArticles: 0,
          updatedArticles: 0,
          isModified: false,
          responseTime: responseTime,
        );
      }
      
      // Parse the feed
      final parsedFeed = await parseFeed(feed.feedUrl);
      
      // Store conditional request headers
      final etag = response.headers.value('etag');
      if (etag != null) {
        _feedEtags[feedId] = etag;
      }
      
      final lastModified = response.headers.value('last-modified');
      if (lastModified != null) {
        _feedLastModified[feedId] = _parseHttpDate(lastModified);
      }
      
      // Update feed metadata
      feed.title = parsedFeed.title ?? feed.title;
      feed.description = parsedFeed.description ?? feed.description;
      feed.websiteUrl = parsedFeed.websiteUrl ?? feed.websiteUrl;
      feed.imageUrl = parsedFeed.imageUrl ?? feed.imageUrl;
      feed.lastUpdated = DateTime.now();
      
      await Feed.db.updateRow(session, feed);
      
      // Process articles
      final existingArticles = await Article.db.find(
        session,
        where: (t) => t.feedId.equals(feedId),
      );
      
      final existingGuids = existingArticles.map((a) => a.guid).toSet();
      final existingUrls = existingArticles.map((a) => a.url).toSet();
      
      int newCount = 0;
      int updatedCount = 0;
      
      for (final item in parsedFeed.items) {
        // Check if article exists
        bool isNew = true;
        Article? existingArticle;
        
        if (item.guid != null && existingGuids.contains(item.guid)) {
          isNew = false;
          existingArticle = existingArticles.firstWhere((a) => a.guid == item.guid);
        } else if (existingUrls.contains(item.url)) {
          isNew = false;
          existingArticle = existingArticles.firstWhere((a) => a.url == item.url);
        }
        
        if (isNew) {
          // Create new article
          final article = Article(
            feedId: feedId,
            title: item.title ?? 'Untitled',
            url: item.url,
            guid: item.guid ?? item.url,
            description: item.description,
            content: item.content,
            author: item.author,
            publishedAt: item.publishedAt ?? DateTime.now(),
            imageUrl: item.imageUrl,
            categories: item.categories,
            isRead: false,
            isStarred: false,
            createdAt: DateTime.now(),
          );
          
          await Article.db.insertRow(session, article);
          newCount++;
        } else if (existingArticle != null) {
          // Check if article was updated
          bool wasUpdated = false;
          
          if (existingArticle.title != item.title) {
            existingArticle.title = item.title ?? existingArticle.title;
            wasUpdated = true;
          }
          if (existingArticle.description != item.description) {
            existingArticle.description = item.description;
            wasUpdated = true;
          }
          if (existingArticle.content != item.content) {
            existingArticle.content = item.content;
            wasUpdated = true;
          }
          if (existingArticle.imageUrl != item.imageUrl) {
            existingArticle.imageUrl = item.imageUrl;
            wasUpdated = true;
          }
          
          if (wasUpdated) {
            await Article.db.updateRow(session, existingArticle);
            updatedCount++;
          }
        }
      }
      
      // Update feed health
      await _updateFeedHealth(feed, true, responseTime, newCount);
      
      // Update article count
      feed.articleCount = await Article.db.count(
        session,
        where: (t) => t.feedId.equals(feedId),
      );
      await Feed.db.updateRow(session, feed);
      
      return FeedUpdateResult(
        feedId: feedId,
        newArticles: newCount,
        updatedArticles: updatedCount,
        isModified: true,
        responseTime: responseTime,
      );
    } catch (e) {
      session.log('Feed update error for ${feed.feedUrl}: $e');
      
      // Update feed health with error
      await _updateFeedHealth(feed, false, 0, 0, e.toString());
      
      throw Exception('Failed to update feed: $e');
    }
  }

  // Batch update feeds
  Future<List<FeedUpdateResult>> batchUpdateFeeds(
    List<Feed> feeds, {
    int concurrency = 5,
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <FeedUpdateResult>[];
    final queue = List<Feed>.from(feeds);
    final inProgress = <Future<FeedUpdateResult>>[];
    
    while (queue.isNotEmpty || inProgress.isNotEmpty) {
      // Start new updates up to concurrency limit
      while (inProgress.length < concurrency && queue.isNotEmpty) {
        final feed = queue.removeAt(0);
        inProgress.add(_updateFeedSafe(feed));
      }
      
      // Wait for at least one to complete
      if (inProgress.isNotEmpty) {
        final completed = await Future.any(inProgress);
        results.add(completed);
        inProgress.removeWhere((f) async => await f == completed);
        
        // Report progress
        onProgress?.call(results.length, feeds.length);
      }
    }
    
    return results;
  }

  // Safe update that catches errors
  Future<FeedUpdateResult> _updateFeedSafe(Feed feed) async {
    try {
      return await updateFeed(feed);
    } catch (e) {
      return FeedUpdateResult(
        feedId: feed.id!,
        newArticles: 0,
        updatedArticles: 0,
        isModified: false,
        responseTime: 0,
        error: e.toString(),
      );
    }
  }

  // Discover feeds from URL
  Future<List<DiscoveredFeed>> discoverFeeds(String url) async {
    final feeds = <DiscoveredFeed>[];
    
    try {
      // First, check if the URL itself is a feed
      try {
        final parsedFeed = await parseFeed(url);
        feeds.add(DiscoveredFeed(
          url: url,
          title: parsedFeed.title ?? 'Unknown Feed',
          description: parsedFeed.description,
          type: parsedFeed.type,
        ));
        return feeds;
      } catch (_) {
        // Not a direct feed, continue with discovery
      }
      
      // Fetch the page
      final response = await _dio.get(url);
      final content = response.data.toString();
      final doc = html_parser.parse(content);
      
      // Look for feed links in HTML
      final linkElements = doc.querySelectorAll('link[rel="alternate"]');
      for (final link in linkElements) {
        final type = link.attributes['type'] ?? '';
        final href = link.attributes['href'] ?? '';
        
        if (href.isNotEmpty && _isFeedType(type)) {
          final feedUrl = _resolveUrl(url, href);
          feeds.add(DiscoveredFeed(
            url: feedUrl,
            title: link.attributes['title'] ?? 'RSS Feed',
            type: _getFeedTypeFromMime(type),
          ));
        }
      }
      
      // Check common feed URLs
      final commonPaths = [
        '/feed', '/rss', '/atom', '/feed.xml', '/rss.xml', '/atom.xml',
        '/index.xml', '/feed/', '/rss/', '/feeds/posts/default',
      ];
      
      for (final path in commonPaths) {
        try {
          final feedUrl = _resolveUrl(url, path);
          final parsedFeed = await parseFeed(feedUrl);
          feeds.add(DiscoveredFeed(
            url: feedUrl,
            title: parsedFeed.title ?? 'RSS Feed',
            description: parsedFeed.description,
            type: parsedFeed.type,
          ));
        } catch (_) {
          // Ignore errors for common paths
        }
      }
      
      // Remove duplicates
      final uniqueFeeds = <String, DiscoveredFeed>{};
      for (final feed in feeds) {
        uniqueFeeds[feed.url] = feed;
      }
      
      return uniqueFeeds.values.toList();
    } catch (e) {
      session.log('Feed discovery error for $url: $e');
      return feeds;
    }
  }

  // Calculate feed statistics
  Future<FeedStatistics> calculateStatistics(int feedId) async {
    final articles = await Article.db.find(
      session,
      where: (t) => t.feedId.equals(feedId),
    );
    
    if (articles.isEmpty) {
      return FeedStatistics(
        totalArticles: 0,
        readArticles: 0,
        starredArticles: 0,
        articlesPerDay: 0.0,
        averageReadTime: 0.0,
        mostActiveHour: 0,
        oldestArticleDate: null,
        newestArticleDate: null,
      );
    }
    
    final readCount = articles.where((a) => a.isRead).length;
    final starredCount = articles.where((a) => a.isStarred).length;
    
    // Sort by date
    articles.sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
    final oldest = articles.first.publishedAt;
    final newest = articles.last.publishedAt;
    
    // Calculate articles per day
    final daysDiff = newest.difference(oldest).inDays + 1;
    final articlesPerDay = articles.length / daysDiff;
    
    // Calculate most active hour
    final hourCounts = <int, int>{};
    for (final article in articles) {
      final hour = article.publishedAt.hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
    }
    
    var mostActiveHour = 0;
    var maxCount = 0;
    hourCounts.forEach((hour, count) {
      if (count > maxCount) {
        maxCount = count;
        mostActiveHour = hour;
      }
    });
    
    // Calculate average read time (placeholder - would need actual read time tracking)
    final averageReadTime = 0.0;
    
    return FeedStatistics(
      totalArticles: articles.length,
      readArticles: readCount,
      starredArticles: starredCount,
      articlesPerDay: articlesPerDay,
      averageReadTime: averageReadTime,
      mostActiveHour: mostActiveHour,
      oldestArticleDate: oldest,
      newestArticleDate: newest,
    );
  }

  // Private helper methods
  ParsedFeed _parseRssFeed(String content, String url) {
    final rssFeed = RssFeed.parse(content);
    
    return ParsedFeed(
      title: rssFeed.title,
      description: rssFeed.description,
      websiteUrl: rssFeed.link,
      imageUrl: rssFeed.image?.url,
      type: 'rss',
      items: rssFeed.items.map((item) => ParsedFeedItem(
        title: item.title,
        url: item.link ?? '',
        guid: item.guid,
        description: item.description,
        content: item.content?.value,
        author: item.author ?? item.dc?.creator,
        publishedAt: item.pubDate,
        imageUrl: _extractImageFromContent(item.description, item.content?.value),
        categories: item.categories?.map((c) => c.value).whereType<String>().toList() ?? [],
      )).toList(),
    );
  }

  ParsedFeed _parseAtomFeed(String content, String url) {
    final atomFeed = AtomFeed.parse(content);
    
    return ParsedFeed(
      title: atomFeed.title,
      description: atomFeed.subtitle,
      websiteUrl: atomFeed.links?.firstWhere(
        (l) => l.rel == 'alternate' || l.rel == null,
        orElse: () => AtomLink(),
      ).href,
      imageUrl: atomFeed.logo,
      type: 'atom',
      items: atomFeed.items.map((item) => ParsedFeedItem(
        title: item.title,
        url: item.links?.firstWhere(
          (l) => l.rel == 'alternate' || l.rel == null,
          orElse: () => AtomLink(),
        ).href ?? '',
        guid: item.id,
        description: item.summary,
        content: item.content,
        author: item.authors?.map((a) => a.name).join(', '),
        publishedAt: item.published ?? item.updated,
        imageUrl: _extractImageFromContent(item.summary, item.content),
        categories: item.categories?.map((c) => c.label ?? c.term).whereType<String>().toList() ?? [],
      )).toList(),
    );
  }

  ParsedFeed _parseJsonFeed(String content, String url) {
    final json = jsonDecode(content);
    
    return ParsedFeed(
      title: json['title'],
      description: json['description'],
      websiteUrl: json['home_page_url'],
      imageUrl: json['icon'] ?? json['favicon'],
      type: 'json',
      items: (json['items'] as List).map((item) => ParsedFeedItem(
        title: item['title'] ?? item['summary']?.substring(0, 50),
        url: item['url'] ?? '',
        guid: item['id']?.toString(),
        description: item['summary'],
        content: item['content_html'] ?? item['content_text'],
        author: item['author']?['name'] ?? item['authors']?.map((a) => a['name']).join(', '),
        publishedAt: item['date_published'] != null 
            ? DateTime.parse(item['date_published']) 
            : null,
        imageUrl: item['image'] ?? item['banner_image'],
        categories: List<String>.from(item['tags'] ?? []),
      )).toList(),
    );
  }

  String? _extractImageFromContent(String? description, String? content) {
    final htmlContent = content ?? description ?? '';
    if (htmlContent.isEmpty) return null;
    
    final doc = html_parser.parse(htmlContent);
    final img = doc.querySelector('img');
    return img?.attributes['src'];
  }

  bool _isFeedType(String mimeType) {
    return mimeType.contains('rss') ||
           mimeType.contains('atom') ||
           mimeType.contains('xml') ||
           mimeType.contains('json');
  }

  String _getFeedTypeFromMime(String mimeType) {
    if (mimeType.contains('rss')) return 'rss';
    if (mimeType.contains('atom')) return 'atom';
    if (mimeType.contains('json')) return 'json';
    return 'unknown';
  }

  String _resolveUrl(String baseUrl, String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    
    final uri = Uri.parse(baseUrl);
    if (path.startsWith('/')) {
      return '${uri.scheme}://${uri.host}$path';
    }
    
    final basePath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return '${uri.scheme}://${uri.host}$basePath$path';
  }

  String _formatHttpDate(DateTime date) {
    // Format as RFC 2616 HTTP date
    final weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];
    final month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1];
    return '$weekday, ${date.day.toString().padLeft(2, '0')} $month ${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')} GMT';
  }

  DateTime? _parseHttpDate(String dateStr) {
    try {
      // Simple HTTP date parser - in production use a proper library
      return DateTime.parse(dateStr);
    } catch (e) {
      return null;
    }
  }

  Future<void> _updateFeedHealth(
    Feed feed,
    bool success,
    int responseTime,
    int newArticles, [
    String? error,
  ]) async {
    final healthData = feed.healthData ?? {};
    
    // Update success rate
    final recentChecks = List<bool>.from(healthData['recentChecks'] ?? []);
    recentChecks.add(success);
    if (recentChecks.length > 100) {
      recentChecks.removeAt(0);
    }
    healthData['recentChecks'] = recentChecks;
    
    final successRate = recentChecks.where((c) => c).length / recentChecks.length;
    healthData['successRate'] = successRate;
    
    // Update response times
    final responseTimes = List<int>.from(healthData['responseTimes'] ?? []);
    if (success) {
      responseTimes.add(responseTime);
      if (responseTimes.length > 100) {
        responseTimes.removeAt(0);
      }
    }
    healthData['responseTimes'] = responseTimes;
    
    if (responseTimes.isNotEmpty) {
      healthData['avgResponseTime'] = responseTimes.reduce((a, b) => a + b) / responseTimes.length;
    }
    
    // Update last check info
    healthData['lastCheck'] = DateTime.now().toIso8601String();
    healthData['lastSuccess'] = success;
    if (error != null) {
      healthData['lastError'] = error;
    }
    
    // Update article rate
    final articleRates = List<int>.from(healthData['articleRates'] ?? []);
    articleRates.add(newArticles);
    if (articleRates.length > 100) {
      articleRates.removeAt(0);
    }
    healthData['articleRates'] = articleRates;
    
    // Determine health status
    String status = 'healthy';
    if (successRate < 0.5) {
      status = 'unhealthy';
    } else if (successRate < 0.8) {
      status = 'degraded';
    }
    healthData['status'] = status;
    
    feed.healthData = healthData;
    await Feed.db.updateRow(session, feed);
  }
}

// Supporting classes
class ParsedFeed {
  final String? title;
  final String? description;
  final String? websiteUrl;
  final String? imageUrl;
  final String type;
  final List<ParsedFeedItem> items;
  
  ParsedFeed({
    this.title,
    this.description,
    this.websiteUrl,
    this.imageUrl,
    required this.type,
    required this.items,
  });
}

class ParsedFeedItem {
  final String? title;
  final String url;
  final String? guid;
  final String? description;
  final String? content;
  final String? author;
  final DateTime? publishedAt;
  final String? imageUrl;
  final List<String> categories;
  
  ParsedFeedItem({
    this.title,
    required this.url,
    this.guid,
    this.description,
    this.content,
    this.author,
    this.publishedAt,
    this.imageUrl,
    required this.categories,
  });
}

class FeedUpdateResult {
  final int feedId;
  final int newArticles;
  final int updatedArticles;
  final bool isModified;
  final int responseTime;
  final String? error;
  
  FeedUpdateResult({
    required this.feedId,
    required this.newArticles,
    required this.updatedArticles,
    required this.isModified,
    required this.responseTime,
    this.error,
  });
}

class DiscoveredFeed {
  final String url;
  final String title;
  final String? description;
  final String type;
  
  DiscoveredFeed({
    required this.url,
    required this.title,
    this.description,
    required this.type,
  });
}

class FeedStatistics {
  final int totalArticles;
  final int readArticles;
  final int starredArticles;
  final double articlesPerDay;
  final double averageReadTime;
  final int mostActiveHour;
  final DateTime? oldestArticleDate;
  final DateTime? newestArticleDate;
  
  FeedStatistics({
    required this.totalArticles,
    required this.readArticles,
    required this.starredArticles,
    required this.articlesPerDay,
    required this.averageReadTime,
    required this.mostActiveHour,
    this.oldestArticleDate,
    this.newestArticleDate,
  });
}