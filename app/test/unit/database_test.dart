import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/database/database.dart';
import 'package:rss_glassmorphism_reader/core/models/article.dart';
import 'package:rss_glassmorphism_reader/core/models/feed.dart';
import 'package:rss_glassmorphism_reader/core/models/folder.dart';
import 'package:sqlite3/sqlite3.dart';

const _dropV5Columns = [
  'ALTER TABLE feeds_table DROP COLUMN site_url',
  'ALTER TABLE feeds_table DROP COLUMN custom_title',
];

const _dropFolderTables = [
  'DROP TABLE folder_feeds_table',
  'DROP TABLE folders_table',
];

/// Builds a database file at an old [version] by creating the current
/// schema and undoing the changes introduced after that version, with
/// optional seeded data inserted before the downgrade.
Future<String> _downgradedDb(
  int version, {
  List<String> extraStatements = const [],
  Future<void> Function(AppDatabase db)? seed,
}) async {
  final dir = await Directory.systemTemp.createTemp('omi_migration');
  final path = '${dir.path}/test.db';

  final db = AppDatabase.testing(NativeDatabase(File(path)));
  await db.getAllFeeds(); // force creation
  if (seed != null) await seed(db);
  await db.close();

  final raw = sqlite3.open(path);
  for (final statement in extraStatements) {
    raw.execute(statement);
  }
  raw.execute('PRAGMA user_version = $version');
  raw.dispose();
  return path;
}

Future<AppDatabase> _openMigrated(String path) async {
  final db = AppDatabase.testing(NativeDatabase(File(path)));
  await db.getAllFeeds(); // triggers migration
  return db;
}

Future<List<String>> _tableNames(AppDatabase db, String table) async {
  final rows = await db
      .customSelect('PRAGMA table_info($table)').get();
  return rows.map((r) => r.read<String>('name')).toList();
}

