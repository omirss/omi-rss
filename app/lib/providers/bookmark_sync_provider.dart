import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/bookmarks/bookmark_sync_service.dart';
import '../core/services/api_service.dart';
import '../core/models/article.dart';
import 'auth_provider.dart';

// Bookmark sync service provider
final bookmarkSyncServiceProvider = Provider<BookmarkSyncService>((ref) {
  final apiService = ref.read(apiServiceProvider);
  return BookmarkSyncService(apiService: apiService);
});

// Browser extension service provider
final browserExtensionServiceProvider = Provider<BrowserExtensionService>((ref) {
  return BrowserExtensionService();
});

// Sync status provider
final bookmarkSyncStatusProvider = StateNotifierProvider<BookmarkSyncStatusNotifier, BookmarkSyncStatus>((ref) {
  return BookmarkSyncStatusNotifier(ref);
});

enum SyncState {
  idle,
  syncing,
  completed,
  error,
}

class BookmarkSyncStatus {
  final SyncState state;
  final String? message;
  final int? itemsToSync;
  final int? itemsSynced;
  final DateTime? lastSyncTime;
  final String? error;
  
  BookmarkSyncStatus({
    this.state = SyncState.idle,
    this.message,
    this.itemsToSync,
    this.itemsSynced,
    this.lastSyncTime,
    this.error,
  });
  
  double get progress {
    if (itemsToSync == null || itemsToSync == 0) return 0.0;
    if (itemsSynced == null) return 0.0;
    return itemsSynced! / itemsToSync!;
  }
  
  BookmarkSyncStatus copyWith({
    SyncState? state,
    String? message,
    int? itemsToSync,
    int? itemsSynced,
    DateTime? lastSyncTime,
    String? error,
  }) {
    return BookmarkSyncStatus(
      state: state ?? this.state,
      message: message ?? this.message,
      itemsToSync: itemsToSync ?? this.itemsToSync,
      itemsSynced: itemsSynced ?? this.itemsSynced,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      error: error ?? this.error,
    );
  }
}

class BookmarkSyncStatusNotifier extends StateNotifier<BookmarkSyncStatus> {
  final Ref ref;
  
  BookmarkSyncStatusNotifier(this.ref) : super(BookmarkSyncStatus()) {
    _loadLastSyncTime();
  }
  
  Future<void> _loadLastSyncTime() async {
    final service = ref.read(bookmarkSyncServiceProvider);
    final lastSync = await service.getLastSyncTime();
    state = state.copyWith(lastSyncTime: lastSync);
  }
  
  void startSync(int itemsToSync) {
    state = state.copyWith(
      state: SyncState.syncing,
      message: 'Starting sync...',
      itemsToSync: itemsToSync,
      itemsSynced: 0,
      error: null,
    );
  }
  
  void updateProgress(String message, int itemsSynced) {
    state = state.copyWith(
      message: message,
      itemsSynced: itemsSynced,
    );
  }
  
  void completeSync(DateTime syncTime) {
    state = state.copyWith(
      state: SyncState.completed,
      message: 'Sync completed successfully',
      lastSyncTime: syncTime,
    );
  }
  
  void setError(String error) {
    state = state.copyWith(
      state: SyncState.error,
      error: error,
    );
  }
  
  void reset() {
    state = BookmarkSyncStatus(lastSyncTime: state.lastSyncTime);
  }
}

// Bookmark sync settings provider
final bookmarkSyncSettingsProvider = StateNotifierProvider<BookmarkSyncSettingsNotifier, BookmarkSyncSettings>((ref) {
  return BookmarkSyncSettingsNotifier();
});

class BookmarkSyncSettings {
  final bool autoSync;
  final int syncIntervalMinutes;
  final bool syncOnStartup;
  final bool syncStarredAsBookmarks;
  final bool importBookmarksAsArticles;
  final String defaultBrowser;
  
  BookmarkSyncSettings({
    this.autoSync = false,
    this.syncIntervalMinutes = 30,
    this.syncOnStartup = true,
    this.syncStarredAsBookmarks = true,
    this.importBookmarksAsArticles = true,
    this.defaultBrowser = 'chrome',
  });
  
