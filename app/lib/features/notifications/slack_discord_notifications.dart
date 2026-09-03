import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/models/article.dart';
import '../../core/models/feed.dart';

abstract class NotificationService {
  Future<void> sendNotification(NotificationPayload payload);
  Future<bool> testConnection();
  String get serviceName;
}

class NotificationPayload {
  final String title;
  final String message;
  final String? url;
  final List<NotificationField>? fields;
  final String? imageUrl;
  final String? color;
  
  NotificationPayload({
    required this.title,
    required this.message,
    this.url,
    this.fields,
    this.imageUrl,
    this.color,
  });
}

class NotificationField {
  final String name;
  final String value;
  final bool inline;
  
  NotificationField({
    required this.name,
    required this.value,
    this.inline = true,
  });
}

class SlackNotificationService implements NotificationService {
  final String webhookUrl;
  final Dio dio;
  
  SlackNotificationService({
    required this.webhookUrl,
    Dio? dio,
  }) : dio = dio ?? Dio();
  
  @override
  String get serviceName => 'Slack';
  
  @override
  Future<void> sendNotification(NotificationPayload payload) async {
    try {
      final slackPayload = {
        'text': payload.title,
        'attachments': [
          {
            'color': payload.color ?? '#2196F3',
            'text': payload.message,
            'fields': payload.fields?.map((field) => {
              'title': field.name,
              'value': field.value,
              'short': field.inline,
            }).toList() ?? [],
            'thumb_url': payload.imageUrl,
            'footer': 'Omi RSS Reader',
            'footer_icon': 'https://raw.githubusercontent.com/yourusername/omi-rss/main/icon.png',
            'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
        ],
      };
      
      if (payload.url != null) {
        slackPayload['attachments'][0]['title_link'] = payload.url;
      }
      
      await dio.post(
        webhookUrl,
        data: slackPayload,
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );
    } catch (e) {
      throw Exception('Failed to send Slack notification: $e');
    }
  }
  
  @override
  Future<bool> testConnection() async {
    try {
      await sendNotification(NotificationPayload(
        title: 'Test Connection',
        message: 'This is a test notification from Omi RSS Reader',
        color: '#4CAF50',
      ));
      return true;
    } catch (e) {
      return false;
    }
  }
}

class DiscordNotificationService implements NotificationService {
  final String webhookUrl;
  final Dio dio;
  
  DiscordNotificationService({
    required this.webhookUrl,
    Dio? dio,
  }) : dio = dio ?? Dio();
  
  @override
  String get serviceName => 'Discord';
  
