import 'package:serverpod/serverpod.dart';
import '../protocol/protocol.dart';
import '../services/ai_service.dart';
import '../websocket/websocket_handler.dart';

class AIEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  // Analyze an article with AI
  Future<AIAnalysis> analyzeArticle(
    Session session,
    int articleId,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Get the article
    final article = await Article.db.findById(session, articleId);
    if (article == null) {
      throw Exception('Article not found');
    }

    // Check if user has access to this article
    final feed = await Feed.db.findById(session, article.feedId);
    if (feed == null || feed.userId != userId) {
      // Check if article is in a shared folder
      final hasAccess = await _checkSharedAccess(session, userId, article.feedId);
      if (!hasAccess) {
        throw Exception('Access denied');
      }
    }

    // Check if we already have an analysis
    final existingAnalysis = await AIAnalysis.db.findFirstRow(
      session,
      where: (t) => t.articleId.equals(articleId),
    );

    if (existingAnalysis != null) {
      // Return cached analysis if recent (within 7 days)
      if (existingAnalysis.analyzedAt.isAfter(
        DateTime.now().subtract(const Duration(days: 7)),
      )) {
        return existingAnalysis;
      }
    }

    // Get AI service
    final aiService = session.serverpod.getSingleton<AIService>();
    
    // Analyze the article
    final analysis = await aiService.analyzeArticle(
      article: article,
      analysisTypes: ['summary', 'key_points', 'sentiment', 'categories'],
    );
    
    // Save analysis to database
    final newAnalysis = AIAnalysis(
      articleId: articleId,
      summary: analysis['summary'] as String?,
      keyPoints: analysis['key_points'] as List<String>?,
      sentiment: analysis['sentiment'] as String?,
      categories: analysis['categories'] as List<String>?,
      tags: analysis['tags'] as List<String>?,
      readingTime: analysis['reading_time'] as int?,
      complexity: analysis['complexity'] as String?,
      analyzedAt: DateTime.now(),
    );
    
    if (existingAnalysis != null) {
      await AIAnalysis.db.updateRow(session, newAnalysis.copyWith(id: existingAnalysis.id));
    } else {
      await AIAnalysis.db.insertRow(session, newAnalysis);
    }
    
    // Notify via WebSocket
    await webSocketHandler.notifyAIAnalysisReady(
      session,
      userId,
      articleId,
      'full_analysis',
    );
    
    return newAnalysis;
  }
  
  // Get AI perspectives on an article from multiple providers
  Future<Map<String, dynamic>> getMultipleAIPerspectives(
    Session session,
    int articleId,
    List<String>? providers,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    
    // Get the article
    final article = await Article.db.findById(session, articleId);
    if (article == null) {
      throw Exception('Article not found');
    }
    
    // Check access
    final feed = await Feed.db.findById(session, article.feedId);
    if (feed == null || feed.userId != userId) {
      final hasAccess = await _checkSharedAccess(session, userId, article.feedId);
      if (!hasAccess) {
        throw Exception('Access denied');
      }
    }
    
    final aiService = session.serverpod.getSingleton<AIService>();
    final requestedProviders = providers ?? ['claude', 'gpt4', 'gemini'];
    final perspectives = <String, dynamic>{};
    
    for (final provider in requestedProviders) {
      try {
        final perspective = await aiService.getArticlePerspective(
          article: article,
          provider: provider,
        );
        perspectives[provider] = perspective;
      } catch (e) {
        session.log('Error getting perspective from $provider: $e', level: LogLevel.error);
        perspectives[provider] = {
          'error': 'Failed to get perspective',
          'message': e.toString(),
        };
      }
    }
    
    return {
      'articleId': articleId,
      'perspectives': perspectives,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  // Generate a concise summary of an article
  Future<Map<String, dynamic>> summarizeArticle(
    Session session,
    int articleId,
    String? provider,
    int? maxLength,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    
    // Get the article
    final article = await Article.db.findById(session, articleId);
    if (article == null) {
      throw Exception('Article not found');
    }
    
    // Check access
    final feed = await Feed.db.findById(session, article.feedId);
    if (feed == null || feed.userId != userId) {
      final hasAccess = await _checkSharedAccess(session, userId, article.feedId);
      if (!hasAccess) {
        throw Exception('Access denied');
      }
    }
    
    final aiService = session.serverpod.getSingleton<AIService>();
    final summary = await aiService.summarizeArticle(
      article: article,
      provider: provider ?? 'claude',
      maxLength: maxLength ?? 200,
    );
    
    return {
      'articleId': articleId,
      'summary': summary,
      'provider': provider ?? 'claude',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  // Extract key points from an article
  Future<Map<String, dynamic>> extractKeyPoints(
    Session session,
    int articleId,
    String? provider,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    
    // Get the article
    final article = await Article.db.findById(session, articleId);
    if (article == null) {
      throw Exception('Article not found');
    }
    
    // Check access
    final feed = await Feed.db.findById(session, article.feedId);
    if (feed == null || feed.userId != userId) {
      final hasAccess = await _checkSharedAccess(session, userId, article.feedId);
      if (!hasAccess) {
        throw Exception('Access denied');
      }
    }
    
    final aiService = session.serverpod.getSingleton<AIService>();
    final keyPoints = await aiService.extractKeyPoints(
      article: article,
      provider: provider ?? 'claude',
    );
    
    return {
      'articleId': articleId,
      'keyPoints': keyPoints,
      'provider': provider ?? 'claude',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  // Generate related questions based on article content
  Future<Map<String, dynamic>> generateQuestions(
    Session session,
    int articleId,
    String? provider,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    
    // Get the article
    final article = await Article.db.findById(session, articleId);
    if (article == null) {
      throw Exception('Article not found');
    }
    
    // Check access
    final feed = await Feed.db.findById(session, article.feedId);
    if (feed == null || feed.userId != userId) {
      final hasAccess = await _checkSharedAccess(session, userId, article.feedId);
      if (!hasAccess) {
        throw Exception('Access denied');
      }
    }
    
    final aiService = session.serverpod.getSingleton<AIService>();
    final questions = await aiService.generateQuestions(
      article: article,
      provider: provider ?? 'claude',
    );
    
    return {
      'articleId': articleId,
      'questions': questions,
      'provider': provider ?? 'claude',
      'timestamp': DateTime.now().toIso8601String(),
    };
    final aiService = session.serverpod.getSingleton<AIService>();

    // Fetch full content if needed
    if (article.content == null || article.content!.isEmpty) {
      // Try to extract full content
      // This would integrate with extraction service
      // For now, use description
      article.content = article.description;
    }

    // Analyze with AI
    final analysis = await aiService.analyzeArticle(article);
    
    // Save to database
    if (existingAnalysis != null) {
      existingAnalysis.summary = analysis.summary;
      existingAnalysis.keyPoints = analysis.keyPoints;
      existingAnalysis.perspectives = analysis.perspectives;
      existingAnalysis.biasAnalysis = analysis.biasAnalysis;
      existingAnalysis.factChecks = analysis.factChecks;
      existingAnalysis.sentiment = analysis.sentiment;
      existingAnalysis.relatedTopics = analysis.relatedTopics;
      existingAnalysis.analyzedAt = analysis.analyzedAt;
      existingAnalysis.provider = analysis.provider;
      
      await AIAnalysis.db.updateRow(session, existingAnalysis);
      return existingAnalysis;
    } else {
      await AIAnalysis.db.insertRow(session, analysis);
      return analysis;
    }
  }

  // Get analysis for multiple articles
  Future<List<AIAnalysis>> getBatchAnalysis(
    Session session,
    List<int> articleIds,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Get existing analyses
    final analyses = await AIAnalysis.db.find(
      session,
      where: (t) => t.articleId.inSet(articleIds),
    );

    final analyzedIds = analyses.map((a) => a.articleId).toSet();
    final missingIds = articleIds.where((id) => !analyzedIds.contains(id)).toList();

    // Analyze missing articles
    if (missingIds.isNotEmpty) {
      final futures = missingIds.map((id) => analyzeArticle(session, id));
      final newAnalyses = await Future.wait(futures);
      analyses.addAll(newAnalyses);
    }

    return analyses;
  }

  // Get perspectives for an article
  Future<List<AIPerspective>> getPerspectives(
    Session session,
    int articleId,
  ) async {
    final analysis = await analyzeArticle(session, articleId);
    return analysis.perspectives;
  }

  // Get bias analysis
  Future<AIBiasAnalysis> getBiasAnalysis(
    Session session,
    int articleId,
  ) async {
    final analysis = await analyzeArticle(session, articleId);
    return analysis.biasAnalysis;
  }

  // Get fact checks
  Future<List<AIFactCheck>> getFactChecks(
    Session session,
    int articleId,
  ) async {
    final analysis = await analyzeArticle(session, articleId);
    return analysis.factChecks;
  }

  // Check facts with external APIs
  Future<List<AIFactCheck>> checkFactsExternal(
    Session session,
    int articleId,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final article = await Article.db.findById(session, articleId);
    if (article == null) {
      throw Exception('Article not found');
    }

    // Extract claims from article
    final analysis = await analyzeArticle(session, articleId);
    final claims = analysis.factChecks.map((f) => f.claim).toList();

    // Check with external APIs
    final aiService = session.serverpod.getSingleton<AIService>();
    return await aiService.checkFactsWithExternalAPIs(claims);
  }

  // Answer a question about an article
  Future<String> askQuestion(
    Session session,
    int articleId,
    String question,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final article = await Article.db.findById(session, articleId);
    if (article == null) {
      throw Exception('Article not found');
    }

    // Check access
    final feed = await Feed.db.findById(session, article.feedId);
    if (feed == null || feed.userId != userId) {
      final hasAccess = await _checkSharedAccess(session, userId, article.feedId);
      if (!hasAccess) {
        throw Exception('Access denied');
      }
    }

    final aiService = session.serverpod.getSingleton<AIService>();
    return await aiService.answerQuestion(article, question);
  }

  // Get AI usage statistics
  Future<AIUsageStats> getUsageStats(
    Session session,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Get analysis count for user's articles
    final userFeeds = await Feed.db.find(
      session,
      where: (t) => t.userId.equals(userId),
    );
    
    final feedIds = userFeeds.map((f) => f.id!).toList();
    if (feedIds.isEmpty) {
      return AIUsageStats(
        totalAnalyses: 0,
        monthlyAnalyses: 0,
        providerBreakdown: {},
        averageResponseTime: 0,
      );
    }

    final articles = await Article.db.find(
      session,
      where: (t) => t.feedId.inSet(feedIds),
    );
    
    final articleIds = articles.map((a) => a.id!).toList();
    if (articleIds.isEmpty) {
      return AIUsageStats(
        totalAnalyses: 0,
        monthlyAnalyses: 0,
        providerBreakdown: {},
        averageResponseTime: 0,
      );
    }

    final analyses = await AIAnalysis.db.find(
      session,
      where: (t) => t.articleId.inSet(articleIds),
    );

    // Calculate statistics
    final now = DateTime.now();
    final monthAgo = now.subtract(const Duration(days: 30));
    
    final monthlyAnalyses = analyses.where(
      (a) => a.analyzedAt.isAfter(monthAgo),
    ).length;

    final providerBreakdown = <String, int>{};
    for (final analysis in analyses) {
      providerBreakdown[analysis.provider] = 
          (providerBreakdown[analysis.provider] ?? 0) + 1;
    }

    return AIUsageStats(
      totalAnalyses: analyses.length,
      monthlyAnalyses: monthlyAnalyses,
      providerBreakdown: providerBreakdown,
      averageResponseTime: 0, // Would need to track this
    );
  }

  // Generate summary for multiple articles
  Future<String> generateCollectionSummary(
    Session session,
    List<int> articleIds,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    if (articleIds.isEmpty) {
      throw Exception('No articles provided');
    }

    // Get articles
    final articles = await Article.db.find(
      session,
      where: (t) => t.articleId.inSet(articleIds),
    );

    if (articles.isEmpty) {
      throw Exception('No articles found');
    }

    // Get analyses for all articles
    final analyses = await getBatchAnalysis(session, articleIds);

    // Combine summaries and key points
    final combinedContent = analyses.map((a) => 
      '${a.summary}\nKey points: ${a.keyPoints.join(', ')}'
    ).join('\n\n---\n\n');

    // Generate overall summary
    final aiService = session.serverpod.getSingleton<AIService>();
    final dummyArticle = Article(
      feedId: 0,
      title: 'Collection Summary',
      url: '',
      guid: '',
      content: combinedContent,
      publishedAt: DateTime.now(),
      isRead: false,
      isStarred: false,
      createdAt: DateTime.now(),
    );

    return await aiService.answerQuestion(
      dummyArticle,
      'Provide a comprehensive summary of these articles, identifying common themes and key insights.',
    );
  }

  // Private helper methods
  Future<bool> _checkSharedAccess(
    Session session,
    int userId,
    int feedId,
  ) async {
    // Check if feed is in a shared folder accessible to user
    // This would integrate with collaboration system
    // For now, return false
    return false;
  }
}

// Supporting classes
class AIUsageStats {
  final int totalAnalyses;
  final int monthlyAnalyses;
  final Map<String, int> providerBreakdown;
  final double averageResponseTime;

  AIUsageStats({
    required this.totalAnalyses,
    required this.monthlyAnalyses,
    required this.providerBreakdown,
    required this.averageResponseTime,
  });

  Map<String, dynamic> toJson() => {
    'totalAnalyses': totalAnalyses,
    'monthlyAnalyses': monthlyAnalyses,
    'providerBreakdown': providerBreakdown,
    'averageResponseTime': averageResponseTime,
  };
}