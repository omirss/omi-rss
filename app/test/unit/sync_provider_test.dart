import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/config/api_config.dart';
import 'package:rss_glassmorphism_reader/core/database/database.dart';
import 'package:rss_glassmorphism_reader/core/models/feed.dart';
import 'package:rss_glassmorphism_reader/core/models/folder.dart';
import 'package:rss_glassmorphism_reader/core/models/user.dart';
import 'package:rss_glassmorphism_reader/providers/auth_provider.dart';
import 'package:rss_glassmorphism_reader/providers/database_provider.dart';
import 'package:rss_glassmorphism_reader/providers/sync_provider.dart';
import 'package:rss_glassmorphism_reader/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _origin = 'http://127.0.0.1:9';

/// Scriptable ApiService for sync tests. Every server interaction the
/// sync engine performs is recorded so tests can assert on the exact
/// behavior (what was pushed, polled, paged).
class _SyncApi extends ApiService {
  _SyncApi(super.ref, {this.userId = 'u1'});

  final String userId;

  /// Feed rows the server "has"; createFeed appends here.
  final List<Feed> serverFeeds = [];

  /// Urls the server accepted via createFeed, in order.
  final List<String> createdFeedUrls = [];

  /// Per-feed GET /feeds/:id answers, consumed left to right.
  final Map<String, List<DateTime?>> pollScript = {};

  int getFeedsCalls = 0;
  int articlePageCalls = 0;
  int refreshFeedCalls = 0;

  @override
  Future<User> getCurrentUser() async =>
      User(id: userId, email: 'a@b.c', username: 'a');

  @override
  Future<List<Feed>> getFeeds() async {
    getFeedsCalls++;
    return List<Feed>.from(serverFeeds);
  }

  @override
  Future<Feed> createFeed(String url,
      {String? folderId, int? updateInterval}) async {
    createdFeedUrls.add(url);
    final feed = Feed(
      id: 'server-${serverFeeds.length + 1}',
      url: url,
      title: 'Server copy of $url',
      updateFrequency: updateInterval ?? 60,
    );
    serverFeeds.add(feed);
    return feed;
  }

  @override
  Future<List<Folder>> getFolders() async => [];

  @override
  Future<ArticlePage> getArticlePage({
    String? feedId,
    String? folderId,
    bool? unreadOnly,
    bool? starredOnly,
    int page = 1,
    int limit = 200,
    String? search,
  }) async {
    articlePageCalls++;
    return ArticlePage(
      articles: const [],
      page: page,
      limit: limit,
      total: 0,
      totalPages: page,
    );
  }

  @override
  Future<void> refreshFeed(String feedId) async {
    refreshFeedCalls++;
  }

  @override
  Future<Feed> getFeed(String feedId) async {
    DateTime? lastFetched;
    final script = pollScript[feedId];
    if (script != null && script.isNotEmpty) {
      lastFetched = script.removeAt(0);
    }
    return Feed(
      id: feedId,
      url: 'https://example.com/$feedId.xml',
      title: feedId,
      lastFetched: lastFetched,
    );
  }
}

/// Boots a container with the fake API and an in-memory database, with
/// an authenticated session. When [db] is passed, its lifetime belongs
/// to the caller (multiple containers can share it).
Future<(ProviderContainer, _SyncApi)> _boot(
  _SyncApi Function(Ref ref) create, {
  AppDatabase? db,
  Map<String, Object> prefs = const {
    'access_token': 'tok',
    'refresh_token': 'ref',
  },
  bool resetPrefs = true,
}) async {
  if (resetPrefs) SharedPreferences.setMockInitialValues(prefs);
  await ApiConfig.setServerUrl(_origin);
  final database = db ?? AppDatabase.testing(NativeDatabase.memory());
  late final _SyncApi api;
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWith((ref) => api = create(ref)),
    databaseProvider.overrideWith((ref) {
      if (db == null) ref.onDispose(database.close);
      return database;
    }),
  ]);
  addTearDown(container.dispose);
  await SharedPreferences.getInstance();
  // Building the provider runs the override, assigning [api]. Let the
  // auth notifier finish restoring the session so the sync engine's
  // _connected check is stable before each test touches it.
  container.read(apiServiceProvider);
  container.read(authProvider.notifier);
  await pumpEventQueue();
  return (container, api);
}

Feed _localFeed(String id, String url) => Feed(
      id: id,
      url: url,
      title: id,
      updateFrequency: 30,
    );

