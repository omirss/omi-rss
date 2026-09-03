import 'package:serverpod/serverpod.dart';
import '../protocol/protocol.dart';
import '../services/generation_service.dart';

class GenerationEndpoint extends Endpoint {
  @override
  bool get requireLogin => false; // Allow anonymous generation for preview

  // Generate feed from URL
  Future<GeneratedFeed> generateFeed(
    Session session,
    String url, {
    String? format,
    bool preview = false,
  }) async {
    // Validate URL
    if (!_isValidUrl(url)) {
      throw Exception('Invalid URL format');
    }

    // Check rate limiting for anonymous users
    final userId = await session.auth.authenticatedUserId;
    if (userId == null && !preview) {
      throw Exception('Authentication required for full feed generation');
    }

    // Get generation service
    final generationService = session.serverpod.getSingleton<GenerationService>();
    
    // Generate feed
    final result = await generationService.generateFeed(
      url,
      format: format ?? 'rss',
      limit: preview ? 3 : 50,
    );

    // Log generation
    await _logGeneration(session, userId, url, result.success);

    if (!result.success) {
      throw Exception(result.error ?? 'Failed to generate feed');
    }

    // If preview mode, limit items
    if (preview && result.items.length > 3) {
      result.items = result.items.take(3).toList();
    }

    return result;
  }

  // Discover available feeds from URL
  Future<List<DiscoveredFeed>> discoverFeeds(
    Session session,
    String url,
  ) async {
    if (!_isValidUrl(url)) {
      throw Exception('Invalid URL format');
    }

    final generationService = session.serverpod.getSingleton<GenerationService>();
    return await generationService.discoverFeeds(url);
  }

  // Get supported sites
  Future<List<SupportedSite>> getSupportedSites(
    Session session, {
    String? category,
  }) async {
    final generationService = session.serverpod.getSingleton<GenerationService>();
    final sites = await generationService.getSupportedSites();

    if (category != null) {
      return sites.where((s) => s.category == category).toList();
    }

    return sites;
  }

  // Get site categories
  Future<List<String>> getSiteCategories(
    Session session,
  ) async {
    final sites = await getSupportedSites(session);
    final categories = sites.map((s) => s.category).toSet().toList();
    categories.sort();
    return categories;
  }

  // Test site rule
  Future<RuleTestResult> testSiteRule(
    Session session,
    String url,
    Map<String, dynamic> rule,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('Authentication required');
    }

    // Check if user is admin
    final user = await User.db.findById(session, userId);
    if (user == null || !user.isAdmin) {
      throw Exception('Admin access required');
    }

