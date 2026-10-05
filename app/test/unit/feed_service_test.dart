import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/database/database.dart';
import 'package:rss_glassmorphism_reader/core/models/article.dart';
import 'package:rss_glassmorphism_reader/core/models/feed.dart';
import 'package:rss_glassmorphism_reader/core/services/feed_service.dart';
import 'package:rss_glassmorphism_reader/services/feed_parser_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future? cancelFuture) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

const _okRss = '''
<rss version="2.0"><channel><title>Feed</title>
<link>https://ok.example/</link>
<item><title>A</title><link>https://ok.example/a</link><guid>a</guid></item>
</channel></rss>
''';

Dio _okDio() {
  return Dio()..httpClientAdapter = _FakeAdapter((options) {
    if (options.uri.host == 'bad.example') {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'unreachable',
      );
    }
    if (options.method == 'HEAD') {
      return ResponseBody.fromString('', 404);
    }
    return ResponseBody.fromString(_okRss, 200);
  });
}

Feed _feed(String id, {String? host}) => Feed(
      id: id,
      url: 'https://${host ?? 'ok.example'}/feed.xml',
      title: 'Feed $id',
    );

void main() {
  test('A19: continueOnError=true processes every feed, progress is exact',
      () async {
    final service = FeedService(
      dio: _okDio(),
      feedParserService:
          FeedParserService(dio: _okDio()),
    );

    final progressCalls = <int>[];
    service.onBatchProgress = (current, total) => progressCalls.add(current);

    final result = await service.batchRefresh(
      [
        _feed('f1', host: 'bad.example'),
        _feed('f2'),
        _feed('f3'),
        _feed('f4'),
      ],
      concurrency: 2,
      continueOnError: true,
    );

    expect(result.totalFeeds, 4);
    expect(result.errors.keys, ['f1']);
    // The failed feed still records a (error-carrying) result; the others
    // succeed.
    expect(result.results.keys, unorderedEquals(['f1', 'f2', 'f3', 'f4']));
    expect(result.successfulFeeds, 3);
    expect(result.failedFeeds, 1);
    expect(progressCalls, hasLength(4),
        reason: 'progress fires exactly once per completed feed');
    expect(progressCalls.last, 4);
  });

  test('A19: continueOnError=false stops launching further work', () async {
    final service = FeedService(
      dio: _okDio(),
      feedParserService:
          FeedParserService(dio: _okDio()),
    );

    final result = await service.batchRefresh(
      [
        _feed('f1', host: 'bad.example'),
        _feed('f2'),
        _feed('f3'),
      ],
      concurrency: 1,
      continueOnError: false,
    );

    expect(result.errors.keys, ['f1']);
    expect(result.results.keys, ['f1'],
        reason: 'no further feeds may start after a failure');
    expect(result.totalFeeds, 3);
  });

  test('A19: invalid concurrency is rejected', () async {
    final service = FeedService(dio: Dio());
    expect(
      () => service.batchRefresh([_feed('f1')], concurrency: 0),
      throwsArgumentError,
    );
  });

  test('A24: articles/day counts only dated articles in the numerator',
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
        guid: 'd1',
        title: 'day1',
        url: 'https://example.com/1',
        publishedAt: DateTime.utc(2026, 10, 1),
      ),
      Article(
        feedId: 'feed-1',
        guid: 'd2',
        title: 'day2',
        url: 'https://example.com/2',
        publishedAt: DateTime.utc(2026, 10, 2),
      ),
      Article(
        feedId: 'feed-1',
        guid: 'd3',
        title: 'day4',
        url: 'https://example.com/3',
        publishedAt: DateTime.utc(2026, 10, 4),
      ),
      Article(
        feedId: 'feed-1',
        guid: 'u1',
        title: 'undated',
        url: 'https://example.com/4',
      ),
      Article(
        feedId: 'feed-1',
        guid: 'u2',
        title: 'undated2',
        url: 'https://example.com/5',
      ),
    ]);

    final service = FeedService(database: db);
    final stats = await service.getFeedStatistics('feed-1');

    expect(stats.totalArticles, 5);
    // 3 dated articles across 4 calendar days (Oct 1..4, inclusive);
    // the 2 undated ones must not inflate the rate.
    expect(stats.articlesPerDay, closeTo(0.75, 0.001));
  });

  test('B07: a refreshFeed() that throws still yields a failed result',
      () async {
    final service = _ThrowingFeedService();

    final result = await service.batchRefresh([_feed('f1')]);

    expect(result.totalFeeds, 1);
    expect(result.failedFeeds, 1);
    expect(result.successfulFeeds, 0);
    expect(result.errors.keys, ['f1']);
    expect(result.results.keys, ['f1'],
        reason: 'thrown failures must appear in the result contract');
    expect(result.results['f1']!.error, isNotNull);
    expect(result.results['f1']!.newArticles, isEmpty);
  });

  test('B08/B09: cleanup caps undated articles without double counting',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);
    await db.feedDao.insertOrUpdateFeed(Feed(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example',
    ));

    final old = DateTime(2020, 1, 1);
    await db.articleDao.insertArticles([
      // Undated, read, ancient: caught by BOTH keepReadFor retention and
      // the per-feed cap; must only be counted once.
      for (var i = 0; i < 5; i++)
        Article(
          feedId: 'feed-1',
          guid: 'old-$i',
          title: 'Old $i',
          url: 'https://example.com/old/$i',
          isRead: true,
          createdAt: old,
        ),
      Article(
        feedId: 'feed-1',
        guid: 'new-0',
        title: 'New 0',
        url: 'https://example.com/new/0',
        publishedAt: DateTime(2026, 10, 4),
      ),
      Article(
        feedId: 'feed-1',
        guid: 'new-1',
        title: 'New 1',
        url: 'https://example.com/new/1',
        publishedAt: DateTime(2026, 10, 3),
      ),
      // Undated and starred: exempt from the cap.
      Article(
        feedId: 'feed-1',
        guid: 'star-0',
        title: 'Starred',
        url: 'https://example.com/star/0',
        isStarred: true,
        createdAt: DateTime(2026, 10, 2),
      ),
    ]);

    final service = FeedService(database: db);
    final deleted = await service.cleanupOldArticles(
      keepReadFor: const Duration(days: 365),
      maxArticlesPerFeed: 3,
    );

    final remaining = await db.getArticlesByFeed('feed-1');
    expect(remaining.map((a) => a.guid),
        unorderedEquals(['new-0', 'new-1', 'star-0']),
        reason: 'undated articles beyond the cap must be deleted');
    expect(deleted, 5,
        reason: 'rows flagged by both retention and cap must not be '
            'double-counted in cleanup metrics');
  });
}

class _ThrowingFeedService extends FeedService {
  _ThrowingFeedService() : super(dio: Dio());

  @override
  Future<RefreshResult> refreshFeed(Feed feed) async {
    throw StateError('refresh exploded');
  }
}
