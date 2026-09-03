import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:webfeed/webfeed.dart';
import 'package:xml/xml.dart' as xml;
import 'package:html/parser.dart' as html_parser;
import 'package:logger/logger.dart';
import '../database/database.dart';

class FeedParserService {
  final Dio _dio;
  final Logger _logger = Logger();
  
  // CORS proxy options for when direct fetch fails
  final List<String> _corsProxies = [
    'https://cors-anywhere.herokuapp.com/',
    'https://api.allorigins.win/raw?url=',
    'https://cors-proxy.htmldriven.com/?url=',
  ];
  int _currentProxyIndex = 0;

  FeedParserService({Dio? dio}) 
    : _dio = dio ?? Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/rss+xml, application/atom+xml, application/json, text/xml, */*',
          'User-Agent': 'OmiRSSReader/1.0',
        },
      ));

  // Main parse method - auto-detects feed type
  Future<ParsedFeed> parseFeed(String url) async {
    try {
      // Normalize URL
      url = _normalizeUrl(url);
      
      // Fetch feed content
      final response = await _fetchFeed(url);
      final contentType = response.headers.value('content-type') ?? '';
      final data = response.data;
      
      ParsedFeed? feedData;
      
      // Try to detect and parse feed type
      if (data is String) {
        // Check if it's JSON
        if (contentType.contains('json') || data.trim().startsWith('{')) {
          feedData = await _parseJSONFeed(data, url);
        } else {
          // Try parsing as XML (RSS/Atom)
          feedData = await _parseXMLFeed(data, url);
        }
      } else {
        throw Exception('Invalid response data type');
      }
      
      // Validate and enhance feed data
      feedData = _validateAndEnhanceFeed(feedData, url);
      
      return feedData;
    } catch (e, stackTrace) {
      _logger.e('Feed parsing error', error: e, stackTrace: stackTrace);
      throw FeedParseException('Failed to parse feed: ${e.toString()}', url);
    }
  }

  // Fetch feed with CORS handling
  Future<Response> _fetchFeed(String url, {bool useCorsProxy = true}) async {
    try {
      // First try direct fetch
      final response = await _dio.get(url);
      
      if (response.statusCode == 200) {
        return response;
      }
      
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'HTTP ${response.statusCode}: ${response.statusMessage}',
      );
    } on DioException catch (e) {
      // If CORS error and proxy enabled, try with proxy
      if (useCorsProxy && _isCorsError(e)) {
        return _fetchWithProxy(url);
      }
      throw e;
    }
  }

  // Check if error is likely CORS-related
  bool _isCorsError(DioException error) {
    return error.type == DioExceptionType.unknown ||
           error.type == DioExceptionType.connectionError ||
           (error.message?.contains('CORS') ?? false) ||
           (error.message?.contains('XMLHttpRequest') ?? false);
  }

  // Fetch using CORS proxy
  Future<Response> _fetchWithProxy(String url) async {
    for (int i = 0; i < _corsProxies.length; i++) {
      final proxyUrl = _corsProxies[_currentProxyIndex] + Uri.encodeComponent(url);
      _currentProxyIndex = (_currentProxyIndex + 1) % _corsProxies.length;
      
      try {
        final response = await _dio.get(proxyUrl);
        
        if (response.statusCode == 200) {
          return response;
        }
      } catch (e) {
        _logger.w('Proxy ${i + 1} failed: ${e.toString()}');
      }
    }
    
    throw Exception('All CORS proxies failed. Please check the feed URL or try again later.');
  }

  // Parse XML feeds (RSS/Atom)
  Future<ParsedFeed> _parseXMLFeed(String xmlText, String feedUrl) async {
    try {
      // Try RSS 2.0 first
      final rssFeed = RssFeed.parse(xmlText);
      if (rssFeed.title != null || rssFeed.items.isNotEmpty) {
        return _convertRssFeed(rssFeed, feedUrl);
      }
    } catch (e) {
      _logger.d('Not an RSS feed, trying Atom');
    }

    try {
      // Try Atom
      final atomFeed = AtomFeed.parse(xmlText);
      if (atomFeed.title != null || atomFeed.items.isNotEmpty) {
        return _convertAtomFeed(atomFeed, feedUrl);
      }
    } catch (e) {
      _logger.d('Not an Atom feed either');
    }

    throw Exception('Unknown XML feed format');
  }

  // Convert RSS feed to ParsedFeed
  ParsedFeed _convertRssFeed(RssFeed rssFeed, String feedUrl) {
    return ParsedFeed(
      type: FeedType.rss,
      title: rssFeed.title ?? 'Untitled Feed',
      description: rssFeed.description ?? '',
      url: feedUrl,
      siteUrl: rssFeed.link ?? feedUrl,
      language: rssFeed.language ?? 'en',
      lastUpdated: rssFeed.lastBuildDate ?? DateTime.now(),
      imageUrl: rssFeed.image?.url,
      items: rssFeed.items.map((item) => ParsedArticle(
        guid: item.guid ?? item.link ?? '',
        title: item.title ?? 'Untitled',
        link: item.link ?? '',
        description: _stripHtml(item.description ?? ''),
        content: item.content?.value ?? item.description ?? '',
        publishedAt: item.pubDate ?? DateTime.now(),
        author: item.author ?? item.dc?.creator ?? '',
        categories: [
          ...?item.categories?.map((cat) => cat.value ?? ''),
        ].where((cat) => cat.isNotEmpty).toList(),
        thumbnail: _extractThumbnail(item),
      )).toList(),
    );
  }

  // Convert Atom feed to ParsedFeed
  ParsedFeed _convertAtomFeed(AtomFeed atomFeed, String feedUrl) {
    return ParsedFeed(
      type: FeedType.atom,
      title: atomFeed.title ?? 'Untitled Feed',
      description: atomFeed.subtitle ?? '',
      url: feedUrl,
      siteUrl: atomFeed.links.firstWhere(
        (link) => link.rel == 'alternate',
        orElse: () => AtomLink(href: feedUrl),
      ).href ?? feedUrl,
      language: 'en', // Atom doesn't have language field
      lastUpdated: atomFeed.updated ?? DateTime.now(),
      imageUrl: atomFeed.logo,
      items: atomFeed.items.map((item) => ParsedArticle(
        guid: item.id ?? '',
        title: item.title ?? 'Untitled',
        link: item.links.firstWhere(
          (link) => link.rel == 'alternate',
          orElse: () => AtomLink(href: ''),
        ).href ?? '',
        description: _stripHtml(item.summary ?? ''),
        content: item.content ?? item.summary ?? '',
        publishedAt: item.published ?? item.updated ?? DateTime.now(),
        author: item.authors.isNotEmpty ? item.authors.first.name ?? '' : '',
        categories: item.categories.map((cat) => cat.term ?? '').where((cat) => cat.isNotEmpty).toList(),
        thumbnail: _extractAtomThumbnail(item),
      )).toList(),
    );
  }

  // Parse JSON Feed
  Future<ParsedFeed> _parseJSONFeed(String jsonText, String feedUrl) async {
    try {
      final Map<String, dynamic> data = json.decode(jsonText);
      
      // Validate JSON Feed
      if (!data.containsKey('version') || !data['version'].toString().startsWith('https://jsonfeed.org')) {
        throw Exception('Not a valid JSON Feed');
      }
      
      return ParsedFeed(
        type: FeedType.json,
        title: data['title'] ?? 'Untitled Feed',
        description: data['description'] ?? '',
        url: feedUrl,
        siteUrl: data['home_page_url'] ?? feedUrl,
        language: data['language'] ?? 'en',
        lastUpdated: DateTime.now(), // JSON Feed doesn't have a last updated field
        imageUrl: data['icon'] ?? data['favicon'],
        items: (data['items'] as List<dynamic>? ?? []).map((item) => ParsedArticle(
          guid: item['id'] ?? item['url'] ?? '',
          title: item['title'] ?? 'Untitled',
          link: item['url'] ?? item['external_url'] ?? '',
          description: _stripHtml(item['summary'] ?? ''),
          content: item['content_html'] ?? item['content_text'] ?? '',
          publishedAt: item['date_published'] != null 
            ? DateTime.parse(item['date_published']) 
            : DateTime.now(),
          author: item['author']?['name'] ?? 
                  (item['authors'] as List?)?.firstOrNull?['name'] ?? '',
          categories: (item['tags'] as List<dynamic>? ?? [])
            .map((tag) => tag.toString())
            .toList(),
          thumbnail: item['image'] ?? item['banner_image'],
        )).toList(),
      );
    } catch (e) {
      throw Exception('Invalid JSON Feed: ${e.toString()}');
    }
  }

  // Normalize and validate feed URL
  String _normalizeUrl(String url) {
    // Add protocol if missing
    if (!url.contains(RegExp(r'^https?://'))) {
      url = 'https://$url';
    }
    
    try {
      final uri = Uri.parse(url);
      return uri.toString();
    } catch (e) {
      throw Exception('Invalid URL: $url');
    }
  }

  // Validate and enhance feed data
  ParsedFeed _validateAndEnhanceFeed(ParsedFeed feed, String originalUrl) {
    // Ensure required fields
    feed.url = feed.url.isNotEmpty ? feed.url : originalUrl;
    feed.title = feed.title.isNotEmpty ? feed.title : 'Untitled Feed';
    
    // Process items
    feed.items = feed.items.map((item) {
      // Ensure GUID
      if (item.guid.isEmpty) {
        item.guid = item.link.isNotEmpty ? item.link : '${feed.url}#${item.title}';
      }
      
      // Clean and limit description
      if (item.description.isEmpty && item.content.isNotEmpty) {
        item.description = _stripHtml(item.content).substring(
          0, 
          item.content.length > 500 ? 500 : item.content.length
        );
      }
      
      // Extract first image if no thumbnail
      if (item.thumbnail == null && item.content.isNotEmpty) {
        final imgMatch = RegExp(r'<img[^>]+src=["\'](https?://[^"\']+)["\']').firstMatch(item.content);
        if (imgMatch != null) {
          item.thumbnail = imgMatch.group(1);
        }
      }
      
      return item;
    }).toList();
    
    // Sort items by date (newest first)
    feed.items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    
    return feed;
  }

  // Strip HTML tags from text
  String _stripHtml(String html) {
    if (html.isEmpty) return '';
    final document = html_parser.parse(html);
    return document.body?.text ?? '';
  }

  // Extract thumbnail from RSS item
  String? _extractThumbnail(RssItem item) {
    // Check media:thumbnail
    if (item.media?.thumbnails.isNotEmpty ?? false) {
      return item.media!.thumbnails.first.url;
    }
    
    // Check enclosure
    if (item.enclosure?.url != null && 
        item.enclosure!.type?.startsWith('image/') == true) {
      return item.enclosure!.url;
    }
    
    // Extract from content
    if (item.content?.value != null) {
      final imgMatch = RegExp(r'<img[^>]+src=["\'](https?://[^"\']+)["\']')
          .firstMatch(item.content!.value);
      if (imgMatch != null) {
        return imgMatch.group(1);
      }
    }
    
    return null;
  }

  // Extract thumbnail from Atom entry
  String? _extractAtomThumbnail(AtomItem item) {
    // Check media elements
    if (item.media?.thumbnails.isNotEmpty ?? false) {
      return item.media!.thumbnails.first.url;
    }
    
    // Check links for images
    for (final link in item.links) {
      if (link.type?.startsWith('image/') == true) {
        return link.href;
      }
    }
    
    // Extract from content
    if (item.content != null) {
      final imgMatch = RegExp(r'<img[^>]+src=["\'](https?://[^"\']+)["\']')
          .firstMatch(item.content!);
      if (imgMatch != null) {
        return imgMatch.group(1);
      }
    }
    
    return null;
  }

  // Test feed URL without fully parsing
  Future<FeedTestResult> testFeed(String url) async {
    try {
      final response = await _fetchFeed(url);
      final data = response.data;
      
      // Quick validation
      if (data is String) {
        if (data.contains('<rss') || 
            data.contains('<feed') || 
            data.contains('"version"') && data.contains('"items"')) {
          return FeedTestResult(
            valid: true,
            url: url,
            feedType: _detectFeedType(data),
          );
        }
      }
      
      return FeedTestResult(
        valid: false,
        url: url,
        error: 'Not a valid feed format',
      );
    } catch (e) {
      return FeedTestResult(
        valid: false,
        url: url,
        error: e.toString(),
      );
    }
  }

  // Detect feed type from content
  FeedType? _detectFeedType(String content) {
    if (content.contains('<rss')) return FeedType.rss;
    if (content.contains('<feed')) return FeedType.atom;
    if (content.contains('"version"') && content.contains('"items"')) return FeedType.json;
    return null;
  }

  // Get feed favicon
  Future<String?> getFeedFavicon(String siteUrl) async {
    try {
      final uri = Uri.parse(siteUrl);
      
      // Try common favicon locations
      final faviconUrls = [
        '${uri.origin}/favicon.ico',
        '${uri.origin}/favicon.png',
        '${uri.origin}/apple-touch-icon.png',
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
      
      // Use Google's favicon service as fallback
      return 'https://www.google.com/s2/favicons?domain=${uri.host}&sz=32';
    } catch (e) {
      return null;
    }
  }
}

// Data classes
enum FeedType { rss, atom, json }

class ParsedFeed {
  FeedType type;
  String title;
  String description;
  String url;
  String siteUrl;
  String? imageUrl;
  String language;
  DateTime lastUpdated;
  List<ParsedArticle> items;

  ParsedFeed({
    required this.type,
    required this.title,
    required this.description,
    required this.url,
    required this.siteUrl,
    this.imageUrl,
    required this.language,
    required this.lastUpdated,
    required this.items,
  });
}

class ParsedArticle {
  String guid;
  String title;
  String link;
  String description;
  String content;
  DateTime publishedAt;
  String author;
  List<String> categories;
  String? thumbnail;

  ParsedArticle({
    required this.guid,
    required this.title,
    required this.link,
    required this.description,
    required this.content,
    required this.publishedAt,
    required this.author,
    required this.categories,
    this.thumbnail,
  });
}

class FeedTestResult {
  final bool valid;
  final String url;
  final FeedType? feedType;
  final String? error;

  FeedTestResult({
    required this.valid,
    required this.url,
    this.feedType,
    this.error,
  });
}

class FeedParseException implements Exception {
  final String message;
  final String url;

  FeedParseException(this.message, this.url);

  @override
  String toString() => 'FeedParseException: $message (URL: $url)';
}