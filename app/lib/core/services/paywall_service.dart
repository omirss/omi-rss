import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html;
import 'extraction_service.dart';

/// Paywall bypass service (hidden functionality)
/// This service implements various techniques to access full article content
class PaywallService {
  final Dio _dio;
  final ExtractionService _extractionService;
  final Map<String, PaywallRule> _rules = {};
  
  // User agents that often get different treatment
  static const Map<String, String> _userAgents = {
    'googlebot': 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
    'bingbot': 'Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)',
    'facebookbot': 'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
    'twitterbot': 'Twitterbot/1.0',
    'linkedinbot': 'LinkedInBot/1.0 (compatible; Mozilla/5.0; Apache-HttpClient +http://www.linkedin.com)',
    'archive': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/600.2.5 (KHTML, like Gecko) Version/8.0.2 Safari/600.2.5 (Applebot/0.1)',
  };
  
  PaywallService({
    Dio? dio,
    ExtractionService? extractionService,
  }) : _dio = dio ?? Dio(),
        _extractionService = extractionService ?? ExtractionService() {
    _dio.options.followRedirects = true;
    _dio.options.maxRedirects = 5;
    _initializeRules();
  }
  
  /// Initialize paywall bypass rules
  void _initializeRules() {
    // New York Times
    _rules['nytimes.com'] = PaywallRule(
      domain: 'nytimes.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.ampVersion,
        PaywallMethod.disableJavascript,
      ],
      selectors: PaywallSelectors(
        paywall: '.meteredContent',
        content: 'section[name="articleBody"]',
        remove: ['.ad', '.related-coverage', '.interactive-content'],
      ),
    );
    
