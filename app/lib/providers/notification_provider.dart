import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../features/notifications/slack_discord_notifications.dart';
import '../core/models/article.dart';
import '../core/models/feed.dart';
import 'package:uuid/uuid.dart';

// Notification manager provider
final notificationManagerProvider = Provider<NotificationManager>((ref) {
  return NotificationManager();
});

// Notification configs provider
final notificationConfigsProvider = StateNotifierProvider<NotificationConfigsNotifier, List<NotificationConfig>>((ref) {
  return NotificationConfigsNotifier(ref);
});

class NotificationConfigsNotifier extends StateNotifier<List<NotificationConfig>> {
  final Ref ref;
  static const String _storageKey = 'notification_configs';
  
  NotificationConfigsNotifier(this.ref) : super([]) {
    _loadConfigs();
  }
  
  Future<void> _loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = prefs.getString(_storageKey);
      
      if (configsJson != null) {
        final configsList = json.decode(configsJson) as List;
        final configs = configsList
            .map((config) => NotificationConfig.fromJson(config))
            .toList();
        
        state = configs;
        
        // Initialize notification services
        final manager = ref.read(notificationManagerProvider);
        for (final config in configs) {
          if (config.enabled) {
            _addServiceToManager(config, manager);
          }
        }
      }
    } catch (e) {
      // Handle error loading configs
    }
  }
  
  Future<void> _saveConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = json.encode(
        state.map((config) => config.toJson()).toList()
      );
      await prefs.setString(_storageKey, configsJson);
    } catch (e) {
      // Handle error saving configs
    }
  }
  
  void _addServiceToManager(NotificationConfig config, NotificationManager manager) {
    NotificationService service;
    
    switch (config.type) {
      case 'slack':
        service = SlackNotificationService(webhookUrl: config.webhookUrl);
        break;
      case 'discord':
        service = DiscordNotificationService(webhookUrl: config.webhookUrl);
        break;
      default:
        return;
    }
    
    manager.addService(config.id, service);
  }
  
  Future<void> addConfig(NotificationConfig config) async {
    final manager = ref.read(notificationManagerProvider);
    
    // Add service to manager if enabled
    if (config.enabled) {
      _addServiceToManager(config, manager);
    }
    
    state = [...state, config];
    await _saveConfigs();
  }
  
  Future<void> updateConfig(NotificationConfig config) async {
    final manager = ref.read(notificationManagerProvider);
    
    // Update service in manager
    manager.removeService(config.id);
    if (config.enabled) {
      _addServiceToManager(config, manager);
    }
    
    state = state.map((c) => c.id == config.id ? config : c).toList();
    await _saveConfigs();
  }
  
  Future<void> removeConfig(String id) async {
    final manager = ref.read(notificationManagerProvider);
    manager.removeService(id);
    
    state = state.where((c) => c.id != id).toList();
    await _saveConfigs();
  }
  
  Future<void> toggleConfig(String id) async {
    final config = state.firstWhere((c) => c.id == id);
    final updatedConfig = config.copyWith(enabled: !config.enabled);
    await updateConfig(updatedConfig);
  }
  
  Future<bool> testConfig(NotificationConfig config) async {
    try {
      NotificationService service;
      
      switch (config.type) {
        case 'slack':
          service = SlackNotificationService(webhookUrl: config.webhookUrl);
          break;
        case 'discord':
          service = DiscordNotificationService(webhookUrl: config.webhookUrl);
          break;
        default:
          return false;
      }
      
      return await service.testConnection();
    } catch (e) {
      return false;
    }
  }
}

// Notification triggers provider
final notificationTriggersProvider = Provider<NotificationTriggerService>((ref) {
  return NotificationTriggerService(ref);
});

class NotificationTriggerService {
  final Ref ref;
  
  NotificationTriggerService(this.ref);
  
  Future<void> checkNewArticles(List<Article> articles, Feed feed) async {
    final configs = ref.read(notificationConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.newArticles);
    
    if (enabledConfigs.isEmpty) return;
    
    // Check if we have enough articles to notify
    final minArticles = enabledConfigs
        .map((c) => c.triggers.minArticlesForNotification)
        .reduce((a, b) => a < b ? a : b);
    
    if (articles.length >= minArticles) {
      final manager = ref.read(notificationManagerProvider);
      await manager.notifyNewArticles(articles, feed);
    }
  }
  
  Future<void> checkStarredArticle(Article article) async {
    final configs = ref.read(notificationConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.starredArticles);
    
    if (enabledConfigs.isNotEmpty) {
      final manager = ref.read(notificationManagerProvider);
      await manager.notifyStarredArticle(article);
    }
  }
  
  Future<void> checkMilestone(String milestone, String description) async {
    final configs = ref.read(notificationConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.milestones);
    
    if (enabledConfigs.isNotEmpty) {
      final manager = ref.read(notificationManagerProvider);
      await manager.notifyMilestone(milestone, description);
    }
  }
  
  Future<void> checkError(String error, String? details) async {
    final configs = ref.read(notificationConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.errors);
    
    if (enabledConfigs.isNotEmpty) {
      final manager = ref.read(notificationManagerProvider);
      await manager.notifyError(error, details);
    }
  }
}

// Helper to create new notification config
final createNotificationConfigProvider = Provider<NotificationConfig Function({
  required String type,
  required String webhookUrl,
  required String name,
})>((ref) {
  return ({
    required String type,
    required String webhookUrl,
    required String name,
  }) {
    return NotificationConfig(
      id: const Uuid().v4(),
      type: type,
      webhookUrl: webhookUrl,
      name: name,
    );
  };
});