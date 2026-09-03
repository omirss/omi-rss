import 'package:freezed_annotation/freezed_annotation.dart';

part 'bypass_statistics.freezed.dart';
part 'bypass_statistics.g.dart';

/// Bypass attempt result
@freezed
class BypassAttempt with _$BypassAttempt {
  const factory BypassAttempt({
    required String id,
    required String url,
    required String domain,
    required String method,
    required bool success,
    required DateTime timestamp,
    required Duration duration,
    String? error,
    Map<String, dynamic>? metadata,
  }) = _BypassAttempt;
  
  factory BypassAttempt.fromJson(Map<String, dynamic> json) =>
      _$BypassAttemptFromJson(json);
}

/// Site bypass statistics
@freezed
class SiteBypassStats with _$SiteBypassStats {
  const factory SiteBypassStats({
    required String domain,
    required String siteName,
    required int totalAttempts,
    required int successfulAttempts,
    required int failedAttempts,
    required double successRate,
    required Map<String, MethodStats> methodStats,
    required DateTime? lastAttempt,
    required DateTime? lastSuccess,
    required Duration averageDuration,
    required List<String> commonErrors,
  }) = _SiteBypassStats;
  
  factory SiteBypassStats.fromJson(Map<String, dynamic> json) =>
      _$SiteBypassStatsFromJson(json);
}

/// Method-specific statistics
@freezed
class MethodStats with _$MethodStats {
  const factory MethodStats({
    required String method,
    required int attempts,
    required int successes,
    required double successRate,
    required Duration averageDuration,
    required DateTime? lastUsed,
  }) = _MethodStats;
  
  factory MethodStats.fromJson(Map<String, dynamic> json) =>
      _$MethodStatsFromJson(json);
}

/// Overall bypass statistics
@freezed
class OverallBypassStats with _$OverallBypassStats {
  const factory OverallBypassStats({
    required int totalSites,
    required int activeSites,
    required int totalAttempts,
    required int successfulAttempts,
    required double overallSuccessRate,
    required Map<String, double> successRateByCategory,
    required List<SiteBypassStats> topPerformingSites,
    required List<SiteBypassStats> worstPerformingSites,
    required Map<String, int> attemptsByHour,
    required Map<DateTime, int> attemptsByDay,
    required DateTime lastUpdated,
  }) = _OverallBypassStats;
  
  factory OverallBypassStats.fromJson(Map<String, dynamic> json) =>
      _$OverallBypassStatsFromJson(json);
}

/// Bypass configuration
@freezed
class BypassConfig with _$BypassConfig {
  const factory BypassConfig({
    required bool enabled,
    required bool autoRetry,
    required int maxRetries,
    required Duration timeout,
    required List<String> preferredMethods,
    required Map<String, bool> sitesEnabled,
    required bool collectStats,
    required bool anonymizeData,
  }) = _BypassConfig;
  
  factory BypassConfig.fromJson(Map<String, dynamic> json) =>
      _$BypassConfigFromJson(json);
  
  factory BypassConfig.defaultConfig() => const BypassConfig(
    enabled: false,
    autoRetry: true,
    maxRetries: 2,
    timeout: Duration(seconds: 30),
    preferredMethods: ['googlebot', 'amp', 'archive'],
    sitesEnabled: {},
    collectStats: true,
    anonymizeData: true,
  );
}