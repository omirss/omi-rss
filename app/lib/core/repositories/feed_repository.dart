import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_glassmorphism_reader/core/api/api_client.dart';
import 'package:rss_glassmorphism_reader/core/api/api_models.dart';
import 'package:rss_glassmorphism_reader/core/api/websocket_service.dart';
import 'package:rss_glassmorphism_reader/core/database/app_database.dart';

final feedRepositoryProvider = Provider((ref) => FeedRepository(
  ref.watch(apiClientProvider),
  ref.watch(appDatabaseProvider),
  ref.watch(websocketServiceProvider),
));

class FeedRepository {
  final ApiClient _apiClient;
  final AppDatabase _database;
  final WebSocketService _webSocket;
  
  FeedRepository(this._apiClient, this._database, this._webSocket) {
    _setupWebSocketHandlers();
  }
  
  void _setupWebSocketHandlers() {
    // Handle real-time feed updates
    _webSocket.subscribe(WebSocketEvents.feedAdded, (data) async {
      final feed = Feed.fromJson(data);
      await _saveFeedToLocal(feed);
    });
    
    _webSocket.subscribe(WebSocketEvents.feedUpdated, (data) async {
      final feed = Feed.fromJson(data);
      await _updateFeedInLocal(feed);
    });
    
    _webSocket.subscribe(WebSocketEvents.feedDeleted, (data) async {
      final feedId = data['feedId'] as String;
      await _deleteFeedFromLocal(feedId);
    });
    
    _webSocket.subscribe(WebSocketEvents.feedNewArticles, (data) async {
      final feedId = data['feedId'] as String;
      final articles = (data['articles'] as List)
          .map((json) => Article.fromJson(json))
          .toList();
      await _saveArticlesToLocal(feedId, articles);
    });
  }
  
  // Get all feeds
  Future<List<Feed>> getFeeds({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      // Try to get from local database first
      final localFeeds = await _database.getAllFeeds();
      if (localFeeds.isNotEmpty) {
        return localFeeds;
      }
    }
    
    // Fetch from API
    final response = await _apiClient.getFeeds();
    if (response.isSuccess && response.data != null) {
      // Save to local database
      for (final feed in response.data!) {
        await _saveFeedToLocal(feed);
      }
      return response.data!;
    } else {
      throw Exception(response.error ?? 'Failed to fetch feeds');
    }
  }
  
  // Add a new feed
  Future<Feed> addFeed(String url, {String? categoryId}) async {
    // Validate URL locally first
    if (!_isValidFeedUrl(url)) {
      throw Exception('Invalid feed URL');
    }
    
    // Check if already exists locally
    final existingFeed = await _database.getFeedByUrl(url);
    if (existingFeed != null) {
      throw Exception('Feed already exists');
    }
    
    // Add via API
    final response = await _apiClient.addFeed(url, categoryId: categoryId);
    if (response.isSuccess && response.data != null) {
      // Save to local database
      await _saveFeedToLocal(response.data!);
      
      // Fetch initial articles
      await refreshFeed(response.data!.id);
      
      return response.data!;
    } else {
      throw Exception(response.error ?? 'Failed to add feed');
    }
  }
  
  // Update feed
  Future<Feed> updateFeed(String feedId, {
    String? title,
    String? categoryId,
  }) async {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (categoryId != null) updates['category_id'] = categoryId;
    
    final response = await _apiClient.updateFeed(feedId, updates);
    if (response.isSuccess && response.data != null) {
      await _updateFeedInLocal(response.data!);
      return response.data!;
    } else {
      throw Exception(response.error ?? 'Failed to update feed');
    }
  }
  
  // Delete feed
  Future<void> deleteFeed(String feedId) async {
    final response = await _apiClient.deleteFeed(feedId);
    if (response.isSuccess) {
      await _deleteFeedFromLocal(feedId);
    } else {
      throw Exception(response.error ?? 'Failed to delete feed');
    }
  }
  
  // Refresh feed
  Future<void> refreshFeed(String feedId) async {
    final response = await _apiClient.refreshFeed(feedId);
    if (!response.isSuccess) {
      throw Exception(response.error ?? 'Failed to refresh feed');
    }
    
    // Articles will be received via WebSocket
  }
  
  // Refresh all feeds
  Future<void> refreshAllFeeds() async {
    final feeds = await getFeeds();
    
    // Refresh feeds in parallel with rate limiting
    const batchSize = 5;
    for (int i = 0; i < feeds.length; i += batchSize) {
      final batch = feeds.skip(i).take(batchSize);
      await Future.wait(
        batch.map((feed) => refreshFeed(feed.id)),
        eagerError: false,
      );
      
      // Small delay between batches
      if (i + batchSize < feeds.length) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }
  
  // Get feed by ID
  Future<Feed?> getFeedById(String feedId) async {
    // Try local first
    final localFeed = await _database.getFeedById(feedId);
    if (localFeed != null) {
      return localFeed;
    }
    
    // Fetch from API if not found locally
    final feeds = await getFeeds(forceRefresh: true);
    return feeds.firstWhere(
      (f) => f.id == feedId,
      orElse: () => throw Exception('Feed not found'),
    );
  }
  
  // Search feeds
  Future<List<Feed>> searchFeeds(String query) async {
    return await _database.searchFeeds(query);
  }
  
  // Get feeds by category
  Future<List<Feed>> getFeedsByCategory(String categoryId) async {
    return await _database.getFeedsByCategory(categoryId);
  }
  
  // Local database operations
  Future<void> _saveFeedToLocal(Feed feed) async {
    await _database.insertFeed(feed);
  }
  
  Future<void> _updateFeedInLocal(Feed feed) async {
    await _database.updateFeed(feed);
  }
  
  Future<void> _deleteFeedFromLocal(String feedId) async {
    await _database.deleteFeed(feedId);
  }
  
  Future<void> _saveArticlesToLocal(String feedId, List<Article> articles) async {
    for (final article in articles) {
      await _database.insertArticle(article);
    }
    
    // Update feed's unread count
    final unreadCount = await _database.getUnreadCount(feedId);
    await _database.updateFeedUnreadCount(feedId, unreadCount);
  }
  
  // Validation
  bool _isValidFeedUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.isScheme('http') || uri.isScheme('https');
    } catch (e) {
      return false;
    }
  }
}