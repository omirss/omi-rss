import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../core/database/database.dart';
import '../core/models/feed.dart';
import '../core/models/folder.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'feed_provider.dart';
import 'settings_provider.dart'
    show sanitizeArticleLimit, sanitizeUpdateInterval, persistedArticleLimit;

/// Sync state
class FeedSyncState {
  final bool isSyncing;
  final DateTime? lastSyncAt;
  final String? lastError;

  const FeedSyncState({
    this.isSyncing = false,
    this.lastSyncAt,
    this.lastError,
  });

  FeedSyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncAt,
    String? lastError,
  }) {
    return FeedSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: lastError,
    );
  }
}

/// Records which (server, account) last owned the local reader
/// database, plus the per-account "pending creates": feed URLs that
/// were explicitly created locally while that account was signed in
/// and have not been pushed to its server yet.
///
/// The library is shared storage, so push decisions need provenance:
/// the sync engine only ever uploads URLs in the ACTIVE account's
/// pending-create set. Feeds that arrived from a server sync, and
/// feeds in a legacy database with no recorded provenance, are never
/// uploaded — nothing is deleted, local-only feeds stay readable, and
/// an explicit OPML import on the server remains the migration path
/// for a legacy library.
class LibraryOwner {
  static const String _key = 'libraryOwner';
  static const String _pendingKey = 'libraryPendingFeedCreates';

  static String ownerKey(String normalizedServerRoot, String userId) =>
      '$normalizedServerRoot\u0000$userId';

  static Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }

  /// Record which account owns the local database. An unassigned
  /// database only adopts an owner while it is still empty; a database
  /// already assigned keeps its owner. A legacy (non-empty, unassigned)
  /// or foreign-owned library is never silently re-bound to whichever
  /// account syncs next.
  static Future<void> recordIfAssignable(
    String normalizedServerRoot,
    String userId, {
    required bool databaseIsEmpty,
  }) async {
    final key = ownerKey(normalizedServerRoot, userId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getString(_key);
      if (current == key) return;
      if (current != null || !databaseIsEmpty) return;
      await prefs.setString(_key, key);
    } catch (_) {
      // Recording provenance is best-effort; a failure only means the
      // gate re-evaluates on the next sync.
    }
  }

  static Future<Map<String, List<String>>> _readPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is List)
            entry.key as String: List<String>.from(entry.value),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writePending(Map<String, List<String>> pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingKey, jsonEncode(pending));
    } catch (_) {
      // Best-effort: a lost record only delays the push to a later sync.
    }
  }

  /// Feed URLs created locally under [owner] and not yet pushed.
  static Future<Set<String>> pendingCreates(String owner) async {
    return (await _readPending())[owner]?.toSet() ?? <String>{};
  }

  /// Remember that [url] was created locally while [owner] was the
  /// active account, so a later sync of THAT account may push it.
  static Future<void> addPendingCreate(String owner, String url) async {
    if (url.isEmpty) return;
    final pending = await _readPending();
    final urls = pending.putIfAbsent(owner, () => <String>[]);
    if (!urls.contains(url)) {
      urls.add(url);
      await _writePending(pending);
    }
  }

  /// Drop a pending create once its feed exists on the owner's server.
  static Future<void> resolvePendingCreate(String owner, String url) async {
    final pending = await _readPending();
    final urls = pending[owner];
    if (urls == null) return;
    final remaining = urls.where((u) => u != url).toList();
    if (remaining.length == urls.length) return;
    if (remaining.isEmpty) {
      pending.remove(owner);
    } else {
      pending[owner] = remaining;
    }
    await _writePending(pending);
  }
}

/// The (server, account) key for the currently signed-in user, or null
/// when no account is active (local mode / signed out). Feeds created
/// while null are unassigned and never pushed automatically.
Future<String?> activeLibraryOwner(Ref ref) async {
  if (!ApiConfig.hasServer) return null;
  final user = ref.read(authProvider).user;
  if (user == null) return null;
  return LibraryOwner.ownerKey(ApiConfig.baseUrl, user.id);
}

