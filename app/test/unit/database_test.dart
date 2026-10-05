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

  test('B01: backups with multiple sync metadata rows are rejected atomically',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));

    await expectLater(
      db.importFromJson({
        'format': 'omi-rss-backup',
        'version': db.schemaVersion,
        'syncMetadata': [
          {
            'deviceId': 'device-a',
            'lastSync': null,
            'syncToken': null,
            'pendingChangesJson': null,
          },
          {
            'deviceId': 'device-b',
            'lastSync': null,
            'syncToken': null,
            'pendingChangesJson': null,
          },
        ],
      }),
      throwsArgumentError,
    );

    expect(await db.getAllFeeds(), hasLength(1),
        reason: 'rejected import must leave the database untouched');
    // Sync accessors keep working rather than throwing on any legacy
    // multi-row state.
    expect((await db.getLastSyncAt()), isNull);
    expect(await db.syncDeviceId(), isNotEmpty);
  });

  test('B15: backups with wrong format or version are rejected', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await expectLater(
      db.importFromJson(<String, dynamic>{}),
      throwsArgumentError,
    );
    await expectLater(
      db.importFromJson(<String, dynamic>{
        'format': 'some-other-tool',
        'version': 1,
      }),
      throwsArgumentError,
    );
    await expectLater(
      db.importFromJson(<String, dynamic>{
        'format': 'omi-rss-backup',
        'version': db.schemaVersion + 1,
      }),
      throwsArgumentError,
    );

    expect(await db.getAllFeeds(), isEmpty);
  });

  test('B16: v5 folder data with dangling references migrates cleanly',
      () async {
    final path = await _downgradedDb(
      5,
      extraStatements: [
        'DROP TABLE folder_feeds_table',
        'DROP TABLE folders_table',
        'CREATE TABLE folders_table (id TEXT NOT NULL PRIMARY KEY,'
            ' name TEXT NOT NULL, description TEXT NULL, parent_id TEXT NULL,'
            ' color TEXT NULL, icon TEXT NULL, position INTEGER NOT NULL'
            ' DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT'
            ' NULL)',
        'CREATE TABLE folder_feeds_table (folder_id TEXT NOT NULL,'
            ' feed_id TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0,'
            ' added_at INTEGER NOT NULL, PRIMARY KEY (folder_id, feed_id))',
        "INSERT INTO folders_table (id, name, parent_id, created_at,"
            " updated_at) VALUES ('root', 'Root', NULL, 0, 0)",
        "INSERT INTO folders_table (id, name, parent_id, created_at,"
            " updated_at) VALUES ('child', 'Child', 'root', 0, 0)",
        "INSERT INTO folders_table (id, name, parent_id, created_at,"
            " updated_at) VALUES ('orphan', 'Orphan', 'ghost', 0, 0)",
        "INSERT INTO folders_table (id, name, parent_id, created_at,"
            " updated_at) VALUES ('grandorphan', 'GO', 'orphan', 0, 0)",
        "INSERT INTO folder_feeds_table (folder_id, feed_id, added_at)"
            " VALUES ('child', 'feed-1', 0)",
        "INSERT INTO folder_feeds_table (folder_id, feed_id, added_at)"
            " VALUES ('ghost-folder', 'feed-1', 0)",
      ],
      seed: (db) async {
        await db.feedDao.insertOrUpdateFeed(Feed(
          id: 'feed-1',
          url: 'https://example.com/feed.xml',
          title: 'Example',
        ));
      },
    );
    final db = await _openMigrated(path);
    addTearDown(db.close);

    final folders = await db.folderDao.getAllFolders();
    expect(folders.map((f) => f.id), unorderedEquals(['root', 'child']),
        reason: 'dangling parent chains must be dropped');
    expect(await db.folderDao.getFeedsInFolder('child'), ['feed-1'],
        reason: 'valid membership survives');
    expect(await db.folderDao.getFeedsInFolder('ghost-folder'), isEmpty);

    final fkViolations =
        await db.customSelect('PRAGMA foreign_key_check').get();
    expect(fkViolations, isEmpty);
  });

  test('B16: foreign keys are enforced at runtime', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    // Folder parent must exist.
    await expectLater(
      db.folderDao.insertFolder(Folder(id: 'f1', name: 'Bad', parentId: 'nope')),
      throwsA(anything),
    );

    await db.folderDao.insertFolder(Folder(id: 'parent', name: 'Parent'));
    await db.folderDao.insertFolder(
        Folder(id: 'child', name: 'Child', parentId: 'parent'));
    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));
    await db.folderDao.addFeedToFolder('parent', 'feed-1');

    // Deleting the feed removes its folder membership (cascade).
    await db.feedDao.deleteFeed('feed-1');
    expect(await db.folderDao.getFeedsInFolder('parent'), isEmpty);

    // Deleting a parent folder promotes children to root (set null).
    await db.folderDao.deleteFolder('parent');
    final folders = await db.folderDao.getAllFolders();
    expect(folders, hasLength(1));
    expect(folders.first.id, 'child');
    expect(folders.first.parentId, isNull);
  });

  test('B16: imports with dangling folder references are rejected atomically',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));

    final feedRow = {
      'id': 'feed-9',
      'url': 'https://example.com/9.xml',
      'title': 'Nine',
      'description': null,
      'link': null,
      'siteUrl': null,
      'customTitle': null,
      'categoryId': null,
      'faviconUrl': null,
      'lastFetched': null,
      'etag': null,
      'lastModified': null,
      'updateFrequency': 60,
      'isActive': true,
      'type': 'rss',
      'createdAt': '2026-10-04T00:00:00.000',
      'updatedAt': '2026-10-04T00:00:00.000',
      'language': null,
      'copyright': null,
      'generator': null,
      'imageUrl': null,
      'customFields': null,
      'successfulFetches': 0,
      'failedFetches': 0,
      'successRate': 0.0,
      'lastError': null,
      'lastErrorAt': null,
    };
    final folderRow = {
      'id': 'folder-9',
      'name': 'Nine',
      'description': null,
      'parentId': 'missing-parent',
      'color': null,
      'icon': null,
      'position': 0,
      'createdAt': '2026-10-04T00:00:00.000',
      'updatedAt': '2026-10-04T00:00:00.000',
    };
    final base = {
      'format': 'omi-rss-backup',
      'version': db.schemaVersion,
    };

    await expectLater(
      db.importFromJson({...base, 'feeds': [feedRow], 'folders': [folderRow]}),
      throwsArgumentError,
    );
    await expectLater(
      db.importFromJson({
        ...base,
        'feeds': [feedRow],
        'folderFeeds': [
          {
            'folderId': 'missing-folder',
            'feedId': 'feed-9',
            'position': 0,
            'addedAt': '2026-10-04T00:00:00.000',
          }
        ],
      }),
      throwsArgumentError,
    );
    await expectLater(
      db.importFromJson({
        ...base,
        'feeds': [feedRow],
        'folders': [
          {
            'id': 'folder-9',
            'name': 'Nine',
            'description': null,
            'parentId': null,
            'color': null,
            'icon': null,
            'position': 0,
            'createdAt': '2026-10-04T00:00:00.000',
            'updatedAt': '2026-10-04T00:00:00.000',
          },
        ],
        'folderFeeds': [
          {
            'folderId': 'folder-9',
            'feedId': 'missing-feed',
            'position': 0,
            'addedAt': '2026-10-04T00:00:00.000',
          }
        ],
      }),
      throwsArgumentError,
    );

    expect(await db.getAllFeeds(), hasLength(1),
        reason: 'rejected imports must leave the database untouched');
  });
}
