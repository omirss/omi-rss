import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/database/database.dart';
import 'package:rss_glassmorphism_reader/core/models/article.dart';
import 'package:rss_glassmorphism_reader/core/models/feed.dart';
import 'package:rss_glassmorphism_reader/core/models/folder.dart';

void main() {
  test('watchUnreadCount emits as articles are inserted', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    final emitted = <int>[];
    final sub = db.articleDao.watchUnreadCount().listen(emitted.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(emitted, isNotEmpty, reason: 'initial emission never happened');

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));
    await db.articleDao.insertArticles(List.generate(
      3,
      (i) => Article(
        feedId: 'feed-1',
        guid: 'guid-$i',
        title: 'Article $i',
        url: 'https://example.com/$i',
      ),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(emitted.last, 3, reason: 'count stream did not update after insert');

    final inserted = await db.articleDao.getAllArticles();
    await db.articleDao.markAsRead(inserted.first.id);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(emitted.last, 2);

    await sub.cancel();
  });

  test('watchFolderUnreadCounts maps folder ids to counts', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    // Warm the connection so migrations run before raw customSelect queries.
    await db.articleDao.getAllArticles();

    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));
    await db.articleDao.insertArticles(List.generate(
      2,
      (i) => Article(
        feedId: 'feed-1',
        guid: 'guid-$i',
        title: 'Article $i',
        url: 'https://example.com/$i',
      ),
    ));

    final counts = await db.articleDao.watchFolderUnreadCounts().first;
    expect(counts, isEmpty, reason: 'no folders exist yet');

    await db.folderDao.insertFolder(Folder(id: 'folder-1', name: 'News'));
    await db.folderDao.addFeedToFolder('folder-1', 'feed-1');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final counts2 = await db.articleDao.watchFolderUnreadCounts().first;
    expect(counts2['folder-1'], 2,
        reason: 'folder unread join must match articles.feed_id to folder_feeds.feed_id');
  });
}
