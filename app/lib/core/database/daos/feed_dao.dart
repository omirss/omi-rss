import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/feeds_table.dart';
import '../tables/articles_table.dart';
import '../../models/feed.dart';

part 'feed_dao.g.dart';

/// Data Access Object for feeds
/// Public API works with the Feed model; conversion to/from drift entries
/// happens internally.
@DriftAccessor(tables: [FeedsTable, ArticlesTable, CategoriesTable])
class FeedDao extends DatabaseAccessor<AppDatabase> with _$FeedDaoMixin {
  FeedDao(AppDatabase db) : super(db);

  /// Get all feeds
  Future<List<Feed>> getAllFeeds() async {
    final rows = await select(feedsTable).get();
    return rows.map(_toModel).toList();
  }

  /// Watch all feeds
  Stream<List<Feed>> watchAllFeeds() {
    return select(feedsTable)
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Get active feeds
  Future<List<Feed>> getActiveFeeds() async {
    final rows = await (select(feedsTable)..where((f) => f.isActive)).get();
    return rows.map(_toModel).toList();
  }

  /// Get feeds by category
  Future<List<Feed>> getFeedsByCategory(String categoryId) async {
    final rows = await (select(feedsTable)
          ..where((f) => f.categoryId.equals(categoryId)))
        .get();
    return rows.map(_toModel).toList();
  }

  /// Get feed by ID
  Future<Feed?> getFeed(String id) async {
    final row = await (select(feedsTable)..where((f) => f.id.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Watch a single feed by ID
  Stream<Feed?> watchFeed(String id) {
    return (select(feedsTable)..where((f) => f.id.equals(id)))
        .watchSingleOrNull()
        .map((row) => row != null ? _toModel(row) : null);
  }

  /// Get feed by URL
  Future<Feed?> getFeedByUrl(String url) async {
    final row = await (select(feedsTable)..where((f) => f.url.equals(url)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Insert feed
  Future<void> insertFeed(Feed feed) async {
    await into(feedsTable).insert(_toEntry(feed),
        mode: InsertMode.insertOrReplace);
  }

  /// Insert or update feed
  Future<void> insertOrUpdateFeed(Feed feed) async {
    await into(feedsTable).insertOnConflictUpdate(_toEntry(feed));
  }

  /// Update feed
  Future<bool> updateFeed(Feed feed) =>
      update(feedsTable).replace(_toEntry(feed));

  /// Delete feed and its articles
  Future<void> deleteFeed(String feedId) async {
    await transaction(() async {
      await (delete(articlesTable)..where((a) => a.feedId.equals(feedId))).go();
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
    final feed = await getFeed(feedId);
    if (feed == null) return;

    final successfulFetches =
        success ? feed.successfulFetches + 1 : feed.successfulFetches;
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
  Future<List<Feed>> getFeedsNeedingUpdate() async {
    final now = DateTime.now();
    final rows = await (select(feedsTable)
          ..where((f) {
            return f.isActive &
                (f.lastFetched.isNull() |
                    f.lastFetched.isSmallerThan(Variable(now)));
          }))
        .get();
    return rows.map(_toModel).toList();
  }

  /// Get feeds modified since a specific date (for sync)
  Future<List<Feed>> getModifiedSince(DateTime? since) async {
    if (since == null) {
      return getAllFeeds();
    }

    final rows = await (select(feedsTable)
          ..where((f) => f.updatedAt.isBiggerOrEqualValue(since))
          ..orderBy([(f) => OrderingTerm.desc(f.updatedAt)]))
        .get();
    return rows.map(_toModel).toList();
  }

  Feed _toModel(FeedEntry entry) {
    return Feed(
      id: entry.id,
      url: entry.url,
      title: entry.title,
      description: entry.description,
      link: entry.link,
      categoryId: entry.categoryId,
      faviconUrl: entry.faviconUrl,
      lastFetched: entry.lastFetched,
      etag: entry.etag,
      lastModified: entry.lastModified,
      updateFrequency: entry.updateFrequency,
      isActive: entry.isActive,
      type: FeedType.values.firstWhere(
        (t) => t.name == entry.type,
        orElse: () => FeedType.rss,
      ),
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
      language: entry.language,
      copyright: entry.copyright,
      generator: entry.generator,
      imageUrl: entry.imageUrl,
      successfulFetches: entry.successfulFetches,
      failedFetches: entry.failedFetches,
      successRate: entry.successRate,
      lastError: entry.lastError,
      lastErrorAt: entry.lastErrorAt,
    );
  }

  FeedEntry _toEntry(Feed feed) {
    return FeedEntry(
      id: feed.id,
      url: feed.url,
      title: feed.title,
      description: feed.description,
      link: feed.link,
      categoryId: feed.categoryId,
      faviconUrl: feed.faviconUrl,
      lastFetched: feed.lastFetched,
      etag: feed.etag,
      lastModified: feed.lastModified,
      updateFrequency: feed.updateFrequency,
      isActive: feed.isActive,
      type: feed.type.name,
      createdAt: feed.createdAt,
      updatedAt: feed.updatedAt,
      language: feed.language,
      copyright: feed.copyright,
      generator: feed.generator,
      imageUrl: feed.imageUrl,
      successfulFetches: feed.successfulFetches,
      failedFetches: feed.failedFetches,
      successRate: feed.successRate,
      lastError: feed.lastError,
      lastErrorAt: feed.lastErrorAt,
    );
  }
}
