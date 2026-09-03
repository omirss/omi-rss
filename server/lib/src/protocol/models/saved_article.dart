import 'package:serverpod/serverpod.dart';

class SavedArticle extends TableRow {
  int? id;
  int userId;
  int articleId;
  String? note;
  List<String>? tags;
  DateTime savedAt;

  SavedArticle({
    this.id,
    required this.userId,
    required this.articleId,
    this.note,
    this.tags,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  static final t = SavedArticleTable();

  static const db = SavedArticleRepository._();

  @override
  String get tableName => 'saved_articles';

  @override
  void setColumn(String columnName, value) {
    switch (columnName) {
      case 'id':
        id = value;
        return;
      case 'user_id':
        userId = value;
        return;
      case 'article_id':
        articleId = value;
        return;
      case 'note':
        note = value;
        return;
      case 'tags':
        tags = value != null ? (SerializationManager.decode(value) as List).cast<String>() : null;
        return;
      case 'saved_at':
        savedAt = value;
        return;
      default:
        throw UnimplementedError();
    }
  }

  factory SavedArticle.fromJson(Map<String, dynamic> json) {
    return SavedArticle(
      id: json['id'] as int?,
      userId: json['userId'] as int,
      articleId: json['articleId'] as int,
      note: json['note'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      'articleId': articleId,
      if (note != null) 'note': note,
      if (tags != null) 'tags': tags,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'article_id': articleId,
      'note': note,
      'tags': tags != null ? SerializationManager.encode(tags!) : null,
      'saved_at': savedAt,
    };
  }
}

class SavedArticleTable extends Table {
  SavedArticleTable() : super(tableName: 'saved_articles');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final userId = ColumnInt('user_id', this);
  late final articleId = ColumnInt('article_id', this);
  late final note = ColumnString('note', this);
  late final tags = ColumnSerializable('tags', this);
  late final savedAt = ColumnDateTime('saved_at', this, hasDefault: true);

  @override
  List<Column> get columns => [
    id,
    userId,
    articleId,
    note,
    tags,
    savedAt,
  ];
}

class SavedArticleInclude extends IncludeObject {
  SavedArticleInclude._({
    UserInclude? user,
    ArticleInclude? article,
  }) : super(includes: {
    if (user != null) 'user': user,
    if (article != null) 'article': article,
  });

  static final i = SavedArticleInclude._();

  SavedArticleInclude user() {
    return SavedArticleInclude._(user: UserInclude.i);
  }

  SavedArticleInclude article({ArticleInclude? include}) {
    return SavedArticleInclude._(article: include ?? ArticleInclude.i);
  }
}

class SavedArticleIncludeList extends IncludeList {
  SavedArticleIncludeList([SavedArticleInclude? include]) 
    : super(include ?? SavedArticleInclude._());
}

class SavedArticleRepository {
  const SavedArticleRepository._();

  Future<List<SavedArticle>> findByUserId(
    Session session,
    int userId, {
    int? limit,
    Transaction? transaction,
  }) async {
    return session.db.find<SavedArticle>(
      where: (t) => t.userId.equals(userId),
      orderBy: (t) => t.savedAt,
      orderDescending: true,
      limit: limit,
      transaction: transaction,
    );
  }

  Future<SavedArticle?> findByUserAndArticle(
    Session session,
    int userId,
    int articleId, {
    Transaction? transaction,
  }) async {
    final saved = await session.db.find<SavedArticle>(
      where: (t) => t.userId.equals(userId) & t.articleId.equals(articleId),
      limit: 1,
      transaction: transaction,
    );
    return saved.isNotEmpty ? saved.first : null;
  }

  Future<List<SavedArticle>> findByTag(
    Session session,
    int userId,
    String tag, {
    Transaction? transaction,
  }) async {
    // This would require a more complex query with JSONB contains
    // For now, we'll fetch all and filter in memory
    final all = await findByUserId(session, userId, transaction: transaction);
    return all.where((s) => s.tags?.contains(tag) ?? false).toList();
  }

  Future<int> countByUserId(
    Session session,
    int userId, {
    Transaction? transaction,
  }) async {
    return session.db.count<SavedArticle>(
      where: (t) => t.userId.equals(userId),
      transaction: transaction,
    );
  }

  Future<bool> isArticleSaved(
    Session session,
    int userId,
    int articleId, {
    Transaction? transaction,
  }) async {
    final count = await session.db.count<SavedArticle>(
      where: (t) => t.userId.equals(userId) & t.articleId.equals(articleId),
      transaction: transaction,
    );
    return count > 0;
  }
}