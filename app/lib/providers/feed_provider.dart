import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../core/services/feed_service.dart';
import '../core/models/feed.dart';
import '../core/models/article.dart';
import '../core/models/folder.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'sync_provider.dart';

/// Feed service provider
final feedServiceProvider = Provider<FeedService>((ref) {
  final database = ref.watch(databaseProvider);

  return FeedService(
    dio: Dio(),
    database: database,
  );
});

/// All feeds provider
final feedsProvider = StreamProvider<List<Feed>>((ref) {
  final database = ref.watch(databaseProvider);
  return database.feedDao.watchAllFeeds();
});

/// Feed by ID provider
final feedByIdProvider = StreamProvider.family<Feed?, String>((ref, feedId) {
  final database = ref.watch(databaseProvider);
  return database.feedDao.watchFeed(feedId);
});

/// Articles by feed provider
final articlesByFeedProvider = StreamProvider.family<List<Article>, String>((ref, feedId) {
  final database = ref.watch(databaseProvider);
  return database.articleDao.watchArticlesByFeed(feedId);
});

/// All articles provider with filters
final articlesProvider = StreamProvider<List<Article>>((ref) {
  final database = ref.watch(databaseProvider);
  final filter = ref.watch(articleFilterProvider);
  
  switch (filter.type) {
    case ArticleFilterType.all:
      return database.articleDao.watchAllArticles();
    case ArticleFilterType.unread:
      return database.articleDao.watchUnreadArticles();
    case ArticleFilterType.starred:
      return database.articleDao.watchStarredArticles();
    case ArticleFilterType.feed:
      return database.articleDao.watchArticlesByFeed(filter.feedId!);
    case ArticleFilterType.category:
      return database.articleDao.watchArticlesByCategory(filter.categoryId!);
    case ArticleFilterType.folder:
      return database.articleDao.watchArticlesByFolder(filter.folderId!);
    case ArticleFilterType.search:
      return database.articleDao.searchArticles(filter.searchQuery!);
  }
});

/// Article filter provider
final articleFilterProvider = StateNotifierProvider<ArticleFilterNotifier, ArticleFilter>((ref) {
  return ArticleFilterNotifier();
});

/// Article filter types
enum ArticleFilterType {
  all,
  unread,
  starred,
  feed,
  category,
  folder,
  search,
}

/// Article filter state
class ArticleFilter {
  final ArticleFilterType type;
  final String? feedId;
  final String? categoryId;
  final String? folderId;
  final String? searchQuery;
  
  ArticleFilter({
    this.type = ArticleFilterType.all,
    this.feedId,
    this.categoryId,
    this.folderId,
    this.searchQuery,
  });
  
