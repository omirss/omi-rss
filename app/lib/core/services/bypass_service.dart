import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'extraction_service.dart';
import 'puppeteer_service.dart';

/// Hidden paywall bypass service - activated by triple-tap on settings
class BypassService {
  final Dio _dio;
  final ExtractionService _extractionService;
  final PuppeteerService _puppeteerService;
  final Map<String, BypassRule> _rules = {};
  bool _isEnabled = false;
  bool _hasAcceptedTerms = false;
  
  // Archive services
  static const String _archivePhUrl = 'https://archive.ph';
  static const String _waybackUrl = 'https://web.archive.org';
  static const String _twelveFtUrl = 'https://12ft.io';
  
  // Common bypass headers
  static const Map<String, String> _googleBotHeaders = {
    'User-Agent': 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Accept-Encoding': 'gzip, deflate',
    'DNT': '1',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
  };
  
  static const Map<String, String> _bingBotHeaders = {
    'User-Agent': 'Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)',
  };
  
  static const Map<String, String> _facebookBotHeaders = {
    'User-Agent': 'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
  };
  
  BypassService({
    Dio? dio,
    ExtractionService? extractionService,
    PuppeteerService? puppeteerService,
  }) : _dio = dio ?? Dio(),
       _extractionService = extractionService ?? ExtractionService(),
       _puppeteerService = puppeteerService ?? PuppeteerService() {
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 20);
    _dio.options.followRedirects = true;
    _dio.options.maxRedirects = 5;
    