    // Wall Street Journal
    _rules['wsj.com'] = PaywallRule(
      domain: 'wsj.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.googleCache,
        PaywallMethod.facebookReferer,
      ],
      selectors: PaywallSelectors(
        paywall: '.wsj-snippet-login',
        content: '.article-content',
        remove: ['.media-object-video', '.newsletter-inset'],
      ),
    );
    
    // Financial Times
    _rules['ft.com'] = PaywallRule(
      domain: 'ft.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.twitterReferer,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.barrier',
        content: '.article__body',
        remove: ['.o-ads', '.o-share'],
      ),
    );
    
    // The Economist
    _rules['economist.com'] = PaywallRule(
      domain: 'economist.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.disableJavascript,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.article__body-text',
        remove: ['.advert', '.newsletter-form'],
      ),
    );
    
    // Bloomberg
    _rules['bloomberg.com'] = PaywallRule(
      domain: 'bloomberg.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.twitterReferer,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.body-content',
        remove: ['.terminal-news-story', '.inline-newsletter'],
      ),
    );
    
    // Medium
    _rules['medium.com'] = PaywallRule(
      domain: 'medium.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.disableCookies,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.meteredContent',
        content: '.section-content',
        remove: ['.js-postShareWidget', '.js-postMetaLockup'],
      ),
    );
    
    // The Atlantic
    _rules['theatlantic.com'] = PaywallRule(
      domain: 'theatlantic.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.disableJavascript,
      ],
      selectors: PaywallSelectors(
        paywall: '.c-nudge__container',
        content: '.article-body',
        remove: ['.c-ad', '.c-recirculation'],
      ),
    );
    
    // Washington Post
    _rules['washingtonpost.com'] = PaywallRule(
      domain: 'washingtonpost.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.googleCache,
      ],
      selectors: PaywallSelectors(
        paywall: '.subscribe-bar',
        content: '.article-body',
        remove: ['.pb-ad', '.inline-video'],
      ),
    );
    
    // The Guardian
    _rules['theguardian.com'] = PaywallRule(
      domain: 'theguardian.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.contributions__epic',
        content: '.article-body-commercial-selector',
        remove: ['.ad-slot', '.rich-link'],
      ),
    );
    
    // Telegraph
    _rules['telegraph.co.uk'] = PaywallRule(
      domain: 'telegraph.co.uk',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.ampVersion,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.martech-modal-component',
        content: '.article-body-text',
        remove: ['.advert', '.martech-wrapper'],
      ),
    );
    
    // The Times
    _rules['thetimes.co.uk'] = PaywallRule(
      domain: 'thetimes.co.uk',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.googleCache,
      ],
      selectors: PaywallSelectors(
        paywall: '#paywall-portal-article-footer',
        content: '.article__content',
        remove: ['.ad-container', '.related-links'],
      ),
    );
    
    // Wired
    _rules['wired.com'] = PaywallRule(
      domain: 'wired.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.disableJavascript,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall-bar',
        content: '.article__body',
        remove: ['.ad-container', '.newsletter-signup'],
      ),
    );
    
    // Vanity Fair
    _rules['vanityfair.com'] = PaywallRule(
      domain: 'vanityfair.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall-bar',
        content: '.article__body',
        remove: ['.ad-container', '.callout--newsletter'],
      ),
    );
    
    // New Yorker
    _rules['newyorker.com'] = PaywallRule(
      domain: 'newyorker.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.disableJavascript,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall-bar',
        content: '.article__body',
        remove: ['.ad', '.social-icons'],
      ),
    );
    
    // Business Insider
    _rules['businessinsider.com'] = PaywallRule(
      domain: 'businessinsider.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.ampVersion,
      ],
      selectors: PaywallSelectors(
        paywall: '.piano-paywall',
        content: '.content-lock-content',
        remove: ['.l-ad', '.newsletter-post-rail'],
      ),
    );
    
    // Barron's
    _rules['barrons.com'] = PaywallRule(
      domain: 'barrons.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.googleCache,
      ],
      selectors: PaywallSelectors(
        paywall: '.snippet__content',
        content: '.article__body',
        remove: ['.dynamic-inset-overflow', '.newsletter-inset'],
      ),
    );
    
    // Scientific American
    _rules['scientificamerican.com'] = PaywallRule(
      domain: 'scientificamerican.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.article-text',
        remove: ['.article-ad', '.newsletter-signup'],
      ),
    );
    
    // Nature
    _rules['nature.com'] = PaywallRule(
      domain: 'nature.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.disableJavascript,
      ],
      selectors: PaywallSelectors(
        paywall: '.c-article-access-denied',
        content: '.c-article-body',
        remove: ['.c-article-ads', '.recommended'],
      ),
    );
    
    // Harvard Business Review
    _rules['hbr.org'] = PaywallRule(
      domain: 'hbr.org',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.disableCookies,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall-overlay',
        content: '.article-body',
        remove: ['.advertisement', '.article-sidebar'],
      ),
    );
    
    // MIT Technology Review
    _rules['technologyreview.com'] = PaywallRule(
      domain: 'technologyreview.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.content--body',
        remove: ['.content--ads', '.newsletter-box'],
      ),
    );
    
    // Foreign Affairs
    _rules['foreignaffairs.com'] = PaywallRule(
      domain: 'foreignaffairs.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.googleCache,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall-prompt',
        content: '.article-body',
        remove: ['.advertisement', '.suggested-reading'],
      ),
    );
    
    // The Spectator
    _rules['spectator.co.uk'] = PaywallRule(
      domain: 'spectator.co.uk',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall-overlay',
        content: '.article-content',
        remove: ['.ad-container', '.related-articles'],
      ),
    );
    
    // Politico Pro
    _rules['politico.com'] = PaywallRule(
      domain: 'politico.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.disableJavascript,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall-content',
        content: '.story-text',
        remove: ['.ad-slot', '.newsletter-promo'],
      ),
    );
    
    // The Information
    _rules['theinformation.com'] = PaywallRule(
      domain: 'theinformation.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.post-content',
        remove: ['.post-ad', '.signup-box'],
      ),
    );
    
    // Stratechery
    _rules['stratechery.com'] = PaywallRule(
      domain: 'stratechery.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.membership-required',
        content: '.entry-content',
        remove: ['.membership-cta'],
      ),
    );
    
    // Substack publications
    _rules['substack.com'] = PaywallRule(
      domain: 'substack.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.disableCookies,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.post-content',
        remove: ['.subscription-widget', '.comments-section'],
      ),
    );
    
    // Seeking Alpha
    _rules['seekingalpha.com'] = PaywallRule(
      domain: 'seekingalpha.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall-container',
        content: '.article-content',
        remove: ['.ad-wrap', '.author-bio'],
      ),
    );
    
    // Los Angeles Times
    _rules['latimes.com'] = PaywallRule(
      domain: 'latimes.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.ampVersion,
      ],
      selectors: PaywallSelectors(
        paywall: '.meter-paywall',
        content: '.rich-text-article-body',
        remove: ['.enhancement', '.promo'],
      ),
    );
    
    // Chicago Tribune
    _rules['chicagotribune.com'] = PaywallRule(
      domain: 'chicagotribune.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.modal',
        content: '.article-body',
        remove: ['.ad-slot', '.related-item'],
      ),
    );
    
    // Boston Globe
    _rules['bostonglobe.com'] = PaywallRule(
      domain: 'bostonglobe.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.meter-paywall',
        content: '.article-content',
        remove: ['.ad', '.related-stories'],
      ),
    );
    
    // San Francisco Chronicle
    _rules['sfchronicle.com'] = PaywallRule(
      domain: 'sfchronicle.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.freeMode',
        content: '.article-content',
        remove: ['.ad-container', '.newsletter-inline'],
      ),
    );
    
    // The Seattle Times
    _rules['seattletimes.com'] = PaywallRule(
      domain: 'seattletimes.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.modal',
        content: '.article-body',
        remove: ['.ad-container', '.related'],
      ),
    );
    
    // Miami Herald
    _rules['miamiherald.com'] = PaywallRule(
      domain: 'miamiherald.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.modal',
        content: '.article-body',
        remove: ['.ad-widget', '.related-stories'],
      ),
    );
    
    // The Denver Post
    _rules['denverpost.com'] = PaywallRule(
      domain: 'denverpost.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.modal',
        content: '.article-body',
        remove: ['.dfp-ad', '.related'],
      ),
    );
    
    // The Sydney Morning Herald
    _rules['smh.com.au'] = PaywallRule(
      domain: 'smh.com.au',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.subscribe-truncate',
        content: '.article__content',
        remove: ['.ad-wrapper', '.related-stories'],
      ),
    );
    
    // The Australian
    _rules['theaustralian.com.au'] = PaywallRule(
      domain: 'theaustralian.com.au',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '#subscribe-truncate',
        content: '.story-content',
        remove: ['.ad-block', '.module-related'],
      ),
    );
    
    // Toronto Star
    _rules['thestar.com'] = PaywallRule(
      domain: 'thestar.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.ampVersion,
      ],
      selectors: PaywallSelectors(
        paywall: '.basic-paywall-new',
        content: '.c-article__body',
        remove: ['.ad-slot', '.related-stories'],
      ),
    );
    
    // National Post
    _rules['nationalpost.com'] = PaywallRule(
      domain: 'nationalpost.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.modal',
        content: '.article-content',
        remove: ['.ad-slot', '.related-posts'],
      ),
    );
    
    // Le Monde
    _rules['lemonde.fr'] = PaywallRule(
      domain: 'lemonde.fr',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.article__content',
        remove: ['.ad', '.services-inread'],
      ),
    );
    
    // Die Zeit
    _rules['zeit.de'] = PaywallRule(
      domain: 'zeit.de',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.disableJavascript,
      ],
      selectors: PaywallSelectors(
        paywall: '.gate',
        content: '.article-body',
        remove: ['.ad', '.article-pagination'],
      ),
    );
    
    // El País
    _rules['elpais.com'] = PaywallRule(
      domain: 'elpais.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.article_body',
        remove: ['.ad', '.article_related'],
      ),
    );
    
    // Corriere della Sera
    _rules['corriere.it'] = PaywallRule(
      domain: 'corriere.it',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.article__body',
        remove: ['.adv', '.correlati'],
      ),
    );
    
    // Nikkei Asian Review
    _rules['asia.nikkei.com'] = PaywallRule(
      domain: 'asia.nikkei.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.ezrichtext-field',
        remove: ['.offer-slot', '.related-article'],
      ),
    );
    
    // South China Morning Post
    _rules['scmp.com'] = PaywallRule(
      domain: 'scmp.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.ampVersion,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall-overlay',
        content: '.article-body',
        remove: ['.advert', '.related-articles'],
      ),
    );
    
    // The Hindu
    _rules['thehindu.com'] = PaywallRule(
      domain: 'thehindu.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.article-body',
        remove: ['.ad', '.related-article'],
      ),
    );
    
    // India Today
    _rules['indiatoday.in'] = PaywallRule(
      domain: 'indiatoday.in',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.description',
        remove: ['.adboxtop', '.rhs'],
      ),
    );
    
    // Quartz
    _rules['qz.com'] = PaywallRule(
      domain: 'qz.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
        PaywallMethod.ampVersion,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.content',
        remove: ['.ad', '.article-aside'],
      ),
    );
    
    // The Verge (for premium content)
    _rules['theverge.com'] = PaywallRule(
      domain: 'theverge.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.c-entry-group-labels--premium',
        content: '.c-entry-content',
        remove: ['.c-ad', '.c-entry-related'],
      ),
    );
    
    // Protocol
    _rules['protocol.com'] = PaywallRule(
      domain: 'protocol.com',
      methods: [
        PaywallMethod.googlebot,
        PaywallMethod.archiveOrg,
      ],
      selectors: PaywallSelectors(
        paywall: '.paywall',
        content: '.article-content',
        remove: ['.ad-container', '.newsletter-signup'],
      ),
    );
    
    // Add more site-specific rules...
  }
  
  /// Attempt to bypass paywall and extract content
  Future<PaywallResult> bypassAndExtract(String url, {
    bool aggressive = false,
    List<PaywallMethod>? preferredMethods,
  }) async {
    try {
      // Detect site and get rule
      final rule = _detectSiteRule(url);
      
      // Determine methods to try
      final methods = preferredMethods ?? 
                      rule?.methods ?? 
                      (aggressive ? PaywallMethod.values : _defaultMethods());
      
      // Try each method
      for (final method in methods) {
        try {
          final result = await _tryMethod(url, method, rule);
          if (result.success && result.content.isNotEmpty) {
            return result;
          }
        } catch (e) {
          // Continue to next method
          continue;
        }
      }
      
      // If all methods fail, try basic extraction
      final basicResult = await _extractionService.extractContent(url);
      return PaywallResult(
        content: basicResult.content,
        title: basicResult.title,
        method: PaywallMethod.none,
        success: basicResult.success,
        fullContent: basicResult.content.length > 500,
      );
      
    } catch (e) {
      return PaywallResult(
        content: '',
        method: PaywallMethod.none,
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Try a specific bypass method
  Future<PaywallResult> _tryMethod(
    String url,
    PaywallMethod method,
    PaywallRule? rule,
  ) async {
    switch (method) {
      case PaywallMethod.googlebot:
        return await _tryGooglebot(url, rule);
        
      case PaywallMethod.archiveOrg:
        return await _tryArchiveOrg(url, rule);
        
      case PaywallMethod.googleCache:
        return await _tryGoogleCache(url, rule);
        
      case PaywallMethod.ampVersion:
        return await _tryAmpVersion(url, rule);
        
      case PaywallMethod.disableJavascript:
        return await _tryNoJavaScript(url, rule);
        
      case PaywallMethod.disableCookies:
        return await _tryNoCookies(url, rule);
        
      case PaywallMethod.facebookReferer:
        return await _tryWithReferer(url, 'https://www.facebook.com/', rule);
        
      case PaywallMethod.twitterReferer:
        return await _tryWithReferer(url, 'https://twitter.com/', rule);
        
      case PaywallMethod.textOnly:
        return await _tryTextOnly(url, rule);
        
      case PaywallMethod.readerMode:
        return await _tryReaderMode(url, rule);
        
      case PaywallMethod.webArchive:
        return await _tryWebArchive(url, rule);
        
      case PaywallMethod.twelveFootLadder:
        return await _tryTwelveFootLadder(url, rule);
        
      case PaywallMethod.none:
      default:
        final result = await _extractionService.extractContent(url);
        return PaywallResult(
          content: result.content,
          title: result.title,
          method: method,
          success: result.success,
        );
    }
  }
  
  /// Try Googlebot user agent
  Future<PaywallResult> _tryGooglebot(String url, PaywallRule? rule) async {
    final response = await _dio.get(
      url,
      options: Options(
        headers: {
          'User-Agent': _userAgents['googlebot'],
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-US,en;q=0.9',
          'Cache-Control': 'no-cache',
        },
      ),
    );
    
    return _extractFromResponse(response.data, url, rule, PaywallMethod.googlebot);
  }
  
  /// Try Archive.org
  Future<PaywallResult> _tryArchiveOrg(String url, PaywallRule? rule) async {
    final archiveUrl = 'https://web.archive.org/web/$url';
    
    try {
      // First check if archived version exists
      final checkUrl = 'https://archive.org/wayback/available?url=$url';
      final checkResponse = await _dio.get(checkUrl);
      final data = jsonDecode(checkResponse.data);
      
      if (data['archived_snapshots']?['closest']?['available'] == true) {
        final snapshotUrl = data['archived_snapshots']['closest']['url'];
        final response = await _dio.get(snapshotUrl);
        
        return _extractFromResponse(
          response.data,
          url,
          rule,
          PaywallMethod.archiveOrg,
        );
      }
    } catch (e) {
      // Fall through
    }
    
    throw Exception('No archive.org snapshot available');
  }
  
  /// Try Google Cache
  Future<PaywallResult> _tryGoogleCache(String url, PaywallRule? rule) async {
    final cacheUrl = 'https://webcache.googleusercontent.com/search?q=cache:$url';
    
    final response = await _dio.get(
      cacheUrl,
      options: Options(
        headers: {
          'User-Agent': _userAgents['googlebot'],
        },
      ),
    );
    
    return _extractFromResponse(response.data, url, rule, PaywallMethod.googleCache);
  }
  
  /// Try AMP version
  Future<PaywallResult> _tryAmpVersion(String url, PaywallRule? rule) async {
    // Try common AMP URL patterns
    final uri = Uri.parse(url);
    final ampPatterns = [
      '${uri.scheme}://${uri.host}/amp${uri.path}',
      '${uri.scheme}://amp.${uri.host}${uri.path}',
      '${uri.scheme}://${uri.host}${uri.path}/amp',
      '${uri.scheme}://${uri.host}${uri.path}?amp=1',
    ];
    
    for (final ampUrl in ampPatterns) {
      try {
        final response = await _dio.get(ampUrl);
        if (response.statusCode == 200) {
          return _extractFromResponse(
            response.data,
            url,
            rule,
            PaywallMethod.ampVersion,
          );
        }
      } catch (e) {
        continue;
      }
    }
    
    throw Exception('No AMP version found');
  }
  
  /// Try without JavaScript
  Future<PaywallResult> _tryNoJavaScript(String url, PaywallRule? rule) async {
    final response = await _dio.get(
      url,
      options: Options(
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)',
        },
      ),
    );
    
    return _extractFromResponse(response.data, url, rule, PaywallMethod.disableJavascript);
  }
  
  /// Try without cookies
  Future<PaywallResult> _tryNoCookies(String url, PaywallRule? rule) async {
    final response = await _dio.get(
      url,
      options: Options(
        headers: {
          'User-Agent': _dio.options.headers['User-Agent'],
          'Cookie': '',
        },
      ),
    );
    
    return _extractFromResponse(response.data, url, rule, PaywallMethod.disableCookies);
  }
  
  /// Try with specific referer
  Future<PaywallResult> _tryWithReferer(
    String url,
    String referer,
    PaywallRule? rule,
  ) async {
    final response = await _dio.get(
      url,
      options: Options(
        headers: {
          'Referer': referer,
          'User-Agent': _dio.options.headers['User-Agent'],
        },
      ),
    );
    
    final method = referer.contains('facebook')
        ? PaywallMethod.facebookReferer
        : PaywallMethod.twitterReferer;
    
    return _extractFromResponse(response.data, url, rule, method);
  }
  
  /// Try text-only version
  Future<PaywallResult> _tryTextOnly(String url, PaywallRule? rule) async {
    // Use a text-only browser service
    final textOnlyUrl = 'https://text.npr.org/s.php?sId=$url';
    
    try {
      final response = await _dio.get(textOnlyUrl);
      return _extractFromResponse(
        response.data,
        url,
        rule,
        PaywallMethod.textOnly,
      );
    } catch (e) {
      throw Exception('Text-only version not available');
    }
  }
  
  /// Try reader mode extraction
  Future<PaywallResult> _tryReaderMode(String url, PaywallRule? rule) async {
    // Enhanced extraction with reader mode optimizations
    final result = await _extractionService.extractContent(
      url,
      includeImages: false,
      includeVideos: false,
    );
    
    return PaywallResult(
      content: result.content,
      title: result.title,
      method: PaywallMethod.readerMode,
      success: result.success && result.content.length > 500,
      fullContent: result.content.length > 500,
    );
  }
  
  /// Try Web Archive
  Future<PaywallResult> _tryWebArchive(String url, PaywallRule? rule) async {
    final archiveUrl = 'https://archive.is/newest/$url';
    
    try {
      final response = await _dio.get(archiveUrl);
      return _extractFromResponse(
        response.data,
        url,
        rule,
        PaywallMethod.webArchive,
      );
    } catch (e) {
      throw Exception('Web archive not available');
    }
  }
  
  /// Try 12ft Ladder
  Future<PaywallResult> _tryTwelveFootLadder(String url, PaywallRule? rule) async {
    final ladderUrl = 'https://12ft.io/$url';
    
    try {
      final response = await _dio.get(ladderUrl);
      return _extractFromResponse(
        response.data,
        url,
        rule,
        PaywallMethod.twelveFootLadder,
      );
    } catch (e) {
      throw Exception('12ft ladder not available');
    }
  }
  
  /// Extract content from response
  Future<PaywallResult> _extractFromResponse(
    String html,
    String originalUrl,
    PaywallRule? rule,
    PaywallMethod method,
  ) async {
    final document = html_parser.parse(html);
    
    // Apply rule-specific extraction if available
    if (rule != null && rule.selectors.content != null) {
      // Remove unwanted elements
      for (final selector in rule.selectors.remove) {
        document.querySelectorAll(selector).forEach((e) => e.remove());
      }
      
      // Extract content
      final contentElement = document.querySelector(rule.selectors.content!);
      if (contentElement != null) {
        final title = document.querySelector('h1')?.text ??
                     document.querySelector('title')?.text ??
                     'Untitled';
        
        return PaywallResult(
          content: contentElement.innerHtml,
          title: title,
          method: method,
          success: true,
          fullContent: contentElement.text.length > 500,
        );
      }
    }
    
    // Fallback to extraction service
    final extractedContent = await _extractionService.extractContent(originalUrl);
    
    return PaywallResult(
      content: extractedContent.content,
      title: extractedContent.title,
      method: method,
      success: extractedContent.success,
      fullContent: extractedContent.content.length > 500,
    );
  }
  
  /// Detect site rule from URL
  PaywallRule? _detectSiteRule(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.replaceAll('www.', '');
      
      // Direct match
      if (_rules.containsKey(host)) {
        return _rules[host];
      }
      
      // Check subdomains
      for (final domain in _rules.keys) {
        if (host.endsWith(domain)) {
          return _rules[domain];
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// Get default methods to try
  List<PaywallMethod> _defaultMethods() {
    return [
      PaywallMethod.googlebot,
      PaywallMethod.archiveOrg,
      PaywallMethod.disableJavascript,
      PaywallMethod.readerMode,
    ];
  }
  
  /// Check if URL might have paywall
  bool mightHavePaywall(String url) {
    return _detectSiteRule(url) != null;
  }
  
  /// Get available bypass methods for URL
  List<PaywallMethod> getAvailableMethods(String url) {
    final rule = _detectSiteRule(url);
    return rule?.methods ?? _defaultMethods();
  }
}

/// Paywall bypass methods
enum PaywallMethod {
  none,
  googlebot,
  archiveOrg,
  googleCache,
  ampVersion,
  disableJavascript,
  disableCookies,
  facebookReferer,
  twitterReferer,
  textOnly,
  readerMode,
  webArchive,
  twelveFootLadder,
}

/// Paywall bypass rule
class PaywallRule {
  final String domain;
  final List<PaywallMethod> methods;
  final PaywallSelectors selectors;
  final Map<String, String>? customHeaders;
  final bool requiresJavaScript;
  
  PaywallRule({
    required this.domain,
    required this.methods,
    required this.selectors,
    this.customHeaders,
    this.requiresJavaScript = false,
  });
}

/// Paywall selectors
class PaywallSelectors {
  final String? paywall;
  final String? content;
  final List<String> remove;
  
  PaywallSelectors({
    this.paywall,
    this.content,
    this.remove = const [],
  });
}

/// Paywall bypass result
class PaywallResult {
  final String content;
  final String? title;
  final PaywallMethod method;
  final bool success;
  final bool fullContent;
  final String? error;
  
  PaywallResult({
    required this.content,
    this.title,
    required this.method,
    required this.success,
    this.fullContent = false,
    this.error,
  });
}