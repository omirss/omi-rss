import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html;
import '../models/article.dart';

/// Full-text extraction service implementing Readability algorithm
class ExtractionService {
  final Dio _dio;
  
  // Content scoring constants
  static const Map<String, int> _positiveScores = {
    'article': 5,
    'body': 5,
    'content': 5,
    'entry': 5,
    'hentry': 5,
    'h-entry': 5,
    'main': 5,
    'page': 5,
    'post': 5,
    'text': 5,
    'blog': 5,
    'story': 5,
  };
  
  static const Map<String, int> _negativeScores = {
    'hidden': -1,
    'hid': -1,
    'banner': -3,
    'combx': -3,
    'comment': -3,
    'com-': -3,
    'contact': -3,
    'foot': -3,
    'footer': -3,
    'footnote': -3,
    'gdpr': -3,
    'head': -3,
    'header': -3,
    'legends': -3,
    'menu': -3,
    'related': -3,
    'remark': -3,
    'replies': -3,
    'rss': -3,
    'shoutbox': -3,
    'sidebar': -3,
    'skyscraper': -3,
    'sponsor': -3,
    'shopping': -3,
    'tags': -3,
    'tool': -3,
    'widget': -3,
    'player': -3,
    'popup': -3,
    'ad': -5,
    'ads': -5,
    'agegate': -5,
    'promo': -5,
    'social': -5,
    'cookie': -5,
    'newsletter': -5,
    'subscription': -5,
    'paywall': -5,
  };
  