void main() {
  tearDown(() async {
    SharedPreferences.setMockInitialValues(const {});
    await ApiConfig.setServerUrl('');
  });

  test(
      'R4-06: a legacy unassigned library is never pushed to the server '
      'and never silently re-bound', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);
    await db.feedDao.insertOrUpdateFeed(
        _localFeed('legacy-1', 'https://example.com/legacy.xml'));

    final (container, api) = await _boot(_SyncApi.new, db: db);
    final notifier = container.read(feedSyncProvider.notifier);
    await notifier.syncFromServer();

    expect(api.createdFeedUrls, isEmpty,
        reason: 'no recorded provenance: the legacy feed must stay local');
    expect(await LibraryOwner.read(), isNull,
        reason: 'a non-empty unassigned library is not silently bound');
    expect(await db.feedDao.getAllFeeds(), hasLength(1),
        reason: 'nothing is deleted');
  });

  test('R4-06: only the active account\'s pending creates are pushed',
      () async {
    final (container, api) = await _boot(_SyncApi.new);
    final notifier = container.read(feedSyncProvider.notifier);
    await notifier.syncFromServer(); // initial (auto) run settles

    final db = container.read(databaseProvider);
    await db.feedDao.insertOrUpdateFeed(
        _localFeed('mine-1', 'https://example.com/mine.xml'));
    await db.feedDao.insertOrUpdateFeed(
        _localFeed('other-1', 'https://example.com/other.xml'));
    // mine.xml was created locally under account u1; other.xml has no
    // provenance (e.g. it arrived from another account's sync).
    await LibraryOwner.addPendingCreate(
        LibraryOwner.ownerKey(_origin, 'u1'), 'https://example.com/mine.xml');

    await notifier.syncFromServer();

    expect(api.createdFeedUrls, ['https://example.com/mine.xml'],
        reason: 'pushes are limited to the account\'s pending creates');
    expect(
      await LibraryOwner.pendingCreates(
          LibraryOwner.ownerKey(_origin, 'u1')),
      isEmpty,
      reason: 'a successful push resolves the pending record',
    );

    // A later sync pushes nothing new.
    await notifier.syncFromServer();
    expect(api.createdFeedUrls, ['https://example.com/mine.xml']);
  });

  test('R4-06: switching accounts never uploads the previous library',
      () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);

    // Account A owns an empty library and syncs: it gets recorded.
    final (containerA, _) =
        await _boot((ref) => _SyncApi(ref, userId: 'a'), db: db);
    await containerA.read(feedSyncProvider.notifier).syncFromServer();
    expect(await LibraryOwner.read(), LibraryOwner.ownerKey(_origin, 'a'));

    // Account B's server has a feed; B's sync pulls it into the shared
    // library but must neither push anything nor steal ownership.
    final (containerB, apiB) = await _boot(
      (ref) => _SyncApi(ref, userId: 'b')
        ..serverFeeds.add(_localFeed('feed-b', 'https://example.com/b.xml')),
      db: db,
      resetPrefs: false, // keep A's recorded ownership
    );
    await containerB.read(feedSyncProvider.notifier).syncFromServer();

    expect(apiB.createdFeedUrls, isEmpty,
        reason: 'the library is assigned to A; B must not push');
    expect(await LibraryOwner.read(), LibraryOwner.ownerKey(_origin, 'a'),
        reason: 'ownership is not stolen by a foreign account');
    expect(
        (await db.feedDao.getAllFeeds()).map((f) => f.id), ['feed-b'],
        reason: 'B\'s server feed is still pulled for reading');
  });

  test('R4-07: concurrent sync calls share one HTTP round', () async {
    final (container, api) = await _boot(_SyncApi.new);
    final notifier = container.read(feedSyncProvider.notifier);

    final a = notifier.syncFromServer();
    final b = notifier.syncFromServer();
    await Future.wait([a, b]);

    expect(api.getFeedsCalls, 1,
        reason: 'the second caller must join the in-flight sync');
  });

  test('R4-07: a failed sync records the error and the next run proceeds',
      () async {
    var calls = 0;
    final (container, _) = await _boot(
      (ref) => _FailingSyncApi(ref, () => calls++ < 1),
    );
    final notifier = container.read(feedSyncProvider.notifier);

    await notifier.syncFromServer(); // fails internally
    expect(container.read(feedSyncProvider).lastError, isNotNull);

    await notifier.syncFromServer(); // must be able to run again
    expect(calls, 2,
        reason: 'the failed flight must not block the next run');
    expect(container.read(feedSyncProvider).isSyncing, isFalse);
  });

  test('R4-18: a queued server refresh is polled until the server-side '
      'fetch timestamp advances, then pages are pulled', () async {
    final db = AppDatabase.testing(NativeDatabase.memory());
    addTearDown(db.close);
    final feed = _localFeed('feed-1', 'https://example.com/feed.xml');
    await db.feedDao.insertOrUpdateFeed(feed);

    await ApiConfig.setServerUrl(_origin);
    SharedPreferences.setMockInitialValues(
        {'access_token': 'tok', 'refresh_token': 'ref'});
    final database = db;
    late final _SyncApi api;
    final container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWith((ref) => api = _SyncApi(ref)),
      databaseProvider.overrideWith((ref) => database),
      feedSyncProvider.overrideWith((ref) => FeedSyncNotifier(
            ref,
            refreshPollInterval: const Duration(milliseconds: 1),
            refreshPollAttempts: 6,
          )),
    ]);
    addTearDown(container.dispose);
    await SharedPreferences.getInstance();
    container.read(apiServiceProvider); // builds and assigns [api]
    container.read(authProvider.notifier);
    await pumpEventQueue();

    // Poll answers: the baseline read plus two polls still show the
    // old timestamp; the queued job's completion shows up on the third
    // poll.
    final baseline = DateTime(2026, 10, 6, 10);
    api.pollScript['feed-1'] = [
      baseline,
      baseline,
      baseline.add(const Duration(minutes: 1)),
    ];

    await container
        .read(feedSyncProvider.notifier)
        .debugRefreshServerFeed(feed);

    expect(api.refreshFeedCalls, 1);
    expect(api.articlePageCalls, greaterThanOrEqualTo(1),
        reason: 'articles are pulled after the queued refresh completes');
    final refreshed = await db.feedDao.getFeed('feed-1');
    expect(refreshed!.lastFetched, isNotNull,
        reason: 'the local fetch marker advances after the poll loop');
  });
}

/// API whose getFeeds fails on demand.
class _FailingSyncApi extends _SyncApi {
  _FailingSyncApi(super.ref, this.shouldFail);

  final bool Function() shouldFail;

  @override
  Future<List<Feed>> getFeeds() async {
    if (shouldFail()) {
      throw const ApiException('boom', statusCode: 503);
    }
    return super.getFeeds();
  }
}
