import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/article.dart';
import '../../core/services/api_service.dart';

class BrowserBookmark {
  final String id;
  final String url;
  final String title;
  final String? favicon;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String browser;
  final String? folderId;
  final String? folderPath;
  
  BrowserBookmark({
    required this.id,
    required this.url,
    required this.title,
    this.favicon,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.browser,
    this.folderId,
    this.folderPath,
  });
  
  factory BrowserBookmark.fromJson(Map<String, dynamic> json) {
    return BrowserBookmark(
      id: json['id'],
      url: json['url'],
      title: json['title'],
      favicon: json['favicon'],
      tags: List<String>.from(json['tags'] ?? []),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      browser: json['browser'],
      folderId: json['folderId'],
      folderPath: json['folderPath'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'favicon': favicon,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'browser': browser,
      'folderId': folderId,
      'folderPath': folderPath,
    };
  }
  
  Article toArticle() {
    return Article(
      id: 'bookmark_$id',
      feedId: 'bookmarks_$browser',
      feedTitle: '$browser Bookmarks',
      title: title,
      url: url,
      content: '<p>Bookmarked from $browser</p>',
      summary: 'Bookmark: $title',
      publishedAt: createdAt,
      updatedAt: updatedAt,
      categories: tags,
      metadata: {
        'type': 'bookmark',
        'browser': browser,
        'favicon': favicon,
        'folderPath': folderPath,
      },
    );
  }
}

class BookmarkFolder {
  final String id;
  final String name;
  final String? parentId;
  final String path;
  
  BookmarkFolder({
    required this.id,
    required this.name,
    this.parentId,
    required this.path,
  });
  
  factory BookmarkFolder.fromJson(Map<String, dynamic> json) {
    return BookmarkFolder(
      id: json['id'],
      name: json['name'],
      parentId: json['parentId'],
      path: json['path'],
    );
  }
}

class SyncResult {
  final List<BrowserBookmark> toAdd;
  final List<BrowserBookmark> toUpdate;
  final List<String> toDelete;
  final int serverUpdated;
  final DateTime syncTime;
  
  SyncResult({
    required this.toAdd,
    required this.toUpdate,
    required this.toDelete,
    required this.serverUpdated,
    required this.syncTime,
  });
  
  factory SyncResult.fromJson(Map<String, dynamic> json) {
    return SyncResult(
      toAdd: (json['toAdd'] as List)
          .map((b) => BrowserBookmark.fromJson(b))
          .toList(),
      toUpdate: (json['toUpdate'] as List)
          .map((b) => BrowserBookmark.fromJson(b))
          .toList(),
      toDelete: List<String>.from(json['toDelete'] ?? []),
      serverUpdated: json['serverUpdated'] ?? 0,
      syncTime: DateTime.parse(json['syncTime']),
    );
  }
}

class BookmarkSyncService {
  final ApiService apiService;
  final Dio dio;
  static const String _tokenKey = 'bookmark_sync_token';
  static const String _lastSyncKey = 'bookmark_last_sync';
  
  BookmarkSyncService({
    required this.apiService,
    Dio? dio,
  }) : dio = dio ?? Dio();
  
  // Get stored sync token
  Future<String?> getSyncToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }
  
  // Store sync token
  Future<void> setSyncToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }
  
  // Get last sync time
  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString(_lastSyncKey);
    return timestamp != null ? DateTime.parse(timestamp) : null;
  }
  
  // Update last sync time
  Future<void> setLastSyncTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, time.toIso8601String());
  }
  
  // Generate sync token
  Future<String> generateSyncToken(String userId, String browser) async {
    try {
      final response = await dio.post(
        '${apiService.baseUrl}/api/bookmarks/sync/token',
        data: {
          'userId': userId,
          'browser': browser,
        },
      );
      
      final token = response.data['token'];
      await setSyncToken(token);
      return token;
    } catch (e) {
      throw Exception('Failed to generate sync token: $e');
    }
  }
  
  // Import bookmarks from browser
  Future<void> importBookmarks(List<BrowserBookmark> bookmarks) async {
    try {
      final token = await getSyncToken();
      if (token == null) {
        throw Exception('No sync token available');
      }
      
      await dio.post(
        '${apiService.baseUrl}/api/bookmarks/sync/import',
        data: {
          'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } catch (e) {
      throw Exception('Failed to import bookmarks: $e');
    }
  }
  
  // Export bookmarks to browser
  Future<List<BrowserBookmark>> exportBookmarks({DateTime? since}) async {
    try {
      final token = await getSyncToken();
      if (token == null) {
        throw Exception('No sync token available');
      }
      
      final queryParams = <String, dynamic>{};
      if (since != null) {
        queryParams['since'] = since.toIso8601String();
      }
      
      final response = await dio.get(
        '${apiService.baseUrl}/api/bookmarks/sync/export',
        queryParameters: queryParams,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
      
      final bookmarks = (response.data['bookmarks'] as List)
          .map((b) => BrowserBookmark.fromJson(b))
          .toList();
      
      return bookmarks;
    } catch (e) {
      throw Exception('Failed to export bookmarks: $e');
    }
  }
  
  // Two-way sync
  Future<SyncResult> syncBookmarks(List<BrowserBookmark> localBookmarks) async {
    try {
      final token = await getSyncToken();
      if (token == null) {
        throw Exception('No sync token available');
      }
      
      final lastSync = await getLastSyncTime();
      
      final response = await dio.post(
        '${apiService.baseUrl}/api/bookmarks/sync/sync',
        data: {
          'bookmarks': localBookmarks.map((b) => b.toJson()).toList(),
          'lastSyncTime': lastSync?.toIso8601String(),
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
      
      final result = SyncResult.fromJson(response.data);
      await setLastSyncTime(result.syncTime);
      
      return result;
    } catch (e) {
      throw Exception('Failed to sync bookmarks: $e');
    }
  }
  
  // Convert article to bookmark
  BrowserBookmark articleToBookmark(Article article, String browser) {
    return BrowserBookmark(
      id: article.id,
      url: article.url,
      title: article.title,
      tags: article.categories,
      createdAt: article.publishedAt ?? DateTime.now(),
      updatedAt: article.updatedAt ?? DateTime.now(),
      browser: browser,
      folderPath: '/RSS Articles/${article.feedTitle ?? 'Unknown Feed'}',
    );
  }
  
  // Get sync history
  Future<List<Map<String, dynamic>>> getSyncHistory({int limit = 10}) async {
    try {
      final token = await getSyncToken();
      if (token == null) {
        throw Exception('No sync token available');
      }
      
      final response = await dio.get(
        '${apiService.baseUrl}/api/bookmarks/sync/history',
        queryParameters: {'limit': limit},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
      
      return List<Map<String, dynamic>>.from(response.data['history']);
    } catch (e) {
      throw Exception('Failed to get sync history: $e');
    }
  }
}

// Browser extension communication service
class BrowserExtensionService {
  static const String extensionId = 'your-extension-id';
  
  // Send message to browser extension
  Future<void> sendToExtension(Map<String, dynamic> message) async {
    // This would use platform channels to communicate with native code
    // which then communicates with the browser extension
    // Implementation depends on the platform (web, desktop)
  }
  
  // Receive messages from browser extension
  Stream<Map<String, dynamic>> get extensionMessages {
    // Stream of messages from the browser extension
    return Stream.empty(); // Placeholder
  }
  
  // Check if extension is installed
  Future<bool> isExtensionInstalled() async {
    // Check if browser extension is installed and active
    return false; // Placeholder
  }
  
  // Open extension install page
  Future<void> installExtension() async {
    // Open browser to extension install page
  }
}