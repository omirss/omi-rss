import 'package:serverpod/serverpod.dart';

class ReadHistory extends TableRow {
  int? id;
  int userId;
  int articleId;
  DateTime readAt;
  int? readDurationSeconds;
  double? scrollPercentage;

  ReadHistory({
    this.id,
    required this.userId,
    required this.articleId,
    DateTime? readAt,
    this.readDurationSeconds,
    this.scrollPercentage,
  }) : readAt = readAt ?? DateTime.now();

  static final t = ReadHistoryTable();

  static const db = ReadHistoryRepository._();

  @override
  String get tableName => 'read_history';

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
      case 'read_at':
        readAt = value;
        return;
      case 'read_duration_seconds':
        readDurationSeconds = value;
        return;
      case 'scroll_percentage':
        scrollPercentage = value;
        return;
      default:
        throw UnimplementedError();
    }
  }

  factory ReadHistory.fromJson(Map<String, dynamic> json) {
    return ReadHistory(
      id: json['id'] as int?,
      userId: json['userId'] as int,
      articleId: json['articleId'] as int,
      readAt: DateTime.parse(json['readAt'] as String),
      readDurationSeconds: json['readDurationSeconds'] as int?,
      scrollPercentage: json['scrollPercentage'] as double?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'userId': userId,
      'articleId': articleId,
      'readAt': readAt.toIso8601String(),
      if (readDurationSeconds != null) 'readDurationSeconds': readDurationSeconds,
      if (scrollPercentage != null) 'scrollPercentage': scrollPercentage,
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'article_id': articleId,
      'read_at': readAt,
      'read_duration_seconds': readDurationSeconds,
      'scroll_percentage': scrollPercentage,
    };
  }
}

class ReadHistoryTable extends Table {
  ReadHistoryTable() : super(tableName: 'read_history');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final userId = ColumnInt('user_id', this);
  late final articleId = ColumnInt('article_id', this);
  late final readAt = ColumnDateTime('read_at', this, hasDefault: true);
  late final readDurationSeconds = ColumnInt('read_duration_seconds', this);
  late final scrollPercentage = ColumnDouble('scroll_percentage', this);

  @override
  List<Column> get columns => [
    id,
    userId,
    articleId,
    readAt,
    readDurationSeconds,
    scrollPercentage,
  ];
}

class ReadHistoryInclude extends IncludeObject {
  ReadHistoryInclude._({
    UserInclude? user,
    ArticleInclude? article,
  }) : super(includes: {
    if (user != null) 'user': user,
    if (article != null) 'article': article,
  });

  static final i = ReadHistoryInclude._();

  ReadHistoryInclude user() {
    return ReadHistoryInclude._(user: UserInclude.i);
  }

  ReadHistoryInclude article({ArticleInclude? include}) {
    return ReadHistoryInclude._(article: include ?? ArticleInclude.i);
  }
}

class ReadHistoryIncludeList extends IncludeList {
  ReadHistoryIncludeList([ReadHistoryInclude? include]) 
    : super(include ?? ReadHistoryInclude._());
}

class ReadHistoryRepository {
  const ReadHistoryRepository._();

  Future<List<ReadHistory>> findByUserId(
    Session session,
    int userId, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    Transaction? transaction,
  }) async {
    var where = ReadHistoryTable().userId.equals(userId);
    
    if (startDate != null) {
      where = where & ReadHistoryTable().readAt.afterOrEqualTo(startDate);
    }
    
    if (endDate != null) {
      where = where & ReadHistoryTable().readAt.beforeOrEqualTo(endDate);
    }
    
    return session.db.find<ReadHistory>(
      where: (t) => where,
      orderBy: (t) => t.readAt,
      orderDescending: true,
      limit: limit,
      transaction: transaction,
    );
  }

  Future<ReadHistory?> findByUserAndArticle(
    Session session,
    int userId,
    int articleId, {
    Transaction? transaction,
  }) async {
    final history = await session.db.find<ReadHistory>(
      where: (t) => t.userId.equals(userId) & t.articleId.equals(articleId),
      orderBy: (t) => t.readAt,
      orderDescending: true,
      limit: 1,
      transaction: transaction,
    );
    return history.isNotEmpty ? history.first : null;
  }

  Future<int> countByUserId(
    Session session,
    int userId, {
    DateTime? startDate,
    DateTime? endDate,
    Transaction? transaction,
  }) async {
    var where = ReadHistoryTable().userId.equals(userId);
    
    if (startDate != null) {
      where = where & ReadHistoryTable().readAt.afterOrEqualTo(startDate);
    }
    
    if (endDate != null) {
      where = where & ReadHistoryTable().readAt.beforeOrEqualTo(endDate);
    }
    
    return session.db.count<ReadHistory>(
      where: (t) => where,
      transaction: transaction,
    );
  }

  Future<List<ReadHistory>> findRecentByUserId(
    Session session,
    int userId, {
    int days = 30,
    Transaction? transaction,
  }) async {
    final startDate = DateTime.now().subtract(Duration(days: days));
    
    return session.db.find<ReadHistory>(
      where: (t) => t.userId.equals(userId) & t.readAt.afterOrEqualTo(startDate),
      orderBy: (t) => t.readAt,
      orderDescending: true,
      transaction: transaction,
    );
  }
}