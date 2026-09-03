import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../features/webhooks/ifttt_zapier_webhooks.dart';
import '../core/models/article.dart';
import '../core/models/feed.dart';
import 'package:uuid/uuid.dart';

// Webhook manager provider
final webhookManagerProvider = Provider<WebhookManager>((ref) {
  return WebhookManager();
});

// Webhook configs provider
final webhookConfigsProvider = StateNotifierProvider<WebhookConfigsNotifier, List<WebhookConfig>>((ref) {
  return WebhookConfigsNotifier(ref);
});

class WebhookConfigsNotifier extends StateNotifier<List<WebhookConfig>> {
  final Ref ref;
  static const String _storageKey = 'webhook_configs';
  
  WebhookConfigsNotifier(this.ref) : super([]) {
    _loadConfigs();
  }
  
  Future<void> _loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = prefs.getString(_storageKey);
      
      if (configsJson != null) {
        final configsList = json.decode(configsJson) as List;
        final configs = configsList
            .map((config) => WebhookConfig.fromJson(config))
            .toList();
        
        state = configs;
        
        // Initialize webhook services
        final manager = ref.read(webhookManagerProvider);
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
  
  void _addServiceToManager(WebhookConfig config, WebhookManager manager) {
    WebhookService service;
    
    switch (config.type) {
      case 'ifttt':
        // Extract webhook key from URL
        final match = RegExp(r'/key/(.+)$').firstMatch(config.webhookUrl);
        if (match != null) {
          service = IFTTTWebhookService(
            webhookKey: match.group(1)!,
            eventName: config.iftttEventName ?? 'omi_rss_event',
          );
        } else {
          return;
        }
        break;
      case 'zapier':
        service = ZapierWebhookService(webhookUrl: config.webhookUrl);
        break;
      default:
        return;
    }
    
    manager.addService(config.id, service);
  }
  
  Future<void> addConfig(WebhookConfig config) async {
    final manager = ref.read(webhookManagerProvider);
    
    // Add service to manager if enabled
    if (config.enabled) {
      _addServiceToManager(config, manager);
    }
    
    state = [...state, config];
    await _saveConfigs();
  }
  
  Future<void> updateConfig(WebhookConfig config) async {
    final manager = ref.read(webhookManagerProvider);
    
    // Update service in manager
    manager.removeService(config.id);
    if (config.enabled) {
      _addServiceToManager(config, manager);
    }
    
    state = state.map((c) => c.id == config.id ? config : c).toList();
    await _saveConfigs();
  }
  
  Future<void> removeConfig(String id) async {
    final manager = ref.read(webhookManagerProvider);
    manager.removeService(id);
    
    state = state.where((c) => c.id != id).toList();
    await _saveConfigs();
  }
  
  Future<void> toggleConfig(String id) async {
    final config = state.firstWhere((c) => c.id == id);
    final updatedConfig = config.copyWith(enabled: !config.enabled);
    await updateConfig(updatedConfig);
  }
  
  Future<bool> testConfig(WebhookConfig config) async {
    try {
      WebhookService service;
      
      switch (config.type) {
        case 'ifttt':
          // Extract webhook key from URL
          final match = RegExp(r'/key/(.+)$').firstMatch(config.webhookUrl);
          if (match != null) {
            service = IFTTTWebhookService(
              webhookKey: match.group(1)!,
              eventName: config.iftttEventName ?? 'omi_rss_event',
            );
          } else {
            return false;
          }
          break;
        case 'zapier':
          service = ZapierWebhookService(webhookUrl: config.webhookUrl);
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

// Webhook trigger service provider
final webhookTriggerServiceProvider = Provider<WebhookTriggerService>((ref) {
  return WebhookTriggerService(ref);
});

class WebhookTriggerService {
  final Ref ref;
  
  WebhookTriggerService(this.ref);
  
  Future<void> checkNewArticle(Article article) async {
    final configs = ref.read(webhookConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.newArticles);
    
    if (enabledConfigs.isNotEmpty) {
      final manager = ref.read(webhookManagerProvider);
      await manager.triggerNewArticle(article);
    }
  }
  
  Future<void> checkStarredArticle(Article article) async {
    final configs = ref.read(webhookConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.starredArticles);
    
    if (enabledConfigs.isNotEmpty) {
      final manager = ref.read(webhookManagerProvider);
      await manager.triggerArticleStarred(article);
    }
  }
  
  Future<void> checkReadArticle(Article article, int readingTimeSeconds) async {
    final configs = ref.read(webhookConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.readArticles);
    
    if (enabledConfigs.isNotEmpty) {
      final manager = ref.read(webhookManagerProvider);
      await manager.triggerArticleRead(article, readingTimeSeconds);
    }
  }
  
  Future<void> checkFeedAdded(Feed feed) async {
    final configs = ref.read(webhookConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.feedAdded);
    
    if (enabledConfigs.isNotEmpty) {
      final manager = ref.read(webhookManagerProvider);
      await manager.triggerFeedAdded(feed);
    }
  }
  
  Future<void> checkFeedError(Feed feed, String error) async {
    final configs = ref.read(webhookConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.feedErrors);
    
    if (enabledConfigs.isNotEmpty) {
      final manager = ref.read(webhookManagerProvider);
      await manager.triggerFeedError(feed, error);
    }
  }
  
  Future<void> checkMilestone(String milestone, String description, dynamic value) async {
    final configs = ref.read(webhookConfigsProvider);
    final enabledConfigs = configs.where((c) => c.enabled && c.triggers.milestones);
    
    if (enabledConfigs.isNotEmpty) {
      final manager = ref.read(webhookManagerProvider);
      await manager.triggerMilestone(milestone, description, value);
    }
  }
}

// Helper to create new webhook config
final createWebhookConfigProvider = Provider<WebhookConfig Function({
  required String type,
  required String webhookUrl,
  required String name,
  String? iftttEventName,
})>((ref) {
  return ({
    required String type,
    required String webhookUrl,
    required String name,
    String? iftttEventName,
  }) {
    return WebhookConfig(
      id: const Uuid().v4(),
      type: type,
      webhookUrl: webhookUrl,
      name: name,
      iftttEventName: iftttEventName,
    );
  };
});