import 'package:serverpod/serverpod.dart';

class Feed extends TableRow {
  int? id;
  String title;
  String url;
  String? description;
  String? imageUrl;
  String? favicon;
  String? category;
  int? folderId;
  int userId;
  Map<String, dynamic>? settings;
  DateTime? lastFetchedAt;
  DateTime? lastSuccessfulFetch;
  String? lastError;
  int errorCount;
  bool isEnabled;
  int articleCount;
  int unreadCount;
  DateTime createdAt;
  DateTime? updatedAt;
  DateTime? deletedAt;

  Feed({
    this.id,
    required this.title,
    required this.url,
    this.description,
    this.imageUrl,
    this.favicon,
    this.category,
    this.folderId,
    required this.userId,
    this.settings,
    this.lastFetchedAt,
    this.lastSuccessfulFetch,
    this.lastError,
    this.errorCount = 0,
    this.isEnabled = true,
    this.articleCount = 0,
    this.unreadCount = 0,
    DateTime? createdAt,
    this.updatedAt,
    this.deletedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static final t = FeedTable();

  static const db = FeedRepository._();

  @override
  int? getColumnIndexForField(String field) {
    switch (field) {
      case 'id': return 0;
      case 'title': return 1;
      case 'url': return 2;
      case 'description': return 3;
      case 'imageUrl': return 4;
      case 'favicon': return 5;
      case 'category': return 6;
      case 'folderId': return 7;
      case 'userId': return 8;
      case 'settings': return 9;
      case 'lastFetchedAt': return 10;
      case 'lastSuccessfulFetch': return 11;
      case 'lastError': return 12;
      case 'errorCount': return 13;
      case 'isEnabled': return 14;
      case 'articleCount': return 15;
      case 'unreadCount': return 16;
      case 'createdAt': return 17;
      case 'updatedAt': return 18;
      case 'deletedAt': return 19;
      default: return null;
    }
  }

  @override
  String get tableName => 'feeds';

  factory Feed.fromJson(Map<String, dynamic> json) {
    return Feed(
      id: json['id'] as int?,
      title: json['title'] as String,
      url: json['url'] as String,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      favicon: json['favicon'] as String?,
      category: json['category'] as String?,
      folderId: json['folderId'] as int?,
      userId: json['userId'] as int,
      settings: json['settings'] as Map<String, dynamic>?,
      lastFetchedAt: json['lastFetchedAt'] != null
          ? DateTime.parse(json['lastFetchedAt'] as String)
          : null,
      lastSuccessfulFetch: json['lastSuccessfulFetch'] != null
          ? DateTime.parse(json['lastSuccessfulFetch'] as String)
          : null,
      lastError: json['lastError'] as String?,
      errorCount: json['errorCount'] as int? ?? 0,
      isEnabled: json['isEnabled'] as bool? ?? true,
      articleCount: json['articleCount'] as int? ?? 0,
      unreadCount: json['unreadCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'url': url,
      if (description != null) 'description': description,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (favicon != null) 'favicon': favicon,
      if (category != null) 'category': category,
      if (folderId != null) 'folderId': folderId,
      'userId': userId,
      if (settings != null) 'settings': settings,
      if (lastFetchedAt != null) 'lastFetchedAt': lastFetchedAt!.toIso8601String(),
      if (lastSuccessfulFetch != null) 'lastSuccessfulFetch': lastSuccessfulFetch!.toIso8601String(),
      if (lastError != null) 'lastError': lastError,
      'errorCount': errorCount,
      'isEnabled': isEnabled,
      'articleCount': articleCount,
      'unreadCount': unreadCount,
      'createdAt': createdAt.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'url': url,
      'description': description,
      'image_url': imageUrl,
      'favicon': favicon,
      'category': category,
      'folder_id': folderId,
      'user_id': userId,
      'settings': settings != null ? SerializationManager.encode(settings!) : null,
      'last_fetched_at': lastFetchedAt,
      'last_successful_fetch': lastSuccessfulFetch,
      'last_error': lastError,
      'error_count': errorCount,
      'is_enabled': isEnabled,
      'article_count': articleCount,
      'unread_count': unreadCount,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }

  @override
  void setColumn(String columnName, value) {
    switch (columnName) {
      case 'id':
        id = value;
        return;
      case 'title':
        title = value;
        return;
      case 'url':
        url = value;
        return;
      case 'description':
        description = value;
        return;
      case 'image_url':
        imageUrl = value;
        return;
      case 'favicon':
        favicon = value;
        return;
      case 'category':
        category = value;
        return;
      case 'folder_id':
        folderId = value;
        return;
      case 'user_id':
        userId = value;
        return;
      case 'settings':
        settings = value != null ? SerializationManager.decode(value) : null;
        return;
      case 'last_fetched_at':
        lastFetchedAt = value;
        return;
      case 'last_successful_fetch':
        lastSuccessfulFetch = value;
        return;
      case 'last_error':
        lastError = value;
        return;
      case 'error_count':
        errorCount = value;
        return;
      case 'is_enabled':
        isEnabled = value;
        return;
      case 'article_count':
        articleCount = value;
        return;
      case 'unread_count':
        unreadCount = value;
        return;
      case 'created_at':
        createdAt = value;
        return;
      case 'updated_at':
        updatedAt = value;
        return;
      case 'deleted_at':
        deletedAt = value;
        return;
      default:
        throw UnimplementedError();
    }
  }
}

class FeedTable extends Table {
  FeedTable() : super(tableName: 'feeds');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final title = ColumnString('title', this);
  late final url = ColumnString('url', this);
  late final description = ColumnString('description', this);
  late final imageUrl = ColumnString('image_url', this);
  late final favicon = ColumnString('favicon', this);
  late final category = ColumnString('category', this);
  late final folderId = ColumnInt('folder_id', this);
  late final userId = ColumnInt('user_id', this);
  late final settings = ColumnSerializable('settings', this);
  late final lastFetchedAt = ColumnDateTime('last_fetched_at', this);
  late final lastSuccessfulFetch = ColumnDateTime('last_successful_fetch', this);
  late final lastError = ColumnString('last_error', this);
  late final errorCount = ColumnInt('error_count', this, hasDefault: true);
  late final isEnabled = ColumnBool('is_enabled', this, hasDefault: true);
  late final articleCount = ColumnInt('article_count', this, hasDefault: true);
  late final unreadCount = ColumnInt('unread_count', this, hasDefault: true);
  late final createdAt = ColumnDateTime('created_at', this, hasDefault: true);
  late final updatedAt = ColumnDateTime('updated_at', this);
  late final deletedAt = ColumnDateTime('deleted_at', this);

  @override
  List<Column> get columns => [
    id,
    title,
    url,
    description,
    imageUrl,
    favicon,
    category,
    folderId,
    userId,
    settings,
    lastFetchedAt,
    lastSuccessfulFetch,
    lastError,
    errorCount,
    isEnabled,
    articleCount,
    unreadCount,
    createdAt,
    updatedAt,
    deletedAt,
  ];
}

class FeedInclude extends IncludeObject {
  FeedInclude._({
    FolderInclude? folder,
    UserInclude? user,
    ArticleIncludeList? articles,
  }) : super(includes: {
    if (folder != null) 'folder': folder,
    if (user != null) 'user': user,
    if (articles != null) 'articles': articles,
  });

  static final i = FeedInclude._();

  FeedInclude folder() {
    return FeedInclude._(folder: FolderInclude.i);
  }

  FeedInclude user() {
    return FeedInclude._(user: UserInclude.i);
  }

  FeedInclude articles({ArticleInclude? include}) {
    return FeedInclude._(articles: ArticleIncludeList(include));
  }
}

class FeedRepository {
  const FeedRepository._();

  Future<List<Feed>> findByUserId(
    Session session,
    int userId, {
    Transaction? transaction,
  }) async {
    return session.db.find<Feed>(
      where: (t) => t.userId.equals(userId) & t.deletedAt.equals(null),
      transaction: transaction,
    );
  }

  Future<Feed?> findByUserIdAndUrl(
    Session session,
    int userId,
    String url, {
    Transaction? transaction,
  }) async {
    final feeds = await session.db.find<Feed>(
      where: (t) => t.userId.equals(userId) & t.url.equals(url) & t.deletedAt.equals(null),
      limit: 1,
      transaction: transaction,
    );
    return feeds.isNotEmpty ? feeds.first : null;
  }

  Future<List<Feed>> findEnabledFeeds(
    Session session, {
    Transaction? transaction,
  }) async {
    return session.db.find<Feed>(
      where: (t) => t.isEnabled.equals(true) & t.deletedAt.equals(null),
      transaction: transaction,
    );
  }

  Future<void> updateArticleCounts(
    Session session,
    int feedId,
    int articleCount,
    int unreadCount, {
    Transaction? transaction,
  }) async {
    await session.db.updateRow<Feed>(
      Feed()
        ..id = feedId
        ..articleCount = articleCount
        ..unreadCount = unreadCount
        ..updatedAt = DateTime.now(),
      columns: [Feed.t.articleCount, Feed.t.unreadCount, Feed.t.updatedAt],
      transaction: transaction,
    );
  }

  Future<void> markAsDeleted(
    Session session,
    int feedId, {
    Transaction? transaction,
  }) async {
    await session.db.updateRow<Feed>(
      Feed()
        ..id = feedId
        ..deletedAt = DateTime.now(),
      columns: [Feed.t.deletedAt],
      transaction: transaction,
    );
  }
}