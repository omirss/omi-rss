import 'dart:async';
import 'package:collection/collection.dart';
import '../models/bypass_statistics.dart';
import '../database/database.dart';

/// Service for tracking bypass success rates and statistics
class BypassStatisticsService {
  final AppDatabase? _database;
  final Map<String, List<BypassAttempt>> _recentAttempts = {};
  final Map<String, SiteBypassStats> _siteStats = {};
  Timer? _cleanupTimer;
  
  // In-memory storage limits
  static const int _maxAttemptsPerSite = 100;
  static const Duration _attemptRetention = Duration(days: 7);
  
  BypassStatisticsService({AppDatabase? database}) : _database = database {
    // Start periodic cleanup
    _cleanupTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _cleanupOldAttempts(),
    );
  }
  
  void dispose() {
    _cleanupTimer?.cancel();
  }
  
  /// Record a bypass attempt
  Future<void> recordAttempt(BypassAttempt attempt) async {
    // Add to recent attempts
    _recentAttempts.putIfAbsent(attempt.domain, () => []).add(attempt);
    
    // Limit stored attempts per site
    if (_recentAttempts[attempt.domain]!.length > _maxAttemptsPerSite) {
      _recentAttempts[attempt.domain]!.removeAt(0);
    }
    
    // Update site statistics
    await _updateSiteStats(attempt.domain);
    
    // Store in database if available
    if (_database != null) {
      await _storeAttemptInDatabase(attempt);
    }
  }
  
  /// Get statistics for a specific site
  Future<SiteBypassStats?> getSiteStats(String domain) async {
    if (_siteStats.containsKey(domain)) {
      return _siteStats[domain];
    }
    
    // Calculate from recent attempts
    await _updateSiteStats(domain);
    return _siteStats[domain];
  }
  
  /// Get overall bypass statistics
  Future<OverallBypassStats> getOverallStats() async {
    // Update all site stats first
    for (final domain in _recentAttempts.keys) {
      await _updateSiteStats(domain);
    }
    
    final allStats = _siteStats.values.toList();
    
    if (allStats.isEmpty) {
      return _createEmptyOverallStats();
    }
    
    // Calculate totals
    final totalAttempts = allStats.fold(0, (sum, stat) => sum + stat.totalAttempts);
    final successfulAttempts = allStats.fold(0, (sum, stat) => sum + stat.successfulAttempts);
    final overallSuccessRate = totalAttempts > 0 ? successfulAttempts / totalAttempts : 0.0;
    
    // Success rate by category
    final successRateByCategory = _calculateSuccessRateByCategory(allStats);
    
    // Top and worst performing sites
    final sortedBySuccess = allStats.sorted((a, b) => b.successRate.compareTo(a.successRate));
    final topPerforming = sortedBySuccess.take(10).toList();
    final worstPerforming = sortedBySuccess.reversed.take(10).toList();
    
    // Attempts by hour
    final attemptsByHour = _calculateAttemptsByHour();
    
    // Attempts by day
    final attemptsByDay = _calculateAttemptsByDay();
    
    return OverallBypassStats(
      totalSites: allStats.length,
      activeSites: allStats.where((s) => s.lastAttempt != null && 
          DateTime.now().difference(s.lastAttempt!).inDays < 7).length,
      totalAttempts: totalAttempts,
      successfulAttempts: successfulAttempts,
      overallSuccessRate: overallSuccessRate,
      successRateByCategory: successRateByCategory,
      topPerformingSites: topPerforming,
      worstPerformingSites: worstPerforming,
      attemptsByHour: attemptsByHour,
      attemptsByDay: attemptsByDay,
      lastUpdated: DateTime.now(),
    );
  }
  
  /// Clear all statistics
  Future<void> clearStats() async {
    _recentAttempts.clear();
    _siteStats.clear();
    
    if (_database != null) {
      // Clear database records
      await _clearDatabaseStats();
    }
  }
  
  /// Clear statistics for a specific site
  Future<void> clearSiteStats(String domain) async {
    _recentAttempts.remove(domain);
    _siteStats.remove(domain);
    
    if (_database != null) {
      await _clearSiteDatabaseStats(domain);
    }
  }
  
  /// Update statistics for a site
  Future<void> _updateSiteStats(String domain) async {
    final attempts = _recentAttempts[domain] ?? [];
    if (attempts.isEmpty) return;
    
    // Count successes and failures
    final successCount = attempts.where((a) => a.success).length;
    final failureCount = attempts.length - successCount;
    final successRate = attempts.isNotEmpty ? successCount / attempts.length : 0.0;
    
    // Calculate method statistics
    final methodStats = <String, MethodStats>{};
    final methodGroups = attempts.groupListsBy((a) => a.method);
    
    for (final entry in methodGroups.entries) {
      final methodAttempts = entry.value;
      final methodSuccesses = methodAttempts.where((a) => a.success).length;
      final durations = methodAttempts.map((a) => a.duration).toList();
      
      methodStats[entry.key] = MethodStats(
        method: entry.key,
        attempts: methodAttempts.length,
        successes: methodSuccesses,
        successRate: methodAttempts.isNotEmpty ? methodSuccesses / methodAttempts.length : 0.0,
        averageDuration: _calculateAverageDuration(durations),
        lastUsed: methodAttempts.last.timestamp,
      );
    }
    
    // Find common errors
    final errors = attempts
        .where((a) => !a.success && a.error != null)
        .map((a) => a.error!)
        .toList();
    final errorCounts = <String, int>{};
    for (final error in errors) {
      errorCounts[error] = (errorCounts[error] ?? 0) + 1;
    }
    final commonErrors = errorCounts.entries
        .sorted((a, b) => b.value.compareTo(a.value))
        .take(5)
        .map((e) => e.key)
        .toList();
    
    // Calculate average duration
    final durations = attempts.map((a) => a.duration).toList();
    final averageDuration = _calculateAverageDuration(durations);
    
    // Get site name from first attempt metadata
    final siteName = attempts.first.metadata?['siteName'] ?? domain;
    
    _siteStats[domain] = SiteBypassStats(
      domain: domain,
      siteName: siteName,
      totalAttempts: attempts.length,
      successfulAttempts: successCount,
      failedAttempts: failureCount,
      successRate: successRate,
      methodStats: methodStats,
      lastAttempt: attempts.last.timestamp,
      lastSuccess: attempts.lastWhereOrNull((a) => a.success)?.timestamp,
      averageDuration: averageDuration,
      commonErrors: commonErrors,
    );
  }
  
  Duration _calculateAverageDuration(List<Duration> durations) {
    if (durations.isEmpty) return Duration.zero;
    
    final totalMicroseconds = durations.fold(0, (sum, d) => sum + d.inMicroseconds);
    return Duration(microseconds: totalMicroseconds ~/ durations.length);
  }
  
  Map<String, double> _calculateSuccessRateByCategory(List<SiteBypassStats> stats) {
    final categories = {
      'news': ['nytimes.com', 'washingtonpost.com', 'theguardian.com', 'bbc.com', 'cnn.com'],
      'financial': ['bloomberg.com', 'wsj.com', 'ft.com', 'reuters.com'],
      'tech': ['wired.com', 'techcrunch.com', 'theverge.com', 'arstechnica.com'],
      'academic': ['nature.com', 'science.org', 'jstor.org', 'ieee.org'],
      'regional': ['lemonde.fr', 'spiegel.de', 'elpais.com', 'scmp.com'],
    };
    
    final result = <String, double>{};
    
    for (final entry in categories.entries) {
      final categoryStats = stats.where((s) => entry.value.contains(s.domain)).toList();
      if (categoryStats.isNotEmpty) {
        final totalAttempts = categoryStats.fold(0, (sum, s) => sum + s.totalAttempts);
        final successfulAttempts = categoryStats.fold(0, (sum, s) => sum + s.successfulAttempts);
        result[entry.key] = totalAttempts > 0 ? successfulAttempts / totalAttempts : 0.0;
      }
    }
    
    return result;
  }
  
  Map<String, int> _calculateAttemptsByHour() {
    final hourCounts = <String, int>{};
    
    for (final attempts in _recentAttempts.values) {
      for (final attempt in attempts) {
        final hour = attempt.timestamp.hour.toString().padLeft(2, '0');
        hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
      }
    }
    
    return hourCounts;
  }
  
  Map<DateTime, int> _calculateAttemptsByDay() {
    final dayCounts = <DateTime, int>{};
    
    for (final attempts in _recentAttempts.values) {
      for (final attempt in attempts) {
        final day = DateTime(
          attempt.timestamp.year,
          attempt.timestamp.month,
          attempt.timestamp.day,
        );
        dayCounts[day] = (dayCounts[day] ?? 0) + 1;
      }
    }
    
    return dayCounts;
  }
  
  void _cleanupOldAttempts() {
    final cutoff = DateTime.now().subtract(_attemptRetention);
    
    for (final entry in _recentAttempts.entries) {
      entry.value.removeWhere((attempt) => attempt.timestamp.isBefore(cutoff));
    }
    
    // Remove empty entries
    _recentAttempts.removeWhere((key, value) => value.isEmpty);
  }
  
  OverallBypassStats _createEmptyOverallStats() {
    return OverallBypassStats(
      totalSites: 0,
      activeSites: 0,
      totalAttempts: 0,
      successfulAttempts: 0,
      overallSuccessRate: 0.0,
      successRateByCategory: {},
      topPerformingSites: [],
      worstPerformingSites: [],
      attemptsByHour: {},
      attemptsByDay: {},
      lastUpdated: DateTime.now(),
    );
  }
  
  // Database operations (placeholder methods)
  Future<void> _storeAttemptInDatabase(BypassAttempt attempt) async {
    // TODO: Implement database storage
  }
  
  Future<void> _clearDatabaseStats() async {
    // TODO: Implement database cleanup
  }
  
  Future<void> _clearSiteDatabaseStats(String domain) async {
    // TODO: Implement site-specific database cleanup
  }
}