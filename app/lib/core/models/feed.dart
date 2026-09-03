import 'package:uuid/uuid.dart';

/// Feed model representing an RSS/Atom/JSON feed
class Feed {
  final String id;
  final String url;
  final String title;
  final String? description;
  final String? link;
  final String? siteUrl; // Website URL (different from feed URL)
  final String? customTitle; // User-defined title override
  final String? categoryId;
  final String? faviconUrl;
  final DateTime? lastFetched;
  final String? etag;
  final String? lastModified;
  final int updateFrequency; // in seconds
  final bool isActive;
  final FeedType type;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Additional metadata
  final String? language;
  final String? copyright;
  final String? generator;
  final String? imageUrl;
  final Map<String, dynamic>? customFields;
  
  // Feed health tracking
  final int successfulFetches;
  final int failedFetches;
  final double successRate;
  final String? lastError;
  final DateTime? lastErrorAt;
  
  Feed({
    String? id,
    required this.url,
    required this.title,
    this.description,
    this.link,
    this.siteUrl,
    this.customTitle,
    this.categoryId,
    this.faviconUrl,
    this.lastFetched,
    this.etag,
    this.lastModified,
    this.updateFrequency = 3600,
    this.isActive = true,
    this.type = FeedType.rss,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.language,
    this.copyright,
    this.generator,
    this.imageUrl,
    this.customFields,
    this.successfulFetches = 0,
    this.failedFetches = 0,
    this.successRate = 0.0,
    this.lastError,
    this.lastErrorAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
  
  Feed copyWith({
    String? id,
    String? url,
    String? title,
    String? description,
    String? link,
    String? siteUrl,
    String? customTitle,
    String? categoryId,
    String? faviconUrl,
    DateTime? lastFetched,
    String? etag,
    String? lastModified,
    int? updateFrequency,
    bool? isActive,
    FeedType? type,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? language,
    String? copyright,
    String? generator,
    String? imageUrl,
    Map<String, dynamic>? customFields,
    int? successfulFetches,
    int? failedFetches,
    double? successRate,
    String? lastError,
    DateTime? lastErrorAt,
  }) {
    return Feed(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      description: description ?? this.description,
      link: link ?? this.link,
      siteUrl: siteUrl ?? this.siteUrl,
      customTitle: customTitle ?? this.customTitle,
      categoryId: categoryId ?? this.categoryId,
      faviconUrl: faviconUrl ?? this.faviconUrl,
      lastFetched: lastFetched ?? this.lastFetched,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      updateFrequency: updateFrequency ?? this.updateFrequency,
      isActive: isActive ?? this.isActive,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      language: language ?? this.language,
      copyright: copyright ?? this.copyright,
      generator: generator ?? this.generator,
      imageUrl: imageUrl ?? this.imageUrl,
      customFields: customFields ?? this.customFields,
      successfulFetches: successfulFetches ?? this.successfulFetches,
      failedFetches: failedFetches ?? this.failedFetches,
      successRate: successRate ?? this.successRate,
      lastError: lastError ?? this.lastError,
      lastErrorAt: lastErrorAt ?? this.lastErrorAt,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'description': description,
      'link': link,
      'siteUrl': siteUrl,
      'customTitle': customTitle,
      'categoryId': categoryId,
      'faviconUrl': faviconUrl,
      'lastFetched': lastFetched?.toIso8601String(),
      'etag': etag,
      'lastModified': lastModified,
      'updateFrequency': updateFrequency,
      'isActive': isActive,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'language': language,
      'copyright': copyright,
      'generator': generator,
      'imageUrl': imageUrl,
      'customFields': customFields,
      'successfulFetches': successfulFetches,
      'failedFetches': failedFetches,
      'successRate': successRate,
      'lastError': lastError,
      'lastErrorAt': lastErrorAt?.toIso8601String(),
    };
  }
  
  factory Feed.fromJson(Map<String, dynamic> json) {
    return Feed(
      id: json['id'] as String,
      url: json['url'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      link: json['link'] as String?,
      siteUrl: json['siteUrl'] as String?,
      customTitle: json['customTitle'] as String?,
      categoryId: json['categoryId'] as String?,
      faviconUrl: json['faviconUrl'] as String?,
      lastFetched: json['lastFetched'] != null
          ? DateTime.parse(json['lastFetched'] as String)
          : null,
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] as String?,
      updateFrequency: json['updateFrequency'] as int? ?? 3600,
      isActive: json['isActive'] as bool? ?? true,
      type: FeedType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => FeedType.rss,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      language: json['language'] as String?,
      copyright: json['copyright'] as String?,
      generator: json['generator'] as String?,
      imageUrl: json['imageUrl'] as String?,
      customFields: json['customFields'] as Map<String, dynamic>?,
      successfulFetches: json['successfulFetches'] as int? ?? 0,
      failedFetches: json['failedFetches'] as int? ?? 0,
      successRate: (json['successRate'] as num?)?.toDouble() ?? 0.0,
      lastError: json['lastError'] as String?,
      lastErrorAt: json['lastErrorAt'] != null
          ? DateTime.parse(json['lastErrorAt'] as String)
          : null,
    );
  }
}

/// Feed types supported
enum FeedType {
  rss,
  atom,
  json,
  unknown,
}

/// Feed statistics
class FeedStats {
  final String feedId;
  final int totalArticles;
  final int unreadArticles;
  final int starredArticles;
  final DateTime? oldestArticle;
  final DateTime? newestArticle;
  final double averageArticlesPerDay;
  final Map<DateTime, int> articlesPerDay;
  final Map<String, int> articlesPerAuthor;
  final Map<String, int> articlesPerTag;
  
  const FeedStats({
    required this.feedId,
    required this.totalArticles,
    required this.unreadArticles,
    required this.starredArticles,
    this.oldestArticle,
    this.newestArticle,
    required this.averageArticlesPerDay,
    required this.articlesPerDay,
    required this.articlesPerAuthor,
    required this.articlesPerTag,
  });
}