/// Sync engine between the server API and the local drift database.
/// The UI reads drift streams (feedsProvider/articlesProvider); this
/// notifier keeps drift populated with server content while authenticated
/// and runs the per-feed refresh schedule while the home shell is alive.
final feedSyncProvider =
    StateNotifierProvider<FeedSyncNotifier, FeedSyncState>((ref) {
  return FeedSyncNotifier(ref);
});

class FeedSyncNotifier extends StateNotifier<FeedSyncState> {
  final Ref ref;
  late final ApiService _api;
  late final AppDatabase _db;
  Timer? _timer;

  /// Server refreshes are QUEUED, not synchronous: after triggering one,
  /// the feed's server-side lastFetchedAt is polled until it advances
  /// (bounded) before articles are pulled, so a queued refresh is no
  /// longer mistaken for a completed one. Injectable for tests.
  final Duration refreshPollInterval;
  final int refreshPollAttempts;

  Future<void>? _syncFlight;
  Future<void>? _tickFlight;
  bool _disposed = false;

  /// Tail of the one top-level operation queue. Full syncs and refresh
  /// batches serialize through it in both directions (a tick waits for
  /// a pull AND a pull waits for a tick), so their database writes can
  /// never interleave. The queued bodies only call internal helpers —
  /// they never re-enter the public entry points — so the linear chain
  /// cannot deadlock.
  Future<void> _opsTail = Future<void>.value();

  Future<void> _serialize(Future<void> Function() body) {
    final previous = _opsTail;
    final done = Completer<void>();
    _opsTail = done.future;
    return Future<void>(() async {
      await previous;
      await body();
    }).whenComplete(done.complete);
  }

