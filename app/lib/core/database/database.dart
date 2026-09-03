import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables/feeds_table.dart';
import 'tables/articles_table.dart';
import 'tables/categories_table.dart';
import 'tables/settings_table.dart';
import 'tables/bypass_rules_table.dart';
import 'tables/market_watchlist_table.dart';
import 'tables/sync_metadata_table.dart';
import '../models/folder.dart';
import 'daos/feed_dao.dart';
import 'daos/article_dao.dart';
import 'daos/category_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/folder_dao.dart';

part 'database.g.dart';

/// Main database class
@DriftDatabase(
  tables: [
    FeedsTable,
    ArticlesTable,
    CategoriesTable,
    SettingsTable,
    BypassRulesTable,
    MarketWatchlistTable,
    SyncMetadataTable,
    FoldersTable,
    FolderFeedsTable,
    FolderMembersTable,
    FolderActivitiesTable,
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
  AppDatabase() : super(_openConnection());
  
  @override
  int get schemaVersion => 2;
  
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        
        // Insert default categories
        await into(categoriesTable).insertAll([
          CategoriesTableCompanion.insert(
            id: const Value('uncategorized'),
            name: 'Uncategorized',
            icon: const Value('folder'),
            sortOrder: const Value(0),
          ),
          CategoriesTableCompanion.insert(
            id: const Value('favorites'),
            name: 'Favorites',
            icon: const Value('star'),
            sortOrder: const Value(1),
          ),
        ]);
        
        // Insert default settings
        await into(settingsTable).insertAll([
          SettingsTableCompanion.insert(
            key: 'theme',
            value: 'default',
          ),
          SettingsTableCompanion.insert(
            key: 'updateFrequency',
            value: '3600',
          ),
          SettingsTableCompanion.insert(
            key: 'articlesPerPage',
            value: '20',
          ),
        ]);
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migration from version 1 to 2: Add folder tables
        if (from < 2) {
          await m.createTable(foldersTable);
          await m.createTable(folderFeedsTable);
          await m.createTable(folderMembersTable);
          await m.createTable(folderActivitiesTable);
        }
      },
    );
  }
  
  /// Delete all data (useful for testing)
  Future<void> deleteEverything() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }
  
  /// Export database to JSON
  Future<Map<String, dynamic>> exportToJson() async {
    final feeds = await select(feedsTable).get();
    final articles = await select(articlesTable).get();
    final categories = await select(categoriesTable).get();
    final settings = await select(settingsTable).get();
    
    return {
      'version': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'feeds': feeds.map((f) => f.toJson()).toList(),
      'articles': articles.map((a) => a.toJson()).toList(),
      'categories': categories.map((c) => c.toJson()).toList(),
      'settings': settings.map((s) => s.toJson()).toList(),
    };
  }
  
  /// Import database from JSON
  Future<void> importFromJson(Map<String, dynamic> data) async {
    await transaction(() async {
      // Clear existing data
      await deleteEverything();
      
      // Import categories first (referenced by feeds)
      final categories = (data['categories'] as List<dynamic>?)
          ?.map((c) => CategoriesTableCompanion.fromJson(c as Map<String, dynamic>))
          .toList();
      if (categories != null && categories.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(categoriesTable, categories);
        });
      }
      
      // Import feeds
      final feeds = (data['feeds'] as List<dynamic>?)
          ?.map((f) => FeedsTableCompanion.fromJson(f as Map<String, dynamic>))
          .toList();
      if (feeds != null && feeds.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(feedsTable, feeds);
        });
      }
      
      // Import articles
      final articles = (data['articles'] as List<dynamic>?)
          ?.map((a) => ArticlesTableCompanion.fromJson(a as Map<String, dynamic>))
          .toList();
      if (articles != null && articles.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(articlesTable, articles);
        });
      }
      
      // Import settings
      final settings = (data['settings'] as List<dynamic>?)
          ?.map((s) => SettingsTableCompanion.fromJson(s as Map<String, dynamic>))
          .toList();
      if (settings != null && settings.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(settingsTable, settings);
        });
      }
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'rss_reader.db'));
    
    return NativeDatabase.createInBackground(file);
  });
}