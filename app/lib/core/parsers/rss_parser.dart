import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../models/feed.dart';
import '../models/article.dart';

/// RSS 2.0 parser with support for common namespaces
class RssParser {
  // Namespace URIs
  static const String dcNamespace = 'http://purl.org/dc/elements/1.1/';
  static const String contentNamespace = 'http://purl.org/rss/1.0/modules/content/';
  static const String mediaNamespace = 'http://search.yahoo.com/mrss/';
  static const String atomNamespace = 'http://www.w3.org/2005/Atom';
  static const String itunesNamespace = 'http://www.itunes.com/dtds/podcast-1.0.dtd';
  
  /// Parse RSS feed from XML string
  Future<Feed> parseFeed(String xmlString, String feedUrl) async {
    try {
      final document = XmlDocument.parse(xmlString);
      final rss = document.findElements('rss').firstOrNull;
      
      if (rss == null) {
        throw FormatException('Invalid RSS feed: missing <rss> element');
      }
      
      final channel = rss.findElements('channel').firstOrNull;
      if (channel == null) {
        throw FormatException('Invalid RSS feed: missing <channel> element');
      }
      
      // Parse feed metadata
      final title = _getElementText(channel, 'title') ?? 'Untitled Feed';
      final description = _getElementText(channel, 'description');
      final link = _getElementText(channel, 'link');
      final language = _getElementText(channel, 'language');
      final copyright = _getElementText(channel, 'copyright');
      final generator = _getElementText(channel, 'generator');
      
      // Parse image
      String? imageUrl;
      final image = channel.findElements('image').firstOrNull;
      if (image != null) {
        imageUrl = _getElementText(image, 'url');
      }
      
      // iTunes image fallback
      imageUrl ??= _getItunesImage(channel);
      
      // Parse last build date
      DateTime? lastBuildDate;
      final lastBuildDateStr = _getElementText(channel, 'lastBuildDate') ??
          _getElementText(channel, 'pubDate');
      if (lastBuildDateStr != null) {
        lastBuildDate = _parseDate(lastBuildDateStr);
      }
      
      return Feed(
        url: feedUrl,
        title: title,
        description: description,
        link: link,
        language: language,
        copyright: copyright,
        generator: generator,
        imageUrl: imageUrl,
        type: FeedType.rss,
        lastFetched: DateTime.now(),
      );
    } catch (e) {
      throw FormatException('Failed to parse RSS feed: $e');
    }
  }
  
  /// Parse articles from RSS feed
  Future<List<Article>> parseArticles(String xmlString, String feedId) async {
    try {
      final document = XmlDocument.parse(xmlString);
      final items = document.findAllElements('item');
      
      final articles = <Article>[];
      
      for (final item in items) {
        try {
          final article = _parseItem(item, feedId);
          if (article != null) {
            articles.add(article);
          }
        } catch (e) {
          // Skip invalid items but continue parsing
          print('Failed to parse item: $e');
        }
      }
      
      return articles;
    } catch (e) {
      throw FormatException('Failed to parse RSS articles: $e');
    }
  }
  