  ExtractionService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    _dio.options.headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cache-Control': 'no-cache',
    };
  }
  
  /// Extract full content from URL
  Future<ExtractedContent> extractContent(String url, {
    bool includeImages = true,
    bool includeVideos = true,
    bool multiPage = true,
  }) async {
    try {
      // Fetch the page
      final response = await _dio.get(url);
      final document = html_parser.parse(response.data);
      
      // Pre-process: remove unwanted elements
      _removeUnwantedElements(document);
      
      // Extract metadata
      final metadata = _extractMetadata(document, url);
      
      // Find and score content candidates
      final candidates = _findContentCandidates(document);
      
      // Select best candidate
      final topCandidate = _selectTopCandidate(candidates);
      
      if (topCandidate == null) {
        throw ExtractionException('No suitable content found');
      }
      
      // Clean and prepare content
      final content = _prepareContent(topCandidate, includeImages, includeVideos);
      
      // Extract multi-page content if enabled
      String fullContent = content;
      List<String> allPages = [url];
      
      if (multiPage) {
        final nextPages = await _extractMultiPageContent(document, url);
        for (final nextPage in nextPages) {
          try {
            final nextContent = await extractContent(
              nextPage,
              includeImages: includeImages,
              includeVideos: includeVideos,
              multiPage: false, // Prevent infinite recursion
            );
            fullContent += '\n\n' + nextContent.content;
            allPages.add(nextPage);
          } catch (e) {
            // Continue with what we have
            break;
          }
        }
      }
      
      // Calculate reading metrics
      final wordCount = _countWords(fullContent);
      final readingTime = (wordCount / 250).ceil(); // Average 250 WPM
      
      return ExtractedContent(
        content: fullContent,
        title: metadata.title,
        author: metadata.author,
        publishedDate: metadata.publishedDate,
        mainImage: metadata.mainImage,
        excerpt: metadata.excerpt,
        wordCount: wordCount,
        readingTime: readingTime,
        images: _extractImages(document),
        videos: _extractVideos(document),
        links: _extractLinks(document),
        pages: allPages,
        success: true,
      );
    } catch (e) {
      return ExtractedContent(
        content: '',
        title: '',
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Remove unwanted elements before processing
  void _removeUnwantedElements(html.Document document) {
    // Remove script and style tags
    document.querySelectorAll('script, style, noscript').forEach((e) => e.remove());
    
    // Remove common ad elements
    document.querySelectorAll('[id*="ad"], [class*="ad"], [id*="banner"], [class*="banner"]')
      .where((e) => !e.classes.contains('article') && !e.classes.contains('header'))
      .forEach((e) => e.remove());
    
    // Remove social media elements
    document.querySelectorAll('[class*="social"], [class*="share"], [id*="social"], [id*="share"]')
      .where((e) => !e.classes.contains('article'))
      .forEach((e) => e.remove());
    
    // Remove cookie notices
    document.querySelectorAll('[class*="cookie"], [id*="cookie"], [class*="gdpr"], [id*="gdpr"]')
      .forEach((e) => e.remove());
    
    // Remove popups and modals
    document.querySelectorAll('[class*="popup"], [class*="modal"], [id*="popup"], [id*="modal"]')
      .forEach((e) => e.remove());
    
    // Remove navigation elements
    document.querySelectorAll('nav, [role="navigation"]').forEach((e) => e.remove());
    
    // Remove forms (usually newsletter signups)
    document.querySelectorAll('form').forEach((e) => e.remove());
  }
  
  /// Extract metadata from document
  _ArticleMetadata _extractMetadata(html.Document document, String url) {
    // Title extraction
    String? title = document.querySelector('meta[property="og:title"]')?.attributes['content'] ??
                   document.querySelector('meta[name="twitter:title"]')?.attributes['content'] ??
                   document.querySelector('h1')?.text ??
                   document.querySelector('title')?.text;
    
    // Author extraction
    String? author = document.querySelector('meta[name="author"]')?.attributes['content'] ??
                    document.querySelector('meta[property="article:author"]')?.attributes['content'] ??
                    document.querySelector('[itemprop="author"]')?.text ??
                    document.querySelector('.author')?.text ??
                    document.querySelector('.byline')?.text;
    
    // Date extraction
    String? publishedDate = document.querySelector('meta[property="article:published_time"]')?.attributes['content'] ??
                           document.querySelector('meta[name="publish_date"]')?.attributes['content'] ??
                           document.querySelector('time[datetime]')?.attributes['datetime'] ??
                           document.querySelector('[itemprop="datePublished"]')?.attributes['datetime'];
    
    // Main image extraction
    String? mainImage = document.querySelector('meta[property="og:image"]')?.attributes['content'] ??
                       document.querySelector('meta[name="twitter:image"]')?.attributes['content'] ??
                       document.querySelector('img[itemprop="image"]')?.attributes['src'];
    
    // Excerpt extraction
    String? excerpt = document.querySelector('meta[property="og:description"]')?.attributes['content'] ??
                     document.querySelector('meta[name="description"]')?.attributes['content'];
    
    return _ArticleMetadata(
      title: title?.trim(),
      author: author?.trim(),
      publishedDate: publishedDate,
      mainImage: mainImage != null ? _makeAbsoluteUrl(mainImage, url) : null,
      excerpt: excerpt?.trim(),
    );
  }
  
  /// Find content candidates
  List<_ContentCandidate> _findContentCandidates(html.Document document) {
    final candidates = <_ContentCandidate>[];
    
    // Look for article-like elements
    final elements = document.querySelectorAll('div, section, article, main');
    
    for (final element in elements) {
      // Skip if too short
      final textLength = element.text.trim().length;
      if (textLength < 25) continue;
      
      // Calculate content score
      double score = 0;
      
      // Score based on class and id
      final classAndId = '${element.classes.join(' ')} ${element.id}'.toLowerCase();
      
      _positiveScores.forEach((key, value) {
        if (classAndId.contains(key)) {
          score += value;
        }
      });
      
      _negativeScores.forEach((key, value) {
        if (classAndId.contains(key)) {
          score += value;
        }
      });
      
      // Score based on paragraph count
      final paragraphs = element.querySelectorAll('p');
      score += paragraphs.length * 0.5;
      
      // Score based on text density
      final linkDensity = _calculateLinkDensity(element);
      score *= (1 - linkDensity);
      
      // Score based on punctuation
      final commas = element.text.split(',').length - 1;
      score += commas * 0.2;
      
      // Store candidate
      if (score > 0) {
        candidates.add(_ContentCandidate(
          element: element,
          score: score,
          textLength: textLength,
        ));
      }
    }
    
    return candidates;
  }
  
  /// Calculate link density
  double _calculateLinkDensity(html.Element element) {
    final textLength = element.text.length;
    if (textLength == 0) return 1.0;
    
    final linkTextLength = element.querySelectorAll('a')
      .map((a) => a.text.length)
      .fold(0, (sum, length) => sum + length);
    
    return linkTextLength / textLength;
  }
  
  /// Select top candidate
  _ContentCandidate? _selectTopCandidate(List<_ContentCandidate> candidates) {
    if (candidates.isEmpty) return null;
    
    // Sort by score
    candidates.sort((a, b) => b.score.compareTo(a.score));
    
    // Return top candidate if significantly better
    if (candidates.length == 1 || candidates[0].score > candidates[1].score * 1.5) {
      return candidates[0];
    }
    
    // Otherwise, consider text length as tiebreaker
    final topScorers = candidates.take(3).toList();
    topScorers.sort((a, b) => b.textLength.compareTo(a.textLength));
    
    return topScorers[0];
  }
  
  /// Prepare content for display
  String _prepareContent(
    _ContentCandidate candidate,
    bool includeImages,
    bool includeVideos,
  ) {
    final element = candidate.element.clone(true);
    
    // Remove remaining unwanted elements
    element.querySelectorAll('aside, .sidebar, .related, .advertisement').forEach((e) => e.remove());
    
    // Clean attributes
    element.querySelectorAll('*').forEach((e) {
      e.attributes.removeWhere((key, value) => 
        key.startsWith('data-') || 
        key == 'style' || 
        key == 'onclick' ||
        key == 'onload'
      );
    });
    
    // Process images
    if (!includeImages) {
      element.querySelectorAll('img').forEach((e) => e.remove());
    } else {
      element.querySelectorAll('img').forEach((img) {
        // Ensure absolute URLs
        final src = img.attributes['src'];
        if (src != null && !src.startsWith('http')) {
          img.attributes['src'] = _makeAbsoluteUrl(src, '');
        }
        
        // Add loading lazy
        img.attributes['loading'] = 'lazy';
      });
    }
    
    // Process videos
    if (!includeVideos) {
      element.querySelectorAll('video, iframe').forEach((e) => e.remove());
    }
    
    // Convert to clean HTML
    return _cleanHtml(element.innerHtml);
  }
  
  /// Clean HTML content
  String _cleanHtml(String html) {
    // Remove extra whitespace
    html = html.replaceAll(RegExp(r'\s+'), ' ');
    
    // Remove empty elements
    html = html.replaceAll(RegExp(r'<(\w+)(\s[^>]*)?>[\s]*</\1>'), '');
    
    // Fix broken tags
    html = html.replaceAll(RegExp(r'<(\w+)(\s[^>]*)?/>'), '<$1$2></$1>');
    
    return html.trim();
  }
  
  /// Extract multi-page content
  Future<List<String>> _extractMultiPageContent(html.Document document, String currentUrl) async {
    final pages = <String>[];
    
    // Look for pagination links
    final paginationSelectors = [
      'a.next',
      'a[rel="next"]',
      'a:contains("Next")',
      'a:contains("Continue")',
      '.pagination a',
      'a.page-link',
    ];
    
    for (final selector in paginationSelectors) {
      try {
        final nextLink = document.querySelector(selector);
        if (nextLink != null) {
          final href = nextLink.attributes['href'];
          if (href != null && !href.startsWith('#')) {
            final nextUrl = _makeAbsoluteUrl(href, currentUrl);
            
            // Verify it's the same domain
            final currentUri = Uri.parse(currentUrl);
            final nextUri = Uri.parse(nextUrl);
            
            if (currentUri.host == nextUri.host) {
              pages.add(nextUrl);
              
              // Look for more pages
              try {
                final nextResponse = await _dio.get(nextUrl);
                final nextDoc = html_parser.parse(nextResponse.data);
                final morePa
                final morePages = await _extractMultiPageContent(nextDoc, nextUrl);
                pages.addAll(morePages);
              } catch (e) {
                // Stop on error
              }
              
              break; // Use first valid pagination link
            }
          }
        }
      } catch (e) {
        // Continue trying other selectors
      }
    }
    
    return pages;
  }
  
  /// Count words in content
  int _countWords(String content) {
    // Remove HTML tags
    final text = content.replaceAll(RegExp(r'<[^>]*>'), ' ');
    
    // Split by whitespace and count
    return text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
  }
  
  /// Extract images from document
  List<ExtractedImage> _extractImages(html.Document document) {
    final images = <ExtractedImage>[];
    
    document.querySelectorAll('img').forEach((img) {
      final src = img.attributes['src'];
      if (src != null && src.isNotEmpty) {
        images.add(ExtractedImage(
          url: src,
          alt: img.attributes['alt'],
          width: int.tryParse(img.attributes['width'] ?? ''),
          height: int.tryParse(img.attributes['height'] ?? ''),
        ));
      }
    });
    
    return images;
  }
  
  /// Extract videos from document
  List<ExtractedVideo> _extractVideos(html.Document document) {
    final videos = <ExtractedVideo>[];
    
    // Extract video tags
    document.querySelectorAll('video').forEach((video) {
      final src = video.attributes['src'] ?? 
                  video.querySelector('source')?.attributes['src'];
      
      if (src != null && src.isNotEmpty) {
        videos.add(ExtractedVideo(
          url: src,
          type: 'video',
          poster: video.attributes['poster'],
        ));
      }
    });
    
    // Extract YouTube/Vimeo embeds
    document.querySelectorAll('iframe').forEach((iframe) {
      final src = iframe.attributes['src'];
      if (src != null) {
        if (src.contains('youtube.com') || src.contains('youtu.be')) {
          videos.add(ExtractedVideo(
            url: src,
            type: 'youtube',
          ));
        } else if (src.contains('vimeo.com')) {
          videos.add(ExtractedVideo(
            url: src,
            type: 'vimeo',
          ));
        }
      }
    });
    
    return videos;
  }
  
  /// Extract links from document
  List<ExtractedLink> _extractLinks(html.Document document) {
    final links = <ExtractedLink>[];
    final seen = <String>{};
    
    document.querySelectorAll('a[href]').forEach((a) {
      final href = a.attributes['href'];
      if (href != null && !href.startsWith('#') && !seen.contains(href)) {
        seen.add(href);
        links.add(ExtractedLink(
          url: href,
          text: a.text.trim(),
        ));
      }
    });
    
    return links;
  }
  
  /// Make URL absolute
  String _makeAbsoluteUrl(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(url).toString();
    } catch (e) {
      return url;
    }
  }
}

/// Article metadata
class _ArticleMetadata {
  final String? title;
  final String? author;
  final String? publishedDate;
  final String? mainImage;
  final String? excerpt;
  
  _ArticleMetadata({
    this.title,
    this.author,
    this.publishedDate,
    this.mainImage,
    this.excerpt,
  });
}

/// Content candidate
class _ContentCandidate {
  final html.Element element;
  final double score;
  final int textLength;
  
  _ContentCandidate({
    required this.element,
    required this.score,
    required this.textLength,
  });
}

/// Extracted content result
class ExtractedContent {
  final String content;
  final String? title;
  final String? author;
  final String? publishedDate;
  final String? mainImage;
  final String? excerpt;
  final int? wordCount;
  final int? readingTime;
  final List<ExtractedImage>? images;
  final List<ExtractedVideo>? videos;
  final List<ExtractedLink>? links;
  final List<String>? pages;
  final bool success;
  final String? error;
  
  ExtractedContent({
    required this.content,
    this.title,
    this.author,
    this.publishedDate,
    this.mainImage,
    this.excerpt,
    this.wordCount,
    this.readingTime,
    this.images,
    this.videos,
    this.links,
    this.pages,
    required this.success,
    this.error,
  });
}

/// Extracted image
class ExtractedImage {
  final String url;
  final String? alt;
  final int? width;
  final int? height;
  
  ExtractedImage({
    required this.url,
    this.alt,
    this.width,
    this.height,
  });
}

/// Extracted video
class ExtractedVideo {
  final String url;
  final String type;
  final String? poster;
  
  ExtractedVideo({
    required this.url,
    required this.type,
    this.poster,
  });
}

/// Extracted link
class ExtractedLink {
  final String url;
  final String text;
  
  ExtractedLink({
    required this.url,
    required this.text,
  });
}

/// Extraction exception
class ExtractionException implements Exception {
  final String message;
  
  ExtractionException(this.message);
  
  @override
  String toString() => message;
}