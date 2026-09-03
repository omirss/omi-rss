import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html;
import '../models/feed.dart';

/// Service for discovering RSS/Atom/JSON feeds from websites
class FeedDiscoveryService {
  final Dio _dio;
  
  FeedDiscoveryService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
    _dio.options.headers = {
      'User-Agent': 'RSS Reader/1.0 (Feed Discovery)',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    };
  }
  
  /// Discover feeds from a URL
  Future<List<DiscoveredFeed>> discoverFeeds(String url) async {
    final feeds = <DiscoveredFeed>[];
    
    try {
      // Normalize URL
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      
      final uri = Uri.parse(url);
      
      // First, check if the URL itself is a feed
      if (await _isFeedUrl(url)) {
        final feedInfo = await _getFeedInfo(url);
        if (feedInfo != null) {
          feeds.add(feedInfo);
          return feeds;
        }
      }
      
      // Fetch the webpage
      final response = await _dio.get(url);
      
      // Parse HTML
      final document = html_parser.parse(response.data);
      
      // 1. Look for <link> tags in head
      feeds.addAll(await _findFeedsInHead(document, uri));
      
      // 2. Look for common feed URLs
      feeds.addAll(await _findCommonFeedUrls(uri));
      
      // 3. Look for feed links in body
      feeds.addAll(await _findFeedsInBody(document, uri));
      
      // 4. Try well-known feed locations
      feeds.addAll(await _tryWellKnownLocations(uri));
      
      // Remove duplicates
      final uniqueFeeds = <String, DiscoveredFeed>{};
      for (final feed in feeds) {
        uniqueFeeds[feed.url] = feed;
      }
      
      return uniqueFeeds.values.toList();
    } catch (e) {
      print('Feed discovery error: $e');
      return feeds;
    }
  }
  
  /// Check if URL is a feed
  Future<bool> _isFeedUrl(String url) async {
    try {
      final response = await _dio.head(url);
      final contentType = response.headers.value('content-type') ?? '';
      
      return contentType.contains('application/rss+xml') ||
             contentType.contains('application/atom+xml') ||
             contentType.contains('application/json') ||
             contentType.contains('application/feed+json') ||
             contentType.contains('text/xml') ||
             url.endsWith('.rss') ||
             url.endsWith('.atom') ||
             url.endsWith('.xml') ||
             url.endsWith('.json');
    } catch (e) {
      return false;
    }
  }
  
  /// Get feed information
  Future<DiscoveredFeed?> _getFeedInfo(String url) async {
    try {
      final response = await _dio.get(url);
      final contentType = response.headers.value('content-type') ?? '';
      final data = response.data;
      
      // Determine feed type
      FeedType? type;
      String? title;
      String? description;
      
      if (data is String) {
        if (data.contains('<rss') || data.contains('<channel>')) {
          type = FeedType.rss;
          final doc = html_parser.parseFragment(data);
          title = doc.querySelector('title')?.text;
          description = doc.querySelector('description')?.text;
        } else if (data.contains('<feed') || data.contains('xmlns="http://www.w3.org/2005/Atom"')) {
          type = FeedType.atom;
          final doc = html_parser.parseFragment(data);
          title = doc.querySelector('title')?.text;
          description = doc.querySelector('subtitle')?.text;
        } else if (data.contains('"version"') && data.contains('"items"')) {
          type = FeedType.json;
          try {
            final json = jsonDecode(data);
            title = json['title'];
            description = json['description'];
          } catch (e) {
            // Not valid JSON
          }
        }
      }
      
      if (type != null) {
        return DiscoveredFeed(
          url: url,
          title: title ?? 'Untitled Feed',
          description: description,
          type: type,
        );
      }
    } catch (e) {
      print('Error getting feed info: $e');
    }
    
    return null;
  }
  
  /// Find feeds in HTML head
  Future<List<DiscoveredFeed>> _findFeedsInHead(html.Document document, Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    
    // Look for <link rel="alternate" type="application/rss+xml">
    final linkElements = document.querySelectorAll('link[rel="alternate"]');
    
    for (final link in linkElements) {
      final type = link.attributes['type'] ?? '';
      final href = link.attributes['href'];
      final title = link.attributes['title'];
      
      if (href != null && (
        type.contains('application/rss+xml') ||
        type.contains('application/atom+xml') ||
        type.contains('application/json') ||
        type.contains('application/feed+json')
      )) {
        final feedUrl = _resolveUrl(href, baseUri);
        final feedType = _getFeedTypeFromMime(type);
        
        feeds.add(DiscoveredFeed(
          url: feedUrl,
          title: title ?? 'RSS Feed',
          type: feedType,
        ));
      }
    }
    
    return feeds;
  }
  
  /// Find common feed URLs
  Future<List<DiscoveredFeed>> _findCommonFeedUrls(Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    final commonPaths = [
      '/rss',
      '/rss.xml',
      '/feed',
      '/feed.xml',
      '/atom.xml',
      '/feeds',
      '/index.xml',
      '/blog/feed',
      '/blog/rss',
      '/news/feed',
      '/news/rss',
      '/.rss',
      '/rss2.xml',
      '/atom',
      '/feed.json',
      '/feed.atom',
    ];
    
    for (final path in commonPaths) {
      final feedUrl = baseUri.resolve(path).toString();
      
      if (await _isFeedUrl(feedUrl)) {
        final feedInfo = await _getFeedInfo(feedUrl);
        if (feedInfo != null) {
          feeds.add(feedInfo);
        }
      }
    }
    
    return feeds;
  }
  
  /// Find feed links in body
  Future<List<DiscoveredFeed>> _findFeedsInBody(html.Document document, Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    
    // Look for RSS/Feed links
    final feedLinks = document.querySelectorAll('a');
    
    for (final link in feedLinks) {
      final href = link.attributes['href'];
      final text = link.text.toLowerCase();
      
      if (href != null && (
        text.contains('rss') ||
        text.contains('feed') ||
        text.contains('atom') ||
        text.contains('subscribe') ||
        href.contains('/rss') ||
        href.contains('/feed') ||
        href.contains('/atom') ||
        href.endsWith('.xml') ||
        href.endsWith('.rss') ||
        href.endsWith('.atom')
      )) {
        final feedUrl = _resolveUrl(href, baseUri);
        
        if (await _isFeedUrl(feedUrl)) {
          final feedInfo = await _getFeedInfo(feedUrl);
          if (feedInfo != null) {
            feeds.add(feedInfo);
          }
        }
      }
    }
    
    return feeds;
  }
  
  /// Try well-known feed locations
  Future<List<DiscoveredFeed>> _tryWellKnownLocations(Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    
    // Platform-specific feeds
    final host = baseUri.host.toLowerCase();
    
    if (host.contains('wordpress')) {
      feeds.addAll(await _tryWordPressFeed(baseUri));
    } else if (host.contains('blogger') || host.contains('blogspot')) {
      feeds.addAll(await _tryBloggerFeed(baseUri));
    } else if (host.contains('medium.com')) {
      feeds.addAll(await _tryMediumFeed(baseUri));
    } else if (host.contains('tumblr.com')) {
      feeds.addAll(await _tryTumblrFeed(baseUri));
    } else if (host.contains('youtube.com')) {
      feeds.addAll(await _tryYouTubeFeed(baseUri));
    } else if (host.contains('reddit.com')) {
      feeds.addAll(await _tryRedditFeed(baseUri));
    }
    
    return feeds;
  }
  
  /// Try WordPress feed URLs
  Future<List<DiscoveredFeed>> _tryWordPressFeed(Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    final wpPaths = ['/feed/', '/comments/feed/', '/wp-rss2.php'];
    
    for (final path in wpPaths) {
      final feedUrl = baseUri.resolve(path).toString();
      final feedInfo = await _getFeedInfo(feedUrl);
      if (feedInfo != null) {
        feeds.add(feedInfo);
      }
    }
    
    return feeds;
  }
  
  /// Try Blogger feed URLs
  Future<List<DiscoveredFeed>> _tryBloggerFeed(Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    final feedUrl = '${baseUri.scheme}://${baseUri.host}/feeds/posts/default';
    
    final feedInfo = await _getFeedInfo(feedUrl);
    if (feedInfo != null) {
      feeds.add(feedInfo);
    }
    
    return feeds;
  }
  
  /// Try Medium feed URLs
  Future<List<DiscoveredFeed>> _tryMediumFeed(Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    final path = baseUri.path;
    
    if (path.startsWith('/@')) {
      // User feed
      final username = path.substring(2).split('/')[0];
      final feedUrl = 'https://medium.com/feed/@$username';
      
      final feedInfo = await _getFeedInfo(feedUrl);
      if (feedInfo != null) {
        feeds.add(feedInfo);
      }
    } else if (path.isNotEmpty && !path.contains('@')) {
      // Publication feed
      final publication = path.substring(1).split('/')[0];
      final feedUrl = 'https://medium.com/feed/$publication';
      
      final feedInfo = await _getFeedInfo(feedUrl);
      if (feedInfo != null) {
        feeds.add(feedInfo);
      }
    }
    
    return feeds;
  }
  
  /// Try Tumblr feed URLs
  Future<List<DiscoveredFeed>> _tryTumblrFeed(Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    final feedUrl = '${baseUri.scheme}://${baseUri.host}/rss';
    
    final feedInfo = await _getFeedInfo(feedUrl);
    if (feedInfo != null) {
      feeds.add(feedInfo);
    }
    
    return feeds;
  }
  
  /// Try YouTube feed URLs
  Future<List<DiscoveredFeed>> _tryYouTubeFeed(Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    final path = baseUri.path;
    
    if (path.contains('/channel/')) {
      // Channel feed
      final channelId = path.split('/channel/')[1].split('/')[0];
      final feedUrl = 'https://www.youtube.com/feeds/videos.xml?channel_id=$channelId';
      
      feeds.add(DiscoveredFeed(
        url: feedUrl,
        title: 'YouTube Channel Feed',
        type: FeedType.atom,
      ));
    } else if (path.contains('/user/')) {
      // User feed
      final username = path.split('/user/')[1].split('/')[0];
      final feedUrl = 'https://www.youtube.com/feeds/videos.xml?user=$username';
      
      feeds.add(DiscoveredFeed(
        url: feedUrl,
        title: 'YouTube User Feed',
        type: FeedType.atom,
      ));
    }
    
    return feeds;
  }
  
  /// Try Reddit feed URLs
  Future<List<DiscoveredFeed>> _tryRedditFeed(Uri baseUri) async {
    final feeds = <DiscoveredFeed>[];
    final path = baseUri.path;
    
    if (path.startsWith('/r/')) {
      // Subreddit feed
      final subreddit = path.split('/')[2];
      final feedUrl = 'https://www.reddit.com/r/$subreddit/.rss';
      
      feeds.add(DiscoveredFeed(
        url: feedUrl,
        title: '/r/$subreddit RSS Feed',
        type: FeedType.rss,
      ));
    } else if (path.startsWith('/user/')) {
      // User feed
      final username = path.split('/')[2];
      final feedUrl = 'https://www.reddit.com/user/$username/.rss';
      
      feeds.add(DiscoveredFeed(
        url: feedUrl,
        title: '/u/$username RSS Feed',
        type: FeedType.rss,
      ));
    }
    
    return feeds;
  }
  
  /// Resolve relative URL to absolute
  String _resolveUrl(String url, Uri baseUri) {
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme) {
        return url;
      } else {
        return baseUri.resolve(url).toString();
      }
    } catch (e) {
      return url;
    }
  }
  
  /// Get feed type from MIME type
  FeedType _getFeedTypeFromMime(String mimeType) {
    if (mimeType.contains('atom')) {
      return FeedType.atom;
    } else if (mimeType.contains('json')) {
      return FeedType.json;
    } else {
      return FeedType.rss;
    }
  }
}

/// Discovered feed information
class DiscoveredFeed {
  final String url;
  final String title;
  final String? description;
  final FeedType type;
  
  DiscoveredFeed({
    required this.url,
    required this.title,
    this.description,
    required this.type,
  });
}