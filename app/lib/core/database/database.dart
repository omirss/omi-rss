import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';
import 'tables/feeds_table.dart';
import 'tables/articles_table.dart';
import 'tables/settings_table.dart';
import 'tables/sync_metadata_table.dart';
import '../models/folder.dart';
import '../models/feed.dart';
import '../models/article.dart';
import '../models/category.dart';
import 'daos/feed_dao.dart';
import 'daos/article_dao.dart';
import 'daos/category_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/folder_dao.dart';
import 'connection/connection.dart';

part 'database.g.dart';

/// Main database class
@DriftDatabase(
  tables: [
    FeedsTable,
    ArticlesTable,
    CategoriesTable,
    SettingsTable,
    SyncMetadataTable,
    FoldersTable,
    FolderFeedsTable,
  ],
  daos: [
    FeedDao,
    ArticleDao,
    CategoryDao,
    SettingsDao,
    FolderDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openAppConnection());

  /// Database with an injectable executor for tests.
  @visibleForTesting
  AppDatabase.testing(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 6;
  
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        
        // Insert default categories
        await batch((batch) {
          batch.insertAll(categoriesTable, [
            CategoriesTableCompanion.insert(
              id: 'uncategorized',
              name: 'Uncategorized',
              icon: const Value('folder'),
              sortOrder: const Value(0),
            ),
            CategoriesTableCompanion.insert(
              id: 'favorites',
              name: 'Favorites',
              icon: const Value('star'),
              sortOrder: const Value(1),
            ),
          ]);
        });

        // Insert default settings
        await batch((batch) {
          batch.insertAll(settingsTable, [
            SettingsTableCompanion.insert(
              key: 'theme',
              value: 'default',
            ),
            SettingsTableCompanion.insert(
              key: 'updateFrequency',
              value: '60',
            ),
            SettingsTableCompanion.insert(
              key: 'articlesPerPage',
              value: '20',
            ),
          ]);
        });
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(foldersTable);
          await m.createTable(folderFeedsTable);
        }
        // v3 had no structural change beyond v2.
        if (from < 4) {
          // update_frequency switched from seconds to minutes; its CHECK
          // constraint changed too. feeds_table is rebuilt with the new
          // definition and articles_table is recreated so its foreign key
          // keeps pointing at feeds_table after the rename dance.
          await customStatement(
              'ALTER TABLE feeds_table RENAME TO feeds_table_v3');
          await customStatement(
              'ALTER TABLE articles_table RENAME TO articles_table_v3');
          await m.createTable(feedsTable);
          await m.createTable(articlesTable);
          await customStatement(''
              'INSERT INTO feeds_table (id, url, title, description, link,'
              ' category_id, favicon_url, last_fetched, etag, last_modified,'
              ' update_frequency, is_active, type, created_at, updated_at,'
              ' language, copyright, generator, image_url, custom_fields,'
              ' successful_fetches, failed_fetches, success_rate, last_error,'
              ' last_error_at) '
              'SELECT id, url, title, description, link, category_id,'
              ' favicon_url, last_fetched, etag, last_modified,'
              ' MAX(update_frequency / 60, 1), is_active, type, created_at,'
              ' updated_at, language, copyright, generator, image_url,'
              ' custom_fields, successful_fetches, failed_fetches, success_rate,'
              ' last_error, last_error_at FROM feeds_table_v3');
          await customStatement(
              'INSERT INTO articles_table SELECT * FROM articles_table_v3');
          await customStatement('DROP TABLE articles_table_v3');
          await customStatement('DROP TABLE feeds_table_v3');
        }
        if (from < 5) {
          // site_url/custom_title. A from<4 rebuild already creates
          // feeds_table at the current (v5) shape, so guard against
          // duplicate columns.
          if (!await _columnExists('feeds_table', 'site_url')) {
            await customStatement(
                'ALTER TABLE feeds_table ADD COLUMN site_url TEXT');
          }
          if (!await _columnExists('feeds_table', 'custom_title')) {
            await customStatement(
                'ALTER TABLE feeds_table ADD COLUMN custom_title TEXT');
          }
        }
        if (from < 6) {
          // Foreign-key constraints for the folder tables. SQLite cannot
          // add constraints via ALTER TABLE, so both tables are rebuilt;
          // rows referencing missing folders or feeds are dropped.
          await customStatement(
              'ALTER TABLE folders_table RENAME TO folders_table_v5');
          await customStatement(
              'ALTER TABLE folder_feeds_table RENAME TO folder_feeds_table_v5');
          await m.createTable(foldersTable);
          await m.createTable(folderFeedsTable);
          await customStatement(''
              'INSERT INTO folders_table (id, name, description, parent_id,'
              ' color, icon, position, created_at, updated_at) '
              'SELECT id, name, description, parent_id, color, icon,'
              ' position, created_at, updated_at FROM folders_table_v5');
          // Drop folders whose parent chain does not reach a root;
          // repeat until stable so multi-level orphans are removed too.
          var removed = -1;
          while (removed != 0) {
            removed = await customUpdate(
                'DELETE FROM folders_table WHERE parent_id IS NOT NULL '
                'AND parent_id NOT IN (SELECT id FROM folders_table)');
          }
          // Cycles (a -> b -> a) survive the dangling-parent sweep
          // because both ends exist. Break them deterministically: any
          // folder not reachable from a root is cyclic, so promote the
          // lowest-id unreachable folder to root and repeat.
          var promoted = -1;
          while (promoted != 0) {
            promoted = await customUpdate(
                'UPDATE folders_table SET parent_id = NULL WHERE id = ('
                "SELECT id FROM folders_table WHERE parent_id IS NOT NULL "
                'AND id NOT IN ('
                'WITH RECURSIVE reachable(id) AS ('
                "SELECT id FROM folders_table WHERE parent_id IS NULL "
                'UNION ALL '
                'SELECT f.id FROM folders_table f '
                'JOIN reachable r ON f.parent_id = r.id) '
                'SELECT id FROM reachable) '
                'ORDER BY id LIMIT 1)');
          }
          await customStatement(''
              'INSERT INTO folder_feeds_table (folder_id, feed_id, position,'
              ' added_at) '
              'SELECT folder_id, feed_id, position, added_at'
              ' FROM folder_feeds_table_v5 '
              'WHERE folder_id IN (SELECT id FROM folders_table) '
              'AND feed_id IN (SELECT id FROM feeds_table)');
          await customStatement('DROP TABLE folder_feeds_table_v5');
          await customStatement('DROP TABLE folders_table_v5');
        }
      },
      beforeOpen: (details) async {
        // Enforce the declared foreign keys at runtime.
        await customStatement('PRAGMA foreign_keys = ON');
        await _canonicalizeSyncMetadata();
      },
    );
  }
  
  /// Commit the result of a local (direct publisher) feed refresh in one
  /// transaction: publisher feed columns, publisher article upserts, and
  /// the per-feed retention cap land together. Every local ingest path
  /// must go through this so the cap is applied consistently with the
  /// server-sync paths.
  Future<void> commitPublisherRefresh(
    Feed refreshedFeed,
    List<Article> publisherArticles,
    int retentionLimit,
  ) {
    return transaction(() async {
      await feedDao.applyPublisherRefresh(refreshedFeed);
      if (publisherArticles.isNotEmpty) {
        await articleDao.upsertPublisherArticles(publisherArticles);
      }
      await articleDao.enforcePerFeedLimit(retentionLimit);
    });
  }

  /// Delete all data (useful for testing)
  Future<void> deleteEverything() async {
    await transaction(() async {
      // Foreign keys are enforced (beforeOpen); defer the checks to the
      // end of the transaction so table deletion order cannot trip them.
      await customStatement('PRAGMA defer_foreign_keys = ON');
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }
  
  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  /// Export database to JSON
  Future<Map<String, dynamic>> exportToJson() async {
    // The importer rejects backups with more than one sync metadata row;
    // tolerated legacy multi-row state must not be exported as-is.
    await _canonicalizeSyncMetadata();
    // One transaction = one consistent SQLite snapshot. Reading each
    // table in its own query would let a concurrent refresh commit
    // between reads and produce a torn backup (articles keyed to feeds
    // that were re-keyed mid-export).
    final s = await transaction(() async {
      return (
        await select(feedsTable).get(),
        await select(articlesTable).get(),
        await select(categoriesTable).get(),
        await select(settingsTable).get(),
        await select(foldersTable).get(),
        await select(folderFeedsTable).get(),
        await select(syncMetadataTable).get(),
      );
    });

    return {
      'format': 'omi-rss-backup',
      'version': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'feeds': s.$1.map((f) => f.toJson()).toList(),
      'articles': s.$2.map((a) => a.toJson()).toList(),
      'categories': s.$3.map((c) => c.toJson()).toList(),
      'settings': s.$4.map((x) => x.toJson()).toList(),
      'folders': s.$5.map((f) => f.toJson()).toList(),
      'folderFeeds': s.$6.map((f) => f.toJson()).toList(),
      'syncMetadata': s.$7.map((x) => x.toJson()).toList(),
    };
  }
  /// Import database from JSON. The payload is fully parsed and validated
  /// before any existing data is deleted; a failure leaves the database
  /// untouched.
  Future<void> importFromJson(Map<String, dynamic> data) async {
    final normalized = _normalizeBackup(data);

    final categories =
        _parseRows(normalized['categories'], CategoryEntry.fromJson);
    final folders =
        _parseRows(normalized['folders'], FolderEntry.fromJson);
    final feeds =
        _parseRows(normalized['feeds'], FeedEntry.fromJson);
    final folderFeeds =
        _parseRows(normalized['folderFeeds'], FolderFeedEntry.fromJson);
    final articles = _parseRows(normalized['articles'], ArticleEntry.fromJson);
    final settings = _parseRows(normalized['settings'], SettingEntry.fromJson);
    final syncMetadata =
        _parseRows(normalized['syncMetadata'], SyncMetadataEntry.fromJson);

    if (syncMetadata.length > 1) {
      throw ArgumentError(
          'Invalid backup: expected at most one sync metadata row');
    }
    final folderIds = folders.map((f) => f.id).toSet();
    for (final folder in folders) {
      final parent = folder.parentId;
      if (parent != null && !folderIds.contains(parent)) {
        throw ArgumentError('Invalid backup: folder ${folder.id} '
            'references missing parent folder $parent');
      }
    }
    // Every parent chain must terminate at a root; cyclic folders
    // would be invisible in hierarchy views.
    final parentByFolderId = {for (final f in folders) f.id: f.parentId};
    for (final folderId in parentByFolderId.keys) {
      String? current = folderId;
      final visited = <String>{};
      while (current != null) {
        if (!visited.add(current)) {
          throw ArgumentError(
              'Invalid backup: folder cycle detected at $current');
        }
        current = parentByFolderId[current];
      }
    }
    final feedIds = feeds.map((f) => f.id).toSet();
    for (final link in folderFeeds) {
      if (!folderIds.contains(link.folderId)) {
        throw ArgumentError('Invalid backup: folder feed entry references '
            'missing folder ${link.folderId}');
      }
      if (!feedIds.contains(link.feedId)) {
        throw ArgumentError('Invalid backup: folder feed entry references '
            'missing feed ${link.feedId}');
      }
    }

    await transaction(() async {
      // Defer FK checks to commit so batch insert order cannot trip them.
      await customStatement('PRAGMA defer_foreign_keys = ON');
      await deleteEverything();
      if (categories.isNotEmpty) {
        await batch((b) => b.insertAll(categoriesTable, categories));
      }
      if (folders.isNotEmpty) {
        await batch((b) => b.insertAll(foldersTable, folders));
      }
      if (feeds.isNotEmpty) {
        await batch((b) => b.insertAll(feedsTable, feeds));
      }
      if (folderFeeds.isNotEmpty) {
        await batch((b) => b.insertAll(folderFeedsTable, folderFeeds));
      }
      if (articles.isNotEmpty) {
        await batch((b) => b.insertAll(articlesTable, articles));
      }
      if (settings.isNotEmpty) {
        await batch((b) => b.insertAll(settingsTable, settings));
      }
      if (syncMetadata.isNotEmpty) {
        await batch((b) => b.insertAll(syncMetadataTable, syncMetadata));
      }
    });
  }

  /// Validate the envelope and bring legacy backups to the current
  /// shape before any row is constructed. Backups predating the
  /// `format` field are recognized by their schema version plus row
  /// payloads; explicit foreign formats stay rejected. Versions before
  /// 4 stored feed update frequency in seconds, current rows are in
  /// minutes (same conversion as the on-disk migration).
  Map<String, dynamic> _normalizeBackup(Map<String, dynamic> data) {
    final format = data['format'];
    if (format == null) {
      final hasRows = const [
        'feeds',
        'articles',
        'categories',
        'folders',
        'folderFeeds',
        'settings',
        'syncMetadata',
      ].any((key) => data[key] is List);
      if (data['version'] is! int || !hasRows) {
        throw ArgumentError('Unsupported backup format: ${data['format']}');
      }
    } else if (format != 'omi-rss-backup') {
      throw ArgumentError('Unsupported backup format: $format');
    }
    final version = data['version'];
    if (version is! int || version < 1 || version > schemaVersion) {
      throw ArgumentError('Unsupported backup version: $version');
    }

    final normalized = Map<String, dynamic>.from(data);
    normalized['format'] = 'omi-rss-backup';
    normalized['version'] = version;

    // A missing table key is not an empty table. Treating it as one
    // would replace the whole database with empty tables when a
    // truncated or hand-assembled envelope is imported; every backup
    // this app ever wrote carries all seven keys, so requiring them
    // cannot reject a legitimate export.
    for (final key in const [
      'feeds',
      'articles',
      'categories',
      'folders',
      'folderFeeds',
      'settings',
      'syncMetadata',
    ]) {
      if (normalized[key] is! List) {
        throw ArgumentError(
            'Incomplete backup: missing table "$key"');
      }
    }

    if (version < 4) {
      final feeds = normalized['feeds'];
      if (feeds is List) {
        final converted = <Map<String, dynamic>>[];
        for (final row in feeds) {
          final feed = Map<String, dynamic>.from(row as Map);
          final frequency = feed['updateFrequency'];
          if (frequency is num) {
            final minutes = frequency.toInt() ~/ 60;
            feed['updateFrequency'] = minutes < 1 ? 1 : minutes;
          }
          converted.add(feed);
        }
        normalized['feeds'] = converted;
      }
    }
    return normalized;
  }

  List<T> _parseRows<T>(
    Object? raw,
    T Function(Map<String, dynamic>, {ValueSerializer? serializer}) fromJson,
  ) {
    if (raw == null) return [];
    if (raw is! List) {
      throw ArgumentError('Invalid backup payload: expected a list of rows');
    }
    return [
      for (final row in raw)
        fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }
  
  /// Convenience accessors used by services

  Future<List<Feed>> getAllFeeds() => feedDao.getAllFeeds();

  Future<void> insertFeed(Feed feed) => feedDao.insertOrUpdateFeed(feed);

  /// Device identity used to key the sync metadata row. Generated once
  /// on first use and stored in the sync metadata table itself. Rows
  /// still carrying the legacy constant id are migrated to a generated
  /// id so installations stop sharing one identity. The migration runs
  /// in a transaction and checks the update count so concurrent calls
  /// converge on one persisted id instead of returning an id that was
  /// never written.
  Future<String> syncDeviceId() async {
    return transaction(() async {
      final existing = await _syncRow();
      if (existing != null && existing.deviceId != 'app-web') {
        return existing.deviceId;
      }
      final deviceId = const Uuid().v4();
      if (existing != null) {
        final changed = await (update(syncMetadataTable)
              ..where((t) => t.deviceId.equals('app-web')))
            .write(SyncMetadataTableCompanion(deviceId: Value(deviceId)));
        if (changed == 1) return deviceId;
        final migrated = await _syncRow();
        if (migrated != null) return migrated.deviceId;
      }
      await into(syncMetadataTable).insert(
        SyncMetadataTableCompanion.insert(deviceId: deviceId),
        mode: InsertMode.insertOrIgnore,
      );
      final row = await _syncRow();
      return row!.deviceId;
    });
  }

  /// The sync metadata table holds a single row. Legacy databases or
  /// hand-edited backups can accumulate more; read deterministically
  /// instead of throwing on multi-row state.
  Future<SyncMetadataEntry?> _syncRow() {
    return (select(syncMetadataTable)
          ..orderBy([
            (t) => OrderingTerm.desc(t.lastSync),
            (t) => OrderingTerm.asc(t.deviceId),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Collapse legacy multi-row sync metadata to one canonical row:
  /// newest lastSync wins, device id breaks ties deterministically.
  Future<void> _canonicalizeSyncMetadata() async {
    final rows = await select(syncMetadataTable).get();
    if (rows.length <= 1) return;
    rows.sort((a, b) {
      final aSync = a.lastSync;
      final bSync = b.lastSync;
      if (aSync != null && bSync != null) {
        final byTime = bSync.compareTo(aSync);
        if (byTime != 0) return byTime;
      } else if (aSync != null) {
        return -1;
      } else if (bSync != null) {
        return 1;
      }
      return a.deviceId.compareTo(b.deviceId);
    });
    await transaction(() async {
      for (final row in rows.skip(1)) {
        await (delete(syncMetadataTable)
              ..where((t) => t.deviceId.equals(row.deviceId)))
            .go();
      }
    });
  }

  Future<DateTime?> getLastSyncAt() async {
    final row = await _syncRow();
    return row?.lastSync;
  }

  Future<void> setLastSyncAt(DateTime time) async {
    final deviceId = await syncDeviceId();
    await into(syncMetadataTable).insertOnConflictUpdate(
      SyncMetadataTableCompanion.insert(
        deviceId: deviceId,
        lastSync: Value(time),
      ),
    );
  }
  
  Future<Category> createCategory(Category category) async {
    await into(categoriesTable).insert(
      CategoriesTableCompanion.insert(
        id: category.id,
        name: category.name,
        color: Value(category.color),
        icon: Value(category.icon),
        sortOrder: Value(category.sortOrder),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return category;
  }
  
  Future<List<Article>> getArticlesByFeed(String feedId) =>
      articleDao.getArticlesByFeed(feedId);
  
  Future<void> markFeedAsRead(String feedId) =>
      articleDao.markFeedAsRead(feedId);
  
  Future<void> markFeedsAsRead(List<String> feedIds) =>
      articleDao.markFeedsAsRead(feedIds);
  
  Future<void> deleteArticles(List<String> articleIds) =>
      articleDao.deleteArticles(articleIds);
}
