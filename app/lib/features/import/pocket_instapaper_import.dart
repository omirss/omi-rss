import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import '../../core/models/article.dart';
import '../../core/models/feed.dart';

abstract class ReadingListImporter {
  Future<List<ImportedArticle>> importFromFile(File file);
  Future<List<ImportedArticle>> importFromApi(String apiKey, {String? username});
}

class ImportedArticle {
  final String title;
  final String url;
  final String? excerpt;
  final DateTime? savedAt;
  final List<String> tags;
  final bool isArchived;
  final bool isFavorite;
  
  ImportedArticle({
    required this.title,
    required this.url,
    this.excerpt,
    this.savedAt,
    this.tags = const [],
    this.isArchived = false,
    this.isFavorite = false,
  });
}

class PocketImporter implements ReadingListImporter {
  static const String apiUrl = 'https://getpocket.com/v3';
  final Dio dio;
  
  PocketImporter({Dio? dio}) : dio = dio ?? Dio();
  
  @override
  Future<List<ImportedArticle>> importFromFile(File file) async {
    try {
      final content = await file.readAsString();
      final document = html_parser.parse(content);
      final articles = <ImportedArticle>[];
      
      // Parse Pocket HTML export
      final links = document.querySelectorAll('a');
      for (final link in links) {
        final url = link.attributes['href'];
        final title = link.text;
        final timeAdded = link.attributes['time_added'];
        final tags = link.attributes['tags']?.split(',') ?? [];
        
        if (url != null && title.isNotEmpty) {
          articles.add(ImportedArticle(
            title: title,
            url: url,
            savedAt: timeAdded != null 
              ? DateTime.fromMillisecondsSinceEpoch(int.parse(timeAdded) * 1000)
              : null,
            tags: tags,
          ));
        }
      }
      
      return articles;
    } catch (e) {
      throw Exception('Failed to parse Pocket export file: $e');
    }
  }
  
  @override
  Future<List<ImportedArticle>> importFromApi(String apiKey, {String? username}) async {
    try {
      // Get access token using consumer key
      final response = await dio.post(
        '$apiUrl/get',
        data: {
          'consumer_key': apiKey,
          'access_token': username, // In Pocket's case, username is the access token
          'detailType': 'complete',
          'state': 'all',
          'sort': 'newest',
        },
      );
      
      final data = response.data;
      final articles = <ImportedArticle>[];
      
      if (data['list'] != null) {
        final items = data['list'] as Map<String, dynamic>;
        
        for (final item in items.values) {
          final tags = <String>[];
          if (item['tags'] != null) {
            final itemTags = item['tags'] as Map<String, dynamic>;
            tags.addAll(itemTags.values.map((tag) => tag['tag'] as String));
          }
          
          articles.add(ImportedArticle(
            title: item['resolved_title'] ?? item['given_title'] ?? 'Untitled',
            url: item['resolved_url'] ?? item['given_url'],
            excerpt: item['excerpt'],
            savedAt: DateTime.fromMillisecondsSinceEpoch(
              int.parse(item['time_added']) * 1000
            ),
            tags: tags,
            isArchived: item['status'] == '1',
            isFavorite: item['favorite'] == '1',
          ));
        }
      }
      
      return articles;
    } catch (e) {
      throw Exception('Failed to import from Pocket API: $e');
    }
  }
}

class InstapaperImporter implements ReadingListImporter {
  static const String apiUrl = 'https://www.instapaper.com/api/1';
  final Dio dio;
  
  InstapaperImporter({Dio? dio}) : dio = dio ?? Dio();
  
  @override
  Future<List<ImportedArticle>> importFromFile(File file) async {
    try {
      final content = await file.readAsString();
      
      // Check if it's HTML or CSV
      if (content.trimLeft().startsWith('<')) {
        return _parseHtmlExport(content);
      } else {
        return _parseCsvExport(content);
      }
    } catch (e) {
      throw Exception('Failed to parse Instapaper export file: $e');
    }
  }
  
  Future<List<ImportedArticle>> _parseHtmlExport(String content) async {
    final document = html_parser.parse(content);
    final articles = <ImportedArticle>[];
    
    // Instapaper HTML export structure
    final bookmarks = document.querySelectorAll('.bookmark');
    for (final bookmark in bookmarks) {
      final link = bookmark.querySelector('a.bookmark_title');
      final url = link?.attributes['href'];
      final title = link?.text;
      
      if (url != null && title != null && title.isNotEmpty) {
        articles.add(ImportedArticle(
          title: title,
          url: url,
        ));
      }
    }
    
    return articles;
  }
  
