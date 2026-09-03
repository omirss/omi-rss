import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:serverpod/serverpod.dart';
import 'package:yaml/yaml.dart';
import '../endpoints/generation_endpoint.dart';

class GenerationService {
  final Session session;
  final Dio _dio;
  final Map<String, dynamic> _siteRules = {};
  final String _rulesPath = 'rules/sites';
  
  GenerationService(this.session) : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
    maxRedirects: 5,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  )) {
    _loadSiteRules();
  }

  // Generate feed from URL
  Future<GeneratedFeed> generateFeed(
    String url, {
    String format = 'rss',
    int limit = 50,
  }) async {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host.replaceAll('www.', '');
      
      // Check if we have a rule for this site
      final rule = _siteRules[domain] ?? await _findRuleForUrl(url);
      
      if (rule != null) {
        return await _generateWithRule(url, rule, format, limit);
      } else {
        // Try generic extraction
        return await _generateGeneric(url, format, limit);
      }
    } catch (e) {
      session.log('Feed generation error: $e');
      return GeneratedFeed(
        success: false,
        error: e.toString(),
        title: '',
        description: '',
        websiteUrl: url,
        feedUrl: url,
        items: [],
        format: format,
      );
    }
  }

  // Discover feeds from URL
  Future<List<DiscoveredFeed>> discoverFeeds(String url) async {
    final feeds = <DiscoveredFeed>[];
    
    try {
      // First check if URL is already a feed
      try {
        final response = await _dio.get(url);
        final content = response.data.toString();
        
        if (_isFeedContent(content)) {
          final feedType = _detectFeedType(content);
          feeds.add(DiscoveredFeed(
            url: url,
            title: _extractFeedTitle(content, feedType),
            type: feedType,
          ));
          return feeds;
        }
      } catch (_) {
        // Not a direct feed
      }
      
      // Fetch HTML page
      final response = await _dio.get(url);
      final doc = html_parser.parse(response.data);
      
      // Look for feed links
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
      
      // Check common feed paths
      final commonPaths = [
        '/feed', '/rss', '/atom', '/feed.xml', '/rss.xml',
        '/atom.xml', '/index.xml', '/feed/', '/rss/',
      ];
      
      for (final path in commonPaths) {
        final feedUrl = _resolveUrl(url, path);
        try {
          final response = await _dio.head(feedUrl);
          if (response.statusCode == 200) {
            feeds.add(DiscoveredFeed(
              url: feedUrl,
              title: 'RSS Feed',
              type: 'rss',
            ));
          }
        } catch (_) {
          // Ignore
        }
      }
    } catch (e) {
      session.log('Feed discovery error: $e');
    }
    
    // Remove duplicates
    final uniqueUrls = <String>{};
    return feeds.where((f) => uniqueUrls.add(f.url)).toList();
  }

  // Get supported sites
  Future<List<SupportedSite>> getSupportedSites() async {
    final sites = <SupportedSite>[];
    
    for (final entry in _siteRules.entries) {
      final rule = entry.value;
      sites.add(SupportedSite(
        domain: entry.key,
        name: rule['name'] ?? entry.key,
        description: rule['description'] ?? 'Feed generation for ${entry.key}',
        category: rule['category'] ?? 'general',
        exampleUrl: rule['example'] ?? 'https://${entry.key}',
        requiresJavaScript: rule['requiresJS'] ?? false,
      ));
    }
    
    sites.sort((a, b) => a.name.compareTo(b.name));
    return sites;
  }

  // Test a site rule
  Future<RuleTestResult> testRule(String url, Map<String, dynamic> rule) async {
    try {
      final items = await _extractItemsWithRule(url, rule, limit: 3);
      
      return RuleTestResult(
        success: items.isNotEmpty,
        items: items,
        debug: {
          'itemCount': items.length,
          'url': url,
          'rule': rule,
        },
      );
    } catch (e) {
      return RuleTestResult(
        success: false,
        items: [],
        error: e.toString(),
        debug: {
          'url': url,
          'rule': rule,
          'error': e.toString(),
        },
      );
    }
  }

  // Extract content from URL
  Future<ExtractedContent> extractContent(String url) async {
    try {
      final response = await _dio.get(url);
      final doc = html_parser.parse(response.data);
      
      // Remove script and style elements
      doc.querySelectorAll('script, style').forEach((e) => e.remove());
      
      // Extract metadata
      final title = doc.querySelector('title')?.text ??
                   doc.querySelector('h1')?.text ??
                   'Untitled';
      
      final author = _extractMeta(doc, ['author', 'article:author', 'twitter:creator']);
      final publishedDate = _extractMeta(doc, ['article:published_time', 'datePublished']);
      final imageUrl = _extractMeta(doc, ['og:image', 'twitter:image']);
      
      // Extract main content
      final contentElement = doc.querySelector('article') ??
                           doc.querySelector('[role="main"]') ??
                           doc.querySelector('main') ??
                           doc.body;
      
      final content = contentElement?.text ?? '';
      final words = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final wordCount = words.length;
      final readingTime = (wordCount / 200).ceil(); // 200 words per minute
      
      return ExtractedContent(
        title: title.trim(),
        content: content.trim(),
        author: author,
        publishedDate: publishedDate != null ? DateTime.tryParse(publishedDate) : null,
        imageUrl: imageUrl,
        wordCount: wordCount,
        readingTime: readingTime,
      );
    } catch (e) {
      session.log('Content extraction error: $e');
      throw Exception('Failed to extract content: $e');
    }
  }

  // Private methods
  void _loadSiteRules() {
    // Load built-in rules
    _siteRules.addAll(_getBuiltInRules());
    
    // Load YAML rules from files
    try {
      final rulesDir = Directory(_rulesPath);
      if (rulesDir.existsSync()) {
        for (final file in rulesDir.listSync(recursive: true)) {
          if (file is File && file.path.endsWith('.yaml')) {
            try {
              final content = file.readAsStringSync();
              final yaml = loadYaml(content);
              if (yaml is Map) {
                final domain = yaml['domain'] ?? _extractDomainFromPath(file.path);
                _siteRules[domain] = Map<String, dynamic>.from(yaml);
              }
            } catch (e) {
              session.log('Error loading rule ${file.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      session.log('Error loading site rules: $e');
    }
  }

  Map<String, dynamic> _getBuiltInRules() {
    return {
      'github.com': {
        'name': 'GitHub',
        'category': 'developer',
        'selectors': {
          'item': '.TimelineItem',
          'title': '.Link--primary',
          'url': '.Link--primary',
          'description': '.markdown-body',
          'author': '.author',
          'date': 'relative-time',
        },
      },
      'reddit.com': {
        'name': 'Reddit',
        'category': 'social',
        'selectors': {
          'item': '[data-testid="post-container"]',
          'title': 'h3',
          'url': 'a[data-click-id="body"]',
          'description': '[data-click-id="text"]',
          'author': 'a[href*="/user/"]',
        },
      },
      'news.ycombinator.com': {
        'name': 'Hacker News',
        'category': 'developer',
        'selectors': {
          'item': '.athing',
          'title': '.storylink, .titleline > a',
          'url': '.storylink, .titleline > a',
          'description': '.title',
          'author': '.hnuser',
        },
      },
    };
  }

  Future<Map<String, dynamic>?> _findRuleForUrl(String url) async {
    final uri = Uri.parse(url);
    
    // Check subdomains
    final parts = uri.host.split('.');
    for (int i = 0; i < parts.length - 1; i++) {
      final domain = parts.sublist(i).join('.');
      if (_siteRules.containsKey(domain)) {
        return _siteRules[domain];
      }
    }
    
    return null;
  }

  Future<GeneratedFeed> _generateWithRule(
    String url,
    Map<String, dynamic> rule,
    String format,
    int limit,
  ) async {
    try {
      final items = await _extractItemsWithRule(url, rule, limit: limit);
      
      // Get site info
      final response = await _dio.get(url);
      final doc = html_parser.parse(response.data);
      
      final title = doc.querySelector('title')?.text ?? 'Generated Feed';
      final description = _extractMeta(doc, ['description', 'og:description']) ?? '';
      
      return GeneratedFeed(
        success: true,
        title: title,
        description: description,
        websiteUrl: url,
        feedUrl: '$url/feed',
        items: items,
        format: format,
      );
    } catch (e) {
      throw Exception('Failed to generate with rule: $e');
    }
  }

  Future<GeneratedFeed> _generateGeneric(
    String url,
    String format,
    int limit,
  ) async {
    try {
      final response = await _dio.get(url);
      final doc = html_parser.parse(response.data);
      
      // Try to find article-like elements
      final articles = doc.querySelectorAll('article, .post, .entry, .item');
      final items = <GeneratedFeedItem>[];
      
      for (final article in articles.take(limit)) {
        final titleElement = article.querySelector('h1, h2, h3, h4, .title');
        final linkElement = article.querySelector('a');
        final contentElement = article.querySelector('p, .content, .summary');
        
        if (titleElement != null) {
          final title = titleElement.text.trim();
          final link = linkElement?.attributes['href'] ?? '';
          final fullUrl = _resolveUrl(url, link);
          
          items.add(GeneratedFeedItem(
            title: title,
            url: fullUrl,
            description: contentElement?.text.trim(),
            publishedAt: DateTime.now(),
            categories: [],
          ));
        }
      }
      
      final title = doc.querySelector('title')?.text ?? 'Generated Feed';
      final description = _extractMeta(doc, ['description', 'og:description']) ?? '';
      
      return GeneratedFeed(
        success: items.isNotEmpty,
        error: items.isEmpty ? 'No articles found' : null,
        title: title,
        description: description,
        websiteUrl: url,
        feedUrl: '$url/feed',
        items: items,
        format: format,
      );
    } catch (e) {
      throw Exception('Failed to generate generic feed: $e');
    }
  }

  Future<List<GeneratedFeedItem>> _extractItemsWithRule(
    String url,
    Map<String, dynamic> rule,
    {required int limit}
  ) async {
    final response = await _dio.get(url);
    final doc = html_parser.parse(response.data);
    
    final selectors = rule['selectors'] as Map<String, dynamic>;
    final itemSelector = selectors['item'];
    
    if (itemSelector == null) {
      throw Exception('No item selector in rule');
    }
    
    final items = <GeneratedFeedItem>[];
    final elements = doc.querySelectorAll(itemSelector);
    
    for (final element in elements.take(limit)) {
      final title = _extractFromElement(element, selectors['title']);
      final itemUrl = _extractFromElement(element, selectors['url'], isUrl: true);
      final description = _extractFromElement(element, selectors['description']);
      final author = _extractFromElement(element, selectors['author']);
      final dateStr = _extractFromElement(element, selectors['date']);
      final imageUrl = _extractFromElement(element, selectors['image'], isUrl: true);
      
      if (title != null && title.isNotEmpty) {
        items.add(GeneratedFeedItem(
          title: title,
          url: itemUrl != null ? _resolveUrl(url, itemUrl) : url,
          description: description,
          author: author,
          publishedAt: dateStr != null ? _parseDate(dateStr) : null,
          imageUrl: imageUrl != null ? _resolveUrl(url, imageUrl) : null,
          categories: [],
        ));
      }
    }
    
    return items;
  }

  String? _extractFromElement(
    dynamic element,
    dynamic selector, {
    bool isUrl = false,
  }) {
    if (selector == null || element == null) return null;
    
    try {
      final targetElement = selector is String
          ? element.querySelector(selector)
          : element;
      
      if (targetElement == null) return null;
      
      if (isUrl) {
        return targetElement.attributes['href'] ??
               targetElement.attributes['src'] ??
               targetElement.text.trim();
      } else {
        return targetElement.text.trim();
      }
    } catch (e) {
      return null;
    }
  }

  String? _extractMeta(dynamic doc, List<String> names) {
    for (final name in names) {
      final element = doc.querySelector('meta[name="$name"], meta[property="$name"]');
      if (element != null) {
        return element.attributes['content'];
      }
    }
    return null;
  }

  DateTime? _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      // Try other formats
      return null;
    }
  }

  bool _isFeedContent(String content) {
    return content.contains('<rss') ||
           content.contains('<feed') ||
           content.contains('<channel>') ||
           (content.trim().startsWith('{') && content.contains('"items"'));
  }

  String _detectFeedType(String content) {
    if (content.contains('<rss')) return 'rss';
    if (content.contains('<feed')) return 'atom';
    if (content.trim().startsWith('{')) return 'json';
    return 'unknown';
  }

  String _extractFeedTitle(String content, String type) {
    try {
      if (type == 'rss' || type == 'atom') {
        final doc = html_parser.parse(content);
        return doc.querySelector('title')?.text ?? 'RSS Feed';
      } else if (type == 'json') {
        final json = jsonDecode(content);
        return json['title'] ?? 'JSON Feed';
      }
    } catch (e) {
      // Ignore
    }
    return 'Feed';
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

  String _extractDomainFromPath(String path) {
    final parts = path.split('/').last.split('.');
    if (parts.length > 1) {
      parts.removeLast(); // Remove extension
    }
    return parts.join('.');
  }
}