  @override
  Future<void> sendNotification(NotificationPayload payload) async {
    try {
      final discordPayload = {
        'content': payload.title,
        'embeds': [
          {
            'description': payload.message,
            'color': _parseColor(payload.color ?? '#2196F3'),
            'fields': payload.fields?.map((field) => {
              'name': field.name,
              'value': field.value,
              'inline': field.inline,
            }).toList() ?? [],
            'thumbnail': payload.imageUrl != null ? {'url': payload.imageUrl} : null,
            'footer': {
              'text': 'Omi RSS Reader',
              'icon_url': 'https://raw.githubusercontent.com/yourusername/omi-rss/main/icon.png',
            },
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      };
      
      if (payload.url != null) {
        discordPayload['embeds'][0]['url'] = payload.url;
      }
      
      await dio.post(
        webhookUrl,
        data: discordPayload,
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );
    } catch (e) {
      throw Exception('Failed to send Discord notification: $e');
    }
  }
  
  @override
  Future<bool> testConnection() async {
    try {
      await sendNotification(NotificationPayload(
        title: 'Test Connection',
        message: 'This is a test notification from Omi RSS Reader',
        color: '#4CAF50',
      ));
      return true;
    } catch (e) {
      return false;
    }
  }
  
  int _parseColor(String hexColor) {
    // Convert hex color to decimal for Discord
    final hex = hexColor.replaceAll('#', '');
    return int.parse(hex, radix: 16);
  }
}

class NotificationManager {
  final Map<String, NotificationService> _services = {};
  
  void addService(String id, NotificationService service) {
    _services[id] = service;
  }
  
  void removeService(String id) {
    _services.remove(id);
  }
  
  NotificationService? getService(String id) {
    return _services[id];
  }
  
  List<String> get serviceIds => _services.keys.toList();
  
  Future<void> notifyNewArticles(List<Article> articles, Feed feed) async {
    if (articles.isEmpty) return;
    
    final payload = NotificationPayload(
      title: '📰 New Articles in ${feed.title}',
      message: '${articles.length} new article${articles.length > 1 ? 's' : ''} available',
      fields: articles.take(5).map((article) => NotificationField(
        name: article.title,
        value: article.summary?.substring(0, 100) ?? 'No summary',
        inline: false,
      )).toList(),
      color: '#2196F3',
    );
    
    await _sendToAll(payload);
  }
  
  Future<void> notifyStarredArticle(Article article) async {
    final payload = NotificationPayload(
      title: '⭐ Article Starred',
      message: article.title,
      url: article.url,
      fields: [
        if (article.author != null)
          NotificationField(
            name: 'Author',
            value: article.author!,
          ),
        if (article.feedTitle != null)
          NotificationField(
            name: 'Feed',
            value: article.feedTitle!,
          ),
      ],
      color: '#FFC107',
    );
    
    await _sendToAll(payload);
  }
  
  Future<void> notifyMilestone(String milestone, String description) async {
    final payload = NotificationPayload(
      title: '🎉 Milestone Reached!',
      message: milestone,
      fields: [
        NotificationField(
          name: 'Achievement',
          value: description,
          inline: false,
        ),
      ],
      color: '#4CAF50',
    );
    
    await _sendToAll(payload);
  }
  
  Future<void> notifyError(String error, String? details) async {
    final payload = NotificationPayload(
      title: '❌ Error Occurred',
      message: error,
      fields: details != null ? [
        NotificationField(
          name: 'Details',
          value: details,
          inline: false,
        ),
      ] : null,
      color: '#F44336',
    );
    
    await _sendToAll(payload);
  }
  
  Future<void> _sendToAll(NotificationPayload payload) async {
    final futures = <Future>[];
    
    for (final service in _services.values) {
      futures.add(
        service.sendNotification(payload).catchError((e) {
          // Log error but don't fail other notifications
          print('Notification failed for ${service.serviceName}: $e');
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

// Notification configuration
class NotificationConfig {
  final String id;
  final String type; // 'slack' or 'discord'
  final String webhookUrl;
  final String name;
  final bool enabled;
  final NotificationTriggers triggers;
  
  NotificationConfig({
    required this.id,
    required this.type,
    required this.webhookUrl,
    required this.name,
    this.enabled = true,
    NotificationTriggers? triggers,
  }) : triggers = triggers ?? NotificationTriggers();
  
  NotificationConfig copyWith({
    String? id,
    String? type,
    String? webhookUrl,
    String? name,
    bool? enabled,
    NotificationTriggers? triggers,
  }) {
    return NotificationConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      triggers: triggers ?? this.triggers,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'webhookUrl': webhookUrl,
      'name': name,
      'enabled': enabled,
      'triggers': triggers.toJson(),
    };
  }
  
  factory NotificationConfig.fromJson(Map<String, dynamic> json) {
    return NotificationConfig(
      id: json['id'],
      type: json['type'],
      webhookUrl: json['webhookUrl'],
      name: json['name'],
      enabled: json['enabled'] ?? true,
      triggers: NotificationTriggers.fromJson(json['triggers'] ?? {}),
    );
  }
}

class NotificationTriggers {
  final bool newArticles;
  final bool starredArticles;
  final bool milestones;
  final bool errors;
  final int minArticlesForNotification;
  
  NotificationTriggers({
    this.newArticles = true,
    this.starredArticles = false,
    this.milestones = true,
    this.errors = true,
    this.minArticlesForNotification = 1,
  });
  
  NotificationTriggers copyWith({
    bool? newArticles,
    bool? starredArticles,
    bool? milestones,
    bool? errors,
    int? minArticlesForNotification,
  }) {
    return NotificationTriggers(
      newArticles: newArticles ?? this.newArticles,
      starredArticles: starredArticles ?? this.starredArticles,
      milestones: milestones ?? this.milestones,
      errors: errors ?? this.errors,
      minArticlesForNotification: minArticlesForNotification ?? this.minArticlesForNotification,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'newArticles': newArticles,
      'starredArticles': starredArticles,
      'milestones': milestones,
      'errors': errors,
      'minArticlesForNotification': minArticlesForNotification,
    };
  }
  
  factory NotificationTriggers.fromJson(Map<String, dynamic> json) {
    return NotificationTriggers(
      newArticles: json['newArticles'] ?? true,
      starredArticles: json['starredArticles'] ?? false,
      milestones: json['milestones'] ?? true,
      errors: json['errors'] ?? true,
      minArticlesForNotification: json['minArticlesForNotification'] ?? 1,
    );
  }
}