  BookmarkSyncSettings copyWith({
    bool? autoSync,
    int? syncIntervalMinutes,
    bool? syncOnStartup,
    bool? syncStarredAsBookmarks,
    bool? importBookmarksAsArticles,
    String? defaultBrowser,
  }) {
    return BookmarkSyncSettings(
      autoSync: autoSync ?? this.autoSync,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      syncOnStartup: syncOnStartup ?? this.syncOnStartup,
      syncStarredAsBookmarks: syncStarredAsBookmarks ?? this.syncStarredAsBookmarks,
      importBookmarksAsArticles: importBookmarksAsArticles ?? this.importBookmarksAsArticles,
      defaultBrowser: defaultBrowser ?? this.defaultBrowser,
    );
  }
}

class BookmarkSyncSettingsNotifier extends StateNotifier<BookmarkSyncSettings> {
  BookmarkSyncSettingsNotifier() : super(BookmarkSyncSettings());
  
  void toggleAutoSync() {
    state = state.copyWith(autoSync: !state.autoSync);
  }
  
  void setSyncInterval(int minutes) {
    state = state.copyWith(syncIntervalMinutes: minutes);
  }
  
  void toggleSyncOnStartup() {
    state = state.copyWith(syncOnStartup: !state.syncOnStartup);
  }
  
  void toggleSyncStarredAsBookmarks() {
    state = state.copyWith(syncStarredAsBookmarks: !state.syncStarredAsBookmarks);
  }
  
  void toggleImportBookmarksAsArticles() {
    state = state.copyWith(importBookmarksAsArticles: !state.importBookmarksAsArticles);
  }
  
  void setDefaultBrowser(String browser) {
    state = state.copyWith(defaultBrowser: browser);
  }
}

// Bookmark sync manager
final bookmarkSyncManagerProvider = Provider<BookmarkSyncManager>((ref) {
  return BookmarkSyncManager(ref);
});

class BookmarkSyncManager {
  final Ref ref;
  
  BookmarkSyncManager(this.ref);
  
  Future<void> setupSync(String browser) async {
    final authState = ref.read(authStateProvider);
    if (authState.user == null) {
      throw Exception('User not authenticated');
    }
    
    final service = ref.read(bookmarkSyncServiceProvider);
    await service.generateSyncToken(authState.user!.id, browser);
  }
  
  Future<void> performSync() async {
    final service = ref.read(bookmarkSyncServiceProvider);
    final statusNotifier = ref.read(bookmarkSyncStatusProvider.notifier);
    final settings = ref.read(bookmarkSyncSettingsProvider);
    
    try {
      // Check if token exists
      final token = await service.getSyncToken();
      if (token == null) {
        throw Exception('No sync token. Please setup sync first.');
      }
      
      statusNotifier.startSync(0);
      
      // Get local bookmarks (starred articles if enabled)
      final localBookmarks = <BrowserBookmark>[];
      
      if (settings.syncStarredAsBookmarks) {
        final starredArticles = await _getStarredArticles();
        final bookmarks = starredArticles.map((article) => 
          service.articleToBookmark(article, settings.defaultBrowser)
        ).toList();
        localBookmarks.addAll(bookmarks);
      }
      
      statusNotifier.startSync(localBookmarks.length);
      
      // Perform sync
      final result = await service.syncBookmarks(localBookmarks);
      
      // Process results
      int processed = 0;
      
      // Add new bookmarks as articles if enabled
      if (settings.importBookmarksAsArticles && result.toAdd.isNotEmpty) {
        statusNotifier.updateProgress('Importing new bookmarks...', processed);
        for (final bookmark in result.toAdd) {
          // Convert bookmark to article and save
          final article = bookmark.toArticle();
          // TODO: Save article to database
          processed++;
          statusNotifier.updateProgress('Importing bookmarks...', processed);
        }
      }
      
      // Update existing bookmarks
      if (result.toUpdate.isNotEmpty) {
        statusNotifier.updateProgress('Updating bookmarks...', processed);
        for (final bookmark in result.toUpdate) {
          // Update article if it exists
          processed++;
          statusNotifier.updateProgress('Updating bookmarks...', processed);
        }
      }
      
      // Complete sync
      statusNotifier.completeSync(result.syncTime);
      
    } catch (e) {
      statusNotifier.setError(e.toString());
      rethrow;
    }
  }
  
  Future<List<Article>> _getStarredArticles() async {
    // TODO: Get starred articles from database
    return [];
  }
  
  Future<bool> checkExtensionInstalled() async {
    final extensionService = ref.read(browserExtensionServiceProvider);
    return await extensionService.isExtensionInstalled();
  }
  
  Future<void> installExtension() async {
    final extensionService = ref.read(browserExtensionServiceProvider);
    await extensionService.installExtension();
  }
}