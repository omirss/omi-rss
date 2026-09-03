import 'package:uuid/uuid.dart';

/// Article model representing a feed item
class Article {
  final String id;
  final String feedId;
  final String guid;
  final String title;
  final String? content;
  final String? summary;
  final String? author;
  final DateTime? publishedAt;
  final String url;
  final String? imageUrl;
  final bool isRead;
  final bool isStarred;
  final bool isArchived;
  final int? readTimeSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // AI-generated fields
  final String? aiSummary;
  final List<String>? aiTags;
  final Map<String, dynamic>? perspectives;
  final double? sentimentScore;
  final double? biasScore;
  
  // Metadata
  final List<Enclosure>? enclosures;
  final List<String>? categories;
  final Map<String, dynamic>? customFields;
  final String? language;
  final String? rights;
  
  // Full-text extraction
  final String? fullContent;
  final DateTime? fullContentFetchedAt;
  final bool? fullContentAvailable;
  
  Article({
    String? id,
    required this.feedId,
    required this.guid,
    required this.title,
    this.content,
    this.summary,
    this.author,
    this.publishedAt,
    required this.url,
    this.imageUrl,
    this.isRead = false,
    this.isStarred = false,
    this.isArchived = false,
    this.readTimeSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.aiSummary,
    this.aiTags,
    this.perspectives,
    this.sentimentScore,
    this.biasScore,
    this.enclosures,
    this.categories,
    this.customFields,
    this.language,
    this.rights,
    this.fullContent,
    this.fullContentFetchedAt,
    this.fullContentAvailable,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
  
  /// Get display content (prefers full content over summary)
  String? get displayContent => fullContent ?? content ?? summary;
  
  /// Calculate estimated read time
  int get estimatedReadTime {
    if (readTimeSeconds != null) return readTimeSeconds!;
    
    final text = displayContent ?? '';
    const wordsPerMinute = 200;
    final wordCount = text.split(RegExp(r'\s+')).length;
    return ((wordCount / wordsPerMinute) * 60).ceil();
  }
  
  Article copyWith({
    String? id,
    String? feedId,
    String? guid,
    String? title,
    String? content,
    String? summary,
    String? author,
    DateTime? publishedAt,
    String? url,
    String? imageUrl,
    bool? isRead,
    bool? isStarred,
    bool? isArchived,
    int? readTimeSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? aiSummary,
    List<String>? aiTags,
    Map<String, dynamic>? perspectives,
    double? sentimentScore,
    double? biasScore,
    List<Enclosure>? enclosures,
    List<String>? categories,
    Map<String, dynamic>? customFields,
    String? language,
    String? rights,
    String? fullContent,
    DateTime? fullContentFetchedAt,
    bool? fullContentAvailable,
  }) {
    return Article(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      guid: guid ?? this.guid,
      title: title ?? this.title,
      content: content ?? this.content,
      summary: summary ?? this.summary,
      author: author ?? this.author,
      publishedAt: publishedAt ?? this.publishedAt,
      url: url ?? this.url,
      imageUrl: imageUrl ?? this.imageUrl,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      isArchived: isArchived ?? this.isArchived,
      readTimeSeconds: readTimeSeconds ?? this.readTimeSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      aiSummary: aiSummary ?? this.aiSummary,
      aiTags: aiTags ?? this.aiTags,
      perspectives: perspectives ?? this.perspectives,
      sentimentScore: sentimentScore ?? this.sentimentScore,
      biasScore: biasScore ?? this.biasScore,
      enclosures: enclosures ?? this.enclosures,
      categories: categories ?? this.categories,
      customFields: customFields ?? this.customFields,
      language: language ?? this.language,
      rights: rights ?? this.rights,
      fullContent: fullContent ?? this.fullContent,
      fullContentFetchedAt: fullContentFetchedAt ?? this.fullContentFetchedAt,
      fullContentAvailable: fullContentAvailable ?? this.fullContentAvailable,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'feedId': feedId,
      'guid': guid,
      'title': title,
      'content': content,
      'summary': summary,
      'author': author,
      'publishedAt': publishedAt?.toIso8601String(),
      'url': url,
      'imageUrl': imageUrl,
      'isRead': isRead,
      'isStarred': isStarred,
      'isArchived': isArchived,
      'readTimeSeconds': readTimeSeconds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'aiSummary': aiSummary,
      'aiTags': aiTags,
      'perspectives': perspectives,
      'sentimentScore': sentimentScore,
      'biasScore': biasScore,
      'enclosures': enclosures?.map((e) => e.toJson()).toList(),
      'categories': categories,
      'customFields': customFields,
      'language': language,
      'rights': rights,
      'fullContent': fullContent,
      'fullContentFetchedAt': fullContentFetchedAt?.toIso8601String(),
      'fullContentAvailable': fullContentAvailable,
    };
  }
  
  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      id: json['id'] as String,
      feedId: json['feedId'] as String,
      guid: json['guid'] as String,
      title: json['title'] as String,
      content: json['content'] as String?,
      summary: json['summary'] as String?,
      author: json['author'] as String?,
      publishedAt: json['publishedAt'] != null
          ? DateTime.parse(json['publishedAt'] as String)
          : null,
      url: json['url'] as String,
      imageUrl: json['imageUrl'] as String?,
      isRead: json['isRead'] as bool? ?? false,
      isStarred: json['isStarred'] as bool? ?? false,
      isArchived: json['isArchived'] as bool? ?? false,
      readTimeSeconds: json['readTimeSeconds'] as int?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      aiSummary: json['aiSummary'] as String?,
      aiTags: (json['aiTags'] as List<dynamic>?)?.cast<String>(),
      perspectives: json['perspectives'] as Map<String, dynamic>?,
      sentimentScore: (json['sentimentScore'] as num?)?.toDouble(),
      biasScore: (json['biasScore'] as num?)?.toDouble(),
      enclosures: (json['enclosures'] as List<dynamic>?)
          ?.map((e) => Enclosure.fromJson(e as Map<String, dynamic>))
          .toList(),
      categories: (json['categories'] as List<dynamic>?)?.cast<String>(),
      customFields: json['customFields'] as Map<String, dynamic>?,
      language: json['language'] as String?,
      rights: json['rights'] as String?,
      fullContent: json['fullContent'] as String?,
      fullContentFetchedAt: json['fullContentFetchedAt'] != null
          ? DateTime.parse(json['fullContentFetchedAt'] as String)
          : null,
      fullContentAvailable: json['fullContentAvailable'] as bool?,
    );
  }
}

/// Enclosure for media attachments
class Enclosure {
  final String url;
  final String? type;
  final int? length;
  final String? title;
  final String? duration;
  
  const Enclosure({
    required this.url,
    this.type,
    this.length,
    this.title,
    this.duration,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'type': type,
      'length': length,
      'title': title,
      'duration': duration,
    };
  }
  
  factory Enclosure.fromJson(Map<String, dynamic> json) {
    return Enclosure(
      url: json['url'] as String,
      type: json['type'] as String?,
      length: json['length'] as int?,
      title: json['title'] as String?,
      duration: json['duration'] as String?,
    );
  }
}

/// Author information
class Author {
  final String name;
  final String? email;
  final String? uri;
  
  const Author({
    required this.name,
    this.email,
    this.uri,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'uri': uri,
    };
  }
  
  factory Author.fromJson(Map<String, dynamic> json) {
    return Author(
      name: json['name'] as String,
      email: json['email'] as String?,
      uri: json['uri'] as String?,
    );
  }
}