  ArticleFilter copyWith({
    ArticleFilterType? type,
    String? feedId,
    String? categoryId,
    String? folderId,
    String? searchQuery,
  }) {
    return ArticleFilter(
      type: type ?? this.type,
      feedId: feedId ?? this.feedId,
      categoryId: categoryId ?? this.categoryId,
      folderId: folderId ?? this.folderId,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// Article filter notifier
class ArticleFilterNotifier extends StateNotifier<ArticleFilter> {
  ArticleFilterNotifier() : super(ArticleFilter());
  
  void showAll() {
    state = ArticleFilter(type: ArticleFilterType.all);
  }
  
  void showUnread() {
    state = ArticleFilter(type: ArticleFilterType.unread);
  }
  
  void showStarred() {
    state = ArticleFilter(type: ArticleFilterType.starred);
  }
  
  void showFeed(String feedId) {
    state = ArticleFilter(
      type: ArticleFilterType.feed,
      feedId: feedId,
    );
  }
  
  void showCategory(String categoryId) {
    state = ArticleFilter(
      type: ArticleFilterType.category,
      categoryId: categoryId,
    );
  }
  
  void showFolder(String folderId) {
    state = ArticleFilter(
      type: ArticleFilterType.folder,
      folderId: folderId,
    );
  }
  
  void search(String query) {
    state = ArticleFilter(
      type: ArticleFilterType.search,
      searchQuery: query,
    );
  }
}

/// Selected feed provider
final selectedFeedProvider = StateProvider<String?>((ref) => null);

/// Show starred articles provider
final showStarredProvider = StateProvider<bool>((ref) => false);

/// Feed refresh provider
final feedRefreshProvider = StateNotifierProvider<FeedRefreshNotifier, AsyncValue<RefreshProgress>>((ref) {
  return FeedRefreshNotifier(ref);
});

/// Refresh progress
class RefreshProgress {
  final int current;
  final int total;
  final String? currentFeedName;
  final bool isComplete;
  
  RefreshProgress({
    required this.current,
    required this.total,
    this.currentFeedName,
    required this.isComplete,
  });
  
  double get progress => total > 0 ? current / total : 0;
}

class FeedRefreshNotifier extends StateNotifier<AsyncValue<RefreshProgress>> {
  final Ref ref;
  
  FeedRefreshNotifier(this.ref) : super(AsyncValue.data(RefreshProgress(
    current: 0,
    total: 0,
    isComplete: true,
  )));
  
  Future<void> refreshAllFeeds() async {
    final feedService = ref.read(feedServiceProvider);
    final database = ref.read(databaseProvider);

    if (ApiConfig.hasServer && ref.read(authProvider).isAuthenticated) {
      try {
        final feeds = await database.feedDao.getAllFeeds();
        final api = ref.read(apiServiceProvider);
        for (final feed in feeds) {
          try {
            await api.refreshFeed(feed.id);
          } catch (_) {
            // Continue with the other feeds
          }
        }
        await ref.read(feedSyncProvider.notifier).syncFromServer();
        state = AsyncValue.data(RefreshProgress(
          current: feeds.length,
          total: feeds.length,
          isComplete: true,
        ));
      } catch (e, stack) {
        state = AsyncValue.error(e, stack);
      }
      return;
    }

    try {
      // Get all feeds
      final feeds = await database.feedDao.getAllFeeds();
      
      if (feeds.isEmpty) return;
      
      state = AsyncValue.data(RefreshProgress(
        current: 0,
        total: feeds.length,
        isComplete: false,
      ));
      
      // Set up progress callback
      feedService.onBatchProgress = (current, total) {
        state = AsyncValue.data(RefreshProgress(
          current: current,
          total: total,
          currentFeedName: current <= feeds.length ? feeds[current - 1].title : null,
          isComplete: false,
        ));
      };
      
      // Refresh all feeds
      final results = await feedService.batchRefresh(feeds);
      
      // Save updated feeds and articles
      for (final result in results.results.values) {
        // Update feed
        await database.feedDao.updateFeed(result.feed);
        
        // Insert new articles
        if (result.newArticles.isNotEmpty) {
          await database.articleDao.insertArticles(result.newArticles);
        }
      }
      
      state = AsyncValue.data(RefreshProgress(
        current: feeds.length,
        total: feeds.length,
        isComplete: true,
      ));
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
  
  Future<void> refreshFeed(String feedId) async {
    final feedService = ref.read(feedServiceProvider);
    final database = ref.read(databaseProvider);
    
    try {
      // Get feed
      final feed = await database.feedDao.getFeed(feedId);
      if (feed == null) return;
      
      state = AsyncValue.data(RefreshProgress(
        current: 0,
        total: 1,
        currentFeedName: feed.title,
        isComplete: false,
      ));
      
      // Refresh feed
      final result = await feedService.refreshFeed(feed);
      
      // Update feed
      await database.feedDao.updateFeed(result.feed);
      
      // Insert new articles
      if (result.newArticles.isNotEmpty) {
        await database.articleDao.insertArticles(result.newArticles);
      }
      
      state = AsyncValue.data(RefreshProgress(
        current: 1,
        total: 1,
        isComplete: true,
      ));
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

/// Feed statistics provider
final feedStatisticsProvider = FutureProvider.family<FeedStatistics, String>((ref, feedId) async {
  final feedService = ref.watch(feedServiceProvider);
  return await feedService.getFeedStatistics(feedId);
});

/// Folders provider
final foldersProvider = StreamProvider<List<Folder>>((ref) {
  final database = ref.watch(databaseProvider);
  return database.folderDao.watchAllFolders();
});