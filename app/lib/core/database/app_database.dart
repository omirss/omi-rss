import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:rss_glassmorphism_reader/core/api/api_models.dart' as api;
import 'dart:io';

part 'app_database.g.dart';

final appDatabaseProvider = Provider((ref) => AppDatabase());

// Tables
class Feeds extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get siteUrl => text().nullable()();
  TextColumn get iconUrl => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastFetched => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  
  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  IntColumn get feedCount => integer().withDefault(const Constant(0))();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  
  @override
  Set<Column> get primaryKey => {id};
}

class Articles extends Table {
  TextColumn get id => text()();
  TextColumn get feedId => text()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get url => text()();
  TextColumn get content => text().nullable()();
  TextColumn get summary => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isSaved => boolean().withDefault(const Constant(false))();
  DateTimeColumn get publishedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get tags => text().nullable()(); // JSON array
  TextColumn get metadata => text().nullable()(); // JSON object
  
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Feeds, Categories, Articles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  
  @override
  int get schemaVersion => 1;
  
  // Feed operations
  Future<List<api.Feed>> getAllFeeds() async {
    final feeds = await select(feeds).get();
    return feeds.map(_feedFromDb).toList();
  }
  
  Future<api.Feed?> getFeedById(String id) async {
    final feed = await (select(feeds)..where((f) => f.id.equals(id))).getSingleOrNull();
    return feed != null ? _feedFromDb(feed) : null;
  }
  
  Future<api.Feed?> getFeedByUrl(String url) async {
    final feed = await (select(feeds)..where((f) => f.url.equals(url))).getSingleOrNull();
    return feed != null ? _feedFromDb(feed) : null;
  }
  
  Future<void> insertFeed(api.Feed feed) async {
    await into(feeds).insertOnConflictUpdate(_feedToDb(feed));
  }
  
  Future<void> updateFeed(api.Feed feed) async {
    await update(feeds).replace(_feedToDb(feed));
  }
  
  Future<void> deleteFeed(String feedId) async {
    await (delete(feeds)..where((f) => f.id.equals(feedId))).go();
    await (delete(articles)..where((a) => a.feedId.equals(feedId))).go();
  }
  
  Future<List<api.Feed>> searchFeeds(String query) async {
    final results = await (select(feeds)
      ..where((f) => f.title.contains(query) | f.description.contains(query)))
      .get();
    return results.map(_feedFromDb).toList();
  }
  
  Future<List<api.Feed>> getFeedsByCategory(String categoryId) async {
    final results = await (select(feeds)
      ..where((f) => f.categoryId.equals(categoryId)))
      .get();
    return results.map(_feedFromDb).toList();
  }
  
  Future<void> updateFeedUnreadCount(String feedId, int count) async {
    await (update(feeds)..where((f) => f.id.equals(feedId)))
      .write(FeedsCompanion(unreadCount: Value(count)));
  }
  
  // Article operations
  Future<List<api.Article>> getArticles({
    String? feedId,
    String? categoryId,
    bool? unreadOnly,
    bool? savedOnly,
    int? limit,
    int? offset,
  }) async {
    final query = select(articles);
    
    if (feedId != null) {
      query.where((a) => a.feedId.equals(feedId));
    }
    
    if (categoryId != null) {
      query.join([
        innerJoin(feeds, feeds.id.equalsExp(articles.feedId)),
      ]);
      query.where(feeds.categoryId.equals(categoryId));
    }
    
    if (unreadOnly == true) {
      query.where((a) => a.isRead.equals(false));
    }
    
    if (savedOnly == true) {
      query.where((a) => a.isSaved.equals(true));
    }
    
    query.orderBy([(a) => OrderingTerm.desc(a.publishedAt)]);
    
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    
    final results = await query.get();
    return results.map(_articleFromDb).toList();
  }
  
  Future<api.Article?> getArticleById(String id) async {
    final article = await (select(articles)..where((a) => a.id.equals(id))).getSingleOrNull();
    return article != null ? _articleFromDb(article) : null;
  }
  
  Future<void> insertArticle(api.Article article) async {
    await into(articles).insertOnConflictUpdate(_articleToDb(article));
  }
  
  Future<void> markAsRead(String articleId, bool isRead) async {
    await (update(articles)..where((a) => a.id.equals(articleId)))
      .write(ArticlesCompanion(isRead: Value(isRead)));
  }
  
  Future<void> markAsSaved(String articleId, bool isSaved) async {
    await (update(articles)..where((a) => a.id.equals(articleId)))
      .write(ArticlesCompanion(isSaved: Value(isSaved)));
  }
  
