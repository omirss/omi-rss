import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../core/models/article.dart';
import '../../core/models/feed.dart';

class OfflineStorage {
  static const String _articlesDir = 'offline_articles';
  static const String _imagesDir = 'offline_images';
  static const String _metadataFile = 'metadata.json';

  // Get app documents directory
  Future<Directory> _getAppDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return Directory(path.join(directory.path, 'omi_rss_offline'));
  }

  // Get offline articles directory
  Future<Directory> _getArticlesDirectory() async {
    final appDir = await _getAppDirectory();
    final articlesDir = Directory(path.join(appDir.path, _articlesDir));
    if (!await articlesDir.exists()) {
      await articlesDir.create(recursive: true);
    }
    return articlesDir;
  }

  // Get offline images directory
  Future<Directory> _getImagesDirectory() async {
    final appDir = await _getAppDirectory();
    final imagesDir = Directory(path.join(appDir.path, _imagesDir));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  // Save article for offline reading
  Future<void> saveArticleOffline(Article article) async {
    try {
      final articlesDir = await _getArticlesDirectory();
      final articleFile = File(path.join(articlesDir.path, '${article.id}.json'));
      
      // Prepare article data
      final articleData = {
        'id': article.id,
        'title': article.title,
        'content': article.content,
        'fullContent': article.fullContent,
        'summary': article.summary,
        'url': article.url,
        'author': article.author,
        'publishedAt': article.publishedAt?.toIso8601String(),
        'updatedAt': article.updatedAt?.toIso8601String(),
        'feedId': article.feedId,
        'feedTitle': article.feedTitle,
        'isRead': article.isRead,
        'isStarred': article.isStarred,
        'readAt': article.readAt?.toIso8601String(),
        'starredAt': article.starredAt?.toIso8601String(),
        'estimatedReadTime': article.estimatedReadTime,
        'wordCount': article.wordCount,
        'language': article.language,
        'categories': article.categories,
        'enclosures': article.enclosures,
        'metadata': article.metadata,
        'downloadedAt': DateTime.now().toIso8601String(),
      };
      
      // Save article data
      await articleFile.writeAsString(json.encode(articleData));
      
      // Download and save images
      if (article.enclosures != null) {
        for (final enclosure in article.enclosures!) {
          if (enclosure['type']?.startsWith('image/') == true) {
            await _downloadImage(enclosure['url'], article.id);
          }
        }
      }
      
      // Update metadata
      await _updateMetadata(article.id, 'downloaded');
    } catch (e) {
      throw Exception('Failed to save article offline: $e');
    }
  }

  // Load offline article
  Future<Article?> loadOfflineArticle(String articleId) async {
    try {
      final articlesDir = await _getArticlesDirectory();
      final articleFile = File(path.join(articlesDir.path, '$articleId.json'));
      
      if (!await articleFile.exists()) {
        return null;
      }
      
      final articleData = json.decode(await articleFile.readAsString());
      
      return Article(
        id: articleData['id'],
        title: articleData['title'],
        content: articleData['content'],
        fullContent: articleData['fullContent'],
        summary: articleData['summary'],
        url: articleData['url'],
        author: articleData['author'],
        publishedAt: articleData['publishedAt'] != null 
          ? DateTime.parse(articleData['publishedAt']) 
          : null,
        updatedAt: articleData['updatedAt'] != null 
          ? DateTime.parse(articleData['updatedAt']) 
          : null,
        feedId: articleData['feedId'],
        feedTitle: articleData['feedTitle'],
        isRead: articleData['isRead'] ?? false,
        isStarred: articleData['isStarred'] ?? false,
        readAt: articleData['readAt'] != null 
          ? DateTime.parse(articleData['readAt']) 
          : null,
        starredAt: articleData['starredAt'] != null 
          ? DateTime.parse(articleData['starredAt']) 
          : null,
        estimatedReadTime: articleData['estimatedReadTime'] ?? 5,
        wordCount: articleData['wordCount'] ?? 0,
        language: articleData['language'],
        categories: List<String>.from(articleData['categories'] ?? []),
        enclosures: articleData['enclosures'],
        metadata: articleData['metadata'],
      );
    } catch (e) {
      throw Exception('Failed to load offline article: $e');
    }
  }

  // Get all offline articles
  Future<List<Article>> getAllOfflineArticles() async {
    try {
      final articlesDir = await _getArticlesDirectory();
      final files = await articlesDir.list().toList();
      final articles = <Article>[];
      
      for (final file in files) {
        if (file is File && file.path.endsWith('.json')) {
          final articleId = path.basenameWithoutExtension(file.path);
          final article = await loadOfflineArticle(articleId);
          if (article != null) {
            articles.add(article);
          }
        }
      }
      
      return articles;
    } catch (e) {
      throw Exception('Failed to get offline articles: $e');
    }
  }

  // Delete offline article
  Future<void> deleteOfflineArticle(String articleId) async {
    try {
      final articlesDir = await _getArticlesDirectory();
      final articleFile = File(path.join(articlesDir.path, '$articleId.json'));
      
      if (await articleFile.exists()) {
        await articleFile.delete();
      }
      
      // Delete associated images
      final imagesDir = await _getImagesDirectory();
      final imageFiles = await imagesDir.list().where((file) {
        return path.basename(file.path).startsWith(articleId);
      }).toList();
      
      for (final imageFile in imageFiles) {
        if (imageFile is File) {
          await imageFile.delete();
        }
      }
      
      // Update metadata
      await _updateMetadata(articleId, 'deleted');
    } catch (e) {
      throw Exception('Failed to delete offline article: $e');
    }
  }

  // Check if article is available offline
  Future<bool> isArticleOffline(String articleId) async {
    final articlesDir = await _getArticlesDirectory();
    final articleFile = File(path.join(articlesDir.path, '$articleId.json'));
    return await articleFile.exists();
  }

  // Get offline storage size
  Future<int> getOfflineStorageSize() async {
    try {
      final appDir = await _getAppDirectory();
      int totalSize = 0;
      
      if (await appDir.exists()) {
        await for (final entity in appDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
      
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  // Clear all offline data
  Future<void> clearOfflineData() async {
    try {
      final appDir = await _getAppDirectory();
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    } catch (e) {
      throw Exception('Failed to clear offline data: $e');
    }
  }

  // Download image for offline use
  Future<void> _downloadImage(String imageUrl, String articleId) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(imageUrl));
      final response = await request.close();
      final bytes = await _consolidateHttpClientResponseBytes(response);
      
      final imagesDir = await _getImagesDirectory();
      final imageName = '${articleId}_${path.basename(imageUrl)}';
      final imageFile = File(path.join(imagesDir.path, imageName));
      
      await imageFile.writeAsBytes(bytes);
    } catch (e) {
      // Ignore image download errors
    }
  }
  
  // Helper to consolidate response bytes
  Future<Uint8List> _consolidateHttpClientResponseBytes(
    HttpClientResponse response,
  ) async {
    final chunks = <List<int>>[];
    await for (final chunk in response) {
      chunks.add(chunk);
    }
    return Uint8List.fromList(
      chunks.expand((x) => x).toList(),
    );
  }

  // Update metadata
  Future<void> _updateMetadata(String articleId, String action) async {
    try {
      final appDir = await _getAppDirectory();
      final metadataFile = File(path.join(appDir.path, _metadataFile));
      
      Map<String, dynamic> metadata = {};
      if (await metadataFile.exists()) {
        metadata = json.decode(await metadataFile.readAsString());
      }
      
      metadata['lastUpdated'] = DateTime.now().toIso8601String();
      metadata['articles'] ??= {};
      metadata['articles'][articleId] = {
        'action': action,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      await metadataFile.writeAsString(json.encode(metadata));
    } catch (e) {
      // Ignore metadata update errors
    }
  }

  // Get offline statistics
  Future<OfflineStatistics> getOfflineStatistics() async {
    try {
      final articles = await getAllOfflineArticles();
      final storageSize = await getOfflineStorageSize();
      
      final appDir = await _getAppDirectory();
      final metadataFile = File(path.join(appDir.path, _metadataFile));
      
      DateTime? lastSync;
      if (await metadataFile.exists()) {
        final metadata = json.decode(await metadataFile.readAsString());
        if (metadata['lastUpdated'] != null) {
          lastSync = DateTime.parse(metadata['lastUpdated']);
        }
      }
      
      return OfflineStatistics(
        articleCount: articles.length,
        storageSize: storageSize,
        lastSync: lastSync,
      );
    } catch (e) {
      return OfflineStatistics(
        articleCount: 0,
        storageSize: 0,
        lastSync: null,
      );
    }
  }
}

class OfflineStatistics {
  final int articleCount;
  final int storageSize;
  final DateTime? lastSync;

  OfflineStatistics({
    required this.articleCount,
    required this.storageSize,
    this.lastSync,
  });

  String get formattedSize {
    if (storageSize < 1024) {
      return '$storageSize B';
    } else if (storageSize < 1024 * 1024) {
      return '${(storageSize / 1024).toStringAsFixed(1)} KB';
    } else if (storageSize < 1024 * 1024 * 1024) {
      return '${(storageSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(storageSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}