import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../features/search/search_service.dart';
import '../services/api_service.dart';
import 'database_provider.dart';

// Search service provider
final searchServiceProvider = Provider<SearchService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return SearchService(
    baseUrl: apiService.baseUrl,
    dio: apiService.dio,
  );
});

// Search history provider
final searchHistoryProvider = StateProvider<SearchHistoryManager>((ref) {
  return SearchHistoryManager();
});

// Search state
class SearchState {
  final String query;
  final List<SearchResult> results;
  final bool isLoading;
  final bool isSearching;
  final String? error;
  final SearchFilters filters;
  final SearchOptions options;
  final int totalResults;
  final bool hasMore;
  
  SearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.isSearching = false,
    this.error,
    SearchFilters? filters,
    SearchOptions? options,
    this.totalResults = 0,
    this.hasMore = false,
  }) : filters = filters ?? SearchFilters(),
       options = options ?? SearchOptions();
  
  bool get hasActiveFilters => 
    filters.feedIds != null ||
    filters.dateFrom != null ||
    filters.dateTo != null ||
    filters.isRead != null ||
    filters.isStarred != null ||
    filters.hasAnnotations != null ||
    filters.categories != null ||
    filters.minScore != null;
  
  SearchState copyWith({
    String? query,
    List<SearchResult>? results,
    bool? isLoading,
    bool? isSearching,
    String? error,
    SearchFilters? filters,
    SearchOptions? options,
    int? totalResults,
    bool? hasMore,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      isSearching: isSearching ?? this.isSearching,
      error: error,
      filters: filters ?? this.filters,
      options: options ?? this.options,
      totalResults: totalResults ?? this.totalResults,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

// Search notifier
class SearchNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  final SearchService _searchService;
  final SearchHistoryManager _historyManager;

  SearchNotifier(this._ref, this._searchService, this._historyManager)
      : super(SearchState());

  void updateQuery(String query) {
    state = state.copyWith(
      query: query,
      isSearching: true,
    );
  }

  Future<List<SearchResult>> _searchLocal(String query) async {
    final database = _ref.read(databaseProvider);
    final articles = await database.articleDao.searchArticles(query).first;
    return articles.map((article) {
      return SearchResult(
        id: article.id,
        type: SearchResultType.article,
        title: article.title,
        snippet: article.summary ?? '',
        score: 0,
        metadata: {
          'feedId': article.feedId,
          if (article.feedTitle != null) 'feedTitle': article.feedTitle,
          'url': article.url,
          if (article.publishedAt != null)
            'publishedAt': article.publishedAt!.toIso8601String(),
        },
        highlights: const [],
      );
    }).toList();
  }

  Future<void> search(String query) async {
    if (query.isEmpty) return;

    state = state.copyWith(
      query: query,
      isLoading: true,
      error: null,
      results: [],
      options: state.options.copyWith(offset: 0),
    );

    try {
      final results = ApiConfig.hasServer
          ? await _searchService.search(
              query,
              filters: state.filters,
              options: state.options,
            )
          : await _searchLocal(query);

      state = state.copyWith(
        results: results,
        isLoading: false,
        totalResults: results.length, // In real app, this would come from server
        hasMore: results.length >= state.options.limit,
      );

      // Add to history
      _historyManager.addSearchQuery(query, results.length);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final results = ApiConfig.hasServer
          ? await _searchService.search(
              state.query,
              filters: state.filters,
              options: state.options.copyWith(
                offset: state.results.length,
              ),
            )
          : const <SearchResult>[];

      state = state.copyWith(
        results: [...state.results, ...results],
        isLoading: false,
        hasMore: results.length >= state.options.limit,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }
  
  void clearSearch() {
    state = SearchState();
  }
  
  void updateFilters(SearchFilters filters) {
    state = state.copyWith(filters: filters);
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }
  
  void clearReadFilter() {
    state = state.copyWith(
      filters: SearchFilters(
        feedIds: state.filters.feedIds,
        dateFrom: state.filters.dateFrom,
        dateTo: state.filters.dateTo,
        isRead: null,
        isStarred: state.filters.isStarred,
        hasAnnotations: state.filters.hasAnnotations,
        categories: state.filters.categories,
        minScore: state.filters.minScore,
      ),
    );
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }
  
  void clearStarredFilter() {
    state = state.copyWith(
      filters: SearchFilters(
        feedIds: state.filters.feedIds,
        dateFrom: state.filters.dateFrom,
        dateTo: state.filters.dateTo,
        isRead: state.filters.isRead,
        isStarred: null,
        hasAnnotations: state.filters.hasAnnotations,
        categories: state.filters.categories,
        minScore: state.filters.minScore,
      ),
    );
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }
  
  void clearDateFilter() {
    state = state.copyWith(
      filters: SearchFilters(
        feedIds: state.filters.feedIds,
        dateFrom: null,
        dateTo: null,
        isRead: state.filters.isRead,
        isStarred: state.filters.isStarred,
        hasAnnotations: state.filters.hasAnnotations,
        categories: state.filters.categories,
        minScore: state.filters.minScore,
      ),
    );
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }
  
  void clearFeedFilter() {
    state = state.copyWith(
      filters: SearchFilters(
        feedIds: null,
        dateFrom: state.filters.dateFrom,
        dateTo: state.filters.dateTo,
        isRead: state.filters.isRead,
        isStarred: state.filters.isStarred,
        hasAnnotations: state.filters.hasAnnotations,
        categories: state.filters.categories,
        minScore: state.filters.minScore,
      ),
    );
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }
  
  void toggleSemanticSearch() {
    state = state.copyWith(
      options: state.options.copyWith(
        semanticSearch: !state.options.semanticSearch,
      ),
    );
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }
  
  void toggleFuzzySearch() {
    state = state.copyWith(
      options: state.options.copyWith(
        fuzzySearch: !state.options.fuzzySearch,
      ),
    );
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }
  
  void setSortBy(SearchSortBy sortBy) {
    state = state.copyWith(
      options: state.options.copyWith(sortBy: sortBy),
    );
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }
}

// Search provider
final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final searchService = ref.watch(searchServiceProvider);
  final historyManager = ref.watch(searchHistoryProvider);
  return SearchNotifier(ref, searchService, historyManager);
});

// Search suggestions provider
final searchSuggestionsProvider = FutureProvider<List<String>>((ref) async {
  final searchState = ref.watch(searchProvider);
  final historyManager = ref.watch(searchHistoryProvider);

  if (searchState.query.isEmpty) {
    // Return recent searches
    return historyManager.history.take(5).map((item) => item.query).toList();
  }

  return historyManager.getSuggestions(searchState.query);
});

// Extension to make options copyable
extension _SearchOptionsCopyWith on SearchOptions {
  SearchOptions copyWith({
    int? limit,
    int? offset,
    bool? includeContent,
    bool? semanticSearch,
    bool? fuzzySearch,
    List<String>? fields,
    SearchSortBy? sortBy,
    SortOrder? sortOrder,
  }) {
    return SearchOptions(
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      includeContent: includeContent ?? this.includeContent,
      semanticSearch: semanticSearch ?? this.semanticSearch,
      fuzzySearch: fuzzySearch ?? this.fuzzySearch,
      fields: fields ?? this.fields,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}