  Future<void> markAllAsRead({String? feedId, String? categoryId}) async {
    final query = update(articles);
    
    if (feedId != null) {
      query.where((a) => a.feedId.equals(feedId));
    }
    
    if (categoryId != null) {
      // This requires a join, so we'll do it differently
      final feedIds = await (select(feeds)
        ..where((f) => f.categoryId.equals(categoryId)))
        .map((f) => f.id)
        .get();
      
      query.where((a) => a.feedId.isIn(feedIds));
    }
    
    await query.write(const ArticlesCompanion(isRead: Value(true)));
  }
  
  Future<int> getUnreadCount(String feedId) async {
    final count = await (select(articles)
      ..where((a) => a.feedId.equals(feedId) & a.isRead.equals(false)))
      .get();
    return count.length;
  }
  
  // Category operations
  Future<List<api.Category>> getAllCategories() async {
    final categories = await select(this.categories).get();
    return categories.map(_categoryFromDb).toList();
  }
  
  Future<void> insertCategory(api.Category category) async {
    await into(categories).insertOnConflictUpdate(_categoryToDb(category));
  }
  
  Future<void> updateCategory(api.Category category) async {
    await update(categories).replace(_categoryToDb(category));
  }
  
  Future<void> deleteCategory(String categoryId) async {
    // Move feeds to uncategorized
    await (update(feeds)..where((f) => f.categoryId.equals(categoryId)))
      .write(const FeedsCompanion(categoryId: Value(null)));
    
    await (delete(categories)..where((c) => c.id.equals(categoryId))).go();
  }
  
  // Converters
  api.Feed _feedFromDb(Feed feed) => api.Feed(
    id: feed.id,
    url: feed.url,
    title: feed.title,
    description: feed.description,
    siteUrl: feed.siteUrl,
    iconUrl: feed.iconUrl,
    categoryId: feed.categoryId,
    unreadCount: feed.unreadCount,
    lastFetched: feed.lastFetched,
    createdAt: feed.createdAt,
    updatedAt: feed.updatedAt,
  );
  
  FeedsCompanion _feedToDb(api.Feed feed) => FeedsCompanion(
    id: Value(feed.id),
    url: Value(feed.url),
    title: Value(feed.title),
    description: Value(feed.description),
    siteUrl: Value(feed.siteUrl),
    iconUrl: Value(feed.iconUrl),
    categoryId: Value(feed.categoryId),
    unreadCount: Value(feed.unreadCount),
    lastFetched: Value(feed.lastFetched),
    createdAt: Value(feed.createdAt),
    updatedAt: Value(feed.updatedAt),
  );
  
  api.Article _articleFromDb(Article article) => api.Article(
    id: article.id,
    feedId: article.feedId,
    title: article.title,
    author: article.author,
    url: article.url,
    content: article.content,
    summary: article.summary,
    imageUrl: article.imageUrl,
    isRead: article.isRead,
    isSaved: article.isSaved,
    publishedAt: article.publishedAt,
    createdAt: article.createdAt,
    tags: article.tags != null ? List<String>.from(jsonDecode(article.tags!)) : null,
    metadata: article.metadata != null ? jsonDecode(article.metadata!) : null,
  );
  
  ArticlesCompanion _articleToDb(api.Article article) => ArticlesCompanion(
    id: Value(article.id),
    feedId: Value(article.feedId),
    title: Value(article.title),
    author: Value(article.author),
    url: Value(article.url),
    content: Value(article.content),
    summary: Value(article.summary),
    imageUrl: Value(article.imageUrl),
    isRead: Value(article.isRead),
    isSaved: Value(article.isSaved),
    publishedAt: Value(article.publishedAt),
    createdAt: Value(article.createdAt),
    tags: Value(article.tags != null ? jsonEncode(article.tags) : null),
    metadata: Value(article.metadata != null ? jsonEncode(article.metadata) : null),
  );
  
  api.Category _categoryFromDb(Category category) => api.Category(
    id: category.id,
    name: category.name,
    icon: category.icon,
    feedCount: category.feedCount,
    unreadCount: category.unreadCount,
    createdAt: category.createdAt,
  );
  
  CategoriesCompanion _categoryToDb(api.Category category) => CategoriesCompanion(
    id: Value(category.id),
    name: Value(category.name),
    icon: Value(category.icon),
    feedCount: Value(category.feedCount),
    unreadCount: Value(category.unreadCount),
    createdAt: Value(category.createdAt),
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'rss_reader.db'));
    return NativeDatabase(file);
  });
}