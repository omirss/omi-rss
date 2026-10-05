import 'dart:async';

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
import 'settings_provider.dart' show sanitizeArticleLimit;

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

  FeedSyncNotifier(this.ref) : super(const FeedSyncState()) {
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
      unawaited(_tick());
    });
  }

  @override
  void dispose() {
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

  /// The articlesPerFeed retention setting.
  Future<int> _perFeedLimit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return sanitizeArticleLimit(prefs.getInt('articlesPerFeed') ?? 50);
    } catch (_) {
      return 50;
    }
  }

  /// Pull server feeds, folders and articles into drift. Local feeds
  /// that only exist locally are pushed to the server so app, extension
  /// and server converge on the same feed set.
  Future<void> syncFromServer() async {
    if (!_connected || state.isSyncing) return;
    if (!await _syncEnabled()) return;

    state = state.copyWith(isSyncing: true, lastError: null);
    try {
      final serverFeeds = await _api.getFeeds();
      final localFeeds = await _db.feedDao.getAllFeeds();
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

      for (final localFeed
          in localFeeds.where((f) => !serverUrls.contains(f.url))) {
        try {
          final created = await _api.createFeed(
            localFeed.url,
            updateInterval: localFeed.updateFrequency.clamp(5, 1440),
          );
          await _db.feedDao.insertOrUpdateFeed(created);
          if (created.id != localFeed.id) {
            await _db.feedDao.mergeFeedIdentity(localFeed.id, created.id);
          }
        } catch (_) {
          // Server refused the feed; keep the local row
        }
      }

      final knownFolders = <String>{};
      try {
        final folders = await _api.getFolders();
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
      // fully converge; retention is applied only afterwards.
      var page = 1;
      while (true) {
        final result = await _api.getArticlePage(page: page, limit: 200);
        if (result.articles.isNotEmpty) {
          await _db.articleDao.insertArticles(result.articles);
        }
        if (page >= result.totalPages) break;
        page++;
      }
      await _db.articleDao.enforcePerFeedLimit(await _perFeedLimit());

      final now = DateTime.now();
      await _db.setLastSyncAt(now);
      state = state.copyWith(isSyncing: false, lastSyncAt: now);
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
    }
  }

  /// Runs every minute: refresh feeds whose updateFrequency (minutes) is
  /// past due since lastFetched. Honors the autoUpdateFeeds setting.
  Future<void> _tick() async {
    bool autoUpdate;
    try {
      final prefs = await SharedPreferences.getInstance();
      autoUpdate = prefs.getBool('autoUpdateFeeds') ?? true;
    } catch (_) {
      autoUpdate = true;
    }
    if (!autoUpdate || state.isSyncing) return;

    final feeds = await _db.feedDao.getAllFeeds();
    final now = DateTime.now();
    final due = feeds.where((feed) {
      if (!feed.isActive) return false;
      final frequency = feed.updateFrequency.clamp(1, 1440);
      return feed.lastFetched == null ||
          now.difference(feed.lastFetched!) >= Duration(minutes: frequency);
    });

    final syncEnabled = await _syncEnabled();
    for (final feed in due) {
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
      await _api.refreshFeed(feed.id);
      final articles = await _api.getArticles(feedId: feed.id, limit: 50);
      await _db.articleDao.insertArticles(articles);
      await _db.articleDao.enforcePerFeedLimit(await _perFeedLimit());
      await _db.feedDao.setLastFetched(feed.id, DateTime.now());
    } catch (_) {
      // Best-effort; retried on the next tick
    }
  }
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

  if (connected) {
    // Send the configured interval so the server stores it; the local
    // row then persists the server value instead of a client-only
    // override a later sync would overwrite.
    final feed = await ref.read(apiServiceProvider).createFeed(
          url,
          updateInterval: defaultInterval.clamp(5, 1440),
        );
    await database.feedDao.insertOrUpdateFeed(feed);
    unawaited(ref.read(feedSyncProvider.notifier).syncFromServer());
    return feed;
  }

  final feedService = ref.read(feedServiceProvider);
  final feed = await feedService.subscribeFeed(url);
  final localFeed = feed.copyWith(updateFrequency: defaultInterval);
  await database.feedDao.insertFeed(localFeed);
  final result = await feedService.refreshFeed(localFeed);
  if (result.upsertArticles.isNotEmpty) {
    await database.articleDao.upsertPublisherArticles(result.upsertArticles);
  }
  return localFeed;
});
