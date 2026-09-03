import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/feed.dart';
import '../models/article.dart';

/// Atom 1.0 parser with full spec support
class AtomParser {
  static const String atomNamespace = 'http://www.w3.org/2005/Atom';
  static const String xhtmlNamespace = 'http://www.w3.org/1999/xhtml';
  
  /// Parse Atom feed from XML string
  Future<Feed> parseFeed(String xmlString, String feedUrl) async {
    try {
      final document = XmlDocument.parse(xmlString);
      final feed = document.findElements('feed', namespace: atomNamespace).firstOrNull ??
                   document.findElements('feed').firstOrNull;
      
      if (feed == null) {
        throw FormatException('Invalid Atom feed: missing <feed> element');
      }
      
      // Parse feed metadata
      final title = _getElementText(feed, 'title') ?? 'Untitled Feed';
      final subtitle = _getElementText(feed, 'subtitle');
      
      // Find alternate link for the feed
      String? link;
      final links = feed.findElements('link', namespace: atomNamespace);
      for (final linkElement in links) {
        final rel = linkElement.getAttribute('rel') ?? 'alternate';
        if (rel == 'alternate') {
          link = linkElement.getAttribute('href');
          break;
        }
      }
      
      // Parse other metadata
      final id = _getElementText(feed, 'id');
      final rights = _getElementText(feed, 'rights');
      final generator = _getElementText(feed, 'generator');
      
      // Parse logo or icon
      final logo = _getElementText(feed, 'logo');
      final icon = _getElementText(feed, 'icon');
      final imageUrl = logo ?? icon;
      
      // Parse updated date
      DateTime? updated;
      final updatedStr = _getElementText(feed, 'updated');
      if (updatedStr != null) {
        updated = _parseAtomDate(updatedStr);
      }
      
      // Parse author
      String? author;
      final authorElement = feed.findElements('author', namespace: atomNamespace).firstOrNull;
      if (authorElement != null) {
        author = _getElementText(authorElement, 'name');
      }
      
      return Feed(
        url: feedUrl,
        title: _cleanText(title),
        description: subtitle,
        link: link,
        copyright: rights,
        generator: generator,
        imageUrl: imageUrl,
        type: FeedType.atom,
        lastFetched: DateTime.now(),
      );
    } catch (e) {
      throw FormatException('Failed to parse Atom feed: $e');
    }
  }
  
  /// Parse articles from Atom feed
  Future<List<Article>> parseArticles(String xmlString, String feedId) async {
    try {
      final document = XmlDocument.parse(xmlString);
      final entries = document.findAllElements('entry');
      
      final articles = <Article>[];
      
      for (final entry in entries) {
        try {
          final article = _parseEntry(entry, feedId);
          if (article != null) {
            articles.add(article);
          }
        } catch (e) {
          // Skip invalid entries but continue parsing
          print('Failed to parse entry: $e');
        }
      }
      
      return articles;
    } catch (e) {
      throw FormatException('Failed to parse Atom articles: $e');
    }
  }
  
  /// Parse individual entry
  Article? _parseEntry(XmlElement entry, String feedId) {
    // Required fields
    final title = _getElementText(entry, 'title');
    if (title == null || title.isEmpty) {
      return null;
    }
    
    // ID (required in Atom)
    final id = _getElementText(entry, 'id') ?? title;
    
    // Find alternate link
    String? url;
    final links = entry.findElements('link');
    for (final link in links) {
      final rel = link.getAttribute('rel') ?? 'alternate';
      if (rel == 'alternate') {
        url = link.getAttribute('href');
        break;
      }
    }
    url ??= '';
    
    // Parse content and summary
    final content = _parseContent(entry);
    final summary = _getElementText(entry, 'summary');
    
    // Parse author
    String? author;
    final authorElement = entry.findElements('author').firstOrNull;
    if (authorElement != null) {
      final name = _getElementText(authorElement, 'name');
      final email = _getElementText(authorElement, 'email');
      if (name != null) {
        author = email != null ? '$name <$email>' : name;
      }
    }
    
    // Parse dates
    DateTime? published;
    final publishedStr = _getElementText(entry, 'published') ??
                        _getElementText(entry, 'issued'); // Atom 0.3 compatibility
    if (publishedStr != null) {
      published = _parseAtomDate(publishedStr);
    }
    
    DateTime? updated;
    final updatedStr = _getElementText(entry, 'updated') ??
                      _getElementText(entry, 'modified'); // Atom 0.3 compatibility
    if (updatedStr != null) {
      updated = _parseAtomDate(updatedStr);
    }
    
    // Use updated as published if published is not available
    published ??= updated;
    
    // Parse categories
    final categories = entry.findElements('category')
        .map((c) => c.getAttribute('term') ?? c.getAttribute('label') ?? '')
        .where((c) => c.isNotEmpty)
        .toList();
    
    // Parse links for enclosures
    final enclosures = _parseEnclosures(entry);
    
    // Extract image from content
    final imageUrl = _extractImageUrl(content);
    
    return Article(
      feedId: feedId,
      guid: id,
      title: _cleanText(title),
      content: content?.text,
      summary: summary != null ? _cleanText(summary) : null,
      author: author,
      publishedAt: published,
      url: url,
      imageUrl: imageUrl,
      categories: categories.isNotEmpty ? categories : null,
      enclosures: enclosures.isNotEmpty ? enclosures : null,
    );
  }
  
