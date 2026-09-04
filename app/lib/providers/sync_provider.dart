import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../core/database/database.dart';
import '../core/models/feed.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'feed_provider.dart';

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

  /// Pull server feeds, folders and articles into drift. Local feeds
  /// that only exist locally are pushed to the server so app, extension
  /// and server converge on the same feed set.
  Future<void> syncFromServer() async {
    if (!_connected || state.isSyncing) return;

    state = state.copyWith(isSyncing: true, lastError: null);
    try {
      final serverFeeds = await _api.getFeeds();
      final localFeeds = await _db.feedDao.getAllFeeds();
      final serverUrls = serverFeeds.map((f) => f.url).toSet();

      for (final serverFeed in serverFeeds) {
        for (final localFeed
            in localFeeds.where((f) => f.url == serverFeed.url && f.id != serverFeed.id)) {
          await _db.feedDao.deleteFeed(localFeed.id);
        }
        await _db.feedDao.insertOrUpdateFeed(serverFeed);
      }

      for (final localFeed
          in localFeeds.where((f) => !serverUrls.contains(f.url))) {
        try {
          final created = await _api.createFeed(localFeed.url);
          await _db.feedDao.deleteFeed(localFeed.id);
          await _db.feedDao.insertOrUpdateFeed(created);
        } catch (_) {
          // Server refused the feed; keep the local row
        }
      }

      try {
        final folders = await _api.getFolders();
        for (final folder in folders) {
          await _db.folderDao.insertFolder(folder);
        }
      } catch (_) {
        // Folders are optional
      }

      final articles = await _api.getArticles(limit: 100);
      await _db.articleDao.insertArticles(articles);

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

    for (final feed in due) {
      if (_connected) {
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
      await _db.feedDao.setLastFetched(feed.id, DateTime.now());
    } catch (_) {
      // Best-effort; retried on the next tick
    }
  }
}

/// Subscribe to a feed. Goes through the server (so extension and other
/// devices see it) when connected, otherwise falls back to direct local
/// parsing into drift.
final subscribeFeedProvider =
    FutureProvider.family<Feed, String>((ref, url) async {
  final database = ref.watch(databaseProvider);
  final connected =
      ApiConfig.hasServer && ref.read(authProvider).isAuthenticated;

  if (connected) {
    final feed = await ref.read(apiServiceProvider).createFeed(url);
    await database.feedDao.insertOrUpdateFeed(feed);
    unawaited(ref.read(feedSyncProvider.notifier).syncFromServer());
    return feed;
  }

  final feedService = ref.read(feedServiceProvider);
  final feed = await feedService.subscribeFeed(url);
  await database.feedDao.insertFeed(feed);
  final result = await feedService.refreshFeed(feed);
  if (result.newArticles.isNotEmpty) {
    await database.articleDao.insertArticles(result.newArticles);
  }
  return feed;
});
