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
    final feeds = await select(feedsTable).get();
    final articles = await select(articlesTable).get();
    final categories = await select(categoriesTable).get();
    final settings = await select(settingsTable).get();
    final folders = await select(foldersTable).get();
    final folderFeeds = await select(folderFeedsTable).get();
    final syncMetadata = await select(syncMetadataTable).get();

    return {
      'format': 'omi-rss-backup',
      'version': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'feeds': feeds.map((f) => f.toJson()).toList(),
      'articles': articles.map((a) => a.toJson()).toList(),
      'categories': categories.map((c) => c.toJson()).toList(),
      'settings': settings.map((s) => s.toJson()).toList(),
      'folders': folders.map((f) => f.toJson()).toList(),
      'folderFeeds': folderFeeds.map((f) => f.toJson()).toList(),
      'syncMetadata': syncMetadata.map((s) => s.toJson()).toList(),
    };
  }
  /// Import database from JSON. The payload is fully parsed and validated
  /// before any existing data is deleted; a failure leaves the database
  /// untouched.
  Future<void> importFromJson(Map<String, dynamic> data) async {
    if (data['format'] != 'omi-rss-backup') {
      throw ArgumentError(
          'Unsupported backup format: ${data['format']}');
    }
    final version = data['version'];
    if (version is! int || version < 1 || version > schemaVersion) {
      throw ArgumentError('Unsupported backup version: $version');
    }

    final categories =
        _parseRows(data['categories'], CategoryEntry.fromJson);
    final folders =
        _parseRows(data['folders'], FolderEntry.fromJson);
    final feeds =
        _parseRows(data['feeds'], FeedEntry.fromJson);
    final folderFeeds =
        _parseRows(data['folderFeeds'], FolderFeedEntry.fromJson);
    final articles = _parseRows(data['articles'], ArticleEntry.fromJson);
    final settings = _parseRows(data['settings'], SettingEntry.fromJson);
    final syncMetadata =
        _parseRows(data['syncMetadata'], SyncMetadataEntry.fromJson);

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
