import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/models/article.dart';

abstract class TranslationProvider {
  Future<String> translate(String text, String targetLanguage, {String? sourceLanguage});
  Future<String> detectLanguage(String text);
  Future<List<SupportedLanguage>> getSupportedLanguages();
  String get providerName;
}

class SupportedLanguage {
  final String code;
  final String name;
  final String nativeName;
  final bool isRTL;
  
  SupportedLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    this.isRTL = false,
  });
}

// Google Translate API provider
class GoogleTranslateProvider implements TranslationProvider {
  final String apiKey;
  final Dio dio;
  static const String baseUrl = 'https://translation.googleapis.com/language/translate/v2';
  
  GoogleTranslateProvider({
    required this.apiKey,
    Dio? dio,
  }) : dio = dio ?? Dio();
  
  @override
  String get providerName => 'Google Translate';
  
  @override
  Future<String> translate(String text, String targetLanguage, {String? sourceLanguage}) async {
    try {
      final response = await dio.post(
        baseUrl,
        queryParameters: {
          'key': apiKey,
        },
        data: {
          'q': text,
          'target': targetLanguage,
          if (sourceLanguage != null) 'source': sourceLanguage,
          'format': 'text',
        },
      );
      
      final translations = response.data['data']['translations'] as List;
      if (translations.isNotEmpty) {
        return translations[0]['translatedText'];
      }
      
      throw Exception('No translation returned');
    } catch (e) {
      throw Exception('Failed to translate: $e');
    }
  }
  
  @override
  Future<String> detectLanguage(String text) async {
    try {
      final response = await dio.post(
        '$baseUrl/detect',
        queryParameters: {
          'key': apiKey,
        },
        data: {
          'q': text,
        },
      );
      
      final detections = response.data['data']['detections'] as List;
      if (detections.isNotEmpty && detections[0].isNotEmpty) {
        return detections[0][0]['language'];
      }
      
      return 'unknown';
    } catch (e) {
      throw Exception('Failed to detect language: $e');
    }
  }
  
  @override
  Future<List<SupportedLanguage>> getSupportedLanguages() async {
    try {
      final response = await dio.get(
        '$baseUrl/languages',
        queryParameters: {
          'key': apiKey,
          'target': 'en',
        },
      );
      
      final languages = response.data['data']['languages'] as List;
      
      return languages.map((lang) => SupportedLanguage(
        code: lang['language'],
        name: lang['name'],
        nativeName: lang['name'],
      )).toList();
    } catch (e) {
      throw Exception('Failed to get supported languages: $e');
    }
  }
}

// LibreTranslate provider (self-hosted option)
class LibreTranslateProvider implements TranslationProvider {
  final String baseUrl;
  final String? apiKey;
  final Dio dio;
  
  LibreTranslateProvider({
    required this.baseUrl,
    this.apiKey,
    Dio? dio,
  }) : dio = dio ?? Dio();
  
  @override
  String get providerName => 'LibreTranslate';
  
  @override
  Future<String> translate(String text, String targetLanguage, {String? sourceLanguage}) async {
    try {
      final response = await dio.post(
        '$baseUrl/translate',
        data: {
          'q': text,
          'source': sourceLanguage ?? 'auto',
          'target': targetLanguage,
          if (apiKey != null) 'api_key': apiKey,
        },
      );
      
      return response.data['translatedText'];
    } catch (e) {
      throw Exception('Failed to translate: $e');
    }
  }
  
  @override
  Future<String> detectLanguage(String text) async {
    try {
      final response = await dio.post(
        '$baseUrl/detect',
        data: {
          'q': text,
          if (apiKey != null) 'api_key': apiKey,
        },
      );
      
      final detections = response.data as List;
      if (detections.isNotEmpty) {
        return detections[0]['language'];
      }
      
      return 'unknown';
    } catch (e) {
      throw Exception('Failed to detect language: $e');
    }
  }
  
  @override
  Future<List<SupportedLanguage>> getSupportedLanguages() async {
    try {
      final response = await dio.get('$baseUrl/languages');
      
      final languages = response.data as List;
      
      return languages.map((lang) => SupportedLanguage(
        code: lang['code'],
        name: lang['name'],
        nativeName: lang['name'],
      )).toList();
    } catch (e) {
      throw Exception('Failed to get supported languages: $e');
    }
  }
}

// Translation service
class TranslationService {
  final Map<String, TranslationProvider> _providers = {};
  TranslationProvider? _activeProvider;
  
  void addProvider(String id, TranslationProvider provider) {
    _providers[id] = provider;
    _activeProvider ??= provider;
  }
  
  void removeProvider(String id) {
    _providers.remove(id);
    if (_activeProvider == _providers[id]) {
      _activeProvider = _providers.values.firstOrNull;
    }
  }
  
  void setActiveProvider(String id) {
    _activeProvider = _providers[id];
  }
  
  TranslationProvider? get activeProvider => _activeProvider;
  
