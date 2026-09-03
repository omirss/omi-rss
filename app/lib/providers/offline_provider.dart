import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/article.dart';
import '../features/offline/offline_storage.dart';

// Offline storage instance provider
final offlineStorageProvider = Provider<OfflineStorage>((ref) {
  return OfflineStorage();
});

// Offline articles state provider
final offlineArticlesProvider = StateNotifierProvider<OfflineArticlesNotifier, AsyncValue<List<Article>>>((ref) {
  return OfflineArticlesNotifier(ref);
});

class OfflineArticlesNotifier extends StateNotifier<AsyncValue<List<Article>>> {
  final Ref ref;
  
  OfflineArticlesNotifier(this.ref) : super(const AsyncValue.loading()) {
    loadOfflineArticles();
  }
  
  Future<void> loadOfflineArticles() async {
    state = const AsyncValue.loading();
    try {
      final storage = ref.read(offlineStorageProvider);
      final articles = await storage.getAllOfflineArticles();
      state = AsyncValue.data(articles);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
  
  Future<void> saveArticleOffline(Article article) async {
    try {
      final storage = ref.read(offlineStorageProvider);
      await storage.saveArticleOffline(article);
      await loadOfflineArticles(); // Reload to update UI
    } catch (e) {
      // Handle error
      throw e;
    }
  }
  
  Future<void> deleteOfflineArticle(String articleId) async {
    try {
      final storage = ref.read(offlineStorageProvider);
      await storage.deleteOfflineArticle(articleId);
      await loadOfflineArticles(); // Reload to update UI
    } catch (e) {
      // Handle error
      throw e;
    }
  }
  
  Future<bool> isArticleOffline(String articleId) async {
    final storage = ref.read(offlineStorageProvider);
    return await storage.isArticleOffline(articleId);
  }
}

// Offline statistics provider
final offlineStatisticsProvider = FutureProvider<OfflineStatistics>((ref) async {
  final storage = ref.read(offlineStorageProvider);
  return await storage.getOfflineStatistics();
});

// Offline sync status provider
final offlineSyncStatusProvider = StateNotifierProvider<OfflineSyncStatusNotifier, OfflineSyncStatus>((ref) {
  return OfflineSyncStatusNotifier();
});

enum SyncState {
  idle,
  syncing,
  completed,
  error,
}

class OfflineSyncStatus {
  final SyncState state;
  final int articlesDownloaded;
  final int totalArticles;
  final String? errorMessage;
  
  OfflineSyncStatus({
    this.state = SyncState.idle,
    this.articlesDownloaded = 0,
    this.totalArticles = 0,
    this.errorMessage,
  });
  
  double get progress => totalArticles > 0 ? articlesDownloaded / totalArticles : 0.0;
  
  OfflineSyncStatus copyWith({
    SyncState? state,
    int? articlesDownloaded,
    int? totalArticles,
    String? errorMessage,
  }) {
    return OfflineSyncStatus(
      state: state ?? this.state,
      articlesDownloaded: articlesDownloaded ?? this.articlesDownloaded,
      totalArticles: totalArticles ?? this.totalArticles,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class OfflineSyncStatusNotifier extends StateNotifier<OfflineSyncStatus> {
  OfflineSyncStatusNotifier() : super(OfflineSyncStatus());
  
  void startSync(int totalArticles) {
    state = state.copyWith(
      state: SyncState.syncing,
      articlesDownloaded: 0,
      totalArticles: totalArticles,
      errorMessage: null,
    );
  }
  
  void updateProgress(int articlesDownloaded) {
    state = state.copyWith(articlesDownloaded: articlesDownloaded);
  }
  
  void completeSync() {
    state = state.copyWith(state: SyncState.completed);
  }
  
  void setError(String errorMessage) {
    state = state.copyWith(
      state: SyncState.error,
      errorMessage: errorMessage,
    );
  }
  
  void reset() {
    state = OfflineSyncStatus();
  }
}

// Offline settings provider
final offlineSettingsProvider = StateNotifierProvider<OfflineSettingsNotifier, OfflineSettings>((ref) {
  return OfflineSettingsNotifier();
});

class OfflineSettings {
  final bool autoDownloadStarred;
  final bool autoDownloadUnread;
  final bool downloadImages;
  final int maxOfflineArticles;
  final int maxStorageSizeMB;
  final bool wifiOnly;
  
  OfflineSettings({
    this.autoDownloadStarred = true,
    this.autoDownloadUnread = false,
    this.downloadImages = true,
    this.maxOfflineArticles = 100,
    this.maxStorageSizeMB = 500,
    this.wifiOnly = true,
  });
  
  OfflineSettings copyWith({
    bool? autoDownloadStarred,
    bool? autoDownloadUnread,
    bool? downloadImages,
    int? maxOfflineArticles,
    int? maxStorageSizeMB,
    bool? wifiOnly,
  }) {
    return OfflineSettings(
      autoDownloadStarred: autoDownloadStarred ?? this.autoDownloadStarred,
      autoDownloadUnread: autoDownloadUnread ?? this.autoDownloadUnread,
      downloadImages: downloadImages ?? this.downloadImages,
      maxOfflineArticles: maxOfflineArticles ?? this.maxOfflineArticles,
      maxStorageSizeMB: maxStorageSizeMB ?? this.maxStorageSizeMB,
      wifiOnly: wifiOnly ?? this.wifiOnly,
    );
  }
}

class OfflineSettingsNotifier extends StateNotifier<OfflineSettings> {
  OfflineSettingsNotifier() : super(OfflineSettings());
  
  void toggleAutoDownloadStarred() {
    state = state.copyWith(autoDownloadStarred: !state.autoDownloadStarred);
  }
  
  void toggleAutoDownloadUnread() {
    state = state.copyWith(autoDownloadUnread: !state.autoDownloadUnread);
  }
  
  void toggleDownloadImages() {
    state = state.copyWith(downloadImages: !state.downloadImages);
  }
  
  void setMaxOfflineArticles(int max) {
    state = state.copyWith(maxOfflineArticles: max);
  }
  
  void setMaxStorageSize(int sizeMB) {
    state = state.copyWith(maxStorageSizeMB: sizeMB);
  }
  
  void toggleWifiOnly() {
    state = state.copyWith(wifiOnly: !state.wifiOnly);
  }
}