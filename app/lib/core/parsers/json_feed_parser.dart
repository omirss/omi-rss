import 'dart:convert';
import '../models/feed.dart';
import '../models/article.dart';

/// JSON Feed 1.1 parser
class JsonFeedParser {
  /// Parse JSON Feed from string
  Future<Feed> parseFeed(String jsonString, String feedUrl) async {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonString);
      
      // Validate version
      final version = json['version'] as String?;
      if (version == null || !version.startsWith('https://jsonfeed.org/version/')) {
        throw FormatException('Invalid JSON Feed: missing or invalid version');
      }
      
      // Required fields
      final title = json['title'] as String?;
      if (title == null || title.isEmpty) {
        throw FormatException('Invalid JSON Feed: missing title');
      }
      
      // Optional fields
      final description = json['description'] as String?;
      final homePageUrl = json['home_page_url'] as String?;
      final feedUrl = json['feed_url'] as String?;
      final icon = json['icon'] as String?;
      final favicon = json['favicon'] as String?;
      final language = json['language'] as String?;
      
      // Author
      String? authorName;
      final author = json['author'] as Map<String, dynamic>?;
      if (author != null) {
        authorName = author['name'] as String?;
      }
      
      // Hub for real-time updates
      final hubs = json['hubs'] as List<dynamic>?;
      
      return Feed(
        url: feedUrl ?? feedUrl,
        title: title,
        description: description,
        link: homePageUrl,
        imageUrl: icon ?? favicon,
        language: language,
        type: FeedType.json,
        lastFetched: DateTime.now(),
        customFields: {
          'version': version,
          'hubs': hubs,
          'author': author,
        },
      );
    } catch (e) {
      throw FormatException('Failed to parse JSON Feed: $e');
    }
  }
  
  /// Parse articles from JSON Feed
  Future<List<Article>> parseArticles(String jsonString, String feedId) async {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonString);
      final items = json['items'] as List<dynamic>?;
      
      if (items == null) {
        return [];
      }
      
      final articles = <Article>[];
      
      for (final item in items) {
        try {
          if (item is Map<String, dynamic>) {
            final article = _parseItem(item, feedId);
            if (article != null) {
              articles.add(article);
            }
          }
        } catch (e) {
          // Skip invalid items but continue parsing
          print('Failed to parse item: $e');
        }
      }
      
      return articles;
    } catch (e) {
      throw FormatException('Failed to parse JSON Feed articles: $e');
    }
  }
  
  /// Parse individual item
  Article? _parseItem(Map<String, dynamic> item, String feedId) {
    // ID is required
    final id = item['id']?.toString();
    if (id == null || id.isEmpty) {
      return null;
    }
    
    // Extract content
    final contentHtml = item['content_html'] as String?;
    final contentText = item['content_text'] as String?;
    final summary = item['summary'] as String?;
    
    // Prefer HTML content over text
    final content = contentHtml ?? contentText;
    
    // URL
    final url = item['url'] as String? ?? '';
    final externalUrl = item['external_url'] as String?;
    
    // Title (optional in JSON Feed but we require it)
    final title = item['title'] as String?;
    if (title == null || title.isEmpty) {
      // Try to extract from content
      final extractedTitle = _extractTitle(contentText ?? summary ?? '');
      if (extractedTitle.isEmpty) {
        return null;
      }
    }
    
    // Dates
    DateTime? publishedAt;
    final datePublished = item['date_published'] as String?;
    if (datePublished != null) {
      publishedAt = DateTime.tryParse(datePublished);
    }
    
    DateTime? modifiedAt;
    final dateModified = item['date_modified'] as String?;
    if (dateModified != null) {
      modifiedAt = DateTime.tryParse(dateModified);
    }
    
    // Author
    String? authorName;
    final author = item['author'] as Map<String, dynamic>?;
    if (author != null) {
      authorName = author['name'] as String?;
    }
    
    // Tags
    final tags = (item['tags'] as List<dynamic>?)
        ?.whereType<String>()
        .toList();
    
    // Images
    final image = item['image'] as String?;
    final bannerImage = item['banner_image'] as String?;
    final imageUrl = image ?? bannerImage;
    
    // Attachments
    final attachments = item['attachments'] as List<dynamic>?;
    final enclosures = _parseAttachments(attachments);
    
    // Language
    final language = item['language'] as String?;
    
    return Article(
      feedId: feedId,
      guid: id,
      title: title ?? _extractTitle(content ?? ''),
      content: contentHtml,
      summary: summary ?? contentText,
      author: authorName,
      publishedAt: publishedAt ?? modifiedAt,
      url: externalUrl ?? url,
      imageUrl: imageUrl,
      categories: tags,
      enclosures: enclosures.isNotEmpty ? enclosures : null,
      language: language,
      customFields: {
        'date_modified': dateModified,
        'json_feed_version': true,
      },
    );
  }
  
  /// Parse attachments into enclosures
  List<Enclosure> _parseAttachments(List<dynamic>? attachments) {
    if (attachments == null) return [];
    
    final enclosures = <Enclosure>[];
    
    for (final attachment in attachments) {
      if (attachment is Map<String, dynamic>) {
        final url = attachment['url'] as String?;
        if (url != null) {
          final mimeType = attachment['mime_type'] as String?;
          final sizeInBytes = attachment['size_in_bytes'] as int?;
          final title = attachment['title'] as String?;
          final durationInSeconds = attachment['duration_in_seconds'] as int?;
          
          enclosures.add(Enclosure(
            url: url,
            type: mimeType,
            length: sizeInBytes,
            title: title,
            duration: durationInSeconds?.toString(),
          ));
        }
      }
    }
    
    return enclosures;
  }
  
  /// Extract title from content
  String _extractTitle(String content) {
    // Take first line or first 50 characters
    final lines = content.split('\n');
    if (lines.isNotEmpty && lines.first.isNotEmpty) {
      return lines.first.length > 100 
          ? '${lines.first.substring(0, 97)}...'
          : lines.first;
    }
    
    if (content.length > 50) {
      return '${content.substring(0, 47)}...';
    }
    
    return content;
  }
  
  /// Validate JSON Feed structure
  bool isValidJsonFeed(String jsonString) {
    try {
      final json = jsonDecode(jsonString);
      if (json is! Map<String, dynamic>) return false;
      
      final version = json['version'] as String?;
      final title = json['title'] as String?;
      
      return version != null && 
             version.startsWith('https://jsonfeed.org/version/') &&
             title != null && 
             title.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  
  /// Get JSON Feed version
  String? getVersion(String jsonString) {
    try {
      final json = jsonDecode(jsonString);
      if (json is Map<String, dynamic>) {
        return json['version'] as String?;
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }
}