  /// Parse content element
  _ContentData? _parseContent(XmlElement entry) {
    final contentElement = entry.findElements('content').firstOrNull;
    if (contentElement == null) return null;
    
    final type = contentElement.getAttribute('type') ?? 'text';
    
    String text;
    if (type == 'xhtml') {
      // XHTML content - extract inner XML
      final div = contentElement.findElements('div', namespace: xhtmlNamespace).firstOrNull;
      text = div?.innerXml ?? contentElement.innerXml;
    } else if (type == 'html') {
      // HTML content
      text = contentElement.innerText;
    } else {
      // Plain text
      text = contentElement.innerText;
    }
    
    return _ContentData(text: text, type: type);
  }
  
  /// Parse enclosures from link elements
  List<Enclosure> _parseEnclosures(XmlElement entry) {
    final enclosures = <Enclosure>[];
    
    final links = entry.findElements('link');
    for (final link in links) {
      final rel = link.getAttribute('rel');
      if (rel == 'enclosure') {
        final href = link.getAttribute('href');
        if (href != null) {
          final lengthStr = link.getAttribute('length');
          enclosures.add(Enclosure(
            url: href,
            type: link.getAttribute('type'),
            length: lengthStr != null ? int.tryParse(lengthStr) : null,
            title: link.getAttribute('title'),
          ));
        }
      }
    }
    
    return enclosures;
  }
  
  /// Extract image URL from content
  String? _extractImageUrl(String? content) {
    if (content == null) return null;
    
    try {
      final document = html_parser.parse(content);
      final img = document.querySelector('img');
      return img?.attributes['src'];
    } catch (e) {
      return null;
    }
  }
  
  /// Get element text
  String? _getElementText(XmlElement parent, String name) {
    return parent.findElements(name, namespace: atomNamespace).firstOrNull?.innerText.trim() ??
           parent.findElements(name).firstOrNull?.innerText.trim();
  }
  
  /// Parse Atom date format (RFC 3339)
  DateTime? _parseAtomDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      // Handle various date formats
      // Atom dates should be RFC 3339 but some feeds use other formats
      try {
        // Try without timezone
        if (dateStr.contains('T')) {
          final parts = dateStr.split('T');
          if (parts.length == 2) {
            final datePart = parts[0];
            final timePart = parts[1].split(RegExp(r'[+-Z]'))[0];
            return DateTime.parse('${datePart}T$timePart');
          }
        }
      } catch (e) {
        // Give up
      }
      return null;
    }
  }
  
  /// Clean text content
  String _cleanText(String text) {
    // Decode HTML entities and clean whitespace
    final document = html_parser.parse(text);
    return document.body?.text ?? text;
  }
  
  /// Validate Atom feed structure
  bool isValidAtomFeed(String xmlString) {
    try {
      final document = XmlDocument.parse(xmlString);
      final feed = document.findElements('feed', namespace: atomNamespace).firstOrNull ??
                   document.findElements('feed').firstOrNull;
      return feed != null;
    } catch (e) {
      return false;
    }
  }
}

/// Helper class for content data
class _ContentData {
  final String text;
  final String type;
  
  _ContentData({required this.text, required this.type});
}