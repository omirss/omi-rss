import 'package:freezed_annotation/freezed_annotation.dart';

part 'alert.freezed.dart';
part 'alert.g.dart';

/// Alert model for notifications
@freezed
class Alert with _$Alert {
  const factory Alert({
    required String id,
    required String title,
    required String message,
    required AlertType type,
    required AlertCategory category,
    required DateTime createdAt,
    DateTime? readAt,
    DateTime? dismissedAt,
    @Default(AlertPriority.medium) AlertPriority priority,
    @Default(true) bool isActive,
    Map<String, dynamic>? metadata,
    List<AlertAction>? actions,
    String? groupId,
    String? imageUrl,
    String? deepLink,
  }) = _Alert;

  factory Alert.fromJson(Map<String, dynamic> json) => _$AlertFromJson(json);
}

/// Alert action that can be taken
@freezed
class AlertAction with _$AlertAction {
  const factory AlertAction({
    required String id,
    required String label,
    required AlertActionType type,
    String? deepLink,
    Map<String, dynamic>? metadata,
    @Default(false) bool isPrimary,
  }) = _AlertAction;

  factory AlertAction.fromJson(Map<String, dynamic> json) =>
      _$AlertActionFromJson(json);
}

/// Alert configuration
@freezed
class AlertConfig with _$AlertConfig {
  const factory AlertConfig({
    required String id,
    required String name,
    required AlertTriggerType triggerType,
    required Map<String, dynamic> conditions,
    required AlertCategory category,
    @Default(true) bool isEnabled,
    @Default(AlertPriority.medium) AlertPriority priority,
    @Default(false) bool playSound,
    @Default(true) bool showNotification,
    @Default(false) bool vibrate,
    String? soundUri,
    List<AlertChannel>? channels,
    Map<String, dynamic>? metadata,
  }) = _AlertConfig;

  factory AlertConfig.fromJson(Map<String, dynamic> json) =>
      _$AlertConfigFromJson(json);
}

/// Alert subscription for feeds/articles
@freezed
class AlertSubscription with _$AlertSubscription {
  const factory AlertSubscription({
    required String id,
    required String userId,
    required AlertSubscriptionType type,
    required String targetId, // feedId, portfolioId, etc.
    required List<AlertConfig> configs,
    @Default(true) bool isActive,
    DateTime? lastTriggered,
    Map<String, dynamic>? metadata,
  }) = _AlertSubscription;

  factory AlertSubscription.fromJson(Map<String, dynamic> json) =>
      _$AlertSubscriptionFromJson(json);
}

/// Alert history entry
@freezed
class AlertHistory with _$AlertHistory {
  const factory AlertHistory({
    required String id,
    required String alertId,
    required String userId,
    required DateTime timestamp,
    required AlertHistoryAction action,
    Map<String, dynamic>? metadata,
  }) = _AlertHistory;

  factory AlertHistory.fromJson(Map<String, dynamic> json) =>
      _$AlertHistoryFromJson(json);
}

// Enums
enum AlertType {
  info,
  warning,
  error,
  success,
  notification,
}

enum AlertCategory {
  // Feed alerts
  feed_update,
  feed_error,
  feed_health,
  
  // Article alerts
  article_keyword,
  article_author,
  article_topic,
  
  // Portfolio alerts
  portfolio_price,
  portfolio_gain_loss,
  portfolio_news,
  portfolio_dividend,
  
  // System alerts
  system_update,
  system_maintenance,
  system_error,
  
  // User alerts
  user_achievement,
  user_milestone,
  user_reminder,
}

enum AlertPriority {
  low,
  medium,
  high,
  urgent,
}

enum AlertActionType {
  open_feed,
  open_article,
  open_portfolio,
  open_settings,
  dismiss,
  snooze,
  custom,
}

enum AlertTriggerType {
  // Feed triggers
  new_articles,
  feed_error,
  feed_inactive,
  
  // Article triggers
  keyword_match,
  author_match,
  topic_match,
  
  // Portfolio triggers
  price_above,
  price_below,
  percent_change,
  volume_spike,
  
  // Time-based triggers
  scheduled,
  recurring,
}

enum AlertChannel {
  in_app,
  push_notification,
  email,
  sms,
  webhook,
}

enum AlertSubscriptionType {
  feed,
  portfolio,
  keyword,
  author,
  global,
}

enum AlertHistoryAction {
  created,
  delivered,
  read,
  dismissed,
  action_taken,
  failed,
}