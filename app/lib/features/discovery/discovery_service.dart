import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/services/api_service.dart';

class FeedSuggestion {
  final String url;
  final String title;
  final String? description;
  final String? category;
  final String? language;
  final double? popularity;
  final double? relevanceScore;
  final String? reason;
  final String? favicon;
  final DateTime? lastUpdated;

  FeedSuggestion({
    required this.url,
    required this.title,
    this.description,
    this.category,
    this.language,
    this.popularity,
    this.relevanceScore,
    this.reason,
    this.favicon,
    this.lastUpdated,
  });

  factory FeedSuggestion.fromJson(Map<String, dynamic> json) {
    return FeedSuggestion(
      url: json['url'],
      title: json['title'],
      description: json['description'],
      category: json['category'],
      language: json['language'],
      popularity: json['popularity']?.toDouble(),
      relevanceScore: json['relevanceScore']?.toDouble(),
      reason: json['reason'],
      favicon: json['favicon'],
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : null,
    );
  }
}

class FeedCategory {
  final String id;
  final String name;
  final String description;

  FeedCategory({
    required this.id,
    required this.name,
    required this.description,
  });

  factory FeedCategory.fromJson(Map<String, dynamic> json) {
    return FeedCategory(
      id: json['id'],
      name: json['name'],
      description: json['description'],
    );
  }
}

class DiscoveryService extends ChangeNotifier {
  final ApiService _apiService;
  
  List<FeedSuggestion> _suggestions = [];
  List<FeedSuggestion> _searchResults = [];
  List<FeedSuggestion> _trendingFeeds = [];
  List<FeedSuggestion> _recommendations = [];
  List<FeedCategory> _categories = [];
  bool _isLoading = false;
  String? _error;

  List<FeedSuggestion> get suggestions => _suggestions;
  List<FeedSuggestion> get searchResults => _searchResults;
  List<FeedSuggestion> get trendingFeeds => _trendingFeeds;
  List<FeedSuggestion> get recommendations => _recommendations;
  List<FeedCategory> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get error => _error;

  DiscoveryService({required ApiService apiService}) : _apiService = apiService;

  Future<void> discoverFeeds({
    List<String>? categories,
    int? limit,
    String? language,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final queryParams = <String, String>{};
      if (categories != null && categories.isNotEmpty) {
        queryParams['categories'] = categories.join(',');
      }
      if (limit != null) {
        queryParams['limit'] = limit.toString();
      }
      if (language != null) {
        queryParams['language'] = language;
      }

      final response = await _apiService.get(
        '/discovery/discover',
        queryParameters: queryParams,
      );

      _suggestions = (response['data'] as List)
          .map((json) => FeedSuggestion.fromJson(json))
          .toList();
    } catch (e) {
      _error = e.toString();
      debugPrint('Failed to discover feeds: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<FeedSuggestion>> generateCustomFeed(String prompt) async {
    try {
      final response = await _apiService.post(
        '/discovery/generate',
        body: {'prompt': prompt},
      );

      return (response['data'] as List)
          .map((json) => FeedSuggestion.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Failed to generate custom feed: $e');
      throw e;
    }
  }

  Future<void> searchFeeds(String query, {
    String? category,
    String? language,
    int? limit,
  }) async {
    if (query.length < 2) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final queryParams = <String, String>{'q': query};
      if (category != null) queryParams['category'] = category;
      if (language != null) queryParams['language'] = language;
      if (limit != null) queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '/discovery/search',
        queryParameters: queryParams,
      );

      _searchResults = (response['data'] as List)
          .map((json) => FeedSuggestion.fromJson(json))
          .toList();
    } catch (e) {
      _error = e.toString();
      debugPrint('Failed to search feeds: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> getTrendingFeeds({
    String? timeframe,
    String? category,
    int? limit,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final queryParams = <String, String>{};
      if (timeframe != null) queryParams['timeframe'] = timeframe;
      if (category != null) queryParams['category'] = category;
      if (limit != null) queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '/discovery/trending',
        queryParameters: queryParams,
      );

      _trendingFeeds = (response['data'] as List)
          .map((json) => FeedSuggestion.fromJson(json))
          .toList();
    } catch (e) {
      _error = e.toString();
      debugPrint('Failed to get trending feeds: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<FeedSuggestion>> getRelatedFeeds(String feedId, {int? limit}) async {
    try {
      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '/discovery/related/$feedId',
        queryParameters: queryParams,
      );

      return (response['data'] as List)
          .map((json) => FeedSuggestion.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Failed to get related feeds: $e');
      throw e;
    }
  }

  Future<void> getRecommendations({int? limit}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = limit.toString();

      final response = await _apiService.get(
        '/discovery/recommendations',
        queryParameters: queryParams,
      );

      _recommendations = (response['data'] as List)
          .map((json) => FeedSuggestion.fromJson(json))
          .toList();
    } catch (e) {
      _error = e.toString();
      debugPrint('Failed to get recommendations: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCategories() async {
    try {
      final response = await _apiService.get('/discovery/categories');
      
      _categories = (response['data'] as List)
          .map((json) => FeedCategory.fromJson(json))
          .toList();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load categories: $e');
    }
  }

  Future<Map<String, dynamic>> importOPML(String filePath) async {
    try {
      final file = await http.MultipartFile.fromPath('file', filePath);
      
      final response = await _apiService.uploadFile(
        '/discovery/import/opml',
        file,
        fieldName: 'file',
      );

      return response['data'];
    } catch (e) {
      debugPrint('Failed to import OPML: $e');
      throw e;
    }
  }

  Future<String> exportOPML() async {
    try {
      final response = await _apiService.get('/discovery/export/opml');
      return response.toString(); // The response is XML string
    } catch (e) {
      debugPrint('Failed to export OPML: $e');
      throw e;
    }
  }

  Future<Map<String, dynamic>> validateFeedUrl(String url) async {
    try {
      final response = await _apiService.post(
        '/discovery/validate',
        body: {'url': url},
      );

      return response['data'];
    } catch (e) {
      debugPrint('Failed to validate feed URL: $e');
      throw e;
    }
  }

  void clearSearchResults() {
    _searchResults = [];
    notifyListeners();
  }

  void clearSuggestions() {
    _suggestions = [];
    notifyListeners();
  }
}