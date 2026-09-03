import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/articles_table.dart';
import '../tables/feeds_table.dart';

part 'article_dao.g.dart';

/// Data Access Object for articles
@DriftAccessor(tables: [ArticlesTable, FeedsTable])
class ArticleDao extends DatabaseAccessor<AppDatabase> with _$ArticleDaoMixin {
  ArticleDao(AppDatabase db) : super(db);
  
  /// Get articles with feed information
  Future<List<ArticleWithFeed>> getArticlesWithFeeds({
    int limit = 20,
    int offset = 0,
    bool unreadOnly = false,
    String? feedId,
    String? searchQuery,
  }) {
    final query = select(articlesTable).join([
      innerJoin(feedsTable, feedsTable.id.equalsExp(articlesTable.feedId)),
    ]);
    
    // Apply filters
    if (unreadOnly) {
      query.where(articlesTable.isRead.equals(false));
    }
    
    if (feedId != null) {
      query.where(articlesTable.feedId.equals(feedId));
    }
    
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query.where(
        articlesTable.title.contains(searchQuery) |
        articlesTable.content.contains(searchQuery) |
        articlesTable.summary.contains(searchQuery),
      );
    }
    
    // Order by published date
    query.orderBy([
      OrderingTerm(expression: articlesTable.publishedAt, mode: OrderingMode.desc),
    ]);
    
    // Apply pagination
    query.limit(limit, offset: offset);
    
    return query.map((row) {
      return ArticleWithFeed(
        article: row.readTable(articlesTable),
        feed: row.readTable(feedsTable),
      );
    }).get();
  }
  
  /// Get article by ID
  Future<ArticleEntry?> getArticleById(String id) {
    return (select(articlesTable)..where((a) => a.id.equals(id))).getSingleOrNull();
  }
  
  /// Get articles by feed
  Future<List<ArticleEntry>> getArticlesByFeed(String feedId) {
    return (select(articlesTable)
      ..where((a) => a.feedId.equals(feedId))
      ..orderBy([(a) => OrderingTerm(expression: a.publishedAt, mode: OrderingMode.desc)]))
      .get();
  }
  
  /// Get starred articles
  Future<List<ArticleWithFeed>> getStarredArticles() {
    final query = select(articlesTable).join([
      innerJoin(feedsTable, feedsTable.id.equalsExp(articlesTable.feedId)),
    ])
      ..where(articlesTable.isStarred.equals(true))
      ..orderBy([
        OrderingTerm(expression: articlesTable.publishedAt, mode: OrderingMode.desc),
      ]);
    
    return query.map((row) {
      return ArticleWithFeed(
        article: row.readTable(articlesTable),
        feed: row.readTable(feedsTable),
      );
    }).get();
  }
  
  /// Insert articles
  Future<void> insertArticles(List<ArticleEntry> articles) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(articlesTable, articles);
    });
  }
  
  /// Mark article as read
  Future<void> markAsRead(String articleId) {
    return (update(articlesTable)..where((a) => a.id.equals(articleId)))
      .write(const ArticlesTableCompanion(
        isRead: Value(true),
        updatedAt: Value.absent(),
      ));
  }
  
  /// Mark articles as read
  Future<void> markMultipleAsRead(List<String> articleIds) {
    return (update(articlesTable)..where((a) => a.id.isIn(articleIds)))
      .write(const ArticlesTableCompanion(
        isRead: Value(true),
        updatedAt: Value.absent(),
      ));
  }
  
  /// Mark all articles in feed as read
  Future<void> markFeedAsRead(String feedId) {
    return (update(articlesTable)..where((a) => a.feedId.equals(feedId)))
      .write(const ArticlesTableCompanion(
        isRead: Value(true),
        updatedAt: Value.absent(),
      ));
  }
  
  /// Toggle star status
  Future<void> toggleStar(String articleId) async {
    final article = await getArticleById(articleId);
    if (article != null) {
      await (update(articlesTable)..where((a) => a.id.equals(articleId)))
        .write(ArticlesTableCompanion(
          isStarred: Value(!article.isStarred),
          updatedAt: const Value.absent(),
        ));
    }
  }
  
  /// Update article with AI data
  Future<void> updateArticleAIData(
    String articleId, {
    String? aiSummary,
    List<String>? aiTags,
    Map<String, dynamic>? perspectives,
    double? sentimentScore,
    double? biasScore,
  }) {
    return (update(articlesTable)..where((a) => a.id.equals(articleId)))
      .write(ArticlesTableCompanion(
        aiSummary: Value(aiSummary),
        aiTags: Value(aiTags != null ? aiTags.join(',') : null),
        perspectivesJson: Value(perspectives != null ? perspectives.toString() : null),
        sentimentScore: Value(sentimentScore),
        biasScore: Value(biasScore),
        updatedAt: const Value.absent(),
      ));
  }
  
  /// Update article with full content
  Future<void> updateArticleFullContent(
    String articleId,
    String fullContent,
  ) {
    return (update(articlesTable)..where((a) => a.id.equals(articleId)))
      .write(ArticlesTableCompanion(
        fullContent: Value(fullContent),
        fullContentFetchedAt: Value(DateTime.now()),
        fullContentAvailable: const Value(true),
        updatedAt: const Value.absent(),
      ));
  }
  
  /// Delete old articles
  Future<int> deleteOldArticles(DateTime before, {bool keepStarred = true}) {
    var query = delete(articlesTable)..where((a) => a.publishedAt.isSmallerThan(Variable(before)));
    
    if (keepStarred) {
      query.where((a) => a.isStarred.equals(false));
    }
    
    return query.go();
  }
  
  /// Get unread count
  Future<int> getUnreadCount({String? feedId}) async {
    final query = selectOnly(articlesTable)
      ..addColumns([articlesTable.id.count()])
      ..where(articlesTable.isRead.equals(false));
    
    if (feedId != null) {
      query.where(articlesTable.feedId.equals(feedId));
    }
    
    return await query.map((row) => row.read(articlesTable.id.count())!).getSingle();
  }
  
  /// Search articles
  Future<List<ArticleWithFeed>> searchArticles(String query) {
    final searchQuery = '%$query%';
    
    final dbQuery = select(articlesTable).join([
      innerJoin(feedsTable, feedsTable.id.equalsExp(articlesTable.feedId)),
    ])
      ..where(
        articlesTable.title.like(searchQuery) |
        articlesTable.content.like(searchQuery) |
        articlesTable.summary.like(searchQuery) |
        articlesTable.author.like(searchQuery),
      )
      ..orderBy([
        OrderingTerm(expression: articlesTable.publishedAt, mode: OrderingMode.desc),
      ])
      ..limit(50);
    
    return dbQuery.map((row) {
      return ArticleWithFeed(
        article: row.readTable(articlesTable),
        feed: row.readTable(feedsTable),
      );
    }).get();
  }
  
  /// Get articles modified since a specific date (for sync)
  Future<List<ArticleEntry>> getModifiedSince(DateTime? since) async {
    if (since == null) {
      return (select(articlesTable)
        ..orderBy([(a) => OrderingTerm(expression: a.updatedAt, mode: OrderingMode.desc)]))
        .get();
    }
    
    return (select(articlesTable)
      ..where((a) => a.updatedAt.isBiggerOrEqualValue(since))
      ..orderBy([(a) => OrderingTerm(expression: a.updatedAt, mode: OrderingMode.desc)]))
      .get();
  }
}

/// Article with feed information
class ArticleWithFeed {
  final ArticleEntry article;
  final FeedEntry feed;
  
  ArticleWithFeed({
    required this.article,
    required this.feed,
  });
}