    _loadRules();
    _loadSettings();
  }
  
  /// Check if bypass is enabled
  bool get isEnabled => _isEnabled && _hasAcceptedTerms;
  
  /// Enable bypass (requires terms acceptance)
  Future<void> enableBypass({required bool accepted}) async {
    if (accepted) {
      _hasAcceptedTerms = true;
      _isEnabled = true;
      await _saveSettings();
    }
  }
  
  /// Disable bypass
  Future<void> disableBypass() async {
    _isEnabled = false;
    await _saveSettings();
  }
  
  /// Bypass paywall and extract content
  Future<ExtractedContent> bypassAndExtract(String url) async {
    if (!isEnabled) {
      // Fall back to regular extraction
      return await _extractionService.extractContent(url);
    }
    
    // Detect site and get rule
    final rule = _detectSiteRule(url);
    
    // Try bypass methods in order
    final methods = rule?.methods ?? _getDefaultMethods();
    
    for (final method in methods) {
      try {
        ExtractedContent? content;
        
        switch (method.type) {
          case BypassMethodType.archive:
            content = await _bypassViaArchive(url, method);
            break;
          case BypassMethodType.googleBot:
            content = await _bypassViaGoogleBot(url, method);
            break;
          case BypassMethodType.javascript:
            content = await _bypassViaJavaScript(url, method);
            break;
          case BypassMethodType.cookie:
            content = await _bypassViaCookie(url, method);
            break;
          case BypassMethodType.referrer:
            content = await _bypassViaReferrer(url, method);
            break;
          case BypassMethodType.amp:
            content = await _bypassViaAMP(url, method);
            break;
          case BypassMethodType.dom:
            content = await _bypassViaDOM(url, method);
            break;
        }
        
        if (content != null && content.success && content.content.isNotEmpty) {
          // Track success rate
          if (rule != null) {
            await _updateSuccessRate(rule.domain, true);
          }
          
          return content;
        }
      } catch (e) {
        print('Bypass method ${method.type} failed: $e');
        continue; // Try next method
      }
    }
    
    // Track failure
    if (rule != null) {
      await _updateSuccessRate(rule.domain, false);
    }
    
    // Fall back to regular extraction
    return await _extractionService.extractContent(url);
  }
  
  /// Bypass via archive service
  Future<ExtractedContent?> _bypassViaArchive(String url, BypassMethod method) async {
    // Try Archive.ph first
    try {
      final archiveUrl = '$_archivePhUrl/$url';
      final response = await _dio.get(archiveUrl);
      
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.data);
        
        // Remove archive.ph UI elements
        document.querySelectorAll('#HEADER, #FOOTER, .CONTENT__HEADER').forEach((e) => e.remove());
        
        // Extract content
        final content = document.querySelector('#CONTENT')?.innerHtml ?? response.data;
        
        return ExtractedContent(
          content: content,
          title: document.querySelector('title')?.text,
          success: true,
        );
      }
    } catch (e) {
      print('Archive.ph failed: $e');
    }
    
    // Try Wayback Machine
    try {
      final waybackUrl = '$_waybackUrl/save/$url';
      final checkUrl = '$_waybackUrl/web/*/$url';
      
      final response = await _dio.get(checkUrl);
      
      if (response.statusCode == 200) {
        // Parse wayback response to find latest snapshot
        final regex = RegExp(r'/web/(\d{14})/');
        final matches = regex.allMatches(response.data.toString());
        
        if (matches.isNotEmpty) {
          final timestamps = matches.map((m) => m.group(1)!).toList();
          timestamps.sort((a, b) => b.compareTo(a)); // Latest first
          
          final snapshotUrl = '$_waybackUrl/web/${timestamps.first}/$url';
          final snapshotResponse = await _dio.get(snapshotUrl);
          
          if (snapshotResponse.statusCode == 200) {
            return await _extractionService.extractContent(snapshotUrl);
          }
        }
      }
    } catch (e) {
      print('Wayback Machine failed: $e');
    }
    
    // Try 12ft.io
    try {
      final twelveFtProxyUrl = '$_twelveFtUrl/proxy?q=$url';
      final response = await _dio.get(twelveFtProxyUrl);
      
      if (response.statusCode == 200) {
        return await _extractionService.extractContent(twelveFtProxyUrl);
      }
    } catch (e) {
      print('12ft.io failed: $e');
    }
    
    return null;
  }
  
  /// Bypass via GoogleBot user agent
  Future<ExtractedContent?> _bypassViaGoogleBot(String url, BypassMethod method) async {
    final headers = Map<String, String>.from(_googleBotHeaders);
    
    // Add custom headers if specified
    if (method.headers != null) {
      headers.addAll(method.headers!);
    }
    
    final response = await _dio.get(
      url,
      options: Options(headers: headers),
    );
    
    if (response.statusCode == 200) {
      // Check if we got full content
      final content = response.data.toString();
      if (!content.contains('paywall') && !content.contains('subscribe')) {
        return await _extractionService.extractContent(url);
      }
    }
    
    // Try other bot user agents
    for (final botHeaders in [_bingBotHeaders, _facebookBotHeaders]) {
      try {
        final response = await _dio.get(
          url,
          options: Options(headers: botHeaders),
        );
        
        if (response.statusCode == 200) {
          final content = response.data.toString();
          if (!content.contains('paywall') && !content.contains('subscribe')) {
            return await _extractionService.extractContent(url);
          }
        }
      } catch (e) {
        continue;
      }
    }
    
    return null;
  }
  
  /// Bypass via JavaScript manipulation
  Future<ExtractedContent?> _bypassViaJavaScript(String url, BypassMethod method) async {
    await _puppeteerService.start();
    
    try {
      // Fetch page with JavaScript
      final html = await _puppeteerService.fetchPage(
        url,
        waitFor: const Duration(seconds: 3),
      );
      
      // Apply JavaScript bypasses
      final scripts = method.scripts ?? _getDefaultBypassScripts();
      
      for (final script in scripts) {
        try {
          await _puppeteerService.executeScript(url, script);
        } catch (e) {
          print('Script execution failed: $e');
        }
      }
      
      // Get final HTML
      final finalHtml = await _puppeteerService.fetchPage(url);
      
      // Extract content from rendered HTML
      final document = html_parser.parse(finalHtml);
      return await _extractContentFromDocument(document, url);
    } finally {
      await _puppeteerService.stop();
    }
  }
  
  /// Bypass via cookie injection
  Future<ExtractedContent?> _bypassViaCookie(String url, BypassMethod method) async {
    final cookies = method.cookies ?? {};
    
    // Common paywall bypass cookies
    cookies.addAll({
      'subscriber': 'true',
      'paid_subscriber': 'true',
      'premium': 'true',
      'has_subscription': 'true',
      'logged_in': 'true',
    });
    
    // Build cookie header
    final cookieHeader = cookies.entries
      .map((e) => '${e.key}=${e.value}')
      .join('; ');
    
    final response = await _dio.get(
      url,
      options: Options(
        headers: {
          'Cookie': cookieHeader,
          ...method.headers ?? {},
        },
      ),
    );
    
    if (response.statusCode == 200) {
      return await _extractionService.extractContent(url);
    }
    
    return null;
  }
  
  /// Bypass via referrer manipulation
  Future<ExtractedContent?> _bypassViaReferrer(String url, BypassMethod method) async {
    final referrers = method.referrers ?? [
      'https://www.google.com/',
      'https://t.co/',
      'https://facebook.com/',
      'https://twitter.com/',
    ];
    
    for (final referrer in referrers) {
      try {
        final response = await _dio.get(
          url,
          options: Options(
            headers: {
              'Referer': referrer,
              ...method.headers ?? {},
            },
          ),
        );
        
        if (response.statusCode == 200) {
          final content = response.data.toString();
          if (!content.contains('paywall') && !content.contains('subscribe')) {
            return await _extractionService.extractContent(url);
          }
        }
      } catch (e) {
        continue;
      }
    }
    
    return null;
  }
  
  /// Bypass via AMP version
  Future<ExtractedContent?> _bypassViaAMP(String url, BypassMethod method) async {
    // Try common AMP URL patterns
    final uri = Uri.parse(url);
    final ampUrls = [
      'https://${uri.host}/amp${uri.path}',
      'https://amp.${uri.host}${uri.path}',
      '${url}?amp=1',
      '${url}/amp',
    ];
    
    for (final ampUrl in ampUrls) {
      try {
        final response = await _dio.get(ampUrl);
        
        if (response.statusCode == 200) {
          final document = html_parser.parse(response.data);
          
          // Check if it's actually an AMP page
          if (document.querySelector('html[amp]') != null ||
              document.querySelector('html[⚡]') != null) {
            
            // Extract AMP content
            final content = document.querySelector('amp-story, main, article')?.innerHtml;
            
            if (content != null && content.isNotEmpty) {
              return ExtractedContent(
                content: content,
                title: document.querySelector('title')?.text,
                success: true,
              );
            }
          }
        }
      } catch (e) {
        continue;
      }
    }
    
    return null;
  }
  
  /// Bypass via DOM manipulation
  Future<ExtractedContent?> _bypassViaDOM(String url, BypassMethod method) async {
    final response = await _dio.get(url);
    
    if (response.statusCode == 200) {
      final document = html_parser.parse(response.data);
      
      // Remove paywall elements
      final paywallSelectors = method.selectors ?? [
        '.paywall',
        '.paywall-overlay',
        '.subscription-required',
        '.premium-content-overlay',
        '#paywall-banner',
        '.article-paywall',
        '.locked-content',
        '.subscriber-only',
        '[data-paywall]',
        '[class*="paywall"]',
        '[id*="paywall"]',
      ];
      
      for (final selector in paywallSelectors) {
        document.querySelectorAll(selector).forEach((e) => e.remove());
      }
      
      // Reveal hidden content
      document.querySelectorAll('[style*="display: none"], [style*="display:none"]')
        .forEach((e) {
          e.attributes.remove('style');
        });
      
      document.querySelectorAll('.hidden, .hide').forEach((e) {
        e.classes.remove('hidden');
        e.classes.remove('hide');
      });
      
      // Look for content that might be blurred or obscured
      document.querySelectorAll('[style*="blur"], [class*="blur"]').forEach((e) {
        e.attributes.remove('style');
        e.classes.removeWhere((c) => c.contains('blur'));
      });
      
      return await _extractContentFromDocument(document, url);
    }
    
    return null;
  }
  
  /// Extract content from HTML document
  Future<ExtractedContent> _extractContentFromDocument(
    html.Document document,
    String url,
  ) async {
    // Use extraction service on the modified document
    final modifiedHtml = document.outerHtml;
    
    // Create a temporary server to serve the modified HTML
    // In practice, we'd parse it directly
    return ExtractedContent(
      content: document.querySelector('article, main, .content')?.innerHtml ?? '',
      title: document.querySelector('h1')?.text,
      success: true,
    );
  }
  
  /// Detect site rule
  BypassRule? _detectSiteRule(String url) {
    final uri = Uri.parse(url);
    final domain = uri.host.replaceAll('www.', '');
    
    return _rules[domain];
  }
  
  /// Get default bypass methods
  List<BypassMethod> _getDefaultMethods() {
    return [
      BypassMethod(type: BypassMethodType.archive),
      BypassMethod(type: BypassMethodType.googleBot),
      BypassMethod(type: BypassMethodType.referrer),
      BypassMethod(type: BypassMethodType.amp),
      BypassMethod(type: BypassMethodType.dom),
    ];
  }
  
  /// Get default bypass scripts
  List<String> _getDefaultBypassScripts() {
    return [
      // Remove paywall overlays
      '''
      document.querySelectorAll('.paywall, .paywall-overlay, [class*="paywall"]').forEach(e => e.remove());
      ''',
      
      // Enable scrolling
      '''
      document.body.style.overflow = 'auto';
      document.documentElement.style.overflow = 'auto';
      ''',
      
      // Remove blur effects
      '''
      document.querySelectorAll('[style*="blur"]').forEach(e => {
        e.style.filter = 'none';
      });
      ''',
      
      // Show hidden content
      '''
      document.querySelectorAll('.hidden, [style*="display: none"]').forEach(e => {
        e.classList.remove('hidden');
        e.style.display = 'block';
      });
      ''',
    ];
  }
  
  /// Load bypass rules
  void _loadRules() {
    // Load built-in rules
    _loadBuiltInRules();
    
    // TODO: Load custom rules from storage
  }
  
  /// Load built-in rules for popular sites
  void _loadBuiltInRules() {
    // New York Times
    _rules['nytimes.com'] = BypassRule(
      domain: 'nytimes.com',
      name: 'The New York Times',
      methods: [
        BypassMethod(
          type: BypassMethodType.googleBot,
          priority: 1,
        ),
        BypassMethod(
          type: BypassMethodType.archive,
          priority: 2,
        ),
        BypassMethod(
          type: BypassMethodType.javascript,
          priority: 3,
          scripts: [
            'window.TimesGateway = undefined;',
            'document.querySelector("#gateway-content").style.display = "none";',
          ],
        ),
      ],
    );
    
    // Wall Street Journal
    _rules['wsj.com'] = BypassRule(
      domain: 'wsj.com',
      name: 'Wall Street Journal',
      methods: [
        BypassMethod(
          type: BypassMethodType.referrer,
          priority: 1,
          referrers: ['https://www.google.com/', 'https://t.co/'],
        ),
        BypassMethod(
          type: BypassMethodType.archive,
          priority: 2,
        ),
        BypassMethod(
          type: BypassMethodType.amp,
          priority: 3,
        ),
      ],
    );
    
    // The Washington Post
    _rules['washingtonpost.com'] = BypassRule(
      domain: 'washingtonpost.com',
      name: 'The Washington Post',
      methods: [
        BypassMethod(
          type: BypassMethodType.googleBot,
          priority: 1,
        ),
        BypassMethod(
          type: BypassMethodType.javascript,
          priority: 2,
          scripts: [
            'window.Fusion.globalContent.content_restrictions = undefined;',
          ],
        ),
      ],
    );
    
    // Financial Times
    _rules['ft.com'] = BypassRule(
      domain: 'ft.com',
      name: 'Financial Times',
      methods: [
        BypassMethod(
          type: BypassMethodType.referrer,
          priority: 1,
          referrers: ['https://www.google.com/'],
        ),
        BypassMethod(
          type: BypassMethodType.cookie,
          priority: 2,
          cookies: {
            'FTCookieConsentGDPR': 'true',
            'FTAllocation': 'true',
          },
        ),
      ],
    );
    
    // The Atlantic
    _rules['theatlantic.com'] = BypassRule(
      domain: 'theatlantic.com',
      name: 'The Atlantic',
      methods: [
        BypassMethod(
          type: BypassMethodType.dom,
          priority: 1,
          selectors: [
            '.c-nudge__container',
            '.c-non-metered-nudge',
          ],
        ),
        BypassMethod(
          type: BypassMethodType.googleBot,
          priority: 2,
        ),
      ],
    );
    
    // Medium
    _rules['medium.com'] = BypassRule(
      domain: 'medium.com',
      name: 'Medium',
      methods: [
        BypassMethod(
          type: BypassMethodType.cookie,
          priority: 1,
          cookies: {
            'uid': '1',
            'sid': '1:1',
            '__cfduid': 'd123456789',
          },
        ),
        BypassMethod(
          type: BypassMethodType.javascript,
          priority: 2,
          scripts: [
            'document.querySelector("#paywall-background").remove();',
          ],
        ),
      ],
    );
    
    // Bloomberg
    _rules['bloomberg.com'] = BypassRule(
      domain: 'bloomberg.com',
      name: 'Bloomberg',
      methods: [
        BypassMethod(
          type: BypassMethodType.googleBot,
          priority: 1,
        ),
        BypassMethod(
          type: BypassMethodType.referrer,
          priority: 2,
          referrers: ['https://t.co/'],
        ),
      ],
    );
    
    // The Economist
    _rules['economist.com'] = BypassRule(
      domain: 'economist.com',
      name: 'The Economist',
      methods: [
        BypassMethod(
          type: BypassMethodType.googleBot,
          priority: 1,
        ),
        BypassMethod(
          type: BypassMethodType.archive,
          priority: 2,
        ),
      ],
    );
    
    // Add more sites...
  }
  
  /// Update success rate for a domain
  Future<void> _updateSuccessRate(String domain, bool success) async {
    // TODO: Track success rates in database
  }
  
  /// Load settings
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('bypass_enabled') ?? false;
    _hasAcceptedTerms = prefs.getBool('bypass_terms_accepted') ?? false;
  }
  
  /// Save settings
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bypass_enabled', _isEnabled);
    await prefs.setBool('bypass_terms_accepted', _hasAcceptedTerms);
  }
}

/// Bypass rule for a site
class BypassRule {
  final String domain;
  final String name;
  final List<BypassMethod> methods;
  final double? successRate;
  final DateTime? lastSuccess;
  final bool isActive;
  
  BypassRule({
    required this.domain,
    required this.name,
    required this.methods,
    this.successRate,
    this.lastSuccess,
    this.isActive = true,
  });
}

/// Bypass method configuration
class BypassMethod {
  final BypassMethodType type;
  final int priority;
  final Map<String, String>? headers;
  final Map<String, String>? cookies;
  final List<String>? referrers;
  final List<String>? scripts;
  final List<String>? selectors;
  
  BypassMethod({
    required this.type,
    this.priority = 0,
    this.headers,
    this.cookies,
    this.referrers,
    this.scripts,
    this.selectors,
  });
}

/// Bypass method types
enum BypassMethodType {
  archive,      // Use archive services
  googleBot,    // Use GoogleBot user agent
  javascript,   // JavaScript manipulation
  cookie,       // Cookie injection
  referrer,     // Referrer spoofing
  amp,          // AMP version
  dom,          // DOM manipulation
}