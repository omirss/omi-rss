import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/portfolio.dart';
import '../database/database.dart';
import '../../providers/settings_provider.dart';

/// Service for managing alerts and notifications
class AlertService {
  final AppDatabase _database;
  final SettingsService _settingsService;
  final FlutterLocalNotificationsPlugin _notifications;
  
  // Alert storage
  final Map<String, Alert> _alerts = {};
  final Map<String, AlertSubscription> _subscriptions = {};
  final List<AlertHistory> _history = [];
  
  // Streams
  final _alertStreamController = StreamController<Alert>.broadcast();
  final _subscriptionStreamController = StreamController<AlertSubscription>.broadcast();
  
  // Alert processing
  Timer? _processTimer;
  final Map<String, DateTime> _lastCheck = {};
  
  AlertService({
    required AppDatabase database,
    required SettingsService settingsService,
    FlutterLocalNotificationsPlugin? notifications,
  }) : _database = database,
       _settingsService = settingsService,
       _notifications = notifications ?? FlutterLocalNotificationsPlugin() {
    _initialize();
  }
  
  Future<void> _initialize() async {
    // Initialize notifications
    await _initializeNotifications();
    
    // Load saved data
    await _loadAlerts();
    await _loadSubscriptions();
    
    // Start processing timer
    _processTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _processAlerts(),
    );
  }
  
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
  }
  
  void dispose() {
    _processTimer?.cancel();
    _alertStreamController.close();
    _subscriptionStreamController.close();
  }
  
  // Streams
  Stream<Alert> get alertStream => _alertStreamController.stream;
  Stream<AlertSubscription> get subscriptionStream => _subscriptionStreamController.stream;
  
  /// Get all active alerts
  List<Alert> getActiveAlerts() {
    return _alerts.values
        .where((alert) => alert.isActive && alert.dismissedAt == null)
        .sorted((a, b) => b.createdAt.compareTo(a.createdAt))
        .toList();
  }
  
  /// Get unread alerts count
  int getUnreadCount() {
    return _alerts.values
        .where((alert) => alert.isActive && alert.readAt == null)
        .length;
  }
  
  /// Create a new alert
  Future<Alert> createAlert({
    required String title,
    required String message,
    required AlertType type,
    required AlertCategory category,
    AlertPriority priority = AlertPriority.medium,
    Map<String, dynamic>? metadata,
    List<AlertAction>? actions,
    String? groupId,
    String? imageUrl,
    String? deepLink,
  }) async {
    final alert = Alert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      type: type,
      category: category,
      createdAt: DateTime.now(),
      priority: priority,
      metadata: metadata,
      actions: actions,
      groupId: groupId,
      imageUrl: imageUrl,
      deepLink: deepLink,
    );
    
    // Save alert
    _alerts[alert.id] = alert;
    await _saveAlert(alert);
    
    // Send to stream
    _alertStreamController.add(alert);
    
    // Show notification if enabled
    if (_shouldShowNotification(alert)) {
      await _showNotification(alert);
    }
    
    // Record history
    await _recordHistory(
      alertId: alert.id,
      action: AlertHistoryAction.created,
    );
    
    return alert;
  }
  
  /// Mark alert as read
  Future<void> markAsRead(String alertId) async {
    final alert = _alerts[alertId];
    if (alert == null || alert.readAt != null) return;
    
    final updatedAlert = alert.copyWith(readAt: DateTime.now());
    _alerts[alertId] = updatedAlert;
    
    await _saveAlert(updatedAlert);
    _alertStreamController.add(updatedAlert);
    
    await _recordHistory(
      alertId: alertId,
      action: AlertHistoryAction.read,
    );
  }
  
  /// Dismiss alert
  Future<void> dismissAlert(String alertId) async {
    final alert = _alerts[alertId];
    if (alert == null || alert.dismissedAt != null) return;
    
    final updatedAlert = alert.copyWith(
      dismissedAt: DateTime.now(),
      isActive: false,
    );
    _alerts[alertId] = updatedAlert;
    
    await _saveAlert(updatedAlert);
    _alertStreamController.add(updatedAlert);
    
    await _recordHistory(
      alertId: alertId,
      action: AlertHistoryAction.dismissed,
    );
  }
  
  /// Handle alert action
  Future<void> handleAction(String alertId, String actionId) async {
    final alert = _alerts[alertId];
    if (alert == null) return;
    
    final action = alert.actions?.firstWhereOrNull((a) => a.id == actionId);
    if (action == null) return;
    
    // Mark as read if not already
    if (alert.readAt == null) {
      await markAsRead(alertId);
    }
    
    // Record action taken
    await _recordHistory(
      alertId: alertId,
      action: AlertHistoryAction.action_taken,
      metadata: {'actionId': actionId},
    );
    
    // Handle action based on type
    switch (action.type) {
      case AlertActionType.dismiss:
        await dismissAlert(alertId);
        break;
      case AlertActionType.snooze:
        await _snoozeAlert(alertId);
        break;
      default:
        // Let the UI handle navigation
        break;
    }
  }
  
  /// Create alert subscription
  Future<AlertSubscription> createSubscription({
    required AlertSubscriptionType type,
    required String targetId,
    required List<AlertConfig> configs,
    Map<String, dynamic>? metadata,
  }) async {
    final subscription = AlertSubscription(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: 'default', // TODO: Get from auth
      type: type,
      targetId: targetId,
      configs: configs,
      metadata: metadata,
    );
    
    _subscriptions[subscription.id] = subscription;
    await _saveSubscription(subscription);
    
    _subscriptionStreamController.add(subscription);
    
    return subscription;
  }
  
  /// Update subscription
  Future<void> updateSubscription(
    String subscriptionId,
    List<AlertConfig> configs,
  ) async {
    final subscription = _subscriptions[subscriptionId];
    if (subscription == null) return;
    
    final updated = subscription.copyWith(configs: configs);
    _subscriptions[subscriptionId] = updated;
    
    await _saveSubscription(updated);
    _subscriptionStreamController.add(updated);
  }
  
  /// Delete subscription
  Future<void> deleteSubscription(String subscriptionId) async {
    _subscriptions.remove(subscriptionId);
    await _deleteSubscriptionFromDb(subscriptionId);
  }
  
  /// Get subscriptions for target
  List<AlertSubscription> getSubscriptionsForTarget(
    String targetId,
    AlertSubscriptionType type,
  ) {
    return _subscriptions.values
        .where((s) => s.targetId == targetId && s.type == type && s.isActive)
        .toList();
  }
  
  /// Process alerts based on subscriptions
  Future<void> _processAlerts() async {
    for (final subscription in _subscriptions.values) {
      if (!subscription.isActive) continue;
      
      // Check rate limiting
      final lastCheck = _lastCheck[subscription.id];
      if (lastCheck != null && 
          DateTime.now().difference(lastCheck).inMinutes < 5) {
        continue;
      }
      
      _lastCheck[subscription.id] = DateTime.now();
      
      // Process based on subscription type
      switch (subscription.type) {
        case AlertSubscriptionType.feed:
          await _processFeedAlerts(subscription);
          break;
        case AlertSubscriptionType.portfolio:
          await _processPortfolioAlerts(subscription);
          break;
        case AlertSubscriptionType.keyword:
          await _processKeywordAlerts(subscription);
          break;
        default:
          break;
      }
    }
  }
  
  /// Process feed alerts
  Future<void> _processFeedAlerts(AlertSubscription subscription) async {
    // TODO: Get feed from database
    // Check for new articles, errors, etc.
    
    for (final config in subscription.configs) {
      if (!config.isEnabled) continue;
      
      switch (config.triggerType) {
        case AlertTriggerType.new_articles:
          // Check for new articles since last check
          final threshold = config.conditions['threshold'] as int? ?? 1;
          // TODO: Query database for new article count
          break;
          
        case AlertTriggerType.feed_error:
          // Check feed health
          break;
          
        case AlertTriggerType.feed_inactive:
          // Check last update time
          break;
          
        default:
          break;
      }
    }
  }
  
  /// Process portfolio alerts
  Future<void> _processPortfolioAlerts(AlertSubscription subscription) async {
    // TODO: Get portfolio from service
    // Check price alerts, gain/loss, etc.
    
    for (final config in subscription.configs) {
      if (!config.isEnabled) continue;
      
      switch (config.triggerType) {
        case AlertTriggerType.price_above:
        case AlertTriggerType.price_below:
          // Check current prices against thresholds
          break;
          
        case AlertTriggerType.percent_change:
          // Check percentage changes
          break;
          
        default:
          break;
      }
    }
  }
  
  /// Process keyword alerts
  Future<void> _processKeywordAlerts(AlertSubscription subscription) async {
    final keywords = subscription.metadata?['keywords'] as List<String>? ?? [];
    if (keywords.isEmpty) return;
    
    // TODO: Search recent articles for keywords
  }
  
  /// Check if alert should trigger notification
  bool _shouldShowNotification(Alert alert) {
    // Check global notification settings
    if (!_settingsService.getSetting('notifications_enabled', true)) {
      return false;
    }
    
    // Check priority settings
    final minPriority = _settingsService.getSetting('min_notification_priority', 'medium');
    final priorityIndex = AlertPriority.values.indexOf(alert.priority);
    final minIndex = AlertPriority.values.indexOf(
      AlertPriority.values.firstWhere((p) => p.name == minPriority),
    );
    
    if (priorityIndex < minIndex) {
      return false;
    }
    
    // Check category settings
    final categoryEnabled = _settingsService.getSetting(
      'notification_${alert.category.name}',
      true,
    );
    
    return categoryEnabled;
  }
  
  /// Show notification
  Future<void> _showNotification(Alert alert) async {
    final androidDetails = AndroidNotificationDetails(
      'alerts_${alert.category.name}',
      'Alert Notifications',
      channelDescription: 'Notifications for ${alert.category.name}',
      importance: _getImportance(alert.priority),
      priority: _getPriority(alert.priority),
      ticker: alert.title,
      styleInformation: BigTextStyleInformation(alert.message),
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      alert.id.hashCode,
      alert.title,
      alert.message,
      details,
      payload: alert.id,
    );
    
    await _recordHistory(
      alertId: alert.id,
      action: AlertHistoryAction.delivered,
    );
  }
  
  /// Handle notification tap
  void _handleNotificationResponse(NotificationResponse response) {
    final alertId = response.payload;
    if (alertId != null) {
      final alert = _alerts[alertId];
      if (alert != null) {
        // Mark as read
        markAsRead(alertId);
        
        // TODO: Navigate to appropriate screen based on alert
      }
    }
  }
  
  /// Snooze alert
  Future<void> _snoozeAlert(String alertId) async {
    final alert = _alerts[alertId];
    if (alert == null) return;
    
    // Hide alert temporarily
    final snoozedAlert = alert.copyWith(isActive: false);
    _alerts[alertId] = snoozedAlert;
    
    // Reactivate after snooze period
    Future.delayed(const Duration(minutes: 30), () {
      if (_alerts.containsKey(alertId)) {
        final reactivated = _alerts[alertId]!.copyWith(isActive: true);
        _alerts[alertId] = reactivated;
        _alertStreamController.add(reactivated);
      }
    });
  }
  
  /// Record alert history
  Future<void> _recordHistory({
    required String alertId,
    required AlertHistoryAction action,
    Map<String, dynamic>? metadata,
  }) async {
    final entry = AlertHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      alertId: alertId,
      userId: 'default', // TODO: Get from auth
      timestamp: DateTime.now(),
      action: action,
      metadata: metadata,
    );
    
    _history.add(entry);
    
    // Limit history size
    if (_history.length > 1000) {
      _history.removeRange(0, _history.length - 1000);
    }
  }
  
  /// Get notification importance
  Importance _getImportance(AlertPriority priority) {
    switch (priority) {
      case AlertPriority.urgent:
        return Importance.max;
      case AlertPriority.high:
        return Importance.high;
      case AlertPriority.medium:
        return Importance.defaultImportance;
      case AlertPriority.low:
        return Importance.low;
    }
  }
  
  /// Get notification priority
  Priority _getPriority(AlertPriority priority) {
    switch (priority) {
      case AlertPriority.urgent:
      case AlertPriority.high:
        return Priority.high;
      case AlertPriority.medium:
        return Priority.defaultPriority;
      case AlertPriority.low:
        return Priority.low;
    }
  }
  
  // Database operations
  Future<void> _loadAlerts() async {
    // TODO: Load from database
  }
  
  Future<void> _saveAlert(Alert alert) async {
    // TODO: Save to database
  }
  
  Future<void> _loadSubscriptions() async {
    // TODO: Load from database
  }
  
  Future<void> _saveSubscription(AlertSubscription subscription) async {
    // TODO: Save to database
  }
  
  Future<void> _deleteSubscriptionFromDb(String subscriptionId) async {
    // TODO: Delete from database
  }
  
  /// Clear all alerts
  Future<void> clearAllAlerts() async {
    _alerts.clear();
    _history.clear();
    // TODO: Clear from database
  }
  
  /// Get alert history
  List<AlertHistory> getHistory({String? alertId, int? limit}) {
    var history = _history;
    
    if (alertId != null) {
      history = history.where((h) => h.alertId == alertId).toList();
    }
    
    history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (limit != null && history.length > limit) {
      history = history.take(limit).toList();
    }
    
    return history;
  }
}