  Future<TranslatedArticle> translateArticle(
    Article article,
    String targetLanguage, {
    bool translateTitle = true,
    bool translateContent = true,
    bool translateSummary = true,
  }) async {
    if (_activeProvider == null) {
      throw Exception('No translation provider configured');
    }
    
    String? translatedTitle;
    String? translatedContent;
    String? translatedSummary;
    String? detectedLanguage;
    
    // Detect source language
    final sampleText = article.content ?? article.summary ?? article.title;
    try {
      detectedLanguage = await _activeProvider!.detectLanguage(sampleText);
    } catch (e) {
      // Continue without source language
    }
    
    // Translate title
    if (translateTitle) {
      try {
        translatedTitle = await _activeProvider!.translate(
          article.title,
          targetLanguage,
          sourceLanguage: detectedLanguage,
        );
      } catch (e) {
        // Keep original if translation fails
      }
    }
    
    // Translate content
    if (translateContent && article.content != null) {
      try {
        // Split long content into chunks
        final chunks = _splitIntoChunks(article.content!, 5000);
        final translatedChunks = <String>[];
        
        for (final chunk in chunks) {
          final translated = await _activeProvider!.translate(
            chunk,
            targetLanguage,
            sourceLanguage: detectedLanguage,
          );
          translatedChunks.add(translated);
        }
        
        translatedContent = translatedChunks.join(' ');
      } catch (e) {
        // Keep original if translation fails
      }
    }
    
    // Translate summary
    if (translateSummary && article.summary != null) {
      try {
        translatedSummary = await _activeProvider!.translate(
          article.summary!,
          targetLanguage,
          sourceLanguage: detectedLanguage,
        );
      } catch (e) {
        // Keep original if translation fails
      }
    }
    
    return TranslatedArticle(
      original: article,
      translatedTitle: translatedTitle ?? article.title,
      translatedContent: translatedContent,
      translatedSummary: translatedSummary,
      sourceLanguage: detectedLanguage ?? 'unknown',
      targetLanguage: targetLanguage,
      translationProvider: _activeProvider!.providerName,
      translatedAt: DateTime.now(),
    );
  }
  
  List<String> _splitIntoChunks(String text, int maxLength) {
    if (text.length <= maxLength) {
      return [text];
    }
    
    final chunks = <String>[];
    final sentences = text.split(RegExp(r'[.!?]+'));
    
    String currentChunk = '';
    for (final sentence in sentences) {
      if (currentChunk.length + sentence.length > maxLength && currentChunk.isNotEmpty) {
        chunks.add(currentChunk.trim());
        currentChunk = sentence;
      } else {
        currentChunk += sentence + '. ';
      }
    }
    
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.trim());
    }
    
    return chunks;
  }
  
  Future<List<SupportedLanguage>> getSupportedLanguages() async {
    if (_activeProvider == null) {
      throw Exception('No translation provider configured');
    }
    
    return await _activeProvider!.getSupportedLanguages();
  }
  
  Future<String> detectLanguage(String text) async {
    if (_activeProvider == null) {
      throw Exception('No translation provider configured');
    }
    
    return await _activeProvider!.detectLanguage(text);
  }
}

// Translated article model
class TranslatedArticle {
  final Article original;
  final String translatedTitle;
  final String? translatedContent;
  final String? translatedSummary;
  final String sourceLanguage;
  final String targetLanguage;
  final String translationProvider;
  final DateTime translatedAt;
  
  TranslatedArticle({
    required this.original,
    required this.translatedTitle,
    this.translatedContent,
    this.translatedSummary,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.translationProvider,
    required this.translatedAt,
  });
  
  Article toArticle() {
    return Article(
      id: original.id,
      feedId: original.feedId,
      feedTitle: original.feedTitle,
      title: translatedTitle,
      url: original.url,
      content: translatedContent ?? original.content,
      fullContent: translatedContent ?? original.fullContent,
      summary: translatedSummary ?? original.summary,
      author: original.author,
      publishedAt: original.publishedAt,
      updatedAt: original.updatedAt,
      isRead: original.isRead,
      isStarred: original.isStarred,
      readAt: original.readAt,
      starredAt: original.starredAt,
      estimatedReadTime: original.estimatedReadTime,
      wordCount: original.wordCount,
      language: targetLanguage,
      categories: original.categories,
      enclosures: original.enclosures,
      metadata: {
        ...original.metadata ?? {},
        'translated': true,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'translationProvider': translationProvider,
        'translatedAt': translatedAt.toIso8601String(),
        'originalTitle': original.title,
      },
    );
  }
}

// Translation cache
class TranslationCache {
  final Map<String, TranslatedArticle> _cache = {};
  final int maxCacheSize;
  
  TranslationCache({this.maxCacheSize = 100});
  
  String _getCacheKey(String articleId, String targetLanguage) {
    return '${articleId}_$targetLanguage';
  }
  
  void add(String articleId, String targetLanguage, TranslatedArticle translation) {
    final key = _getCacheKey(articleId, targetLanguage);
    
    // Remove oldest entries if cache is full
    if (_cache.length >= maxCacheSize) {
      final oldest = _cache.entries
          .reduce((a, b) => a.value.translatedAt.isBefore(b.value.translatedAt) ? a : b);
      _cache.remove(oldest.key);
    }
    
    _cache[key] = translation;
  }
  
  TranslatedArticle? get(String articleId, String targetLanguage) {
    final key = _getCacheKey(articleId, targetLanguage);
    return _cache[key];
  }
  
  void clear() {
    _cache.clear();
  }
  
  void remove(String articleId) {
    _cache.removeWhere((key, _) => key.startsWith('${articleId}_'));
  }
}