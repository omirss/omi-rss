import 'package:dio/dio.dart';

// Search result model
class SearchResult {
  final String id;
  final SearchResultType type;
  final String title;
  final String snippet;
  final double score;
  final Map<String, dynamic> metadata;
  final List<TextHighlight> highlights;
  
  SearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.snippet,
    required this.score,
    required this.metadata,
    required this.highlights,
  });
  
  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      id: json['id'],
      type: SearchResultType.values.firstWhere(
        (t) => t.toString().split('.').last == json['type'],
        orElse: () => SearchResultType.article,
      ),
      title: json['title'],
      snippet: json['snippet'],
      score: json['score'].toDouble(),
      metadata: json['metadata'],
      highlights: (json['highlights'] as List)
        .map((h) => TextHighlight.fromJson(h))
        .toList(),
    );
  }
}

enum SearchResultType {
  article,
  feed,
  highlight,
  annotation,
}

class TextHighlight {
  final String field;
  final List<String> snippets;
  final List<HighlightPosition> positions;
  
  TextHighlight({
    required this.field,
    required this.snippets,
    required this.positions,
  });
  
  factory TextHighlight.fromJson(Map<String, dynamic> json) {
    return TextHighlight(
      field: json['field'],
      snippets: List<String>.from(json['snippets']),
      positions: (json['positions'] as List)
        .map((p) => HighlightPosition.fromJson(p))
        .toList(),
    );
  }
}

class HighlightPosition {
  final int start;
  final int end;
  
  HighlightPosition({required this.start, required this.end});
  
  factory HighlightPosition.fromJson(Map<String, dynamic> json) {
    return HighlightPosition(
      start: json['start'],
      end: json['end'],
    );
  }
}

// Search filters
class SearchFilters {
  final List<String>? feedIds;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool? isRead;
  final bool? isStarred;
  final bool? hasAnnotations;
  final List<String>? categories;
  final double? minScore;
  
  SearchFilters({
    this.feedIds,
    this.dateFrom,
    this.dateTo,
    this.isRead,
    this.isStarred,
    this.hasAnnotations,
    this.categories,
    this.minScore,
  });
  
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (feedIds != null) json['feedIds'] = feedIds;
    if (dateFrom != null) json['dateFrom'] = dateFrom!.toIso8601String();
    if (dateTo != null) json['dateTo'] = dateTo!.toIso8601String();
    if (isRead != null) json['isRead'] = isRead;
    if (isStarred != null) json['isStarred'] = isStarred;
    if (hasAnnotations != null) json['hasAnnotations'] = hasAnnotations;
    if (categories != null) json['categories'] = categories;
    if (minScore != null) json['minScore'] = minScore;
    return json;
  }
}

// Search options
class SearchOptions {
  final int limit;
  final int offset;
  final bool includeContent;
  final bool semanticSearch;
  final bool fuzzySearch;
  final List<String>? fields;
  final SearchSortBy sortBy;
  final SortOrder sortOrder;
  
  SearchOptions({
    this.limit = 20,
    this.offset = 0,
    this.includeContent = false,
    this.semanticSearch = true,
    this.fuzzySearch = true,
    this.fields,
    this.sortBy = SearchSortBy.relevance,
    this.sortOrder = SortOrder.desc,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'limit': limit,
      'offset': offset,
      'includeContent': includeContent,
      'semanticSearch': semanticSearch,
      'fuzzySearch': fuzzySearch,
      'fields': fields,
      'sortBy': sortBy.toString().split('.').last,
      'sortOrder': sortOrder.toString().split('.').last,
    };
  }
}

enum SearchSortBy {
  relevance,
  date,
  title,
}

enum SortOrder {
  asc,
  desc,
}

// Search service
class SearchService {
  final Dio _dio;
  final String baseUrl;

  SearchService({
    required this.baseUrl,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  // Search articles
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters? filters,
    SearchOptions? options,
  }) async {
    try {
      final limit = options?.limit ?? 20;
      final offset = options?.offset ?? 0;
      final queryParams = <String, dynamic>{
        'search': query,
        'limit': limit,
        'page': (offset ~/ limit) + 1,
        if (filters?.isRead != null) 'isRead': filters!.isRead.toString(),
        if (filters?.isStarred != null) 'isStarred': filters!.isStarred.toString(),
      };

      final response = await _dio.get(
        '$baseUrl/articles',
        queryParameters: queryParams,
      );

      final articles = (response.data['articles'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();

      return articles.map((article) {
        return SearchResult(
          id: article['id'] as String,
          type: SearchResultType.article,
          title: (article['title'] as String?) ?? '',
          snippet: (article['summary'] as String?) ?? '',
          score: 0,
          metadata: {
            if (article['feedId'] != null) 'feedId': article['feedId'],
            if (article['feedTitle'] != null) 'feedTitle': article['feedTitle'],
            if (article['url'] != null) 'url': article['url'],
            if (article['publishedAt'] != null)
              'publishedAt': article['publishedAt'],
          },
          highlights: const [],
        );
      }).toList();
    } catch (e) {
      throw Exception('Search failed: $e');
    }
  }
}

// Search history manager
class SearchHistoryManager {
  final List<SearchHistoryItem> _history = [];
  static const int maxHistoryItems = 50;
  
  List<SearchHistoryItem> get history => List.unmodifiable(_history);
  
  void addSearchQuery(String query, int resultCount) {
    // Remove duplicate if exists
    _history.removeWhere((item) => item.query == query);
    
    // Add to beginning
    _history.insert(0, SearchHistoryItem(
      query: query,
      timestamp: DateTime.now(),
      resultCount: resultCount,
    ));
    
    // Limit history size
    if (_history.length > maxHistoryItems) {
      _history.removeRange(maxHistoryItems, _history.length);
    }
  }
  
  void removeFromHistory(String query) {
    _history.removeWhere((item) => item.query == query);
  }
  
  void clearHistory() {
    _history.clear();
  }
  
  List<String> getSuggestions(String partial) {
    final lowerPartial = partial.toLowerCase();
    return _history
      .where((item) => item.query.toLowerCase().contains(lowerPartial))
      .map((item) => item.query)
      .take(5)
      .toList();
  }
}

class SearchHistoryItem {
  final String query;
  final DateTime timestamp;
  final int resultCount;
  
  SearchHistoryItem({
    required this.query,
    required this.timestamp,
    required this.resultCount,
  });
}