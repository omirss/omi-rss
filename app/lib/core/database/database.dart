import 'package:drift/drift.dart';
import 'tables/feeds_table.dart';
import 'tables/articles_table.dart';
import 'tables/categories_table.dart';
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
  
  @override
  int get schemaVersion => 3;
  
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
              value: '3600',
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
        if (from < 3) {
          await m.createTable(foldersTable);
          await m.createTable(folderFeedsTable);
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
      await deleteEverything();
      
      final categories = (data['categories'] as List<dynamic>?)
          ?.map((c) => CategoriesTableCompanion.insert(
                id: (c as Map<String, dynamic>)['id'] as String,
                name: c['name'] as String,
              ))
          .toList();
      if (categories != null && categories.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(categoriesTable, categories);
        });
      }
      
      final feeds = (data['feeds'] as List<dynamic>?)
          ?.map((f) {
            final json = f as Map<String, dynamic>;
            return FeedsTableCompanion.insert(
              id: json['id'] as String,
              url: json['url'] as String,
              title: json['title'] as String,
            );
          })
          .toList();
      if (feeds != null && feeds.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(feedsTable, feeds);
        });
      }
      
      final articles = (data['articles'] as List<dynamic>?)
          ?.map((a) {
            final json = a as Map<String, dynamic>;
            return ArticlesTableCompanion.insert(
              id: json['id'] as String,
              feedId: json['feedId'] as String,
              guid: json['guid'] as String,
              title: json['title'] as String,
              url: json['url'] as String,
            );
          })
          .toList();
      if (articles != null && articles.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(articlesTable, articles);
        });
      }
      
      final settings = (data['settings'] as List<dynamic>?)
          ?.map((s) {
            final json = s as Map<String, dynamic>;
            return SettingsTableCompanion.insert(
              key: json['key'] as String,
              value: json['value'] as String,
            );
          })
          .toList();
      if (settings != null && settings.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(settingsTable, settings);
        });
      }
    });
  }
  
  /// Convenience accessors used by services
  
  Future<List<Feed>> getAllFeeds() => feedDao.getAllFeeds();
  
  Future<void> insertFeed(Feed feed) => feedDao.insertOrUpdateFeed(feed);
  
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
