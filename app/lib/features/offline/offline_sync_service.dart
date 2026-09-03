import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/article.dart';
import '../../providers/feed_provider.dart';
import '../../providers/offline_provider.dart';
import 'offline_storage.dart';

class OfflineSyncService {
  final Ref ref;
  
  OfflineSyncService(this.ref);
  
  Future<void> syncOfflineArticles() async {
    final settings = ref.read(offlineSettingsProvider);
    final storage = ref.read(offlineStorageProvider);
    final syncStatus = ref.read(offlineSyncStatusProvider.notifier);
    
    try {
      syncStatus.startSync(0);
      
      // Get articles to sync
      List<Article> articlesToSync = [];
      
      if (settings.autoDownloadStarred) {
        // Get starred articles
        final starredArticles = await _getStarredArticles();
        articlesToSync.addAll(starredArticles);
      }
      
      if (settings.autoDownloadUnread) {
        // Get unread articles
        final unreadArticles = await _getUnreadArticles();
        articlesToSync.addAll(unreadArticles);
      }
      
      // Remove duplicates
      final uniqueArticles = articlesToSync.toSet().toList();
      
      // Check storage limits
      final currentStats = await storage.getOfflineStatistics();
      final currentArticleCount = currentStats.articleCount;
      
      // Filter articles based on max limit
      final articlesToDownload = uniqueArticles
          .where((article) => currentArticleCount < settings.maxOfflineArticles)
          .take(settings.maxOfflineArticles - currentArticleCount)
          .toList();
      
      if (articlesToDownload.isEmpty) {
        syncStatus.completeSync();
        return;
      }
      
      syncStatus.startSync(articlesToDownload.length);
      
      // Download articles
      int downloaded = 0;
      for (final article in articlesToDownload) {
        try {
          // Check if already offline
          final isOffline = await storage.isArticleOffline(article.id);
          if (!isOffline) {
            await storage.saveArticleOffline(article);
          }
          downloaded++;
          syncStatus.updateProgress(downloaded);
          
          // Check storage size limit
          final stats = await storage.getOfflineStatistics();
          if (stats.storageSize > settings.maxStorageSizeMB * 1024 * 1024) {
            break;
          }
        } catch (e) {
          // Continue with next article
        }
      }
      
      syncStatus.completeSync();
      
      // Refresh offline articles list
      ref.invalidate(offlineArticlesProvider);
      ref.invalidate(offlineStatisticsProvider);
      
    } catch (e) {
      syncStatus.setError(e.toString());
    }
  }
  
  Future<List<Article>> _getStarredArticles() async {
    try {
      // Get all articles from feeds
      final articles = <Article>[];
      final feeds = await ref.read(feedsProvider.future);
      
      for (final feed in feeds) {
        final feedArticles = await ref.read(articlesProvider(feed.id).future);
        articles.addAll(feedArticles.where((article) => article.isStarred));
      }
      
      return articles;
    } catch (e) {
      return [];
    }
  }
  
  Future<List<Article>> _getUnreadArticles() async {
    try {
      // Get all articles from feeds
      final articles = <Article>[];
      final feeds = await ref.read(feedsProvider.future);
      
      for (final feed in feeds) {
        final feedArticles = await ref.read(articlesProvider(feed.id).future);
        articles.addAll(feedArticles.where((article) => !article.isRead));
      }
      
      // Sort by published date and take recent ones
      articles.sort((a, b) => (b.publishedAt ?? DateTime.now())
          .compareTo(a.publishedAt ?? DateTime.now()));
      
      return articles.take(50).toList(); // Limit to 50 most recent unread
    } catch (e) {
      return [];
    }
  }
  
  Future<void> cleanupOldOfflineArticles() async {
    try {
      final storage = ref.read(offlineStorageProvider);
      final settings = ref.read(offlineSettingsProvider);
      
      // Get all offline articles
      final offlineArticles = await storage.getAllOfflineArticles();
      
      // Sort by download date (oldest first)
      offlineArticles.sort((a, b) {
        final aDate = a.metadata?['downloadedAt'] != null
            ? DateTime.parse(a.metadata!['downloadedAt'])
            : DateTime.now();
        final bDate = b.metadata?['downloadedAt'] != null
            ? DateTime.parse(b.metadata!['downloadedAt'])
            : DateTime.now();
        return aDate.compareTo(bDate);
      });
      
      // Remove oldest articles if over limit
      if (offlineArticles.length > settings.maxOfflineArticles) {
        final toRemove = offlineArticles.length - settings.maxOfflineArticles;
        for (int i = 0; i < toRemove; i++) {
          await storage.deleteOfflineArticle(offlineArticles[i].id);
        }
      }
      
      // Check storage size
      final stats = await storage.getOfflineStatistics();
      if (stats.storageSize > settings.maxStorageSizeMB * 1024 * 1024) {
        // Remove articles until under limit
        for (final article in offlineArticles) {
          await storage.deleteOfflineArticle(article.id);
          final newStats = await storage.getOfflineStatistics();
          if (newStats.storageSize <= settings.maxStorageSizeMB * 1024 * 1024) {
            break;
          }
        }
      }
      
      // Refresh offline articles list
      ref.invalidate(offlineArticlesProvider);
      ref.invalidate(offlineStatisticsProvider);
      
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}

// Offline sync service provider
final offlineSyncServiceProvider = Provider<OfflineSyncService>((ref) {
  return OfflineSyncService(ref);
});