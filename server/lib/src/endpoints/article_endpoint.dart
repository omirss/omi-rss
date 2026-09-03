import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import '../protocol/protocol.dart';
import '../services/full_text_service.dart';
import '../services/ai_service.dart';

class ArticleEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  /// Get articles with filtering and pagination
  Future<ArticleListResult> getArticles(
    Session session, {
    int? feedId,
    int? folderId,
    bool? isRead,
    bool? isStarred,
    bool? isArchived,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    ArticleOrder orderBy = ArticleOrder.publishedDesc,
    int limit = 20,
    int offset = 0,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Build filter
    final filter = ArticleFilter(
      isRead: isRead,
      isStarred: isStarred,
      isArchived: isArchived,
      feedId: feedId,
      search: search,
      startDate: startDate,
      endDate: endDate,
    );

    // If filtering by folder, get feed IDs in that folder
    List<int>? feedIds;
    if (folderId != null) {
      final feeds = await session.db.find<Feed>(
        where: (t) => t.folderId.equals(folderId) & t.userId.equals(userId) & t.deletedAt.equals(null),
      );
      feedIds = feeds.map((f) => f.id!).toList();
      
      if (feedIds.isEmpty) {
        return ArticleListResult(articles: [], total: 0, hasMore: false);
      }
    }

    // Get articles
    final articles = await Article.db.findByUserId(
      session,
      userId,
      filter: filter,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    // Get total count
    var countWhere = Article.t.userId.equals(userId) & Article.t.deletedAt.equals(null);
    if (filter.isRead != null) {
      countWhere = countWhere & Article.t.isRead.equals(filter.isRead!);
    }
    if (filter.isStarred != null) {
      countWhere = countWhere & Article.t.isStarred.equals(filter.isStarred!);
    }
    if (filter.isArchived != null) {
      countWhere = countWhere & Article.t.isArchived.equals(filter.isArchived!);
    }
    if (feedIds != null) {
      countWhere = countWhere & Article.t.feedId.inSet(feedIds);
    } else if (filter.feedId != null) {
      countWhere = countWhere & Article.t.feedId.equals(filter.feedId!);
    }

    final total = await session.db.count<Article>(where: countWhere);

    return ArticleListResult(
      articles: articles,
      total: total,
      hasMore: offset + articles.length < total,
    );
  }

  /// Get a specific article
  Future<Article?> getArticle(Session session, int articleId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final article = await session.db.findById<Article>(articleId);
    if (article != null && article.userId != userId) {
      throw Exception('Unauthorized access to article');
    }

    return article;
  }

  /// Mark article as read
  Future<void> markAsRead(Session session, int articleId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final article = await session.db.findById<Article>(articleId);
    if (article == null || article.userId != userId) {
      throw Exception('Unauthorized access to article');
    }

    await Article.db.markAsRead(session, articleId);
    
    // Update feed unread count
    await _updateFeedUnreadCount(session, article.feedId);
  }

  /// Mark multiple articles as read
  Future<void> markMultipleAsRead(Session session, List<int> articleIds) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership of all articles
    final articles = await session.db.find<Article>(
      where: (t) => t.id.inSet(articleIds) & t.userId.equals(userId),
    );

    if (articles.length != articleIds.length) {
      throw Exception('Unauthorized access to some articles');
    }

    // Mark as read
    await session.db.transaction((transaction) async {
      for (final articleId in articleIds) {
        await Article.db.markAsRead(session, articleId, transaction: transaction);
      }
    });

    // Update feed unread counts
    final feedIds = articles.map((a) => a.feedId).toSet();
    for (final feedId in feedIds) {
      await _updateFeedUnreadCount(session, feedId);
    }
  }

  /// Toggle starred status
  Future<void> toggleStarred(Session session, int articleId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final article = await session.db.findById<Article>(articleId);
    if (article == null || article.userId != userId) {
      throw Exception('Unauthorized access to article');
    }

    await Article.db.toggleStarred(session, articleId, !article.isStarred);
  }

  /// Archive article
  Future<void> archiveArticle(Session session, int articleId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final article = await session.db.findById<Article>(articleId);
    if (article == null || article.userId != userId) {
      throw Exception('Unauthorized access to article');
    }

    await session.db.updateRow<Article>(
      Article()
        ..id = articleId
        ..isArchived = true
        ..updatedAt = DateTime.now(),
      columns: [Article.t.isArchived, Article.t.updatedAt],
    );
  }

  /// Delete article
  Future<void> deleteArticle(Session session, int articleId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final article = await session.db.findById<Article>(articleId);
    if (article == null || article.userId != userId) {
      throw Exception('Unauthorized access to article');
    }

    await Article.db.markAsDeleted(session, articleId);
    
    // Update feed article count
    await _updateFeedArticleCount(session, article.feedId);
  }

  /// Get full text of article
  Future<String?> getFullText(Session session, int articleId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final article = await session.db.findById<Article>(articleId);
    if (article == null || article.userId != userId) {
      throw Exception('Unauthorized access to article');
    }

    // Return cached full text if available
    if (article.fullContent != null) {
      return article.fullContent;
    }

    // Extract full text
    final fullTextService = FullTextService();
    final fullText = await fullTextService.extractFullText(article.url);

    if (fullText != null) {
      // Cache the full text
      await session.db.updateRow<Article>(
        Article()
          ..id = articleId
          ..fullContent = fullText
          ..updatedAt = DateTime.now(),
        columns: [Article.t.fullContent, Article.t.updatedAt],
      );
    }

    return fullText;
  }

  /// Update article tags
  Future<Article> updateTags(Session session, int articleId, List<String> tags) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final article = await session.db.findById<Article>(articleId);
    if (article == null || article.userId != userId) {
      throw Exception('Unauthorized access to article');
    }

    article.tags = tags;
    article.updatedAt = DateTime.now();

    return await session.db.updateRow<Article>(article);
  }

  /// Search articles
  Future<List<Article>> searchArticles(
    Session session,
    String query, {
    int limit = 20,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    return await session.db.find<Article>(
      where: (t) => t.userId.equals(userId) &
          t.deletedAt.equals(null) &
          (t.title.ilike('%$query%') | t.content.ilike('%$query%')),
      limit: limit,
      orderBy: Article.t.publishedAt.descending,
    );
  }

  /// Get AI analysis for article
  Future<AIAnalysis?> getAIAnalysis(
    Session session,
    int articleId, {
    bool forceRefresh = false,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify ownership
    final article = await session.db.findById<Article>(articleId);
    if (article == null || article.userId != userId) {
      throw Exception('Unauthorized access to article');
    }

    // Check for existing analysis
    if (!forceRefresh) {
      final existingAnalysis = await session.db.findFirstRow<AIAnalysis>(
        where: (t) => t.articleId.equals(articleId),
      );
      
      if (existingAnalysis != null) {
        return existingAnalysis;
      }
    }

    // Generate new analysis
    final aiService = session.serverpod.getSingleton<AIService>();
    final analysis = await aiService.analyzeArticle(session, article);

    return analysis;
  }

  /// Helper to update feed unread count
  Future<void> _updateFeedUnreadCount(Session session, int feedId) async {
    final unreadCount = await session.db.count<Article>(
      where: (t) => t.feedId.equals(feedId) & 
          t.isRead.equals(false) & 
          t.deletedAt.equals(null),
    );

    await session.db.updateRow<Feed>(
      Feed()
        ..id = feedId
        ..unreadCount = unreadCount
        ..updatedAt = DateTime.now(),
      columns: [Feed.t.unreadCount, Feed.t.updatedAt],
    );
  }

  /// Helper to update feed article count
  Future<void> _updateFeedArticleCount(Session session, int feedId) async {
    final articleCount = await session.db.count<Article>(
      where: (t) => t.feedId.equals(feedId) & t.deletedAt.equals(null),
    );

    await session.db.updateRow<Feed>(
      Feed()
        ..id = feedId
        ..articleCount = articleCount
        ..updatedAt = DateTime.now(),
      columns: [Feed.t.articleCount, Feed.t.updatedAt],
    );
  }
}

class ArticleListResult {
  final List<Article> articles;
  final int total;
  final bool hasMore;

  ArticleListResult({
    required this.articles,
    required this.total,
    required this.hasMore,
  });

  Map<String, dynamic> toJson() => {
    'articles': articles.map((a) => a.toJson()).toList(),
    'total': total,
    'hasMore': hasMore,
  };
}