void main() {
  test('A01: v1 database migrates to v5 without double-creating tables',
      () async {
    final path = await _downgradedDb(1,
        extraStatements: [..._dropV5Columns, ..._dropFolderTables]);
    final db = await _openMigrated(path);
    addTearDown(db.close);

    final folderTables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name IN ('folders_table','folder_feeds_table')",
    ).get();
    expect(folderTables, hasLength(2));

    final feedColumns = await _tableNames(db, 'feeds_table');
    expect(feedColumns, containsAll(['site_url', 'custom_title']));

    final fkViolations =
        await db.customSelect('PRAGMA foreign_key_check').get();
    expect(fkViolations, isEmpty);
  });

  test('A01: v3 database migrates to v5', () async {
    final path =
        await _downgradedDb(3, extraStatements: _dropV5Columns);
    final db = await _openMigrated(path);
    addTearDown(db.close);

    final feedColumns = await _tableNames(db, 'feeds_table');
    expect(feedColumns, containsAll(['site_url', 'custom_title']));

    final fkViolations =
        await db.customSelect('PRAGMA foreign_key_check').get();
    expect(fkViolations, isEmpty);
  });

  test('A01: v4 database migrates to v5 and existing data survives',
      () async {
    final path = await _downgradedDb(
      4,
      extraStatements: _dropV5Columns,
      seed: (db) async {
        await db.feedDao.insertOrUpdateFeed(Feed(
          id: 'feed-1',
          url: 'https://example.com/feed.xml',
          title: 'Example',
        ));
        await db.articleDao.insertArticles([
          Article(
            feedId: 'feed-1',
            guid: 'g1',
            title: 'Article',
            url: 'https://example.com/1',
          ),
        ]);
      },
    );
    final db = await _openMigrated(path);
    addTearDown(db.close);

    final feeds = await db.getAllFeeds();
    expect(feeds, hasLength(1));
    expect(feeds.first.title, 'Example');
    final articles = await db.getArticlesByFeed('feed-1');
    expect(articles, hasLength(1));
    expect(articles.first.guid, 'g1');
  });

  test('A02: export -> import round-trips all durable data', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
      siteUrl: 'https://example.com',
      customTitle: 'My Example',
    ));
    await db.folderDao.insertFolder(Folder(id: 'folder-1', name: 'News'));
    await db.folderDao.addFeedToFolder('folder-1', 'feed-1');
    await db.articleDao.insertArticles([
      Article(
        feedId: 'feed-1',
        guid: 'g1',
        title: 'Read and starred',
        url: 'https://example.com/1',
        isRead: true,
        isStarred: true,
        publishedAt: DateTime.utc(2026, 10, 1),
      ),
    ]);

    final export1 = await db.exportToJson();

    // Wipe and restore through the public import path.
    await db.importFromJson(Map<String, dynamic>.from(export1));

    final feeds = await db.getAllFeeds();
    expect(feeds.first.siteUrl, 'https://example.com',
        reason: 'A16: siteUrl must survive the round trip');
    expect(feeds.first.customTitle, 'My Example',
        reason: 'A16: customTitle must survive the round trip');

    final articles = await db.articleDao.getAllArticles();
    expect(articles.first.isRead, isTrue,
        reason: 'read state must survive backup/restore');
    expect(articles.first.isStarred, isTrue,
        reason: 'starred state must survive backup/restore');
    expect(articles.first.publishedAt?.toUtc(), DateTime.utc(2026, 10, 1));

    final folders = await db.folderDao.getAllFolders();
    expect(folders, hasLength(1));
    expect(folders.first.name, 'News');

    final export2 = await db.exportToJson();
    for (final key in [
      'feeds',
      'articles',
      'categories',
      'settings',
      'folders',
      'folderFeeds',
      'syncMetadata',
    ]) {
      expect(export2[key], equals(export1[key]),
          reason: '$key must round-trip semantically');
    }
  });

  test('A02: invalid payload never deletes existing data', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));

    await expectLater(
      db.importFromJson({'feeds': 42}),
      throwsArgumentError,
    );
    await expectLater(
      db.importFromJson({
        'feeds': [
          {'id': 'x', 'title': 'missing url'}
        ]
      }),
      throwsA(isA<Error>()),
    );

    expect(await db.getAllFeeds(), hasLength(1),
        reason: 'failed imports must leave the database untouched');
  });

  test('A07: enclosures and perspectives survive a DB round trip', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Podcast',
    ));
    final enclosures = [
      const Enclosure(
        url: 'https://cdn.example.com/ep1.mp3',
        type: 'audio/mpeg',
        length: 12345,
      ),
      const Enclosure(url: 'https://cdn.example.com/ep1.jpg', type: 'image/jpeg'),
    ];
    final perspectives = {
      'left': {'score': 0.2},
      'right': {'score': 0.8},
    };

    await db.articleDao.insertArticles([
      Article(
        feedId: 'feed-1',
        guid: 'g1',
        title: 'Episode 1',
        url: 'https://example.com/ep1',
        enclosures: enclosures,
        perspectives: perspectives,
      ),
    ]);

    final articles = await db.articleDao.getAllArticles();
    expect(articles.first.enclosures, hasLength(2));
    expect(articles.first.enclosures!.first.url, enclosures.first.url);
    expect(articles.first.enclosures!.first.type, 'audio/mpeg');
    expect(articles.first.enclosures!.first.length, 12345);
    expect(articles.first.enclosures!.last.url, enclosures.last.url);
    expect(articles.first.perspectives, equals(perspectives));
  });

  test('A16: siteUrl and customTitle persist beyond the DAO round trip',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
      siteUrl: 'https://example.com',
      customTitle: 'Custom',
    ));

    final feeds = await db.getAllFeeds();
    expect(feeds.first.url, 'https://example.com/feed.xml');
    expect(feeds.first.siteUrl, 'https://example.com');
    expect(feeds.first.customTitle, 'Custom');
  });

  test('A23: device ids are unique per installation and not the legacy constant',
      () async {
    final db1 = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db1.close);
    final db2 = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db2.close);

    final id1a = await db1.syncDeviceId();
    final id1b = await db1.syncDeviceId();
    final id2 = await db2.syncDeviceId();

    expect(id1a, isNot('app-web'));
    expect(id1b, id1a, reason: 'id is stable within one installation');
    expect(id2, isNot(id1a), reason: 'installations must not share an id');
  });
}
