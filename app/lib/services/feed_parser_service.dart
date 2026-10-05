import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart' as xml;
import 'package:html/parser.dart' as html_parser;
import 'package:logger/logger.dart';
import '../core/parsers/feed_dates.dart';

final RegExp _imgSrcRegex =
    RegExp(r"""<img[^>]+src=["'](https?://[^"']+)["']""");

class FeedParserService {
  final Dio _dio;
  final Logger _logger = Logger();

  /// Feed responses larger than this are aborted before being buffered.
  static const int maxFeedBytes = 5 * 1024 * 1024;

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

  // Fetch feed content with a hard response-size ceiling. Feed URLs and
  // contents are never sent to third-party services.
  Future<Response<String>> _fetchFeed(String url) async {
    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(responseType: ResponseType.stream),
    );

    if (response.statusCode != 200) {
      final body = response.data;
      if (body != null) {
        await body.stream.drain<void>().catchError((_) {});
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: Response<ResponseBody>(
          requestOptions: response.requestOptions,
          statusCode: response.statusCode,
          statusMessage: response.statusMessage,
        ),
        message: 'HTTP ${response.statusCode}: ${response.statusMessage}',
      );
    }

    final body = await _readCapped(response.data!, url);
    return Response<String>(
      requestOptions: response.requestOptions,
      statusCode: response.statusCode,
      headers: response.headers,
      data: body,
    );
  }

  Future<String> _readCapped(ResponseBody body, String url) async {
    final bytes = <int>[];
    var received = 0;
    final completer = Completer<String>();
    late final StreamSubscription<List<int>> subscription;
    subscription = body.stream.listen(
      (chunk) {
        received += chunk.length;
        if (received > maxFeedBytes) {
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.completeError(FeedParseException(
              'Feed response exceeds $maxFeedBytes bytes: $url',
              url,
            ));
          }
          return;
        }
        bytes.addAll(chunk);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(utf8.decode(bytes, allowMalformed: true));
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    return completer.future;
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
      image = _resolveUrl(_text(imageEl, 'url'), feedUrl);
    }

    return ParsedFeed(
      type: FeedType.rss,
      title: _text(channel, 'title') ?? 'Untitled Feed',
      description: _text(channel, 'description') ?? '',
      url: feedUrl,
      siteUrl: _resolveUrl(_text(channel, 'link'), feedUrl) ?? feedUrl,
      language: _text(channel, 'language') ?? 'en',
      lastUpdated: parseFeedDate(_text(channel, 'lastBuildDate') ?? _text(channel, 'pubDate')) ?? DateTime.now(),
      imageUrl: image,
      items: channel.findAllElements('item').map((item) => ParsedArticle(
        guid: _text(item, 'guid') ?? _text(item, 'link') ?? '',
        title: _text(item, 'title') ?? 'Untitled',
        link: _resolveUrl(_text(item, 'link'), feedUrl) ?? '',
        description: _stripHtml(_text(item, 'description') ?? ''),
        content: _text(item, 'content:encoded') ?? _text(item, 'description') ?? '',
        publishedAt: parseFeedDate(_text(item, 'pubDate')) ?? DateTime.now(),
        author: _text(item, 'author') ?? _text(item, 'dc:creator') ?? '',
        categories: [
          ...item.findElements('category').map((cat) => cat.innerText.trim()),
        ].where((cat) => cat.isNotEmpty).toList(),
        thumbnail: _resolveUrl(_extractThumbnail(item), feedUrl),
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
          siteUrl = _resolveUrl(href, feedUrl)!;
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
      lastUpdated: parseFeedDate(_text(feed, 'updated')) ?? DateTime.now(),
      imageUrl: _resolveUrl(_text(feed, 'logo'), feedUrl),
      items: feed.findElements('entry').map((entry) {
        String entryLink = '';
        for (final link in entry.findElements('link')) {
          if (link.getAttribute('rel') == 'alternate' || link.getAttribute('rel') == null) {
            final href = link.getAttribute('href');
            if (href != null && href.isNotEmpty) {
              entryLink = _resolveUrl(href, feedUrl)!;
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
          publishedAt: parseFeedDate(_text(entry, 'published')) ?? parseFeedDate(_text(entry, 'updated')) ?? DateTime.now(),
          author: _text(entry, 'author') != null ? _text(entry, 'author')! : '',
          categories: [
            ...entry.findElements('category').map((cat) => cat.getAttribute('term') ?? ''),
          ].where((cat) => cat.isNotEmpty).toList(),
          thumbnail: _resolveUrl(_extractAtomThumbnail(entry), feedUrl),
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
        siteUrl: _resolveUrl(data['home_page_url'] as String?, feedUrl) ?? feedUrl,
        language: data['language'] ?? 'en',
        lastUpdated: DateTime.now(), // JSON Feed doesn't have a last updated field
        imageUrl: _resolveUrl(data['icon'] as String? ?? data['favicon'] as String?, feedUrl),
        items: _parseJsonItems(data['items'] as List<dynamic>? ?? [], feedUrl),
      );
    } catch (e) {
      throw Exception('Invalid JSON Feed: ${e.toString()}');
    }
  }

  // Parse JSON Feed items independently so one malformed entry cannot
  // abort the whole feed.
  List<ParsedArticle> _parseJsonItems(List<dynamic> rawItems, String feedUrl) {
    final items = <ParsedArticle>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      try {
        items.add(_parseJsonItem(Map<String, dynamic>.from(raw), feedUrl));
      } catch (e) {
        _logger.w('Skipping malformed JSON Feed item', error: e);
      }
    }
    return items;
  }

  ParsedArticle _parseJsonItem(Map<String, dynamic> item, String feedUrl) {
    return ParsedArticle(
      guid: item['id']?.toString() ?? item['url']?.toString() ?? '',
      title: item['title']?.toString() ?? 'Untitled',
      link: _resolveUrl(
              (item['url'] ?? item['external_url'])?.toString(), feedUrl) ??
          '',
      description: _stripHtml(item['summary']?.toString() ?? ''),
      content: item['content_html']?.toString() ??
          item['content_text']?.toString() ??
          '',
      publishedAt: parseFeedDate(item['date_published'] as String?) ??
          parseFeedDate(item['date_modified'] as String?) ??
          DateTime.now(),
      author: _jsonAuthor(item),
      categories: (item['tags'] as List<dynamic>? ?? [])
          .map((tag) => tag.toString())
          .toList(),
      thumbnail: _resolveUrl(
          (item['image'] ?? item['banner_image'])?.toString(), feedUrl),
    );
  }

  String _jsonAuthor(Map<String, dynamic> item) {
    final author = item['author'];
    if (author is Map && author['name'] is String) {
      return author['name'] as String;
    }
    final authors = item['authors'];
    if (authors is List) {
      for (final a in authors) {
        if (a is Map && a['name'] is String) return a['name'] as String;
      }
    }
    return '';
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
        final stripped = _stripHtml(item.content);
        item.description =
            stripped.length > 500 ? stripped.substring(0, 500) : stripped;
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

  // Resolve a possibly relative link against the feed document URL
  String? _resolveUrl(String? value, String base) {
    if (value == null || value.isEmpty) return value;
    try {
      return Uri.parse(base).resolve(value).toString();
    } catch (_) {
      return value;
    }
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

      // No icon. Subscription domains are never disclosed to
      // third-party favicon services.
      return null;
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