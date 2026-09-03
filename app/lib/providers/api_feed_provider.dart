import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../core/models/feed.dart';
import '../core/models/article.dart';
import '../core/models/folder.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../core/database/database.dart';

/// Remote feeds provider - fetches from API and syncs with local DB
final apiFeedsProvider = FutureProvider<List<Feed>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  final authState = ref.watch(authProvider);
  
  if (!authState.isAuthenticated) {
    return [];
  }
  
  try {
    // Fetch feeds from API
    final feeds = await apiService.getFeeds();
    
    // Sync with local database
    for (final feed in feeds) {
      await database.feedDao.insertOrUpdateFeed(feed);
    }
    
    return feeds;
  } catch (e) {
    // Fall back to local data if API fails
    return await database.feedDao.getAllFeeds();
  }
});

/// Remote articles provider - fetches from API and syncs with local DB
final apiArticlesProvider = FutureProvider.family<List<Article>, ArticleQuery>((ref, query) async {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  final authState = ref.watch(authProvider);
  
  if (!authState.isAuthenticated) {
    return [];
  }
  
  try {
    // Fetch articles from API
    final articles = await apiService.getArticles(
      feedId: query.feedId,
      folderId: query.folderId,
      unreadOnly: query.unreadOnly,
      limit: query.limit,
      offset: query.offset,
      search: query.search,
    );
    
    // Sync with local database
    for (final article in articles) {
      await database.articleDao.insertOrUpdateArticle(article);
    }
    
    return articles;
  } catch (e) {
    // Fall back to local data if API fails
    if (query.feedId != null) {
      return await database.articleDao.getArticlesByFeed(query.feedId!);
    } else if (query.unreadOnly == true) {
      return await database.articleDao.getUnreadArticles();
    } else {
      return await database.articleDao.getAllArticles();
    }
  }
});

/// Article query parameters
class ArticleQuery {
  final int? feedId;
  final int? folderId;
  final bool? unreadOnly;
  final bool? starredOnly;
  final int? limit;
  final int? offset;
  final String? search;
  
  ArticleQuery({
    this.feedId,
    this.folderId,
    this.unreadOnly,
    this.starredOnly,
    this.limit,
    this.offset,
    this.search,
  });
}

/// Subscribe to feed through API
final subscribeFeedProvider = FutureProvider.family<Feed, String>((ref, url) async {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  
  // Subscribe through API
  final feed = await apiService.createFeed(url);
  
  // Save to local database
  await database.feedDao.insertOrUpdateFeed(feed);
  
  // Trigger refresh to get articles
  ref.invalidate(apiFeedsProvider);
  
  return feed;
});

/// Unsubscribe from feed through API
final unsubscribeFeedProvider = FutureProvider.family<void, int>((ref, feedId) async {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  
  // Delete through API
  await apiService.deleteFeed(feedId);
  
  // Remove from local database
  await database.feedDao.deleteFeed(feedId.toString());
  
  // Trigger refresh
  ref.invalidate(apiFeedsProvider);
});

/// Refresh single feed through API
final refreshFeedProvider = FutureProvider.family<void, int>((ref, feedId) async {
  final apiService = ref.watch(apiServiceProvider);
  
  // Refresh through API
  await apiService.refreshFeed(feedId);
  
  // Trigger articles refresh
  ref.invalidate(apiArticlesProvider(ArticleQuery(feedId: feedId)));
});

/// Mark article as read/unread through API
final markArticleReadProvider = FutureProvider.family<void, MarkReadParams>((ref, params) async {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  
  // Update through API
  await apiService.markArticleRead(params.articleId, params.isRead);
  
  // Update local database
  if (params.isRead) {
    await database.articleDao.markAsRead(params.articleId.toString());
  } else {
    await database.articleDao.markAsUnread(params.articleId.toString());
  }
});

class MarkReadParams {
  final int articleId;
  final bool isRead;
  
  MarkReadParams({required this.articleId, required this.isRead});
}

/// Mark article as saved/unsaved through API
final markArticleSavedProvider = FutureProvider.family<void, MarkSavedParams>((ref, params) async {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  
  // Update through API
  await apiService.markArticleSaved(params.articleId, params.isSaved);
  
  // Update local database
  await database.articleDao.setStarred(params.articleId.toString(), params.isSaved);
});

class MarkSavedParams {
  final int articleId;
  final bool isSaved;
  
  MarkSavedParams({required this.articleId, required this.isSaved});
}

/// Mark all articles as read through API
final markAllReadProvider = FutureProvider.family<void, MarkAllReadParams>((ref, params) async {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  
  // Update through API
  await apiService.markAllRead(feedId: params.feedId, folderId: params.folderId);
  
  // Update local database
  if (params.feedId != null) {
    await database.articleDao.markFeedAsRead(params.feedId.toString());
  } else {
    await database.articleDao.markAllAsRead();
  }
  
  // Trigger refresh
  ref.invalidate(apiArticlesProvider(ArticleQuery(
    feedId: params.feedId,
    folderId: params.folderId,
  )));
});

class MarkAllReadParams {
  final int? feedId;
  final int? folderId;
  
  MarkAllReadParams({this.feedId, this.folderId});
}

/// Folders provider through API
final apiFoldersProvider = FutureProvider<List<Folder>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  final authState = ref.watch(authProvider);
  
  if (!authState.isAuthenticated) {
    return [];
  }
  
  try {
    // Fetch folders from API
    final folders = await apiService.getFolders();
    
    // Sync with local database
    for (final folder in folders) {
      await database.folderDao.insertOrUpdateFolder(folder);
    }
    
    return folders;
  } catch (e) {
    // Fall back to local data if API fails
    return await database.folderDao.getAllFolders();
  }
});

/// Create folder through API
final createFolderProvider = FutureProvider.family<Folder, String>((ref, name) async {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  
  // Create through API
  final folder = await apiService.createFolder(name);
  
  // Save to local database
  await database.folderDao.insertOrUpdateFolder(folder);
  
  // Trigger refresh
  ref.invalidate(apiFoldersProvider);
  
  return folder;
});

/// Combined provider that uses API when online and local DB when offline
final feedsProvider = StreamProvider<List<Feed>>((ref) {
  final database = ref.watch(databaseProvider);
  final authState = ref.watch(authProvider);
  
  // Trigger API sync when authenticated
  if (authState.isAuthenticated) {
    ref.watch(apiFeedsProvider);
  }
  
  // Always return local data for instant UI updates
  return database.feedDao.watchAllFeeds();
});

/// Combined articles provider
final articlesProvider = StreamProvider.family<List<Article>, ArticleQuery>((ref, query) {
  final database = ref.watch(databaseProvider);
  final authState = ref.watch(authProvider);
  
  // Trigger API sync when authenticated
  if (authState.isAuthenticated) {
    ref.watch(apiArticlesProvider(query));
  }
  
  // Return local data based on query
  if (query.feedId != null) {
    return database.articleDao.watchArticlesByFeed(query.feedId.toString());
  } else if (query.unreadOnly == true) {
    return database.articleDao.watchUnreadArticles();
  } else if (query.starredOnly == true) {
    return database.articleDao.watchStarredArticles();
  } else if (query.search != null) {
    return database.articleDao.searchArticles(query.search!);
  } else {
    return database.articleDao.watchAllArticles();
  }
});

/// Selected feed provider
final selectedFeedProvider = StateProvider<String?>((ref) => null);

/// Show starred articles provider
final showStarredProvider = StateProvider<bool>((ref) => false);