  FeedSyncNotifier(
    this.ref, {
    this.refreshPollInterval = const Duration(milliseconds: 500),
    this.refreshPollAttempts = 6,
  }) : super(const FeedSyncState()) {
    _api = ref.read(apiServiceProvider);
    _db = ref.read(databaseProvider);
    ref.listen<AuthState>(
      authProvider,
      (previous, next) {
        if (next.isAuthenticated && !(previous?.isAuthenticated ?? false)) {
          unawaited(syncFromServer());
        }
      },
      fireImmediately: true,
    );
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(tickOnce());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  bool get _connected =>
      ApiConfig.hasServer && ref.read(authProvider).isAuthenticated;

  /// The enableSync setting (persisted by the settings screen). When off,
  /// no server pull/push happens from the sync engine.
  Future<bool> _syncEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('enableSync') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// The articlesPerFeed retention setting. Corrupt persisted values
  /// fall back to the 50 default instead of being clamped: a stored -1
  /// must not become a destructive "keep 1" cap.
  Future<int> _perFeedLimit() => persistedArticleLimit();

  /// Single-flight full sync. Two callers (auth listener, manual
  /// refresh, subscribe) share one run; the flight is registered before
  /// the queued body can start, so synchronous re-entry through a state
  /// listener joins instead of racing past the check. The body itself
  /// runs on the shared operation queue (see [_serialize]).
  Future<void> syncFromServer() {
    if (_disposed || !mounted) return Future<void>.value();
    final existing = _syncFlight;
    if (existing != null) return existing;
    final done = Completer<void>();
    _syncFlight = done.future;
    _serialize(_syncBody).then((_) {
      done.complete();
      if (identical(_syncFlight, done.future)) _syncFlight = null;
    }, onError: (Object error, StackTrace stack) {
      done.completeError(error, stack);
      if (identical(_syncFlight, done.future)) _syncFlight = null;
    });
    return done.future;
  }

  /// One timer tick: refreshes due feeds. Ticks never overlap each
  /// other and share the operation queue with full syncs, so a pull
  /// and a refresh batch cannot interleave database writes.
  Future<void> tickOnce() {
    if (_disposed || !mounted) return Future<void>.value();
    final existing = _tickFlight;
    if (existing != null) return existing;
    final done = Completer<void>();
    _tickFlight = done.future;
    _serialize(() async {
      try {
        await _tickBody();
        done.complete();
      } catch (error) {
        // Timer-driven failures must not escape into the zone.
        if (mounted) {
          state = state.copyWith(lastError: error.toString());
        }
        done.complete();
      }
    });
    return done.future;
  }

  /// Pull server feeds, folders and articles into drift. Local feeds
  /// are pushed to the server only when the active account explicitly
  /// created them locally (pending-create provenance, see
  /// [LibraryOwner]) — never wholesale, so accounts never leak into
  /// each other's subscription sets.
  Future<void> _syncBody() async {
    if (!_connected) return;
    if (!await _syncEnabled()) return;
    if (_disposed || !mounted) return;

    state = state.copyWith(isSyncing: true, lastError: null);
    try {
      final user = ref.read(authProvider).user;
      final owner = user == null
          ? null
          : LibraryOwner.ownerKey(ApiConfig.baseUrl, user.id);
      final feedCount = (await _db.feedDao.getAllFeeds()).length;
      if (_disposed || !mounted) return;

      // Provenance gate (R4-06): only feed URLs the ACTIVE account
      // explicitly created locally (pending creates) may be uploaded.
      // Server-pulled rows and legacy/unassigned libraries never push,
      // so switching accounts or servers cannot leak one account's
      // subscriptions into another's.
      final pendingPushUrls =
          owner == null ? const <String>{} : await LibraryOwner.pendingCreates(owner);
      if (_disposed || !mounted) return;

      final serverFeeds = await _api.getFeeds();
      if (_disposed || !mounted) return;
      final localFeeds = await _db.feedDao.getAllFeeds();
      if (_disposed || !mounted) return;
      final serverUrls = serverFeeds.map((f) => f.url).toSet();

      for (final serverFeed in serverFeeds) {
        // The server row must exist before local data is re-keyed onto
        // its id, so foreign keys hold throughout the merge.
        await _db.feedDao.insertOrUpdateFeed(serverFeed);
        for (final localFeed in localFeeds
            .where((f) => f.url == serverFeed.url && f.id != serverFeed.id)) {
          await _db.feedDao.mergeFeedIdentity(localFeed.id, serverFeed.id);
        }
      }

      if (owner != null) {
        for (final localFeed in localFeeds.where((f) =>
            !serverUrls.contains(f.url) && pendingPushUrls.contains(f.url))) {
          try {
            final created = await _api.createFeed(
              localFeed.url,
              updateInterval: localFeed.updateFrequency.clamp(5, 1440),
            );
            if (_disposed || !mounted) return;
            await _db.feedDao.insertOrUpdateFeed(created);
            if (created.id != localFeed.id) {
              await _db.feedDao.mergeFeedIdentity(localFeed.id, created.id);
            }
            // Pushed: this URL is no longer pending for the account.
            await LibraryOwner.resolvePendingCreate(owner, localFeed.url);
          } catch (_) {
            // Server refused the feed; keep the local row and the
            // pending record for a later retry.
          }
        }
      }

      final knownFolders = <String>{};
      try {
        final folders = await _api.getFolders();
        if (_disposed || !mounted) return;
        // Insert parents before children: folder parent ids are foreign
        // keys, so a child arriving before its parent would be rejected.
        final pending = List<Folder>.from(folders);
        while (pending.isNotEmpty) {
          final ready = pending
              .where((f) => f.parentId == null || knownFolders.contains(f.parentId))
              .toList();
          if (ready.isEmpty) break; // cyclic/dangling parents: skip the rest
          for (final folder in ready) {
            await _db.folderDao.insertFolder(folder);
            knownFolders.add(folder.id);
          }
          pending.removeWhere((f) => knownFolders.contains(f.id));
        }

        // Server folder membership lives on the feed, the local UI
        // reads the join table: reconcile every server feed's
        // membership. Only runs when the folder list was actually
        // fetched, so an unreachable folders endpoint cannot strip
        // existing local memberships.
        for (final serverFeed in serverFeeds) {
          final folderId = serverFeed.folderId != null &&
                  knownFolders.contains(serverFeed.folderId)
              ? serverFeed.folderId
              : null;
          await _db.folderDao
              .replaceFeedFolderMembership(serverFeed.id, folderId);
        }
      } catch (_) {
        // Folders are optional
      }

      // Walk every page so accounts with more than one page of articles
      // fully converge; retention is applied only afterwards. Server
      // rows are reconciled against local identities per row: a local
      // row with the same (feed, guid) but a different id must be
      // rekeyed, not blindly inserted.
      var page = 1;
      while (true) {
        final result = await _api.getArticlePage(page: page, limit: 200);
        if (_disposed || !mounted) return;
        if (result.articles.isNotEmpty) {
          await _db.articleDao.upsertServerArticles(result.articles);
        }
        if (page >= result.totalPages) break;
        page++;
      }
      await _db.articleDao.enforcePerFeedLimit(await _perFeedLimit());

      // Ownership marker (diagnostics / a future explicit binding UI):
      // an empty unassigned database adopts this account; an assigned
      // one keeps its owner; legacy and foreign libraries stay as-is.
      if (owner != null) {
        await LibraryOwner.recordIfAssignable(
          ApiConfig.baseUrl,
          user!.id,
          databaseIsEmpty: feedCount == 0,
        );
      }
      final now = DateTime.now();
      await _db.setLastSyncAt(now);
      if (_disposed || !mounted) return;
      state = state.copyWith(isSyncing: false, lastSyncAt: now);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isSyncing: false, lastError: e.toString());
      }
    }
  }

  /// Runs every minute: refresh feeds whose updateFrequency (minutes) is
  /// past due since lastFetched. Honors the autoUpdateFeeds setting.
  Future<void> _tickBody() async {
    bool autoUpdate;
    try {
      final prefs = await SharedPreferences.getInstance();
      autoUpdate = prefs.getBool('autoUpdateFeeds') ?? true;
    } catch (_) {
      autoUpdate = true;
    }
    if (!autoUpdate || state.isSyncing || _disposed || !mounted) return;

    final feeds = await _db.feedDao.getAllFeeds();
    if (_disposed || !mounted) return;
    final now = DateTime.now();
    final due = feeds.where((feed) {
      if (!feed.isActive) return false;
      final frequency = feed.updateFrequency.clamp(1, 1440);
      return feed.lastFetched == null ||
          now.difference(feed.lastFetched!) >= Duration(minutes: frequency);
    });

    final syncEnabled = await _syncEnabled();
    for (final feed in due) {
      if (_disposed || !mounted) return;
      if (_connected && syncEnabled) {
        await _refreshServerFeed(feed);
      } else {
        await ref
            .read(feedRefreshProvider.notifier)
            .refreshFeed(feed.id);
      }
    }
  }

  Future<void> _refreshServerFeed(Feed feed) async {
    try {
      // Baseline the SERVER-side fetch clock before queueing: the local
      // lastFetched is a client timestamp and cannot be compared against
      // the server's. An unreadable baseline degrades to "any fetch
      // counts as progress".
      DateTime? baseline;
      try {
        baseline = (await _api.getFeed(feed.id)).lastFetched;
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          // The feed does not exist on this server (legacy library, a
          // signed-out creation, or an OPML import the server refused —
          // e.g. host-gated LAN URLs). It is local-only BY DESIGN:
          // fall through to the local publisher refresh so it keeps
          // auto-updating while signed in, instead of the 404 being
          // swallowed on every tick forever.
          await _refreshLocalFeed(feed);
          return;
        }
        // Baseline unknown; proceed with the queued refresh anyway.
      } catch (_) {
        // Baseline unknown; proceed with the queued refresh anyway.
      }
      await _api.refreshFeed(feed.id);
      // POST /feeds/:id/refresh only QUEUES a server-side job. Wait
      // (bounded) for the feed's server-side fetch timestamp to move
      // before treating the refresh as completed.
      await _waitForServerRefresh(feed.id, baseline);
      // Pull every page for this feed, not just the newest slice, so
      // retention converges with the full sync.
      var page = 1;
      while (true) {
        final result =
            await _api.getArticlePage(page: page, limit: 200, feedId: feed.id);
        if (_disposed || !mounted) return;
        if (result.articles.isNotEmpty) {
          await _db.articleDao.upsertServerArticles(result.articles);
        }
        if (page >= result.totalPages) break;
        page++;
      }
      await _db.articleDao.enforcePerFeedLimit(await _perFeedLimit());
      await _db.feedDao.setLastFetched(feed.id, DateTime.now());
    } catch (_) {
      // Best-effort; retried on the next tick
    }
  }

  /// Refresh a local-only feed straight from its publisher — the same
  /// path the tick uses while signed out. Used when the server answers
  /// 404 for a feed (it never adopted it), so feeds the server refuses
  /// still auto-refresh while signed in. The commit persists
  /// lastFetched (even for a failed fetch attempt), matching the
  /// signed-out tick behavior exactly.
  Future<void> _refreshLocalFeed(Feed feed) async {
    await ref.read(feedRefreshProvider.notifier).refreshFeed(feed.id);
  }

  Future<void> _waitForServerRefresh(String feedId, DateTime? baseline) async {
    for (var attempt = 0; attempt < refreshPollAttempts; attempt++) {
      try {
        final fetched = (await _api.getFeed(feedId)).lastFetched;
        if (fetched != null &&
            (baseline == null || fetched.isAfter(baseline))) {
          return;
        }
      } catch (_) {
        // Endpoint trouble must not block the article pull entirely.
        return;
      }
      await Future<void>.delayed(refreshPollInterval);
    }
    // Bounded patience: pull whatever is current now; the next tick
    // will pick up anything the queue job wrote late.
  }

  /// Test hook: run the per-feed server refresh path (poll + paged
  /// pull) for one feed without going through the timer.
  @visibleForTesting
  Future<void> debugRefreshServerFeed(Feed feed) => _refreshServerFeed(feed);
}

