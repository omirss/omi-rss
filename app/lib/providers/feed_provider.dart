import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/services/feed_service.dart';
import '../core/services/feed_discovery_service.dart';
import '../core/database/database.dart';
import '../core/models/feed.dart';
import '../core/models/article.dart';
import '../core/models/folder.dart';
import 'database_provider.dart';

/// Feed service provider
final feedServiceProvider = Provider<FeedService>((ref) {
  final database = ref.watch(databaseProvider);
  final dio = Dio();
  final discoveryService = FeedDiscoveryService(dio: dio);
  
  return FeedService(
    dio: dio,
    database: database,
    discoveryService: discoveryService,
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

/// Feed subscription notifier
final feedSubscriptionProvider = StateNotifierProvider<FeedSubscriptionNotifier, AsyncValue<void>>((ref) {
  return FeedSubscriptionNotifier(ref);
});

class FeedSubscriptionNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref ref;
  
  FeedSubscriptionNotifier(this.ref) : super(const AsyncValue.data(null));
  
  Future<Feed> subscribeFeed(String url) async {
    state = const AsyncValue.loading();
    
    try {
      final feedService = ref.read(feedServiceProvider);
      final database = ref.read(databaseProvider);
      
      // Subscribe to feed
      final feed = await feedService.subscribeFeed(url);
      
      // Save to database
      await database.feedDao.insertFeed(feed);
      
      // Fetch initial articles
      final result = await feedService.refreshFeed(feed);
      
      // Save articles
      if (result.newArticles.isNotEmpty) {
        await database.articleDao.insertArticles(result.newArticles);
      }
      
      state = const AsyncValue.data(null);
      return feed;
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
  
  Future<void> unsubscribeFeed(String feedId) async {
    state = const AsyncValue.loading();
    
    try {
      final database = ref.read(databaseProvider);
      
      // Delete feed and all its articles
      await database.feedDao.deleteFeed(feedId);
      
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}

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
  
  FeedRefreshNotifier(this.ref) : super(const AsyncValue.data(RefreshProgress(
    current: 0,
    total: 0,
    isComplete: true,
  )));
  
  Future<void> refreshAllFeeds() async {
    final feedService = ref.read(feedServiceProvider);
    final database = ref.read(databaseProvider);
    
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

/// Feed discovery provider
final feedDiscoveryProvider = FutureProvider.family<List<DiscoveredFeed>, String>((ref, url) async {
  final feedService = ref.watch(feedServiceProvider);
  return await feedService.discoverFeeds(url);
});

/// Article actions provider
final articleActionsProvider = Provider<ArticleActions>((ref) {
  return ArticleActions(ref);
});

class ArticleActions {
  final Ref ref;
  
  ArticleActions(this.ref);
  
  Future<void> markAsRead(String articleId) async {
    final database = ref.read(databaseProvider);
    await database.articleDao.markAsRead(articleId);
  }
  
  Future<void> markAsUnread(String articleId) async {
    final database = ref.read(databaseProvider);
    await database.articleDao.markAsUnread(articleId);
  }
  
  Future<void> toggleStarred(String articleId) async {
    final database = ref.read(databaseProvider);
    final article = await database.articleDao.getArticle(articleId);
    if (article != null) {
      await database.articleDao.setStarred(articleId, !article.isStarred);
    }
  }
  
  Future<void> markAllAsRead({String? feedId, String? categoryId}) async {
    final database = ref.read(databaseProvider);
    if (feedId != null) {
      await database.articleDao.markFeedAsRead(feedId);
    } else {
      await database.articleDao.markAllAsRead();
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

/// Create initial sample feeds
final initializeSampleFeedsProvider = FutureProvider<void>((ref) async {
  final database = ref.read(databaseProvider);
  final feedService = ref.read(feedServiceProvider);
  
  // Check if any feeds exist
  final existingFeeds = await database.feedDao.getAllFeeds();
  if (existingFeeds.isNotEmpty) return;
  
  // Sample feed URLs
  final sampleFeeds = [
    'https://news.ycombinator.com/rss',
    'https://feeds.arstechnica.com/arstechnica/index',
    'https://www.theverge.com/rss/index.xml',
    'https://feeds.feedburner.com/TechCrunch/',
    'https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml',
  ];
  
  // Subscribe to each feed
  for (final url in sampleFeeds) {
    try {
      // Subscribe to feed
      final feed = await feedService.subscribeFeed(url);
      
      // Save to database
      await database.feedDao.insertFeed(feed);
      
      // Fetch initial articles
      final result = await feedService.refreshFeed(feed);
      
      // Save articles
      if (result.newArticles.isNotEmpty) {
        await database.articleDao.insertArticles(result.newArticles);
      }
    } catch (e) {
      // Continue with next feed if one fails
      print('Failed to subscribe to $url: $e');
    }
  }
});