    final generationService = session.serverpod.getSingleton<GenerationService>();
    return await generationService.testRule(url, rule);
  }

  // Submit new site rule
  Future<bool> submitSiteRule(
    Session session,
    String domain,
    Map<String, dynamic> rule,
    String category,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('Authentication required');
    }

    // Validate rule structure
    if (!_isValidRule(rule)) {
      throw Exception('Invalid rule format');
    }

    // Save rule submission
    final submission = GenerationRuleSubmission(
      userId: userId,
      domain: domain,
      rule: rule,
      category: category,
      status: 'pending',
      submittedAt: DateTime.now(),
    );

    await GenerationRuleSubmission.db.insertRow(session, submission);

    // Notify admins
    await _notifyAdminsOfSubmission(session, submission);

    return true;
  }

  // Get generation statistics
  Future<GenerationStats> getGenerationStats(
    Session session,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    
    // Get overall stats for admins, user stats for regular users
    if (userId != null) {
      final user = await User.db.findById(session, userId);
      if (user != null && user.isAdmin) {
        return await _getOverallStats(session);
      }
    }

    return await _getUserStats(session, userId);
  }

  // Extract full text from URL
  Future<ExtractedContent> extractFullText(
    Session session,
    String url,
  ) async {
    if (!_isValidUrl(url)) {
      throw Exception('Invalid URL format');
    }

    final generationService = session.serverpod.getSingleton<GenerationService>();
    return await generationService.extractContent(url);
  }

  // Get popular generated feeds
  Future<List<PopularFeed>> getPopularFeeds(
    Session session, {
    int limit = 20,
  }) async {
    // Get most generated domains from logs
    final logs = await GenerationLog.db.find(
      session,
      where: (t) => t.success.equals(true),
      orderBy: (t) => t.generatedAt,
      orderDescending: true,
      limit: 1000,
    );

    // Count by domain
    final domainCounts = <String, int>{};
    for (final log in logs) {
      final uri = Uri.parse(log.url);
      final domain = uri.host;
      domainCounts[domain] = (domainCounts[domain] ?? 0) + 1;
    }

    // Sort by count
    final sortedDomains = domainCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Get site info for top domains
    final generationService = session.serverpod.getSingleton<GenerationService>();
    final supportedSites = await generationService.getSupportedSites();
    final siteMap = {for (var site in supportedSites) site.domain: site};

    final popularFeeds = <PopularFeed>[];
    for (final entry in sortedDomains.take(limit)) {
      final site = siteMap[entry.key];
      if (site != null) {
        popularFeeds.add(PopularFeed(
          domain: entry.key,
          name: site.name,
          description: site.description,
          category: site.category,
          generationCount: entry.value,
          exampleUrl: site.exampleUrl,
        ));
      }
    }

    return popularFeeds;
  }

  // Private helper methods
  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }

  bool _isValidRule(Map<String, dynamic> rule) {
    // Validate rule has required fields
    return rule.containsKey('selectors') &&
           rule['selectors'] is Map &&
           rule['selectors']['item'] != null;
  }

  Future<void> _logGeneration(
    Session session,
    int? userId,
    String url,
    bool success,
  ) async {
    final log = GenerationLog(
      userId: userId,
      url: url,
      success: success,
      generatedAt: DateTime.now(),
    );

    await GenerationLog.db.insertRow(session, log);
  }

  Future<void> _notifyAdminsOfSubmission(
    Session session,
    GenerationRuleSubmission submission,
  ) async {
    // Get admin users
    final admins = await User.db.find(
      session,
      where: (t) => t.isAdmin.equals(true),
    );

    // Send notification to each admin
    // This would integrate with notification service
    for (final admin in admins) {
      session.log('New rule submission for ${submission.domain} from user ${submission.userId}');
    }
  }

  Future<GenerationStats> _getOverallStats(Session session) async {
    final now = DateTime.now();
    final dayAgo = now.subtract(const Duration(days: 1));
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = now.subtract(const Duration(days: 30));

    final totalGenerations = await GenerationLog.db.count(session);
    final successfulGenerations = await GenerationLog.db.count(
      session,
      where: (t) => t.success.equals(true),
    );

    final dailyGenerations = await GenerationLog.db.count(
      session,
      where: (t) => t.generatedAt.afterOrEqualTo(dayAgo),
    );

    final weeklyGenerations = await GenerationLog.db.count(
      session,
      where: (t) => t.generatedAt.afterOrEqualTo(weekAgo),
    );

    final monthlyGenerations = await GenerationLog.db.count(
      session,
      where: (t) => t.generatedAt.afterOrEqualTo(monthAgo),
    );

    final uniqueUsers = await GenerationLog.db
        .find(session)
        .then((logs) => logs.where((l) => l.userId != null).map((l) => l.userId).toSet().length);

    return GenerationStats(
      totalGenerations: totalGenerations,
      successfulGenerations: successfulGenerations,
      successRate: totalGenerations > 0 ? successfulGenerations / totalGenerations : 0,
      dailyGenerations: dailyGenerations,
      weeklyGenerations: weeklyGenerations,
      monthlyGenerations: monthlyGenerations,
      uniqueUsers: uniqueUsers,
    );
  }

  Future<GenerationStats> _getUserStats(Session session, int? userId) async {
    if (userId == null) {
      return GenerationStats(
        totalGenerations: 0,
        successfulGenerations: 0,
        successRate: 0,
        dailyGenerations: 0,
        weeklyGenerations: 0,
        monthlyGenerations: 0,
        uniqueUsers: 0,
      );
    }

    final userLogs = await GenerationLog.db.find(
      session,
      where: (t) => t.userId.equals(userId),
    );

    final now = DateTime.now();
    final dayAgo = now.subtract(const Duration(days: 1));
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = now.subtract(const Duration(days: 30));

    final successful = userLogs.where((l) => l.success).length;
    final daily = userLogs.where((l) => l.generatedAt.isAfter(dayAgo)).length;
    final weekly = userLogs.where((l) => l.generatedAt.isAfter(weekAgo)).length;
    final monthly = userLogs.where((l) => l.generatedAt.isAfter(monthAgo)).length;

    return GenerationStats(
      totalGenerations: userLogs.length,
      successfulGenerations: successful,
      successRate: userLogs.isNotEmpty ? successful / userLogs.length : 0,
      dailyGenerations: daily,
      weeklyGenerations: weekly,
      monthlyGenerations: monthly,
      uniqueUsers: 1,
    );
  }
}

