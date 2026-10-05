import 'package:uuid/uuid.dart';

/// Feed model representing an RSS/Atom/JSON feed
class Feed {
  static const Object _unset = Object();

  final String id;
  final String url;
  final String title;
  final String? description;
  final String? link;
  final String? siteUrl; // Website URL (different from feed URL)
  final String? customTitle; // User-defined title override
  final String? categoryId;
  // Transport-only: server folder membership. Never persisted to
  // category_id; reconciled through folder_feeds_table instead.
  final String? folderId;
  final String? faviconUrl;
  final DateTime? lastFetched;
  final String? etag;
  final String? lastModified;
  final int updateFrequency; // in minutes
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
    this.folderId,
    this.faviconUrl,
    this.lastFetched,
    this.etag,
    this.lastModified,
    this.updateFrequency = 60,
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
  
  /// Nullable parameters use a sentinel so passing null explicitly
  /// clears the field instead of keeping the old value.
  Feed copyWith({
    String? id,
    String? url,
    String? title,
    Object? description = _unset,
    Object? link = _unset,
    Object? siteUrl = _unset,
    Object? customTitle = _unset,
    Object? categoryId = _unset,
    Object? faviconUrl = _unset,
    Object? lastFetched = _unset,
    Object? etag = _unset,
    Object? lastModified = _unset,
    int? updateFrequency,
    bool? isActive,
    FeedType? type,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? language = _unset,
    Object? copyright = _unset,
    Object? generator = _unset,
    Object? imageUrl = _unset,
    Object? customFields = _unset,
    int? successfulFetches,
    int? failedFetches,
    double? successRate,
    Object? lastError = _unset,
    Object? lastErrorAt = _unset,
    String? folderId,
  }) {
    return Feed(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      description: identical(description, _unset)
          ? this.description
          : description as String?,
      link: identical(link, _unset) ? this.link : link as String?,
      siteUrl: identical(siteUrl, _unset) ? this.siteUrl : siteUrl as String?,
      customTitle: identical(customTitle, _unset)
          ? this.customTitle
          : customTitle as String?,
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      folderId: folderId ?? this.folderId,
      faviconUrl: identical(faviconUrl, _unset)
          ? this.faviconUrl
          : faviconUrl as String?,
      lastFetched: identical(lastFetched, _unset)
          ? this.lastFetched
          : lastFetched as DateTime?,
      etag: identical(etag, _unset) ? this.etag : etag as String?,
      lastModified: identical(lastModified, _unset)
          ? this.lastModified
          : lastModified as String?,
      updateFrequency: updateFrequency ?? this.updateFrequency,
      isActive: isActive ?? this.isActive,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      language: identical(language, _unset) ? this.language : language as String?,
      copyright:
          identical(copyright, _unset) ? this.copyright : copyright as String?,
      generator:
          identical(generator, _unset) ? this.generator : generator as String?,
      imageUrl: identical(imageUrl, _unset) ? this.imageUrl : imageUrl as String?,
      customFields: identical(customFields, _unset)
          ? this.customFields
          : customFields as Map<String, dynamic>?,
      successfulFetches: successfulFetches ?? this.successfulFetches,
      failedFetches: failedFetches ?? this.failedFetches,
      successRate: successRate ?? this.successRate,
      lastError: identical(lastError, _unset)
          ? this.lastError
          : lastError as String?,
      lastErrorAt: identical(lastErrorAt, _unset)
          ? this.lastErrorAt
          : lastErrorAt as DateTime?,
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
      folderId: json['folderId'] as String?,
      faviconUrl: json['faviconUrl'] as String? ?? json['favicon'] as String?,
      lastFetched: json['lastFetched'] != null
          ? DateTime.tryParse(json['lastFetched'] as String)
          : json['lastFetchedAt'] != null
              ? DateTime.tryParse(json['lastFetchedAt'] as String)
              : null,
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] as String?,
      updateFrequency: (json['updateInterval'] as num?)?.toInt() ??
          (json['updateFrequency'] as num?)?.toInt() ??
          60,
      isActive: json['isActive'] as bool? ?? true,
      type: FeedType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => FeedType.rss,
      ),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      language: json['language'] as String?,
      copyright: json['copyright'] as String?,
      generator: json['generator'] as String?,
      imageUrl: json['imageUrl'] as String?,
      customFields: json['customFields'] as Map<String, dynamic>? ??
          json['settings'] as Map<String, dynamic>?,
      successfulFetches: json['successfulFetches'] as int? ?? 0,
      failedFetches: json['failedFetches'] as int? ??
          (json['errorCount'] as num?)?.toInt() ??
          0,
      successRate: (json['successRate'] as num?)?.toDouble() ?? 0.0,
      lastError: json['lastError'] as String? ?? json['lastFetchError'] as String?,
      lastErrorAt: json['lastErrorAt'] != null
          ? DateTime.tryParse(json['lastErrorAt'] as String)
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