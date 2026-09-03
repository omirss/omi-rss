import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/feeds_table.dart';
import '../tables/articles_table.dart';

part 'feed_dao.g.dart';

/// Data Access Object for feeds
@DriftAccessor(tables: [FeedsTable, ArticlesTable, CategoriesTable])
class FeedDao extends DatabaseAccessor<AppDatabase> with _$FeedDaoMixin {
  FeedDao(AppDatabase db) : super(db);
  
  /// Get all feeds
  Future<List<FeedEntry>> getAllFeeds() => select(feedsTable).get();
  
  /// Get active feeds
  Future<List<FeedEntry>> getActiveFeeds() {
    return (select(feedsTable)..where((f) => f.isActive)).get();
  }
  
  /// Get feeds by category
  Future<List<FeedEntry>> getFeedsByCategory(String categoryId) {
    return (select(feedsTable)..where((f) => f.categoryId.equals(categoryId))).get();
  }
  
  /// Get feed by ID
  Future<FeedEntry?> getFeedById(String id) {
    return (select(feedsTable)..where((f) => f.id.equals(id))).getSingleOrNull();
  }
  
  /// Get feed by URL
  Future<FeedEntry?> getFeedByUrl(String url) {
    return (select(feedsTable)..where((f) => f.url.equals(url))).getSingleOrNull();
  }
  
  /// Get feeds with categories
  Future<List<FeedWithCategory>> getFeedsWithCategories() {
    final query = select(feedsTable).join([
      leftOuterJoin(
        categoriesTable,
        categoriesTable.id.equalsExp(feedsTable.categoryId),
      ),
    ]);
    
    return query.map((row) {
      return FeedWithCategory(
        feed: row.readTable(feedsTable),
        category: row.readTableOrNull(categoriesTable),
      );
    }).get();
  }
  
  /// Get feed statistics
  Future<FeedStatistics> getFeedStatistics(String feedId) async {
    // Total articles
    final totalQuery = selectOnly(articlesTable)
      ..addColumns([articlesTable.id.count()])
      ..where(articlesTable.feedId.equals(feedId));
    final total = await totalQuery.map((row) => row.read(articlesTable.id.count())!).getSingle();
    
    // Unread articles
    final unreadQuery = selectOnly(articlesTable)
      ..addColumns([articlesTable.id.count()])
      ..where(articlesTable.feedId.equals(feedId))
      ..where(articlesTable.isRead.equals(false));
    final unread = await unreadQuery.map((row) => row.read(articlesTable.id.count())!).getSingle();
    
    // Starred articles
    final starredQuery = selectOnly(articlesTable)
      ..addColumns([articlesTable.id.count()])
      ..where(articlesTable.feedId.equals(feedId))
      ..where(articlesTable.isStarred.equals(true));
    final starred = await starredQuery.map((row) => row.read(articlesTable.id.count())!).getSingle();
    
    return FeedStatistics(
      totalArticles: total,
      unreadArticles: unread,
      starredArticles: starred,
    );
  }
  
  /// Insert feed
  Future<void> insertFeed(FeedEntry feed) => into(feedsTable).insert(feed);
  
  /// Update feed
  Future<bool> updateFeed(FeedEntry feed) => update(feedsTable).replace(feed);
  
  /// Delete feed and its articles
  Future<void> deleteFeed(String feedId) async {
    await transaction(() async {
      // Delete all articles for this feed
      await (delete(articlesTable)..where((a) => a.feedId.equals(feedId))).go();
      // Delete the feed
      await (delete(feedsTable)..where((f) => f.id.equals(feedId))).go();
    });
  }
  
  /// Update feed fetch status
  Future<void> updateFeedFetchStatus(
    String feedId, {
    required DateTime lastFetched,
    String? etag,
    String? lastModified,
    bool success = true,
    String? error,
  }) async {
    final feed = await getFeedById(feedId);
    if (feed == null) return;
    
    final successfulFetches = success ? feed.successfulFetches + 1 : feed.successfulFetches;
    final failedFetches = success ? feed.failedFetches : feed.failedFetches + 1;
    final totalFetches = successfulFetches + failedFetches;
    final successRate = totalFetches > 0 ? successfulFetches / totalFetches : 0.0;
    
    await (update(feedsTable)..where((f) => f.id.equals(feedId))).write(
      FeedsTableCompanion(
        lastFetched: Value(lastFetched),
        etag: Value(etag),
        lastModified: Value(lastModified),
        successfulFetches: Value(successfulFetches),
        failedFetches: Value(failedFetches),
        successRate: Value(successRate),
        lastError: Value(error),
        lastErrorAt: Value(success ? null : DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
  
  /// Get feeds that need updating
  Future<List<FeedEntry>> getFeedsNeedingUpdate() async {
    final now = DateTime.now();
    
    return (select(feedsTable)
      ..where((f) {
        return f.isActive & 
          (f.lastFetched.isNull() | 
           f.lastFetched.isSmallerThan(
             Variable(now.subtract(Duration(seconds: f.updateFrequency)))
           ));
      }))
      .get();
  }
  
  /// Get feeds modified since a specific date (for sync)
  Future<List<FeedEntry>> getModifiedSince(DateTime? since) async {
    if (since == null) {
      return getAllFeeds();
    }
    
    return (select(feedsTable)
      ..where((f) => f.updatedAt.isBiggerOrEqualValue(since))
      ..orderBy([(f) => OrderingTerm.desc(f.updatedAt)]))
      .get();
  }
}

/// Feed with category information
class FeedWithCategory {
  final FeedEntry feed;
  final CategoryEntry? category;
  
  FeedWithCategory({
    required this.feed,
    this.category,
  });
}

/// Feed statistics
class FeedStatistics {
  final int totalArticles;
  final int unreadArticles;
  final int starredArticles;
  
  FeedStatistics({
    required this.totalArticles,
    required this.unreadArticles,
    required this.starredArticles,
  });
}