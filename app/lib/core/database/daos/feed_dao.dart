import 'dart:convert';

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
    await into(feedsTable).insertOnConflictUpdate(_toEntry(feed));
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

  /// Re-key a local feed onto a server feed identity without losing
  /// local data. Articles and folder memberships move to [newFeedId];
  /// when an article already exists under [newFeedId] with the same
  /// guid, user-owned state (read/starred/archived/full content) is
  /// merged into the surviving row before the duplicate is dropped.
  /// The caller must ensure the [newFeedId] row already exists so
  /// foreign keys hold throughout.
  Future<void> mergeFeedIdentity(String oldFeedId, String newFeedId) async {
    if (oldFeedId == newFeedId) return;
    await transaction(() async {
      await customUpdate(
        'UPDATE articles_table SET '
        'is_read = CASE WHEN is_read != 0 THEN 1 '
        'ELSE (SELECT moving.is_read FROM articles_table moving '
        'WHERE moving.feed_id = ? AND moving.guid = articles_table.guid) END, '
        'is_starred = CASE WHEN is_starred != 0 THEN 1 '
        'ELSE (SELECT moving.is_starred FROM articles_table moving '
        'WHERE moving.feed_id = ? AND moving.guid = articles_table.guid) END, '
        'is_archived = CASE WHEN is_archived != 0 THEN 1 '
        'ELSE (SELECT moving.is_archived FROM articles_table moving '
        'WHERE moving.feed_id = ? AND moving.guid = articles_table.guid) END, '
        'read_time_seconds = COALESCE(read_time_seconds, '
        '(SELECT moving.read_time_seconds FROM articles_table moving '
        'WHERE moving.feed_id = ? AND moving.guid = articles_table.guid)), '
        'full_content = COALESCE(full_content, '
        '(SELECT moving.full_content FROM articles_table moving '
        'WHERE moving.feed_id = ? AND moving.guid = articles_table.guid)), '
        'full_content_fetched_at = COALESCE(full_content_fetched_at, '
        '(SELECT moving.full_content_fetched_at FROM articles_table moving '
        'WHERE moving.feed_id = ? AND moving.guid = articles_table.guid)), '
        'full_content_available = COALESCE(full_content_available, '
        '(SELECT moving.full_content_available FROM articles_table moving '
        'WHERE moving.feed_id = ? AND moving.guid = articles_table.guid)) '
        'WHERE feed_id = ? AND EXISTS ('
        'SELECT 1 FROM articles_table moving WHERE moving.feed_id = ? '
        'AND moving.guid = articles_table.guid)',
        variables: [
          for (var i = 0; i < 7; i++) Variable.withString(oldFeedId),
          Variable.withString(newFeedId),
          Variable.withString(oldFeedId),
        ],
      );
      await customUpdate(
        'DELETE FROM articles_table WHERE feed_id = ? AND guid IN '
        '(SELECT guid FROM articles_table WHERE feed_id = ?)',
        variables: [
          Variable.withString(oldFeedId),
          Variable.withString(newFeedId),
        ],
      );
      await customUpdate(
        'UPDATE articles_table SET feed_id = ? WHERE feed_id = ?',
        variables: [
          Variable.withString(newFeedId),
          Variable.withString(oldFeedId),
        ],
      );

      final memberships = await (select(attachedDatabase.folderFeedsTable)
            ..where((ff) => ff.feedId.equals(oldFeedId)))
          .get();
      for (final membership in memberships) {
        await into(attachedDatabase.folderFeedsTable).insert(
          FolderFeedEntry(
            folderId: membership.folderId,
            feedId: newFeedId,
            position: membership.position,
            addedAt: membership.addedAt,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
      await (delete(attachedDatabase.folderFeedsTable)
            ..where((ff) => ff.feedId.equals(oldFeedId)))
          .go();

      await (delete(feedsTable)..where((f) => f.id.equals(oldFeedId))).go();
    });
  }

  /// Record the last time a feed refresh was triggered locally, without
  /// touching health counters or cache headers.
  Future<void> setLastFetched(String feedId, DateTime time) {
    return (update(feedsTable)..where((f) => f.id.equals(feedId))).write(
      FeedsTableCompanion(
        lastFetched: Value(time),
        updatedAt: Value(DateTime.now()),
      ),
    );
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
      siteUrl: entry.siteUrl,
      customTitle: entry.customTitle,
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
      customFields: _decodeCustomFields(entry.customFields),
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
      siteUrl: feed.siteUrl,
      customTitle: feed.customTitle,
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
      customFields:
          feed.customFields == null ? null : jsonEncode(feed.customFields),
      successfulFetches: feed.successfulFetches,
      failedFetches: feed.failedFetches,
      successRate: feed.successRate,
      lastError: feed.lastError,
      lastErrorAt: feed.lastErrorAt,
    );
  }

  /// Malformed stored JSON must not break the whole feed list.
  static Map<String, dynamic>? _decodeCustomFields(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