  Future<List<ImportedArticle>> _parseCsvExport(String content) async {
    final articles = <ImportedArticle>[];
    final lines = content.split('\n');
    
    // Skip header
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      
      final parts = _parseCsvLine(line);
      if (parts.length >= 2) {
        articles.add(ImportedArticle(
          title: parts[1],
          url: parts[0],
        ));
      }
    }
    
    return articles;
  }
  
  List<String> _parseCsvLine(String line) {
    final parts = <String>[];
    bool inQuotes = false;
    String current = '';
    
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        parts.add(current.trim());
        current = '';
      } else {
        current += char;
      }
    }
    
    if (current.isNotEmpty) {
      parts.add(current.trim());
    }
    
    return parts;
  }
  
  @override
  Future<List<ImportedArticle>> importFromApi(String apiKey, {String? username}) async {
    try {
      // Instapaper uses OAuth
      // For simplicity, we'll use basic auth with username/password
      final basicAuth = 'Basic ${base64Encode(utf8.encode('$username:$apiKey'))}';
      
      final response = await dio.get(
        '$apiUrl/bookmarks/list',
        options: Options(
          headers: {
            'Authorization': basicAuth,
          },
        ),
      );
      
      final articles = <ImportedArticle>[];
      final bookmarks = response.data as List;
      
      for (final bookmark in bookmarks) {
        if (bookmark['type'] == 'bookmark') {
          articles.add(ImportedArticle(
            title: bookmark['title'] ?? 'Untitled',
            url: bookmark['url'],
            excerpt: bookmark['description'],
            savedAt: DateTime.fromMillisecondsSinceEpoch(
              bookmark['time'] * 1000
            ),
            isArchived: bookmark['progress'] == 1.0,
            isFavorite: bookmark['starred'] == 1,
          ));
        }
      }
      
      return articles;
    } catch (e) {
      throw Exception('Failed to import from Instapaper API: $e');
    }
  }
}

class ImportService {
  final PocketImporter pocketImporter;
  final InstapaperImporter instapaperImporter;
  
  ImportService({
    PocketImporter? pocketImporter,
    InstapaperImporter? instapaperImporter,
  }) : pocketImporter = pocketImporter ?? PocketImporter(),
       instapaperImporter = instapaperImporter ?? InstapaperImporter();
  
  Future<List<ImportedArticle>> importFromPocketFile(File file) async {
    return await pocketImporter.importFromFile(file);
  }
  
  Future<List<ImportedArticle>> importFromPocketApi(String consumerKey, String accessToken) async {
    return await pocketImporter.importFromApi(consumerKey, username: accessToken);
  }
  
  Future<List<ImportedArticle>> importFromInstapaperFile(File file) async {
    return await instapaperImporter.importFromFile(file);
  }
  
  Future<List<ImportedArticle>> importFromInstapaperApi(String username, String password) async {
    return await instapaperImporter.importFromApi(password, username: username);
  }
  
  // Convert imported articles to feed format
  Feed createImportedFeed(String source, List<ImportedArticle> articles) {
    return Feed(
      id: 'imported_${source}_${DateTime.now().millisecondsSinceEpoch}',
      title: '$source Import',
      description: 'Articles imported from $source',
      url: 'https://imported.local/$source',
      feedUrl: 'https://imported.local/$source/feed',
      category: 'Imported',
      iconUrl: null,
      lastUpdated: DateTime.now(),
      updateFrequency: 0, // No updates for imported feeds
      isActive: true,
      metadata: {
        'source': source,
        'importedAt': DateTime.now().toIso8601String(),
        'articleCount': articles.length,
      },
    );
  }
  
  // Convert imported articles to Article format
  List<Article> convertToArticles(String feedId, List<ImportedArticle> imports) {
    return imports.map((import) {
      final now = DateTime.now();
      return Article(
        id: 'imported_${import.url.hashCode}_${now.millisecondsSinceEpoch}',
        feedId: feedId,
        title: import.title,
        url: import.url,
        content: import.excerpt ?? '',
        summary: import.excerpt,
        author: null,
        publishedAt: import.savedAt ?? now,
        updatedAt: now,
        isRead: import.isArchived,
        isStarred: import.isFavorite,
        categories: import.tags,
        metadata: {
          'imported': true,
          'source': feedId.contains('pocket') ? 'pocket' : 'instapaper',
        },
      );
    }).toList();
  }
}