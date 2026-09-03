import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/feed.dart';
import '../models/article.dart';
import 'generation_rule.dart';
import 'robots_service.dart';

/// Feed generation service (RSSHub functionality)
class GenerationService {
  final Dio _dio;
  final Map<String, GenerationRule> _rules = {};
  final RobotsService _robotsService;
  final RateLimiter _rateLimiter;
  bool _rulesLoaded = false;
  
  GenerationService({
    Dio? dio,
    RobotsService? robotsService,
  }) : _dio = dio ?? Dio(),
        _robotsService = robotsService ?? RobotsService(),
        _rateLimiter = RateLimiter() {
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 5);
    _dio.options.headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };
  }
  
  /// Generate feed from URL
  Future<GeneratedFeed> generateFeed(
    String url, {
    FeedFormat format = FeedFormat.rss,
    bool includeFullText = false,
    bool applyRules = true,
  }) async {
    try {
      // Start timer for timeout enforcement
      final startTime = DateTime.now();
      
      // Validate and normalize URL
      url = _validateAndNormalizeUrl(url);
      
      // Check robots.txt
      final isAllowed = await _robotsService.isAllowed(
        url,
        userAgent: 'RSSGenerator/1.0',
      );
      
      if (!isAllowed) {
        throw GenerationException('URL is disallowed by robots.txt');
      }
      
      // Get crawl delay
      final crawlDelay = await _robotsService.getCrawlDelay(
        url,
        userAgent: 'RSSGenerator/1.0',
      );
      
      // Apply rate limiting
      final uri = Uri.parse(url);
      await _rateLimiter.waitIfNeeded(uri.host, customDelay: crawlDelay);
      
      // Load rules if not already loaded
      if (!_rulesLoaded) {
        await _loadRules();
      }
      
      // Detect site and find matching rule
      final rule = applyRules ? _detectSiteRule(url) : null;
      
      if (rule != null) {
        // Apply site-specific rule
        return await _applyRule(url, rule, format, includeFullText, startTime);
      } else {
        // Fallback to generic extraction
        return await _genericExtraction(url, format, includeFullText, startTime);
      }
    } catch (e) {
      throw GenerationException('Failed to generate feed: $e');
    }
  }
  
  /// Preview feed generation
  Future<FeedPreview> previewFeed(String url) async {
    try {
      final generated = await generateFeed(
        url,
        format: FeedFormat.rss,
        includeFullText: true,
      );
      
      // Take first 3 articles for preview
      final previewArticles = generated.articles.take(3).toList();
      
      return FeedPreview(
        feedUrl: generated.feedUrl,
        title: generated.feed.title,
        description: generated.feed.description,
        articles: previewArticles,
        generationTimeMs: generated.generationTimeMs,
      );
    } catch (e) {
      throw GenerationException('Failed to preview feed: $e');
    }
  }
  
  /// Test a specific rule
  Future<bool> testRule(String url, GenerationRule rule) async {
    try {
      final result = await _applyRule(
        url,
        rule,
        FeedFormat.rss,
        false,
        DateTime.now(),
      );
      return result.articles.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  
  /// Validate and normalize URL
  String _validateAndNormalizeUrl(String url) {
    // Add protocol if missing
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    
    // Validate URL format
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) {
        throw GenerationException('Invalid URL format');
      }
      return uri.toString();
    } catch (e) {
      throw GenerationException('Invalid URL: $url');
    }
  }
  
  /// Load generation rules from YAML files
  Future<void> _loadRules() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final rulesDir = Directory(p.join(appDir.path, 'rules', 'sites'));
      
      if (await rulesDir.exists()) {
        await for (final file in rulesDir.list()) {
          if (file is File && file.path.endsWith('.yaml')) {
            try {
              final content = await file.readAsString();
              final yaml = loadYaml(content) as Map;
              final rule = GenerationRule.fromYaml(yaml);
              _rules[rule.site] = rule;
            } catch (e) {
              print('Failed to load rule from ${file.path}: $e');
            }
          }
        }
      }
      
      // Load built-in rules
      _loadBuiltInRules();
      
      _rulesLoaded = true;
    } catch (e) {
      print('Failed to load rules: $e');
      _rulesLoaded = true; // Prevent repeated attempts
    }
  }
  
  /// Load built-in rules (hardcoded for common sites)
  void _loadBuiltInRules() {
    // Twitter/X
    _rules['twitter.com'] = GenerationRule(
      site: 'twitter.com',
      name: 'Twitter/X',
      patterns: [
        RulePattern(pattern: '/{username}', example: '/elonmusk'),
        RulePattern(pattern: '/search?q={query}', example: '/search?q=flutter'),
      ],
      selectors: RuleSelectors(
        feedTitle: RuleSelector(css: 'h2[role="heading"]', attribute: 'text'),
        feedDescription: RuleSelector(css: 'div[data-testid="UserDescription"]', attribute: 'text'),
        items: RuleSelector(css: 'article[role="article"]'),
        itemTitle: RuleSelector(css: 'div[lang]', attribute: 'text'),
        itemLink: RuleSelector(css: 'a[href*="/status/"]', attribute: 'href'),
        itemContent: RuleSelector(css: 'div[lang]', attribute: 'html'),
        itemDate: RuleSelector(css: 'time', attribute: 'datetime'),
        itemAuthor: RuleSelector(css: 'span[data-testid="User-Name"]', attribute: 'text'),
      ),
      transforms: [
        RuleTransform(action: 'remove', selector: '.promotional'),
        RuleTransform(action: 'absolute_urls', base: 'https://twitter.com'),
      ],
      javascriptRequired: true,
    );
    
    // GitHub
    _rules['github.com'] = GenerationRule(
      site: 'github.com',
      name: 'GitHub',
      patterns: [
        RulePattern(pattern: '/{owner}/{repo}', example: '/flutter/flutter'),
        RulePattern(pattern: '/{owner}/{repo}/releases', example: '/flutter/flutter/releases'),
        RulePattern(pattern: '/{owner}/{repo}/commits', example: '/flutter/flutter/commits'),
      ],
      selectors: RuleSelectors(
        feedTitle: RuleSelector(css: 'h1 strong a', attribute: 'text'),
        feedDescription: RuleSelector(css: 'p.f4', attribute: 'text'),
        items: RuleSelector(css: '.Box-row'),
        itemTitle: RuleSelector(css: 'a.Link--primary', attribute: 'text'),
        itemLink: RuleSelector(css: 'a.Link--primary', attribute: 'href'),
        itemContent: RuleSelector(css: '.markdown-body', attribute: 'html'),
        itemDate: RuleSelector(css: 'relative-time', attribute: 'datetime'),
        itemAuthor: RuleSelector(css: 'a.commit-author', attribute: 'text'),
      ),
      transforms: [
        RuleTransform(action: 'absolute_urls', base: 'https://github.com'),
      ],
    );
    
    // Reddit
    _rules['reddit.com'] = GenerationRule(
      site: 'reddit.com',
      name: 'Reddit',
      patterns: [
        RulePattern(pattern: '/r/{subreddit}', example: '/r/programming'),
        RulePattern(pattern: '/user/{username}', example: '/user/spez'),
      ],
      selectors: RuleSelectors(
        feedTitle: RuleSelector(css: 'h1', attribute: 'text'),
        feedDescription: RuleSelector(css: 'div[data-testid="subreddit-sidebar"]', attribute: 'text'),
        items: RuleSelector(css: 'div[data-testid="post-container"]'),
        itemTitle: RuleSelector(css: 'h3', attribute: 'text'),
        itemLink: RuleSelector(css: 'a[data-click-id="body"]', attribute: 'href'),
        itemContent: RuleSelector(css: 'div[data-click-id="text"]', attribute: 'html'),
        itemDate: RuleSelector(css: 'span[data-testid="post_timestamp"]', attribute: 'text'),
        itemAuthor: RuleSelector(css: 'a[data-testid="post_author_link"]', attribute: 'text'),
      ),
      transforms: [
        RuleTransform(action: 'absolute_urls', base: 'https://reddit.com'),
      ],
    );
  }
  
  /// Detect site rule from URL
  GenerationRule? _detectSiteRule(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.replaceAll('www.', '');
      
      // Direct match
      if (_rules.containsKey(host)) {
        return _rules[host];
      }
      
      // Check if it's a subdomain
      final parts = host.split('.');
      if (parts.length > 2) {
        final mainDomain = parts.sublist(parts.length - 2).join('.');
        if (_rules.containsKey(mainDomain)) {
          return _rules[mainDomain];
        }
      }
      
      // Alias check (e.g., x.com -> twitter.com)
      if (host == 'x.com') {
        return _rules['twitter.com'];
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// Apply site-specific rule
  Future<GeneratedFeed> _applyRule(
    String url,
    GenerationRule rule,
    FeedFormat format,
    bool includeFullText,
    DateTime startTime,
  ) async {
    // Check timeout
    _checkTimeout(startTime);
    
    // Check robots.txt
    final userAgent = rule.userAgent ?? _dio.options.headers['User-Agent'];
    final isAllowed = await _robotsService.isAllowed(url, userAgent: userAgent);
    if (!isAllowed) {
      throw GenerationException('Access denied by robots.txt');
    }
    
    // Get crawl delay from robots.txt
    final crawlDelay = await _robotsService.getCrawlDelay(url, userAgent: userAgent);
    
    // Apply rate limiting
    final uri = Uri.parse(url);
    final delay = crawlDelay ?? 
                  (rule.rateLimit > 0 ? Duration(milliseconds: rule.rateLimit) : null);
    if (delay != null) {
      await _rateLimiter.waitIfNeeded(uri.host, customDelay: delay);
    }
    
    // Fetch page content
    final response = await _dio.get(url, options: Options(
      headers: rule.userAgent != null ? {'User-Agent': rule.userAgent} : null,
    ));
    
    // Parse HTML
    final document = html_parser.parse(response.data);
    
    // Extract feed information
    final feedTitle = _extractText(document, rule.selectors.feedTitle) ?? 'Generated Feed';
    final feedDescription = _extractText(document, rule.selectors.feedDescription);
    
    // Extract items
    final itemElements = document.querySelectorAll(rule.selectors.items.css);
    final articles = <Article>[];
    
    for (final element in itemElements.take(20)) { // Limit to 20 items
      _checkTimeout(startTime);
      
      final title = _extractTextFromElement(element, rule.selectors.itemTitle);
      if (title == null || title.isEmpty) continue;
      
      final link = _extractTextFromElement(element, rule.selectors.itemLink);
      final content = _extractTextFromElement(element, rule.selectors.itemContent);
      final dateStr = _extractTextFromElement(element, rule.selectors.itemDate);
      final author = _extractTextFromElement(element, rule.selectors.itemAuthor);
      
      // Apply transforms
      String? processedContent = content;
      String? processedLink = link;
      
      for (final transform in rule.transforms) {
        switch (transform.action) {
          case 'remove':
            if (transform.selector != null && processedContent != null) {
              final contentDoc = html_parser.parseFragment(processedContent);
              contentDoc.querySelectorAll(transform.selector!).forEach((e) => e.remove());
              processedContent = contentDoc.outerHtml;
            }
            break;
          case 'absolute_urls':
            if (transform.base != null && processedLink != null) {
              processedLink = _makeAbsoluteUrl(processedLink, transform.base!);
            }
            break;
          case 'clean_tracking':
            processedLink = _cleanTrackingParams(processedLink ?? '');
            break;
        }
      }
      
      articles.add(Article(
        feedId: '', // Will be set later
        guid: processedLink ?? title,
        title: title,
        content: processedContent,
        url: processedLink ?? url,
        author: author,
        publishedAt: dateStr != null ? _parseDate(dateStr) : null,
      ));
    }
    
    // Create feed
    final feed = Feed(
      url: url,
      title: feedTitle,
      description: feedDescription,
      type: FeedType.rss,
    );
    
    // Generate feed URL
    final feedUrl = await _generateFeedUrl(url, format);
    
    return GeneratedFeed(
      feed: feed,
      articles: articles,
      feedUrl: feedUrl,
      format: format,
      generationTimeMs: DateTime.now().difference(startTime).inMilliseconds,
    );
  }
  
  /// Generic extraction for sites without rules
  Future<GeneratedFeed> _genericExtraction(
    String url,
    FeedFormat format,
    bool includeFullText,
    DateTime startTime,
  ) async {
    _checkTimeout(startTime);
    
    // Check robots.txt
    final userAgent = _dio.options.headers['User-Agent'] as String;
    final isAllowed = await _robotsService.isAllowed(url, userAgent: userAgent);
    if (!isAllowed) {
      throw GenerationException('Access denied by robots.txt');
    }
    
    // Apply rate limiting with default delay
    final uri = Uri.parse(url);
    final crawlDelay = await _robotsService.getCrawlDelay(url, userAgent: userAgent);
    await _rateLimiter.waitIfNeeded(uri.host, customDelay: crawlDelay);
    
    final response = await _dio.get(url);
    final document = html_parser.parse(response.data);
    
    // Try to extract title
    final title = document.querySelector('title')?.text ?? 
                  document.querySelector('h1')?.text ?? 
                  'Generated Feed';
    
    // Try to extract description
    final description = document.querySelector('meta[name="description"]')?.attributes['content'] ??
                       document.querySelector('meta[property="og:description"]')?.attributes['content'];
    
    // Try to find article-like elements
    final articles = <Article>[];
    
    // Common article selectors
    final articleSelectors = [
      'article',
      '.post',
      '.entry',
      '.item',
      '[itemtype*="Article"]',
      '[itemtype*="BlogPosting"]',
    ];
    
    for (final selector in articleSelectors) {
      final elements = document.querySelectorAll(selector);
      if (elements.isNotEmpty) {
        for (final element in elements.take(20)) {
          _checkTimeout(startTime);
          
          // Extract article data
          final articleTitle = element.querySelector('h1, h2, h3, h4')?.text;
          if (articleTitle == null || articleTitle.isEmpty) continue;
          
          final articleLink = element.querySelector('a')?.attributes['href'];
          final articleContent = element.querySelector('.content, .summary, p')?.innerHtml;
          final articleDate = element.querySelector('time, .date')?.attributes['datetime'] ??
                             element.querySelector('time, .date')?.text;
          
          articles.add(Article(
            feedId: '',
            guid: articleLink ?? articleTitle,
            title: articleTitle,
            content: articleContent,
            url: articleLink != null ? _makeAbsoluteUrl(articleLink, url) : url,
            publishedAt: articleDate != null ? _parseDate(articleDate) : null,
          ));
        }
        
        if (articles.isNotEmpty) break;
      }
    }
    
    final feed = Feed(
      url: url,
      title: title,
      description: description,
      type: FeedType.rss,
    );
    
    final feedUrl = await _generateFeedUrl(url, format);
    
    return GeneratedFeed(
      feed: feed,
      articles: articles,
      feedUrl: feedUrl,
      format: format,
      generationTimeMs: DateTime.now().difference(startTime).inMilliseconds,
    );
  }
  
  /// Extract text using selector
  String? _extractText(html_dom.Document document, RuleSelector selector) {
    final element = document.querySelector(selector.css);
    return _extractFromElement(element, selector.attribute);
  }
  
  /// Extract text from element using selector
  String? _extractTextFromElement(html_dom.Element parent, RuleSelector selector) {
    final element = parent.querySelector(selector.css);
    return _extractFromElement(element, selector.attribute);
  }
  
  /// Extract value from element based on attribute
  String? _extractFromElement(html_dom.Element? element, String attribute) {
    if (element == null) return null;
    
    switch (attribute) {
      case 'text':
        return element.text.trim();
      case 'html':
        return element.innerHtml;
      case 'href':
      case 'src':
      case 'datetime':
        return element.attributes[attribute];
      default:
        return element.attributes[attribute] ?? element.text.trim();
    }
  }
  
  /// Make URL absolute
  String _makeAbsoluteUrl(String url, String base) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    try {
      final baseUri = Uri.parse(base);
      final resolved = baseUri.resolve(url);
      return resolved.toString();
    } catch (e) {
      return url;
    }
  }
  
  /// Clean tracking parameters from URL
  String _cleanTrackingParams(String url) {
    try {
      final uri = Uri.parse(url);
      final cleanParams = <String, dynamic>{};
      
      // Common tracking parameters to remove
      final trackingParams = [
        'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
        'fbclid', 'gclid', 'msclkid', 'mc_cid', 'mc_eid',
      ];
      
      uri.queryParameters.forEach((key, value) {
        if (!trackingParams.contains(key)) {
          cleanParams[key] = value;
        }
      });
      
      return uri.replace(queryParameters: cleanParams).toString();
    } catch (e) {
      return url;
    }
  }
  
  /// Parse date string
  DateTime? _parseDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      // Try common formats
      // Add more date parsing logic as needed
      return null;
    }
  }
  
  /// Generate feed URL
  Future<String> _generateFeedUrl(String sourceUrl, FeedFormat format) async {
    // In a real implementation, this would save the generated feed
    // and return a URL to access it
    final hash = sourceUrl.hashCode.toString();
    return 'https://rss-reader.app/generated/$hash.${format.extension}';
  }
  
  /// Check timeout
  void _checkTimeout(DateTime startTime) {
    if (DateTime.now().difference(startTime).inSeconds >= 5) {
      throw GenerationException('Generation timeout exceeded');
    }
  }
  
  /// Get available site rules
  List<GenerationRule> getAvailableRules() {
    if (!_rulesLoaded) {
      _loadBuiltInRules();
      _rulesLoaded = true;
    }
    return _rules.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}

/// Feed format enum
enum FeedFormat {
  rss('rss', 'xml'),
  atom('atom', 'xml'),
  json('json', 'json');
  
  final String name;
  final String extension;
  
  const FeedFormat(this.name, this.extension);
}

/// Generated feed result
class GeneratedFeed {
  final Feed feed;
  final List<Article> articles;
  final String feedUrl;
  final FeedFormat format;
  final int generationTimeMs;
  
  GeneratedFeed({
    required this.feed,
    required this.articles,
    required this.feedUrl,
    required this.format,
    required this.generationTimeMs,
  });
}

/// Feed preview
class FeedPreview {
  final String feedUrl;
  final String title;
  final String? description;
  final List<Article> articles;
  final int generationTimeMs;
  
  FeedPreview({
    required this.feedUrl,
    required this.title,
    this.description,
    required this.articles,
    required this.generationTimeMs,
  });
}

/// Generation exception
class GenerationException implements Exception {
  final String message;
  
  GenerationException(this.message);
  
  @override
  String toString() => message;
}