// Supporting classes
class GeneratedFeed {
  final bool success;
  final String? error;
  final String title;
  final String description;
  final String websiteUrl;
  final String feedUrl;
  final List<GeneratedFeedItem> items;
  final String format;

  GeneratedFeed({
    required this.success,
    this.error,
    required this.title,
    required this.description,
    required this.websiteUrl,
    required this.feedUrl,
    required this.items,
    required this.format,
  });
}

class GeneratedFeedItem {
  final String title;
  final String url;
  final String? description;
  final String? content;
  final DateTime? publishedAt;
  final String? author;
  final String? imageUrl;
  final List<String> categories;

  GeneratedFeedItem({
    required this.title,
    required this.url,
    this.description,
    this.content,
    this.publishedAt,
    this.author,
    this.imageUrl,
    required this.categories,
  });
}

class SupportedSite {
  final String domain;
  final String name;
  final String description;
  final String category;
  final String exampleUrl;
  final bool requiresJavaScript;

  SupportedSite({
    required this.domain,
    required this.name,
    required this.description,
    required this.category,
    required this.exampleUrl,
    required this.requiresJavaScript,
  });
}

class RuleTestResult {
  final bool success;
  final List<GeneratedFeedItem> items;
  final String? error;
  final Map<String, dynamic> debug;

  RuleTestResult({
    required this.success,
    required this.items,
    this.error,
    required this.debug,
  });
}

class ExtractedContent {
  final String? title;
  final String? content;
  final String? author;
  final DateTime? publishedDate;
  final String? imageUrl;
  final int wordCount;
  final int readingTime;

  ExtractedContent({
    this.title,
    this.content,
    this.author,
    this.publishedDate,
    this.imageUrl,
    required this.wordCount,
    required this.readingTime,
  });
}

class PopularFeed {
  final String domain;
  final String name;
  final String description;
  final String category;
  final int generationCount;
  final String exampleUrl;

  PopularFeed({
    required this.domain,
    required this.name,
    required this.description,
    required this.category,
    required this.generationCount,
    required this.exampleUrl,
  });
}

class GenerationStats {
  final int totalGenerations;
  final int successfulGenerations;
  final double successRate;
  final int dailyGenerations;
  final int weeklyGenerations;
  final int monthlyGenerations;
  final int uniqueUsers;

  GenerationStats({
    required this.totalGenerations,
    required this.successfulGenerations,
    required this.successRate,
    required this.dailyGenerations,
    required this.weeklyGenerations,
    required this.monthlyGenerations,
    required this.uniqueUsers,
  });

  Map<String, dynamic> toJson() => {
    'totalGenerations': totalGenerations,
    'successfulGenerations': successfulGenerations,
    'successRate': successRate,
    'dailyGenerations': dailyGenerations,
    'weeklyGenerations': weeklyGenerations,
    'monthlyGenerations': monthlyGenerations,
    'uniqueUsers': uniqueUsers,
  };
}