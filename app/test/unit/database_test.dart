import 'dart:io';

import 'package:drift/drift.dart' show Value;
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
      'articles': <String>[],
      'categories': <String>[],
      'folderFeeds': <String>[],
      'settings': <String>[],
      'syncMetadata': <String>[],
    };

    await expectLater(
      db.importFromJson({
        ...base,
        'feeds': [feedRow],
        'folders': [folderRow],
      }),
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

  test('C15: export canonicalizes legacy multi-row sync metadata',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.syncMetadataTable).insert(
          SyncMetadataTableCompanion.insert(
            deviceId: 'device-a',
            lastSync: Value(DateTime.utc(2026, 9, 1)),
          ),
        );
    await db.into(db.syncMetadataTable).insert(
          SyncMetadataTableCompanion.insert(
            deviceId: 'device-b',
            lastSync: Value(DateTime.utc(2026, 10, 1)),
          ),
        );

    final export = await db.exportToJson();
    final rows = export['syncMetadata'] as List;
    expect(rows, hasLength(1),
        reason: 'an export must never carry rows its importer rejects');
    expect(rows.first['deviceId'], 'device-b',
        reason: 'the newest lastSync row is the canonical one');

    await db.importFromJson(Map<String, dynamic>.from(export));
    expect(await db.getLastSyncAt(), isNotNull,
        reason: 'the canonicalized backup round-trips');
  });

  test('C16: concurrent device-id migration converges on one row',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.syncMetadataTable).insert(
          SyncMetadataTableCompanion.insert(deviceId: 'app-web'),
        );

    final ids = await Future.wait([db.syncDeviceId(), db.syncDeviceId()]);
    expect(ids[0], ids[1],
        reason: 'both callers must observe the single persisted id');

    final rows = await db.select(db.syncMetadataTable).get();
    expect(rows, hasLength(1));
    expect(rows.first.deviceId, ids[0]);
    expect(rows.first.deviceId, isNot('app-web'));
  });

  test('C01: server folderId never lands in category_id', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    final feed = Feed.fromJson({
      'id': 'feed-srv',
      'url': 'https://example.com/feed.xml',
      'title': 'Server Feed',
      'folderId': '11111111-1111-1111-1111-111111111111',
    });
    expect(feed.categoryId, isNull,
        reason: 'folder ids are not category ids');
    expect(feed.folderId, '11111111-1111-1111-1111-111111111111');

    // With FKs enforced, persisting a folder UUID as category_id
    // would fail; insertion must succeed now.
    await db.feedDao.insertOrUpdateFeed(feed);
    final stored = await db.feedDao.getFeed('feed-srv');
    expect(stored!.categoryId, isNull);
  });

  test(
      'C03: replaceFeedFolderMembership adds, moves, and removes', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.folderDao.insertFolder(Folder(id: 'folder-1', name: 'One'));
    await db.folderDao.insertFolder(Folder(id: 'folder-2', name: 'Two'));
    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));

    await db.folderDao.replaceFeedFolderMembership('feed-1', 'folder-1');
    expect(await db.folderDao.getFeedsInFolder('folder-1'), ['feed-1']);

    // A different folder replaces, not adds.
    await db.folderDao.replaceFeedFolderMembership('feed-1', 'folder-2');
    expect(await db.folderDao.getFeedsInFolder('folder-1'), isEmpty);
    expect(await db.folderDao.getFeedsInFolder('folder-2'), ['feed-1']);

    // null clears membership entirely.
    await db.folderDao.replaceFeedFolderMembership('feed-1', null);
    expect(await db.folderDao.getFeedsInFolder('folder-2'), isEmpty);
  });

  test(
      'C04: merging feed identities preserves articles, user state, '
      'and folder membership', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.folderDao.insertFolder(Folder(id: 'folder-1', name: 'News'));
    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-local',
      url: 'https://example.com/feed.xml',
      title: 'Local',
    ));
    await db.folderDao.addFeedToFolder('folder-1', 'feed-local');
    await db.articleDao.insertArticles([
      Article(
        id: 'local-shared',
        feedId: 'feed-local',
        guid: 'g1',
        title: 'Old title',
        url: 'https://example.com/1',
        isRead: true,
        isStarred: true,
        fullContent: 'locally extracted',
      ),
      Article(
        id: 'local-unique',
        feedId: 'feed-local',
        guid: 'g2',
        title: 'Only local',
        url: 'https://example.com/2',
        isStarred: true,
      ),
    ]);

    // Server already synced the same article under its own feed id.
    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-server',
      url: 'https://example.com/feed.xml',
      title: 'Server',
    ));
    await db.articleDao.insertArticles([
      Article(
        id: 'server-shared',
        feedId: 'feed-server',
        guid: 'g1',
        title: 'Server title',
        url: 'https://example.com/1',
      ),
    ]);

    await db.feedDao.mergeFeedIdentity('feed-local', 'feed-server');

    expect(await db.feedDao.getFeed('feed-local'), isNull,
        reason: 'the local identity must be retired');
    expect(await db.feedDao.getFeed('feed-server'), isNotNull);

    final articles = await db.getArticlesByFeed('feed-server');
    expect(articles.map((a) => a.guid), unorderedEquals(['g1', 'g2']));
    final shared = articles.firstWhere((a) => a.guid == 'g1');
    expect(shared.id, 'server-shared',
        reason: 'the surviving row keeps the server id');
    expect(shared.isRead, isTrue, reason: 'local read state must survive');
    expect(shared.isStarred, isTrue,
        reason: 'local starred state must survive');
    expect(shared.fullContent, 'locally extracted',
        reason: 'local full-content cache must survive');
    final unique = articles.firstWhere((a) => a.guid == 'g2');
    expect(unique.isStarred, isTrue);

    expect(await db.folderDao.getFeedsInFolder('folder-1'), ['feed-server'],
        reason: 'folder membership must follow the new identity');
  });

  test(
      'C06: pre-format legacy backups import; foreign payloads still fail',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));
    final legacy =
        Map<String, dynamic>.from(await db.exportToJson())..remove('format');

    await db.importFromJson(legacy);
    expect(await db.getAllFeeds(), hasLength(1),
        reason: 'backups made before the format field must restore');

    await expectLater(
      db.importFromJson(
          {'format': 'some-other-tool', 'version': 1, 'feeds': []}),
      throwsArgumentError,
    );
    await expectLater(
      db.importFromJson({'version': 1}),
      throwsArgumentError,
      reason: 'a format-less payload without rows is not recognizable',
    );
    expect(await db.getAllFeeds(), hasLength(1),
        reason: 'rejected imports must leave the database untouched');
  });

  Map<String, dynamic> legacyFeedRow(String id, int frequency) => {
        'id': id,
        'url': 'https://example.com/$id.xml',
        'title': id,
        'description': null,
        'link': null,
        'siteUrl': null,
        'customTitle': null,
        'categoryId': null,
        'faviconUrl': null,
        'lastFetched': null,
        'etag': null,
        'lastModified': null,
        'updateFrequency': frequency,
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

  test('C07: pre-v4 backup frequencies convert seconds to minutes',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.importFromJson({
      'version': 3,
      'feeds': [
        legacyFeedRow('feed-3600', 3600),
        legacyFeedRow('feed-30', 30),
      ],
      'articles': <String>[],
      'categories': <String>[],
      'folders': <String>[],
      'folderFeeds': <String>[],
      'settings': <String>[],
      'syncMetadata': <String>[],
    });

    final frequencies = {
      for (final feed in await db.getAllFeeds()) feed.id: feed.updateFrequency,
    };
    expect(frequencies['feed-3600'], 60,
        reason: '3600 seconds must restore as 60 minutes');
    expect(frequencies['feed-30'], 1,
        reason: 'sub-minute values clamp to the 1-minute minimum');
  });

  test('C08: cyclic folder imports are rejected atomically', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));

    Map<String, dynamic> folderRow(String id, String? parentId) => {
          'id': id,
          'name': id,
          'description': null,
          'parentId': parentId,
          'color': null,
          'icon': null,
          'position': 0,
          'createdAt': '2026-10-04T00:00:00.000',
          'updatedAt': '2026-10-04T00:00:00.000',
        };

    final cycleBase = {
      'format': 'omi-rss-backup',
      'version': db.schemaVersion,
      'feeds': <String>[],
      'articles': <String>[],
      'categories': <String>[],
      'folderFeeds': <String>[],
      'settings': <String>[],
      'syncMetadata': <String>[],
    };

    await expectLater(
      db.importFromJson({
        ...cycleBase,
        'folders': [
          folderRow('a', 'b'),
          folderRow('b', 'a'),
        ],
      }),
      throwsArgumentError,
      reason: 'a two-folder cycle must be rejected',
    );
    await expectLater(
      db.importFromJson({
        ...cycleBase,
        'folders': [folderRow('self', 'self')],
      }),
      throwsArgumentError,
      reason: 'self-parenting must be rejected',
    );

    expect(await db.getAllFeeds(), hasLength(1),
        reason: 'rejected imports must leave the database untouched');
  });

  test(
      'C08: cyclic v5 folder data migrates to a valid hierarchy', () async {
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
            " updated_at) VALUES ('a', 'A', 'b', 0, 0)",
        "INSERT INTO folders_table (id, name, parent_id, created_at,"
            " updated_at) VALUES ('b', 'B', 'a', 0, 0)",
      ],
    );
    final db = await _openMigrated(path);
    addTearDown(db.close);

    final folders = await db.folderDao.getAllFolders();
    expect(folders.map((f) => f.id),
        unorderedEquals(['root', 'child', 'a', 'b']),
        reason: 'cyclic folders must survive, not be dropped');
    final byId = {for (final f in folders) f.id: f.parentId};
    // The cycle is broken deterministically: 'a' (lowest id in the
    // cycle) is promoted to root, 'b' stays its child.
    expect(byId['a'], isNull);
    expect(byId['b'], 'a');
    expect(byId['child'], 'root');

    final fkViolations =
        await db.customSelect('PRAGMA foreign_key_check').get();
    expect(fkViolations, isEmpty);
  });

  test('C09: nested custom fields survive the feed DB round trip',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    final customFields = {
      'nested': {
        'list': [1, 2, 3],
        'flag': true,
      },
      'name': 'value',
    };
    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
      customFields: customFields,
    ));

    final stored = await db.feedDao.getFeed('feed-1');
    expect(stored!.customFields, equals(customFields));

    // Malformed stored JSON must not break the whole feed list.
    await db.customUpdate(
        "UPDATE feeds_table SET custom_fields = '{oops' WHERE id = 'feed-1'");
    final feeds = await db.getAllFeeds();
    expect(feeds, hasLength(1));
    expect(feeds.first.customFields, isNull);
  });

  test('C14: enforcePerFeedLimit rejects non-positive limits', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));
    await db.articleDao.insertArticles([
      Article(
        feedId: 'feed-1',
        guid: 'g1',
        title: 'Kept',
        url: 'https://example.com/1',
      ),
    ]);

    expect(() => db.articleDao.enforcePerFeedLimit(0), throwsArgumentError);
    expect(() => db.articleDao.enforcePerFeedLimit(-1), throwsArgumentError);

    expect(await db.getArticlesByFeed('feed-1'), hasLength(1),
        reason: 'an invalid limit must never wipe articles');
  });

  test('R4-02: retention works on an empty database (real table name)',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.articleDao.enforcePerFeedLimit(50), 0,
        reason: 'the old SQL targeted a nonexistent "articles" table and '
            'threw on every call');
  });

  test('R4-02: retention caps per feed, keeps starred and NULL-dated rows '
      'ranked by created_at', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    for (final feedId in ['feed-a', 'feed-b']) {
      await db.feedDao.insertOrUpdateFeed(Feed(
        id: feedId,
        url: 'https://example.com/$feedId.xml',
        title: feedId,
      ));
    }

    final created = DateTime(2026, 1, 1);
    final articles = <Article>[
      // feed-a: 4 dated articles sharing one timestamp (id tiebreak
      // decides), 1 undated, 1 old-but-starred.
      for (var i = 0; i < 4; i++)
        Article(
          id: 'a-dated-$i',
          feedId: 'feed-a',
          guid: 'a-dated-$i',
          title: 'dated $i',
          url: 'https://example.com/a/$i',
          publishedAt: created,
          createdAt: created,
        ),
      Article(
        id: 'a-undated',
        feedId: 'feed-a',
        guid: 'a-undated',
        title: 'undated',
        url: 'https://example.com/a/undated',
        publishedAt: null,
        createdAt: created.add(const Duration(days: 1)),
      ),
      Article(
        id: 'a-starred-old',
        feedId: 'feed-a',
        guid: 'a-starred-old',
        title: 'starred',
        url: 'https://example.com/a/starred',
        publishedAt: created.subtract(const Duration(days: 365)),
        createdAt: created.subtract(const Duration(days: 365)),
        isStarred: true,
      ),
      // feed-b: one article — a global or per-wrong-feed cap would eat it.
      Article(
        id: 'b-only',
        feedId: 'feed-b',
        guid: 'b-only',
        title: 'b',
        url: 'https://example.com/b',
        publishedAt: created,
        createdAt: created,
      ),
    ];
    await db.articleDao.insertArticles(articles);

    final deleted = await db.articleDao.enforcePerFeedLimit(2);

    expect(deleted, 3, reason: '3 of feed-a\'s 6 rows fall outside the cap');
    final keptA = await db.getArticlesByFeed('feed-a');
    // Ranking: COALESCE(published_at, created_at) DESC, id DESC —
    // position 1 is the undated row (newest created_at), position 2 is
    // a-dated-3 (the id tiebreak inside the equal-timestamp group), and
    // the starred row is exempt regardless of age.
    expect(keptA.map((a) => a.id), unorderedEquals([
      'a-undated',
      'a-dated-3',
      'a-starred-old',
    ]));
    expect(await db.getArticlesByFeed('feed-b'), hasLength(1),
        reason: 'the cap is per feed');
  });

  test('R4-02: retention deletions reach drift article streams', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));
    final created = DateTime(2026, 1, 1);
    await db.articleDao.insertArticles([
      for (var i = 0; i < 5; i++)
        Article(
          id: 'a-$i',
          feedId: 'feed-1',
          guid: 'g$i',
          title: 'T$i',
          url: 'https://example.com/$i',
          publishedAt: created,
          createdAt: created,
        ),
    ]);

    final emitted = <List<Article>>[];
    final sub = db.articleDao.watchAllArticles().listen(emitted.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);
    emitted.clear();

    await db.articleDao.enforcePerFeedLimit(1);
    await Future<void>.delayed(Duration.zero);

    expect(emitted, isNotEmpty,
        reason: 'customUpdate must declare updates: {articles_table} so '
            'article-only watchers observe the deletions');
    expect(emitted.last, hasLength(1));
  });

  test('R4-02: commitPublisherRefresh lands feed, articles and cap together '
      'and preserves user-owned feed columns', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Publisher title',
      customTitle: 'My custom name',
      updateFrequency: 15,
      isActive: false,
    ));

    // A refresh that started before the user's edits would carry the
    // stale pre-edit row; only publisher columns may be applied.
    final refreshed = (await db.feedDao.getFeed('feed-1'))!.copyWith(
      title: 'New publisher title',
      successfulFetches: 5,
      lastFetched: DateTime(2026, 10, 6),
    );
    await db.commitPublisherRefresh(
      refreshed,
      [
        Article(
          feedId: 'feed-1',
          guid: 'g1',
          title: 'One',
          url: 'https://example.com/1',
          publishedAt: DateTime(2026, 10, 1),
        ),
        Article(
          feedId: 'feed-1',
          guid: 'g2',
          title: 'Two',
          url: 'https://example.com/2',
          publishedAt: DateTime(2026, 10, 2),
        ),
        Article(
          feedId: 'feed-1',
          guid: 'g3',
          title: 'Three',
          url: 'https://example.com/3',
          publishedAt: DateTime(2026, 10, 3),
        ),
      ],
      2,
    );

    final feed = await db.feedDao.getFeed('feed-1');
    expect(feed!.title, 'New publisher title');
    expect(feed.successfulFetches, 5);
    expect(feed.customTitle, 'My custom name',
        reason: 'a network refresh must not clobber user edits');
    expect(feed.updateFrequency, 15);
    expect(feed.isActive, isFalse);

    final kept =
        (await db.getArticlesByFeed('feed-1')).map((a) => a.guid).toSet();
    expect(kept, {'g2', 'g3'},
        reason: 'the retention cap is applied by the same commit');
  });

  test('R4-03: local-first sync order — server rows rekey local identities '
      'without UNIQUE(feed_id, guid) failures', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    // The real pipeline order: local subscription exists first...
    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-local',
      url: 'https://example.com/feed.xml',
      title: 'Local',
    ));
    await db.articleDao.insertArticles([
      Article(
        id: 'local-article',
        feedId: 'feed-local',
        guid: 'g1',
        title: 'Old title',
        url: 'https://example.com/1',
        isRead: true,
        isStarred: true,
        fullContent: 'cached extraction',
        fullContentFetchedAt: DateTime(2026, 10, 1),
      ),
    ]);

    // ...then the server feed arrives and identities merge...
    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-server',
      url: 'https://example.com/feed.xml',
      title: 'Server',
    ));
    await db.feedDao.mergeFeedIdentity('feed-local', 'feed-server');

    // ...and only THEN are server article pages pulled. The moved local
    // row still carries its local id; the server row for the same item
    // has a different one.
    await db.articleDao.upsertServerArticles([
      Article(
        id: 'server-article',
        feedId: 'feed-server',
        guid: 'g1',
        title: 'Server title',
        url: 'https://example.com/1',
      ),
    ]);

    final articles = await db.getArticlesByFeed('feed-server');
    expect(articles, hasLength(1), reason: 'one item, one row');
    final row = articles.first;
    expect(row.id, 'server-article',
        reason: 'the canonical server id wins');
    expect(row.title, 'Server title');
    expect(row.isRead, isTrue, reason: 'rekeying preserves local read state');
    expect(row.isStarred, isTrue,
        reason: 'rekeying preserves local starred state');
    expect(row.fullContent, 'cached extraction',
        reason: 'the local full-content cache survives the rekey');

    // Pulling the same page again changes nothing.
    await db.articleDao.upsertServerArticles([
      Article(
        id: 'server-article',
        feedId: 'feed-server',
        guid: 'g1',
        title: 'Server title',
        url: 'https://example.com/1',
      ),
    ]);
    expect(await db.getArticlesByFeed('feed-server'), hasLength(1),
        reason: 'server pulls are idempotent');
  });

  test('R4-03: a server article id belonging to another feed is rejected '
      'without partial writes', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-a',
      url: 'https://example.com/a.xml',
      title: 'A',
    ));
    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-b',
      url: 'https://example.com/b.xml',
      title: 'B',
    ));
    await db.articleDao.insertArticles([
      Article(
        id: 'taken',
        feedId: 'feed-b',
        guid: 'other',
        title: 'B article',
        url: 'https://example.com/b/1',
      ),
    ]);

    await expectLater(
      db.articleDao.upsertServerArticles([
        Article(
          id: 'taken', // already used by feed-b
          feedId: 'feed-a',
          guid: 'fresh-guid',
          title: 'A article',
          url: 'https://example.com/a/1',
        ),
      ]),
      throwsA(isA<StateError>()),
    );

    expect(await db.getArticlesByFeed('feed-a'), isEmpty,
        reason: 'the transaction must roll back');
    expect((await db.getArticlesByFeed('feed-b')).first.id, 'taken',
        reason: 'the pre-existing row is untouched');
  });

  test('R4-03: server rows carry a real guid distinct from the url',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));

    // A client that previously stored the URL-fallback guid and now
    // receives the real publisher guid keeps ONE row keyed by the real
    // guid once the server id lands.
    await db.articleDao.upsertServerArticles([
      Article(
        id: 'server-1',
        feedId: 'feed-1',
        guid: 'https://example.com/1', // legacy URL fallback
        title: 'One',
        url: 'https://example.com/1',
      ),
    ]);
    await db.articleDao.upsertServerArticles([
      Article(
        id: 'server-1',
        feedId: 'feed-1',
        guid: 'urn:uuid:real-guid',
        title: 'One',
        url: 'https://example.com/1',
      ),
    ]);

    final rows = await db.getArticlesByFeed('feed-1');
    expect(rows, hasLength(1),
        reason: 'the same server id maps to one row; the guid is '
            'corrected in place');
    expect(rows.first.guid, 'urn:uuid:real-guid');
  });

  test('R4-03: mergeFeedIdentity invalidates article streams', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-local',
      url: 'https://example.com/feed.xml',
      title: 'Local',
    ));
    await db.articleDao.insertArticles([
      Article(
        feedId: 'feed-local',
        guid: 'g1',
        title: 'T',
        url: 'https://example.com/1',
      ),
    ]);

    final emitted = <List<Article>>[];
    final sub = db.articleDao.watchAllArticles().listen(emitted.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);
    emitted.clear();

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-server',
      url: 'https://example.com/feed.xml',
      title: 'Server',
    ));
    await db.feedDao.mergeFeedIdentity('feed-local', 'feed-server');
    await Future<void>.delayed(Duration.zero);

    expect(emitted, isNotEmpty,
        reason: 'raw article UPDATE/DELETE must declare table updates so '
            'article-only watchers see the re-keyed rows');
    expect(emitted.last.first.feedId, 'feed-server');
  });

  test('R4-10: a refresh without enclosure data keeps stored enclosures',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));
    await db.articleDao.insertArticles([
      Article(
        feedId: 'feed-1',
        guid: 'g1',
        title: 'With media',
        url: 'https://example.com/1',
        enclosures: [
          const Enclosure(
            url: 'https://example.com/audio.mp3',
            type: 'audio/mpeg',
          ),
        ],
      ),
    ]);

    // The active refresh parser does not carry enclosures at all.
    await db.articleDao.upsertPublisherArticles([
      Article(
        feedId: 'feed-1',
        guid: 'g1',
        title: 'With media, refreshed',
        url: 'https://example.com/1',
        publishedAt: DateTime(2026, 10, 1),
        enclosures: null,
      ),
    ]);

    final row = (await db.getArticlesByFeed('feed-1')).first;
    expect(row.title, 'With media, refreshed');
    expect(row.enclosures, isNotNull,
        reason: 'a parser that never read enclosures must not erase them');
    expect(row.enclosures!.first.url, 'https://example.com/audio.mp3');
  });

  test('R4-11: refreshing an undated article keeps its stored date',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));
    final firstSeen = DateTime(2026, 9, 1);
    await db.articleDao.insertArticles([
      Article(
        feedId: 'feed-1',
        guid: 'g1',
        title: 'Undated',
        url: 'https://example.com/1',
        publishedAt: firstSeen,
        createdAt: firstSeen,
      ),
    ]);

    // A later refresh where the publisher still supplies no date must
    // not move the publication date to "now".
    await db.articleDao.upsertPublisherArticles([
      Article(
        feedId: 'feed-1',
        guid: 'g1',
        title: 'Undated',
        url: 'https://example.com/1',
        publishedAt: null,
      ),
    ]);

    final row = (await db.getArticlesByFeed('feed-1')).first;
    expect(row.publishedAt, firstSeen);

    // A real publisher date still overwrites.
    await db.articleDao.upsertPublisherArticles([
      Article(
        feedId: 'feed-1',
        guid: 'g1',
        title: 'Undated',
        url: 'https://example.com/1',
        publishedAt: DateTime(2026, 10, 5, 12),
      ),
    ]);
    expect((await db.getArticlesByFeed('feed-1')).first.publishedAt,
        DateTime(2026, 10, 5, 12));
  });

  test('R4-12: an incomplete backup envelope is rejected, not imported as '
      'empty tables', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));

    final full = Map<String, dynamic>.from(await db.exportToJson());
    for (final missing in ['feeds', 'articles', 'folders', 'syncMetadata']) {
      final truncated = Map<String, dynamic>.from(full)..remove(missing);
      await expectLater(
        db.importFromJson(truncated),
        throwsArgumentError,
        reason: 'a missing "$missing" key must not read as an empty table',
      );
    }

    expect(await db.getAllFeeds(), hasLength(1),
        reason: 'the existing database survives every rejected import');
  });

  test('R4-13: export reads one consistent snapshot', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));
    await db.articleDao.insertArticles([
      Article(
        feedId: 'feed-1',
        guid: 'g1',
        title: 'One',
        url: 'https://example.com/1',
      ),
    ]);

    final export = await db.exportToJson();
    expect(export['feeds'], hasLength(1));
    expect(export['articles'], hasLength(1));
    // Every exported article's feed id resolves inside the same export:
    // the tables were read inside one transaction, so a concurrent
    // re-key can never split the snapshot.
    final feedIds =
        (export['feeds'] as List).map((f) => (f as Map)['id']).toSet();
    for (final article in export['articles'] as List) {
      expect(feedIds, contains((article as Map)['feedId']));
    }
  });
}
