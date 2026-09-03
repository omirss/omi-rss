import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart' as xml;
import 'package:html/parser.dart' as html_parser;
import 'package:logger/logger.dart';

final RegExp _imgSrcRegex =
    RegExp(r"""<img[^>]+src=["'](https?://[^"']+)["']""");

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
    final document = xml.XmlDocument.parse(xmlText);

    final channel = document.findAllElements('channel').firstOrNull;
    if (channel != null) {
      return _convertRssFeed(document, channel, feedUrl);
    }

    final feed = document.findAllElements('feed').firstOrNull;
    if (feed != null) {
      return _convertAtomFeed(feed, feedUrl);
    }

    throw Exception('Unknown XML feed format');
  }

  // Convert RSS feed to ParsedFeed
  ParsedFeed _convertRssFeed(xml.XmlDocument document, xml.XmlElement channel, String feedUrl) {
    String? image;
    final imageEl = channel.findElements('image').firstOrNull;
    if (imageEl != null) {
      image = _text(imageEl, 'url');
    }

    return ParsedFeed(
      type: FeedType.rss,
      title: _text(channel, 'title') ?? 'Untitled Feed',
      description: _text(channel, 'description') ?? '',
      url: feedUrl,
      siteUrl: _text(channel, 'link') ?? feedUrl,
      language: _text(channel, 'language') ?? 'en',
      lastUpdated: _parseDate(_text(channel, 'lastBuildDate') ?? _text(channel, 'pubDate')) ?? DateTime.now(),
      imageUrl: image,
      items: channel.findAllElements('item').map((item) => ParsedArticle(
        guid: _text(item, 'guid') ?? _text(item, 'link') ?? '',
        title: _text(item, 'title') ?? 'Untitled',
        link: _text(item, 'link') ?? '',
        description: _stripHtml(_text(item, 'description') ?? ''),
        content: _text(item, 'content:encoded') ?? _text(item, 'description') ?? '',
        publishedAt: _parseDate(_text(item, 'pubDate')) ?? DateTime.now(),
        author: _text(item, 'author') ?? _text(item, 'dc:creator') ?? '',
        categories: [
          ...item.findElements('category').map((cat) => cat.innerText.trim()),
        ].where((cat) => cat.isNotEmpty).toList(),
        thumbnail: _extractThumbnail(item),
      )).toList(),
    );
  }

  // Convert Atom feed to ParsedFeed
  ParsedFeed _convertAtomFeed(xml.XmlElement feed, String feedUrl) {
    String siteUrl = feedUrl;
    for (final link in feed.findElements('link')) {
      if (link.getAttribute('rel') == 'alternate' || link.getAttribute('rel') == null) {
        final href = link.getAttribute('href');
        if (href != null && href.isNotEmpty) {
          siteUrl = href;
          break;
        }
      }
    }

    return ParsedFeed(
      type: FeedType.atom,
      title: _text(feed, 'title') ?? 'Untitled Feed',
      description: _text(feed, 'subtitle') ?? '',
      url: feedUrl,
      siteUrl: siteUrl,
      language: _text(feed, 'language') ?? 'en',
      lastUpdated: _parseDate(_text(feed, 'updated')) ?? DateTime.now(),
      imageUrl: _text(feed, 'logo'),
      items: feed.findElements('entry').map((entry) {
        String entryLink = '';
        for (final link in entry.findElements('link')) {
          if (link.getAttribute('rel') == 'alternate' || link.getAttribute('rel') == null) {
            final href = link.getAttribute('href');
            if (href != null && href.isNotEmpty) {
              entryLink = href;
              break;
            }
          }
        }
        return ParsedArticle(
          guid: _text(entry, 'id') ?? '',
          title: _text(entry, 'title') ?? 'Untitled',
          link: entryLink,
          description: _stripHtml(_text(entry, 'summary') ?? ''),
          content: _text(entry, 'content') ?? _text(entry, 'summary') ?? '',
          publishedAt: _parseDate(_text(entry, 'published')) ?? _parseDate(_text(entry, 'updated')) ?? DateTime.now(),
          author: _text(entry, 'author') != null ? _text(entry, 'author')! : '',
          categories: [
            ...entry.findElements('category').map((cat) => cat.getAttribute('term') ?? ''),
          ].where((cat) => cat.isNotEmpty).toList(),
          thumbnail: _extractAtomThumbnail(entry),
        );
      }).toList(),
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
        final imgMatch = _imgSrcRegex.firstMatch(item.content);
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
  String? _extractThumbnail(xml.XmlElement item) {
    // Check media:thumbnail
    final mediaThumb = item.findAllElements('media:thumbnail').firstOrNull;
    if (mediaThumb != null) {
      return mediaThumb.getAttribute('url');
    }

    // Check enclosure
    final enclosure = item.findElements('enclosure').firstOrNull;
    if (enclosure != null && (enclosure.getAttribute('type') ?? '').startsWith('image/')) {
      return enclosure.getAttribute('url');
    }

    // Extract from content
    final content = _text(item, 'content:encoded') ?? _text(item, 'description');
    if (content != null) {
      final imgMatch = _imgSrcRegex.firstMatch(content);
      if (imgMatch != null) {
        return imgMatch.group(1);
      }
    }

    return null;
  }

  // Extract thumbnail from Atom entry
  String? _extractAtomThumbnail(xml.XmlElement entry) {
    // Check media elements
    final mediaThumb = entry.findAllElements('media:thumbnail').firstOrNull;
    if (mediaThumb != null) {
      return mediaThumb.getAttribute('url');
    }

    // Check links for images
    for (final link in entry.findElements('link')) {
      if ((link.getAttribute('type') ?? '').startsWith('image/')) {
        return link.getAttribute('href');
      }
    }

    // Extract from content
    final content = _text(entry, 'content');
    if (content != null) {
      final imgMatch = _imgSrcRegex.firstMatch(content);
      if (imgMatch != null) {
        return imgMatch.group(1);
      }
    }

    return null;
  }

  // XML helpers
  String? _text(xml.XmlElement element, String tag) {
    final el = element.findElements(tag).firstOrNull;
    return el?.innerText.trim();
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    final match = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})\w*\s+(\d{4})[\s,T]+(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(raw);
    if (match == null) return null;
    final month = _months[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      match.group(6) != null ? int.parse(match.group(6)!) : 0,
    );
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