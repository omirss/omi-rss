import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import '../protocol/protocol.dart';
import '../services/feed_service.dart';
import '../services/feed_parser_service.dart';
import '../services/opml_service.dart';

class FeedEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  /// Get all feeds for the current user
  Future<List<Feed>> getFeeds(Session session) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    return await Feed.db.findByUserId(session, userId);
  }

  /// Get a specific feed by ID
  Future<Feed?> getFeed(Session session, int feedId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final feed = await session.db.findById<Feed>(feedId);
    if (feed != null && feed.userId != userId) {
      throw Exception('Unauthorized access to feed');
    }

    return feed;
  }

  /// Add a new feed
  Future<Feed> addFeed(Session session, String url, {int? folderId}) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Check if feed already exists for user
    final existingFeed = await Feed.db.findByUserIdAndUrl(session, userId, url);
    if (existingFeed != null) {
      throw Exception('Feed already exists');
    }

    // Parse feed to get metadata
    final parser = FeedParserService();
    final feedData = await parser.parseFeed(url);

    // Create feed
    final feed = Feed(
      title: feedData.title ?? 'Untitled Feed',
      url: url,
      description: feedData.description,
      imageUrl: feedData.imageUrl,
      favicon: await parser.extractFavicon(url),
      folderId: folderId,
      userId: userId,
      isEnabled: true,
    );

    // Save to database
    final savedFeed = await session.db.insertRow<Feed>(feed);

    // Fetch initial articles
    final feedService = session.serverpod.getSingleton<FeedService>();
    await feedService.fetchFeedArticles(session, savedFeed.id!);

    return savedFeed;
  }

  /// Update a feed
  Future<Feed> updateFeed(Session session, Feed feed) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final existingFeed = await session.db.findById<Feed>(feed.id!);
    if (existingFeed == null || existingFeed.userId != userId) {
      throw Exception('Unauthorized access to feed');
    }

    feed.userId = userId;
    feed.updatedAt = DateTime.now();

    return await session.db.updateRow<Feed>(feed);
  }

  /// Delete a feed
  Future<void> deleteFeed(Session session, int feedId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final feed = await session.db.findById<Feed>(feedId);
    if (feed == null || feed.userId != userId) {
      throw Exception('Unauthorized access to feed');
    }

    // Soft delete
    await Feed.db.markAsDeleted(session, feedId);
  }

  /// Refresh a feed
  Future<void> refreshFeed(Session session, int feedId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final feed = await session.db.findById<Feed>(feedId);
    if (feed == null || feed.userId != userId) {
      throw Exception('Unauthorized access to feed');
    }

    // Fetch new articles
    final feedService = session.serverpod.getSingleton<FeedService>();
    await feedService.fetchFeedArticles(session, feedId);
  }

  /// Refresh all feeds for user
  Future<void> refreshAllFeeds(Session session) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final feeds = await Feed.db.findByUserId(session, userId);
    final feedService = session.serverpod.getSingleton<FeedService>();

    // Refresh feeds in parallel with rate limiting
    await Future.wait(
      feeds.map((feed) => feedService.fetchFeedArticles(session, feed.id!)),
    );
  }

  /// Discover feeds from a URL
  Future<List<String>> discoverFeeds(Session session, String url) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final parser = FeedParserService();
    return await parser.discoverFeeds(url);
  }

  /// Import feeds from OPML
  Future<ImportResult> importOPML(Session session, String opmlContent) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final opmlService = OPMLService();
    return await opmlService.importOPML(session, userId, opmlContent);
  }

  /// Export feeds to OPML
  Future<String> exportOPML(Session session) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final feeds = await Feed.db.findByUserId(session, userId);
    final folders = await session.db.find<Folder>(
      where: (t) => t.userId.equals(userId) & t.deletedAt.equals(null),
    );

    final opmlService = OPMLService();
    return opmlService.exportOPML(feeds, folders);
  }

  /// Get feed statistics
  Future<FeedStatistics> getFeedStatistics(Session session, int feedId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final feed = await session.db.findById<Feed>(feedId);
    if (feed == null || feed.userId != userId) {
      throw Exception('Unauthorized access to feed');
    }

    // Get article counts
    final totalCount = await session.db.count<Article>(
      where: (t) => t.feedId.equals(feedId) & t.deletedAt.equals(null),
    );

    final unreadCount = await session.db.count<Article>(
      where: (t) => t.feedId.equals(feedId) & t.isRead.equals(false) & t.deletedAt.equals(null),
    );

    final starredCount = await session.db.count<Article>(
      where: (t) => t.feedId.equals(feedId) & t.isStarred.equals(true) & t.deletedAt.equals(null),
    );

    // Get date range
    final articles = await session.db.find<Article>(
      where: (t) => t.feedId.equals(feedId) & t.deletedAt.equals(null),
      orderBy: Article.t.publishedAt.ascending,
      limit: 1,
    );

    DateTime? oldestArticleDate;
    if (articles.isNotEmpty) {
      oldestArticleDate = articles.first.publishedAt;
    }

    return FeedStatistics(
      feedId: feedId,
      totalArticles: totalCount,
      unreadArticles: unreadCount,
      starredArticles: starredCount,
      oldestArticleDate: oldestArticleDate,
      lastFetchedAt: feed.lastFetchedAt,
      lastSuccessfulFetch: feed.lastSuccessfulFetch,
      errorCount: feed.errorCount,
      averageArticlesPerDay: _calculateAverageArticlesPerDay(
        totalCount,
        oldestArticleDate,
        DateTime.now(),
      ),
    );
  }

  double _calculateAverageArticlesPerDay(
    int totalArticles,
    DateTime? startDate,
    DateTime endDate,
  ) {
    if (startDate == null || totalArticles == 0) return 0;
    
    final days = endDate.difference(startDate).inDays;
    if (days == 0) return totalArticles.toDouble();
    
    return totalArticles / days;
  }
}

class ImportResult {
  final int feedsImported;
  final int feedsSkipped;
  final int foldersCreated;
  final List<String> errors;

  ImportResult({
    required this.feedsImported,
    required this.feedsSkipped,
    required this.foldersCreated,
    required this.errors,
  });

  Map<String, dynamic> toJson() => {
    'feedsImported': feedsImported,
    'feedsSkipped': feedsSkipped,
    'foldersCreated': foldersCreated,
    'errors': errors,
  };
}

class FeedStatistics {
  final int feedId;
  final int totalArticles;
  final int unreadArticles;
  final int starredArticles;
  final DateTime? oldestArticleDate;
  final DateTime? lastFetchedAt;
  final DateTime? lastSuccessfulFetch;
  final int errorCount;
  final double averageArticlesPerDay;

  FeedStatistics({
    required this.feedId,
    required this.totalArticles,
    required this.unreadArticles,
    required this.starredArticles,
    this.oldestArticleDate,
    this.lastFetchedAt,
    this.lastSuccessfulFetch,
    required this.errorCount,
    required this.averageArticlesPerDay,
  });

  Map<String, dynamic> toJson() => {
    'feedId': feedId,
    'totalArticles': totalArticles,
    'unreadArticles': unreadArticles,
    'starredArticles': starredArticles,
    'oldestArticleDate': oldestArticleDate?.toIso8601String(),
    'lastFetchedAt': lastFetchedAt?.toIso8601String(),
    'lastSuccessfulFetch': lastSuccessfulFetch?.toIso8601String(),
    'errorCount': errorCount,
    'averageArticlesPerDay': averageArticlesPerDay,
  };
}