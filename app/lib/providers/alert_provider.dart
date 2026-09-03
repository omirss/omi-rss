import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../core/models/alert.dart';
import '../core/services/alert_service.dart';
import 'database_provider.dart';
import 'settings_provider.dart';

part 'alert_provider.g.dart';

/// Provider for alert service
@riverpod
AlertService alertService(AlertServiceRef ref) {
  final database = ref.watch(databaseProvider);
  final settingsService = ref.watch(settingsServiceProvider);
  
  final service = AlertService(
    database: database,
    settingsService: settingsService,
  );
  
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
}

/// Provider for active alerts
@riverpod
List<Alert> activeAlerts(ActiveAlertsRef ref) {
  final service = ref.watch(alertServiceProvider);
  
  // Watch the alert stream for updates
  ref.listen(alertStreamProvider, (previous, next) {
    // Trigger rebuild when new alerts arrive
    ref.invalidateSelf();
  });
  
  return service.getActiveAlerts();
}

/// Provider for unread alert count
@riverpod
int unreadAlertCount(UnreadAlertCountRef ref) {
  final service = ref.watch(alertServiceProvider);
  
  // Watch the alert stream for updates
  ref.listen(alertStreamProvider, (previous, next) {
    ref.invalidateSelf();
  });
  
  return service.getUnreadCount();
}

/// Provider for alert stream
@riverpod
Stream<Alert> alertStream(AlertStreamRef ref) {
  final service = ref.watch(alertServiceProvider);
  return service.alertStream;
}

/// Provider for alert history
@riverpod
Future<List<AlertHistory>> alertHistory(AlertHistoryRef ref, {int? limit}) async {
  final service = ref.watch(alertServiceProvider);
  return Future.value(service.getHistory(limit: limit ?? 100));
}

/// Provider for alert subscriptions
@riverpod
Stream<AlertSubscription> alertSubscriptionStream(AlertSubscriptionStreamRef ref) {
  final service = ref.watch(alertServiceProvider);
  return service.subscriptionStream;
}

/// Provider for subscriptions by target
@riverpod
List<AlertSubscription> targetSubscriptions(
  TargetSubscriptionsRef ref,
  String targetId,
  AlertSubscriptionType type,
) {
  final service = ref.watch(alertServiceProvider);
  
  // Watch subscription stream for updates
  ref.listen(alertSubscriptionStreamProvider, (previous, next) {
    ref.invalidateSelf();
  });
  
  return service.getSubscriptionsForTarget(targetId, type);
}

/// Provider for creating feed alert subscription
@riverpod
Future<AlertSubscription> createFeedAlertSubscription(
  CreateFeedAlertSubscriptionRef ref, {
  required String feedId,
  required List<AlertConfig> configs,
}) async {
  final service = ref.read(alertServiceProvider);
  
  return service.createSubscription(
    type: AlertSubscriptionType.feed,
    targetId: feedId,
    configs: configs,
  );
}

/// Provider for creating portfolio alert subscription
@riverpod
Future<AlertSubscription> createPortfolioAlertSubscription(
  CreatePortfolioAlertSubscriptionRef ref, {
  required String portfolioId,
  required List<AlertConfig> configs,
}) async {
  final service = ref.read(alertServiceProvider);
  
  return service.createSubscription(
    type: AlertSubscriptionType.portfolio,
    targetId: portfolioId,
    configs: configs,
  );
}

/// Provider for creating keyword alert subscription
@riverpod
Future<AlertSubscription> createKeywordAlertSubscription(
  CreateKeywordAlertSubscriptionRef ref, {
  required List<String> keywords,
  required List<AlertConfig> configs,
}) async {
  final service = ref.read(alertServiceProvider);
  
  return service.createSubscription(
    type: AlertSubscriptionType.keyword,
    targetId: keywords.join(','),
    configs: configs,
    metadata: {'keywords': keywords},
  );
}

/// Provider for alert statistics
@riverpod
AlertStatistics alertStatistics(AlertStatisticsRef ref) {
  final alerts = ref.watch(activeAlertsProvider);
  final history = ref.watch(alertHistoryProvider(limit: 1000)).valueOrNull ?? [];
  
  // Count by type
  final typeCount = <AlertType, int>{};
  for (final alert in alerts) {
    typeCount[alert.type] = (typeCount[alert.type] ?? 0) + 1;
  }
  
  // Count by category
  final categoryCount = <AlertCategory, int>{};
  for (final alert in alerts) {
    categoryCount[alert.category] = (categoryCount[alert.category] ?? 0) + 1;
  }
  
  // Recent activity
  final now = DateTime.now();
  final last24h = history.where((h) => 
    now.difference(h.timestamp).inHours < 24
  ).length;
  
  final last7d = history.where((h) => 
    now.difference(h.timestamp).inDays < 7
  ).length;
  
  return AlertStatistics(
    totalActive: alerts.length,
    unreadCount: alerts.where((a) => a.readAt == null).length,
    typeCount: typeCount,
    categoryCount: categoryCount,
    alertsLast24h: last24h,
    alertsLast7d: last7d,
  );
}

/// Alert statistics model
class AlertStatistics {
  final int totalActive;
  final int unreadCount;
  final Map<AlertType, int> typeCount;
  final Map<AlertCategory, int> categoryCount;
  final int alertsLast24h;
  final int alertsLast7d;
  
  AlertStatistics({
    required this.totalActive,
    required this.unreadCount,
    required this.typeCount,
    required this.categoryCount,
    required this.alertsLast24h,
    required this.alertsLast7d,
  });
}