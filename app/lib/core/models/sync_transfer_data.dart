import 'feed.dart';
import 'article.dart';
import 'folder.dart';

/// Sync transfer data model for transferring between devices
class SyncTransferData {
  final String version;
  final String deviceId;
  final DateTime timestamp;
  final SyncTransferContent data;

  SyncTransferData({
    required this.version,
    required this.deviceId,
    required this.timestamp,
    required this.data,
  });

  factory SyncTransferData.fromJson(Map<String, dynamic> json) {
    return SyncTransferData(
      version: json['version'] as String,
      deviceId: json['deviceId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      data: SyncTransferContent.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'deviceId': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'data': data.toJson(),
    };
  }
}

/// Content of sync transfer data
class SyncTransferContent {
  final List<Feed> feeds;
  final List<Article> articles;
  final List<Folder> folders;
  final Map<String, bool> readStatus;
  final List<String> savedArticles;
  final Map<String, dynamic> settings;

  SyncTransferContent({
    required this.feeds,
    required this.articles,
    required this.folders,
    required this.readStatus,
    required this.savedArticles,
    required this.settings,
  });

  factory SyncTransferContent.fromJson(Map<String, dynamic> json) {
    return SyncTransferContent(
      feeds: (json['feeds'] as List<dynamic>)
          .map((e) => Feed.fromJson(e as Map<String, dynamic>))
          .toList(),
      articles: (json['articles'] as List<dynamic>)
          .map((e) => Article.fromJson(e as Map<String, dynamic>))
          .toList(),
      folders: (json['folders'] as List<dynamic>)
          .map((e) => Folder.fromJson(e as Map<String, dynamic>))
          .toList(),
      readStatus: Map<String, bool>.from(json['readStatus'] as Map),
      savedArticles: List<String>.from(json['savedArticles'] as List),
      settings: Map<String, dynamic>.from(json['settings'] as Map),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'feeds': feeds.map((e) => e.toJson()).toList(),
      'articles': articles.map((e) => e.toJson()).toList(),
      'folders': folders.map((e) => e.toJson()).toList(),
      'readStatus': readStatus,
      'savedArticles': savedArticles,
      'settings': settings,
    };
  }
}