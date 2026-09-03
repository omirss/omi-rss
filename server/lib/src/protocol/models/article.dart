import 'package:serverpod/serverpod.dart';

class Article extends TableRow {
  int? id;
  int feedId;
  int userId;
  String title;
  String url;
  String? content;
  String? excerpt;
  String? author;
  String? imageUrl;
  DateTime? publishedAt;
  bool isRead;
  bool isStarred;
  bool isArchived;
  List<String>? tags;
  Map<String, dynamic>? metadata;
  String? fullContent;
  DateTime? readAt;
  DateTime createdAt;
  DateTime? updatedAt;
  DateTime? deletedAt;

  Article({
    this.id,
    required this.feedId,
    required this.userId,
    required this.title,
    required this.url,
    this.content,
    this.excerpt,
    this.author,
    this.imageUrl,
    this.publishedAt,
    this.isRead = false,
    this.isStarred = false,
    this.isArchived = false,
    this.tags,
    this.metadata,
    this.fullContent,
    this.readAt,
    DateTime? createdAt,
    this.updatedAt,
    this.deletedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static final t = ArticleTable();

  static const db = ArticleRepository._();

  @override
  int? getColumnIndexForField(String field) {
    switch (field) {
      case 'id': return 0;
      case 'feedId': return 1;
      case 'userId': return 2;
      case 'title': return 3;
      case 'url': return 4;
      case 'content': return 5;
      case 'excerpt': return 6;
      case 'author': return 7;
      case 'imageUrl': return 8;
      case 'publishedAt': return 9;
      case 'isRead': return 10;
      case 'isStarred': return 11;
      case 'isArchived': return 12;
      case 'tags': return 13;
      case 'metadata': return 14;
      case 'fullContent': return 15;
      case 'readAt': return 16;
      case 'createdAt': return 17;
      case 'updatedAt': return 18;
      case 'deletedAt': return 19;
      default: return null;
    }
  }

  @override
  String get tableName => 'articles';

  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      id: json['id'] as int?,
      feedId: json['feedId'] as int,
      userId: json['userId'] as int,
      title: json['title'] as String,
      url: json['url'] as String,
      content: json['content'] as String?,
      excerpt: json['excerpt'] as String?,
      author: json['author'] as String?,
      imageUrl: json['imageUrl'] as String?,
      publishedAt: json['publishedAt'] != null
          ? DateTime.parse(json['publishedAt'] as String)
          : null,
      isRead: json['isRead'] as bool? ?? false,
      isStarred: json['isStarred'] as bool? ?? false,
      isArchived: json['isArchived'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      fullContent: json['fullContent'] as String?,
      readAt: json['readAt'] != null
          ? DateTime.parse(json['readAt'] as String)
          : null,
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
      'feedId': feedId,
      'userId': userId,
      'title': title,
      'url': url,
      if (content != null) 'content': content,
      if (excerpt != null) 'excerpt': excerpt,
      if (author != null) 'author': author,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
      'isRead': isRead,
      'isStarred': isStarred,
      'isArchived': isArchived,
      if (tags != null) 'tags': tags,
      if (metadata != null) 'metadata': metadata,
      if (fullContent != null) 'fullContent': fullContent,
      if (readAt != null) 'readAt': readAt!.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'feed_id': feedId,
      'user_id': userId,
      'title': title,
      'url': url,
      'content': content,
      'excerpt': excerpt,
      'author': author,
      'image_url': imageUrl,
      'published_at': publishedAt,
      'is_read': isRead,
      'is_starred': isStarred,
      'is_archived': isArchived,
      'tags': tags != null ? SerializationManager.encode(tags!) : null,
      'metadata': metadata != null ? SerializationManager.encode(metadata!) : null,
      'full_content': fullContent,
      'read_at': readAt,
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
      case 'feed_id':
        feedId = value;
        return;
      case 'user_id':
        userId = value;
        return;
      case 'title':
        title = value;
        return;
      case 'url':
        url = value;
        return;
      case 'content':
        content = value;
        return;
      case 'excerpt':
        excerpt = value;
        return;
      case 'author':
        author = value;
        return;
      case 'image_url':
        imageUrl = value;
        return;
      case 'published_at':
        publishedAt = value;
        return;
      case 'is_read':
        isRead = value;
        return;
      case 'is_starred':
        isStarred = value;
        return;
      case 'is_archived':
        isArchived = value;
        return;
      case 'tags':
        tags = value != null ? SerializationManager.decode(value) : null;
        return;
      case 'metadata':
        metadata = value != null ? SerializationManager.decode(value) : null;
        return;
      case 'full_content':
        fullContent = value;
        return;
      case 'read_at':
        readAt = value;
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

class ArticleTable extends Table {
  ArticleTable() : super(tableName: 'articles');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final feedId = ColumnInt('feed_id', this);
  late final userId = ColumnInt('user_id', this);
  late final title = ColumnString('title', this);
  late final url = ColumnString('url', this);
  late final content = ColumnString('content', this);
  late final excerpt = ColumnString('excerpt', this);
  late final author = ColumnString('author', this);
  late final imageUrl = ColumnString('image_url', this);
  late final publishedAt = ColumnDateTime('published_at', this);
  late final isRead = ColumnBool('is_read', this, hasDefault: true);
  late final isStarred = ColumnBool('is_starred', this, hasDefault: true);
  late final isArchived = ColumnBool('is_archived', this, hasDefault: true);
  late final tags = ColumnSerializable('tags', this);
  late final metadata = ColumnSerializable('metadata', this);
  late final fullContent = ColumnString('full_content', this);
  late final readAt = ColumnDateTime('read_at', this);
  late final createdAt = ColumnDateTime('created_at', this, hasDefault: true);
  late final updatedAt = ColumnDateTime('updated_at', this);
  late final deletedAt = ColumnDateTime('deleted_at', this);

  @override
  List<Column> get columns => [
    id,
    feedId,
    userId,
    title,
    url,
    content,
    excerpt,
    author,
    imageUrl,
    publishedAt,
    isRead,
    isStarred,
    isArchived,
    tags,
    metadata,
    fullContent,
    readAt,
    createdAt,
    updatedAt,
    deletedAt,
  ];
}

class ArticleInclude extends IncludeObject {
  ArticleInclude._({
    FeedInclude? feed,
    UserInclude? user,
    AIAnalysisInclude? aiAnalysis,
  }) : super(includes: {
    if (feed != null) 'feed': feed,
    if (user != null) 'user': user,
    if (aiAnalysis != null) 'aiAnalysis': aiAnalysis,
  });

  static final i = ArticleInclude._();

  ArticleInclude feed() {
    return ArticleInclude._(feed: FeedInclude.i);
  }

  ArticleInclude user() {
    return ArticleInclude._(user: UserInclude.i);
  }

  ArticleInclude aiAnalysis() {
    return ArticleInclude._(aiAnalysis: AIAnalysisInclude.i);
  }
}

class ArticleIncludeList extends IncludeList {
  ArticleIncludeList([ArticleInclude? include]) : super(include);
}

class ArticleRepository {
  const ArticleRepository._();

  Future<List<Article>> findByUserId(
    Session session,
    int userId, {
    int? limit,
    int? offset,
    ArticleOrder? orderBy,
    ArticleFilter? filter,
    Transaction? transaction,
  }) async {
    var where = Article.t.userId.equals(userId) & Article.t.deletedAt.equals(null);
    
    if (filter != null) {
      if (filter.isRead != null) {
        where = where & Article.t.isRead.equals(filter.isRead!);
      }
      if (filter.isStarred != null) {
        where = where & Article.t.isStarred.equals(filter.isStarred!);
      }
      if (filter.isArchived != null) {
        where = where & Article.t.isArchived.equals(filter.isArchived!);
      }
      if (filter.feedId != null) {
        where = where & Article.t.feedId.equals(filter.feedId!);
      }
      if (filter.search != null && filter.search!.isNotEmpty) {
        where = where & (
          Article.t.title.ilike('%${filter.search}%') |
          Article.t.content.ilike('%${filter.search}%')
        );
      }
    }
    
    return session.db.find<Article>(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.toOrderBy() ?? Article.t.publishedAt.descending,
      transaction: transaction,
    );
  }

  Future<Article?> findByUserIdAndUrl(
    Session session,
    int userId,
    String url, {
    Transaction? transaction,
  }) async {
    final articles = await session.db.find<Article>(
      where: (t) => t.userId.equals(userId) & t.url.equals(url) & t.deletedAt.equals(null),
      limit: 1,
      transaction: transaction,
    );
    return articles.isNotEmpty ? articles.first : null;
  }

  Future<void> markAsRead(
    Session session,
    int articleId, {
    Transaction? transaction,
  }) async {
    await session.db.updateRow<Article>(
      Article()
        ..id = articleId
        ..isRead = true
        ..readAt = DateTime.now()
        ..updatedAt = DateTime.now(),
      columns: [Article.t.isRead, Article.t.readAt, Article.t.updatedAt],
      transaction: transaction,
    );
  }

  Future<void> toggleStarred(
    Session session,
    int articleId,
    bool isStarred, {
    Transaction? transaction,
  }) async {
    await session.db.updateRow<Article>(
      Article()
        ..id = articleId
        ..isStarred = isStarred
        ..updatedAt = DateTime.now(),
      columns: [Article.t.isStarred, Article.t.updatedAt],
      transaction: transaction,
    );
  }

  Future<void> markAsDeleted(
    Session session,
    int articleId, {
    Transaction? transaction,
  }) async {
    await session.db.updateRow<Article>(
      Article()
        ..id = articleId
        ..deletedAt = DateTime.now(),
      columns: [Article.t.deletedAt],
      transaction: transaction,
    );
  }
}

class ArticleFilter {
  final bool? isRead;
  final bool? isStarred;
  final bool? isArchived;
  final int? feedId;
  final String? search;
  final DateTime? startDate;
  final DateTime? endDate;

  ArticleFilter({
    this.isRead,
    this.isStarred,
    this.isArchived,
    this.feedId,
    this.search,
    this.startDate,
    this.endDate,
  });
}

enum ArticleOrder {
  publishedDesc,
  publishedAsc,
  createdDesc,
  createdAsc,
  titleAsc,
  titleDesc,
}

extension ArticleOrderExtension on ArticleOrder {
  Order toOrderBy() {
    switch (this) {
      case ArticleOrder.publishedDesc:
        return Article.t.publishedAt.descending;
      case ArticleOrder.publishedAsc:
        return Article.t.publishedAt.ascending;
      case ArticleOrder.createdDesc:
        return Article.t.createdAt.descending;
      case ArticleOrder.createdAsc:
        return Article.t.createdAt.ascending;
      case ArticleOrder.titleAsc:
        return Article.t.title.ascending;
      case ArticleOrder.titleDesc:
        return Article.t.title.descending;
    }
  }
}