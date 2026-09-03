import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/models/article.dart';
import '../../core/models/feed.dart';

abstract class WebhookService {
  Future<void> trigger(WebhookEvent event);
  Future<bool> testConnection();
  String get serviceName;
}

class WebhookEvent {
  final String eventType;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  WebhookEvent({
    required this.eventType,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  Map<String, dynamic> toJson() {
    return {
      'event_type': eventType,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class IFTTTWebhookService implements WebhookService {
  final String webhookKey;
  final String eventName;
  final Dio dio;
  
  IFTTTWebhookService({
    required this.webhookKey,
    required this.eventName,
    Dio? dio,
  }) : dio = dio ?? Dio();
  
  @override
  String get serviceName => 'IFTTT';
  
  String get webhookUrl => 'https://maker.ifttt.com/trigger/$eventName/with/key/$webhookKey';
  
  @override
  Future<void> trigger(WebhookEvent event) async {
    try {
      // IFTTT accepts up to 3 value parameters
      final values = _extractIFTTTValues(event);
      
      await dio.post(
        webhookUrl,
        data: {
          'value1': values[0],
          'value2': values[1],
          'value3': values[2],
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );
    } catch (e) {
      throw Exception('Failed to trigger IFTTT webhook: $e');
    }
  }
  
  List<String> _extractIFTTTValues(WebhookEvent event) {
    final values = <String>['', '', ''];
    
    switch (event.eventType) {
      case 'new_article':
        values[0] = event.data['title'] ?? '';
        values[1] = event.data['url'] ?? '';
        values[2] = event.data['feed'] ?? '';
        break;
      case 'article_starred':
        values[0] = event.data['title'] ?? '';
        values[1] = event.data['url'] ?? '';
        values[2] = 'Starred at ${event.timestamp.toLocal()}';
        break;
      case 'feed_error':
        values[0] = event.data['feed'] ?? 'Unknown feed';
        values[1] = event.data['error'] ?? 'Unknown error';
        values[2] = event.timestamp.toLocal().toString();
        break;
      case 'milestone_reached':
        values[0] = event.data['milestone'] ?? '';
        values[1] = event.data['description'] ?? '';
        values[2] = event.data['value']?.toString() ?? '';
        break;
      default:
        values[0] = event.eventType;
        values[1] = json.encode(event.data);
        values[2] = event.timestamp.toLocal().toString();
    }
    
    return values;
  }
  
  @override
  Future<bool> testConnection() async {
    try {
      await trigger(WebhookEvent(
        eventType: 'test',
        data: {
          'message': 'Test webhook from Omi RSS Reader',
        },
      ));
      return true;
    } catch (e) {
      return false;
    }
  }
}

class ZapierWebhookService implements WebhookService {
  final String webhookUrl;
  final Dio dio;
  
  ZapierWebhookService({
    required this.webhookUrl,
    Dio? dio,
  }) : dio = dio ?? Dio();
  
  @override
  String get serviceName => 'Zapier';
  
  @override
  Future<void> trigger(WebhookEvent event) async {
    try {
      // Zapier accepts any JSON payload
      final payload = {
        'event': event.eventType,
        'timestamp': event.timestamp.toIso8601String(),
        'source': 'Omi RSS Reader',
        ...event.data,
      };
      
      await dio.post(
        webhookUrl,
        data: payload,
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );
    } catch (e) {
      throw Exception('Failed to trigger Zapier webhook: $e');
    }
  }
  
  @override
  Future<bool> testConnection() async {
    try {
      await trigger(WebhookEvent(
        eventType: 'test_connection',
        data: {
          'message': 'Test webhook from Omi RSS Reader',
          'status': 'testing',
        },
      ));
      return true;
    } catch (e) {
      return false;
    }
  }
}

class WebhookManager {
  final Map<String, WebhookService> _services = {};
  
  void addService(String id, WebhookService service) {
    _services[id] = service;
  }
  
  void removeService(String id) {
    _services.remove(id);
  }
  
  WebhookService? getService(String id) {
    return _services[id];
  }
  
  List<String> get serviceIds => _services.keys.toList();
  
  // Event triggers
  Future<void> triggerNewArticle(Article article) async {
    final event = WebhookEvent(
      eventType: 'new_article',
      data: {
        'id': article.id,
        'title': article.title,
        'url': article.url,
        'author': article.author,
        'feed': article.feedTitle,
        'feed_id': article.feedId,
        'published_at': article.publishedAt?.toIso8601String(),
        'summary': article.summary,
        'categories': article.categories,
      },
    );
    
    await _triggerAll(event);
  }
  
  Future<void> triggerArticleStarred(Article article) async {
    final event = WebhookEvent(
      eventType: 'article_starred',
      data: {
        'id': article.id,
        'title': article.title,
        'url': article.url,
        'feed': article.feedTitle,
        'starred_at': article.starredAt?.toIso8601String(),
      },
    );
    
    await _triggerAll(event);
  }
  
  Future<void> triggerArticleRead(Article article, int readingTimeSeconds) async {
    final event = WebhookEvent(
      eventType: 'article_read',
      data: {
        'id': article.id,
        'title': article.title,
        'url': article.url,
        'feed': article.feedTitle,
        'reading_time_seconds': readingTimeSeconds,
        'word_count': article.wordCount,
      },
    );
    
    await _triggerAll(event);
  }
  
  Future<void> triggerFeedAdded(Feed feed) async {
    final event = WebhookEvent(
      eventType: 'feed_added',
      data: {
        'id': feed.id,
        'title': feed.title,
        'url': feed.url,
        'feed_url': feed.feedUrl,
        'category': feed.category,
      },
    );
    
    await _triggerAll(event);
  }
  
  Future<void> triggerFeedError(Feed feed, String error) async {
    final event = WebhookEvent(
      eventType: 'feed_error',
      data: {
        'id': feed.id,
        'feed': feed.title,
        'url': feed.feedUrl,
        'error': error,
      },
    );
    
    await _triggerAll(event);
  }
  
  Future<void> triggerMilestone(String milestone, String description, dynamic value) async {
    final event = WebhookEvent(
      eventType: 'milestone_reached',
      data: {
        'milestone': milestone,
        'description': description,
        'value': value,
      },
    );
    
    await _triggerAll(event);
  }
  
  Future<void> triggerCustomEvent(String eventType, Map<String, dynamic> data) async {
    final event = WebhookEvent(
      eventType: eventType,
      data: data,
    );
    
    await _triggerAll(event);
  }
  
  Future<void> _triggerAll(WebhookEvent event) async {
    final futures = <Future>[];
    
    for (final service in _services.values) {
      futures.add(
        service.trigger(event).catchError((e) {
          // Log error but don't fail other webhooks
          print('Webhook failed for ${service.serviceName}: $e');
        }),
      );
    }
    
    await Future.wait(futures);
  }
  
  Future<Map<String, bool>> testAllConnections() async {
    final results = <String, bool>{};
    
    for (final entry in _services.entries) {
      try {
        results[entry.key] = await entry.value.testConnection();
      } catch (e) {
        results[entry.key] = false;
      }
    }
    
    return results;
  }
}

// Webhook configuration
class WebhookConfig {
  final String id;
  final String type; // 'ifttt' or 'zapier'
  final String name;
  final String webhookUrl;
  final String? iftttEventName;
  final bool enabled;
  final WebhookTriggers triggers;
  
  WebhookConfig({
    required this.id,
    required this.type,
    required this.name,
    required this.webhookUrl,
    this.iftttEventName,
    this.enabled = true,
    WebhookTriggers? triggers,
  }) : triggers = triggers ?? WebhookTriggers();
  
  WebhookConfig copyWith({
    String? id,
    String? type,
    String? name,
    String? webhookUrl,
    String? iftttEventName,
    bool? enabled,
    WebhookTriggers? triggers,
  }) {
    return WebhookConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      iftttEventName: iftttEventName ?? this.iftttEventName,
      enabled: enabled ?? this.enabled,
      triggers: triggers ?? this.triggers,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'webhookUrl': webhookUrl,
      'iftttEventName': iftttEventName,
      'enabled': enabled,
      'triggers': triggers.toJson(),
    };
  }
  
  factory WebhookConfig.fromJson(Map<String, dynamic> json) {
    return WebhookConfig(
      id: json['id'],
      type: json['type'],
      name: json['name'],
      webhookUrl: json['webhookUrl'],
      iftttEventName: json['iftttEventName'],
      enabled: json['enabled'] ?? true,
      triggers: WebhookTriggers.fromJson(json['triggers'] ?? {}),
    );
  }
}

class WebhookTriggers {
  final bool newArticles;
  final bool starredArticles;
  final bool readArticles;
  final bool feedAdded;
  final bool feedErrors;
  final bool milestones;
  
  WebhookTriggers({
    this.newArticles = true,
    this.starredArticles = true,
    this.readArticles = false,
    this.feedAdded = true,
    this.feedErrors = true,
    this.milestones = true,
  });
  
  WebhookTriggers copyWith({
    bool? newArticles,
    bool? starredArticles,
    bool? readArticles,
    bool? feedAdded,
    bool? feedErrors,
    bool? milestones,
  }) {
    return WebhookTriggers(
      newArticles: newArticles ?? this.newArticles,
      starredArticles: starredArticles ?? this.starredArticles,
      readArticles: readArticles ?? this.readArticles,
      feedAdded: feedAdded ?? this.feedAdded,
      feedErrors: feedErrors ?? this.feedErrors,
      milestones: milestones ?? this.milestones,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'newArticles': newArticles,
      'starredArticles': starredArticles,
      'readArticles': readArticles,
      'feedAdded': feedAdded,
      'feedErrors': feedErrors,
      'milestones': milestones,
    };
  }
  
  factory WebhookTriggers.fromJson(Map<String, dynamic> json) {
    return WebhookTriggers(
      newArticles: json['newArticles'] ?? true,
      starredArticles: json['starredArticles'] ?? true,
      readArticles: json['readArticles'] ?? false,
      feedAdded: json['feedAdded'] ?? true,
      feedErrors: json['feedErrors'] ?? true,
      milestones: json['milestones'] ?? true,
    );
  }
}