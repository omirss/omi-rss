import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../core/models/bypass_statistics.dart';
import '../core/services/bypass_statistics_service.dart';
import '../core/database/database.dart';
import 'database_provider.dart';

part 'bypass_provider.g.dart';

/// Provider for bypass statistics service
@riverpod
BypassStatisticsService bypassStatisticsService(BypassStatisticsServiceRef ref) {
  final database = ref.watch(databaseProvider);
  final service = BypassStatisticsService(database: database);
  
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
}

/// Provider for overall bypass statistics
@riverpod
Future<OverallBypassStats> bypassStatistics(BypassStatisticsRef ref) async {
  final service = ref.watch(bypassStatisticsServiceProvider);
  return service.getOverallStats();
}

/// Provider for site-specific bypass statistics
@riverpod
Future<SiteBypassStats?> siteBypassStatistics(
  SiteBypassStatisticsRef ref,
  String domain,
) async {
  final service = ref.watch(bypassStatisticsServiceProvider);
  return service.getSiteStats(domain);
}

/// Provider for bypass enabled state
@riverpod
class BypassEnabled extends _$BypassEnabled {
  @override
  bool build() {
    // Load from secure storage
    return _loadBypassEnabled();
  }
  
  void toggle() {
    state = !state;
    _saveBypassEnabled(state);
  }
  
  void enable() {
    state = true;
    _saveBypassEnabled(true);
  }
  
  void disable() {
    state = false;
    _saveBypassEnabled(false);
  }
  
  bool _loadBypassEnabled() {
    // TODO: Load from secure storage
    return false;
  }
  
  void _saveBypassEnabled(bool enabled) {
    // TODO: Save to secure storage
  }
}

/// Provider for bypass configuration
@riverpod
class BypassConfigNotifier extends _$BypassConfigNotifier {
  @override
  BypassConfig build() {
    // Load from storage or use default
    return _loadConfig() ?? BypassConfig.defaultConfig();
  }
  
  void updateConfig(BypassConfig config) {
    state = config;
    _saveConfig(config);
  }
  
  void resetToDefault() {
    state = BypassConfig.defaultConfig();
    _saveConfig(state);
  }
  
  void toggleSite(String domain, bool enabled) {
    final sitesEnabled = Map<String, bool>.from(state.sitesEnabled);
    sitesEnabled[domain] = enabled;
    state = state.copyWith(sitesEnabled: sitesEnabled);
    _saveConfig(state);
  }
  
  void updatePreferredMethods(List<String> methods) {
    state = state.copyWith(preferredMethods: methods);
    _saveConfig(state);
  }
  
  BypassConfig? _loadConfig() {
    // TODO: Load from storage
    return null;
  }
  
  void _saveConfig(BypassConfig config) {
    // TODO: Save to storage
  }
}

/// Shorthand providers
final bypassConfigProvider = bypassConfigNotifierProvider;

/// Provider to record bypass attempts
@riverpod
class BypassRecorder extends _$BypassRecorder {
  @override
  Future<void> build() async {
    // Initial state
  }
  
  Future<void> recordAttempt(BypassAttempt attempt) async {
    final service = ref.read(bypassStatisticsServiceProvider);
    await service.recordAttempt(attempt);
    
    // Invalidate statistics to refresh UI
    ref.invalidate(bypassStatisticsProvider);
    if (attempt.domain.isNotEmpty) {
      ref.invalidate(siteBypassStatisticsProvider(attempt.domain));
    }
  }
}