/// Subscribe to a feed. Goes through the server (so extension and other
/// devices see it) when connected, otherwise falls back to direct local
/// parsing into drift. New subscriptions default their refresh interval
/// to the updateInterval setting.
final subscribeFeedProvider =
    FutureProvider.family<Feed, String>((ref, url) async {
  final database = ref.watch(databaseProvider);
  final connected =
      ApiConfig.hasServer && ref.read(authProvider).isAuthenticated;

  int defaultInterval = 30;
  try {
    final prefs = await SharedPreferences.getInstance();
    defaultInterval = prefs.getInt('updateInterval') ?? 30;
  } catch (_) {}
  // A corrupt persisted interval must not produce a feed row that
  // violates the update_frequency CHECK constraint.
  final safeInterval = sanitizeUpdateInterval(defaultInterval);

  if (connected) {
    // Send the configured interval so the server stores it; the local
    // row then persists the server value instead of a client-only
    // override a later sync would overwrite.
    final feed = await ref.read(apiServiceProvider).createFeed(
          url,
          updateInterval: safeInterval,
        );
    await database.feedDao.insertOrUpdateFeed(feed);
    unawaited(ref.read(feedSyncProvider.notifier).syncFromServer());
    return feed;
  }

  final feedService = ref.read(feedServiceProvider);
  final feed = await feedService.subscribeFeed(url);
  final localFeed = feed.copyWith(updateFrequency: safeInterval);
  await database.feedDao.insertFeed(localFeed);
  // Provenance: this URL was created locally, so the account that is
  // actively signed in (if any) may push it on a later sync. Signed-out
  // creation stays unassigned and is never uploaded automatically.
  final owner = await activeLibraryOwner(ref);
  if (owner != null) {
    await LibraryOwner.addPendingCreate(owner, url);
  }
  final result = await feedService.refreshFeed(localFeed);
  // Feed row, publisher articles and the retention cap commit together.
  await database.commitPublisherRefresh(
    result.feed.copyWith(updateFrequency: safeInterval),
    result.upsertArticles,
    sanitizeArticleLimit(await persistedArticleLimit()),
  );
  return localFeed;
});