  /// Parse individual item
  Article? _parseItem(XmlElement item, String feedId) {
    // Required fields
    final title = _getElementText(item, 'title');
    if (title == null || title.isEmpty) {
      return null;
    }
    
    // GUID (fallback to link if not present)
    final guid = _getElementText(item, 'guid') ?? 
                 _getElementText(item, 'link') ?? 
                 title;
    
    // URL
    final url = _getElementText(item, 'link') ?? '';
    
    // Description and content
    final description = _getElementText(item, 'description');
    final content = _getNamespacedElementText(item, 'encoded', contentNamespace) ??
                   description;
    
    // Clean HTML from content
    final cleanDescription = description != null ? _cleanHtml(description) : null;
    
    // Author
    final author = _getElementText(item, 'author') ??
                  _getNamespacedElementText(item, 'creator', dcNamespace) ??
                  _getItunesAuthor(item);
    
    // Published date
    DateTime? publishedAt;
    final pubDateStr = _getElementText(item, 'pubDate') ??
                      _getNamespacedElementText(item, 'date', dcNamespace);
    if (pubDateStr != null) {
      publishedAt = _parseDate(pubDateStr);
    }
    
    // Categories
    final categories = item.findElements('category')
        .map((e) => e.innerText.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    
    // Media content
    final imageUrl = _extractImageUrl(item, content);
    
    // Enclosures
    final enclosures = _parseEnclosures(item);
    
    return Article(
      feedId: feedId,
      guid: guid,
      title: _cleanHtml(title),
      content: content,
      summary: cleanDescription,
      author: author,
      publishedAt: publishedAt,
      url: url,
      imageUrl: imageUrl,
      categories: categories.isNotEmpty ? categories : null,
      enclosures: enclosures.isNotEmpty ? enclosures : null,
    );
  }
  
  /// Extract image URL from item
  String? _extractImageUrl(XmlElement item, String? content) {
    // Try media:content first
    final mediaContent = item.findElements('content', namespace: mediaNamespace);
    for (final media in mediaContent) {
      final medium = media.getAttribute('medium');
      final url = media.getAttribute('url');
      if (medium == 'image' && url != null) {
        return url;
      }
    }
    
    // Try media:thumbnail
    final mediaThumbnail = item.findElements('thumbnail', namespace: mediaNamespace)
        .firstOrNull;
    if (mediaThumbnail != null) {
      final url = mediaThumbnail.getAttribute('url');
      if (url != null) return url;
    }
    
    // Try enclosure with image type
    final enclosure = item.findElements('enclosure').firstOrNull;
    if (enclosure != null) {
      final type = enclosure.getAttribute('type');
      final url = enclosure.getAttribute('url');
      if (type != null && type.startsWith('image/') && url != null) {
        return url;
      }
    }
    
    // Extract from content HTML
    if (content != null) {
      final document = html_parser.parse(content);
      final img = document.querySelector('img');
      if (img != null) {
        return img.attributes['src'];
      }
    }
    
    return null;
  }
  
  /// Parse enclosures
  List<Enclosure> _parseEnclosures(XmlElement item) {
    final enclosures = <Enclosure>[];
    
    // Standard enclosures
    for (final enclosure in item.findElements('enclosure')) {
      final url = enclosure.getAttribute('url');
      if (url != null) {
        enclosures.add(Enclosure(
          url: url,
          type: enclosure.getAttribute('type'),
          length: int.tryParse(enclosure.getAttribute('length') ?? ''),
        ));
      }
    }
    
    // Media RSS content
    for (final media in item.findElements('content', namespace: mediaNamespace)) {
      final url = media.getAttribute('url');
      if (url != null) {
        enclosures.add(Enclosure(
          url: url,
          type: media.getAttribute('type'),
          length: int.tryParse(media.getAttribute('fileSize') ?? ''),
          duration: media.getAttribute('duration'),
        ));
      }
    }
    
    return enclosures;
  }
  
  /// Get element text
  String? _getElementText(XmlElement parent, String name) {
    return parent.findElements(name).firstOrNull?.innerText.trim();
  }
  
  /// Get namespaced element text
  String? _getNamespacedElementText(XmlElement parent, String name, String namespace) {
    return parent.findElements(name, namespace: namespace)
        .firstOrNull?.innerText.trim();
  }
  
  /// Get iTunes author
  String? _getItunesAuthor(XmlElement item) {
    return item.findElements('author', namespace: itunesNamespace)
        .firstOrNull?.innerText.trim();
  }
  
  /// Get iTunes image
  String? _getItunesImage(XmlElement channel) {
    final image = channel.findElements('image', namespace: itunesNamespace)
        .firstOrNull;
    return image?.getAttribute('href');
  }
  
  /// Parse various date formats
  DateTime? _parseDate(String dateStr) {
    try {
      // Try parsing as RFC 822 (standard RSS date format)
      return DateTime.parse(dateStr);
    } catch (e) {
      // Try other common formats
      final formats = [
        RegExp(r'(\w{3}),\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-]\d{4})'),
        RegExp(r'(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'),
      ];
      
      // Add more date parsing logic as needed
      return null;
    }
  }
  
  /// Clean HTML tags from text
  String _cleanHtml(String html) {
    final document = html_parser.parse(html);
    return document.body?.text ?? html;
  }
  
  /// Validate RSS feed structure
  bool isValidRssFeed(String xmlString) {
    try {
      final document = XmlDocument.parse(xmlString);
      final rss = document.findElements('rss').firstOrNull;
      final channel = rss?.findElements('channel').firstOrNull;
      return rss != null && channel != null;
    } catch (e) {
      return false;
    }
  }
}