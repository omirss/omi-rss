import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import '../../ui/glass_theme.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_text_field.dart';
import '../../ui/components/glass_button.dart';
import '../../ui/components/glass_dialog.dart';
import 'search_service.dart';
import 'search_result_card.dart';
import 'search_filters_sheet.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _showFilters = false;
  
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _focusNode.requestFocus();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      // Load more results
      ref.read(searchProvider.notifier).loadMore();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final suggestions = ref.watch(searchSuggestionsProvider);
    
    return Scaffold(
      backgroundColor: GlassTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Search header
            _buildSearchHeader(context, searchState),
            
            // Search results or suggestions
            Expanded(
              child: searchState.isSearching && searchState.query.isEmpty
                ? _buildSuggestions(suggestions)
                : _buildSearchResults(searchState),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSearchHeader(BuildContext context, SearchState state) {
    return GlassContainer(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              // Back button
              GlassButton(
                icon: Icons.arrow_back,
                onPressed: () => Navigator.pop(context),
                variant: GlassButtonVariant.icon,
              ),
              const SizedBox(width: 8),
              
              // Search field
              Expanded(
                child: GlassTextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  hintText: 'Search articles, feeds, annotations...',
                  prefixIcon: Icons.search,
                  suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchProvider.notifier).clearSearch();
                        },
                      )
                    : null,
                  onChanged: (value) {
                    ref.read(searchProvider.notifier).updateQuery(value);
                  },
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      ref.read(searchProvider.notifier).search(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              
              // Filter button
              GlassButton(
                icon: Icons.filter_list,
                onPressed: () => _showFilterSheet(context),
                variant: GlassButtonVariant.icon,
                isSelected: state.hasActiveFilters,
              ),
            ],
          ),
          
          // Search options
          if (state.query.isNotEmpty) ...[  
            const SizedBox(height: 12),
            _buildSearchOptions(state),
          ],
          
          // Active filters
          if (state.hasActiveFilters) ...[  
            const SizedBox(height: 12),
            _buildActiveFilters(state),
          ],
        ],
      ),
    );
  }
  
  Widget _buildSearchOptions(SearchState state) {
    return Wrap(
      spacing: 8,
      children: [
        FilterChip(
          label: const Text('Semantic'),
          selected: state.options.semanticSearch,
          onSelected: (selected) {
            ref.read(searchProvider.notifier).toggleSemanticSearch();
          },
          selectedColor: GlassTheme.primaryColor.withOpacity(0.3),
          labelStyle: TextStyle(
            color: state.options.semanticSearch ? Colors.white : Colors.white70,
          ),
        ),
        FilterChip(
          label: const Text('Fuzzy'),
          selected: state.options.fuzzySearch,
          onSelected: (selected) {
            ref.read(searchProvider.notifier).toggleFuzzySearch();
          },
          selectedColor: GlassTheme.primaryColor.withOpacity(0.3),
          labelStyle: TextStyle(
            color: state.options.fuzzySearch ? Colors.white : Colors.white70,
          ),
        ),
        // Sort by dropdown
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButton<SearchSortBy>(
            value: state.options.sortBy,
            underline: const SizedBox(),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            dropdownColor: GlassTheme.surfaceColor,
            items: SearchSortBy.values.map((sort) => 
              DropdownMenuItem(
                value: sort,
                child: Text(_getSortLabel(sort)),
              ),
            ).toList(),
            onChanged: (value) {
              if (value != null) {
                ref.read(searchProvider.notifier).setSortBy(value);
              }
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildActiveFilters(SearchState state) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (state.filters.isRead != null)
          Chip(
            label: Text(state.filters.isRead! ? 'Read' : 'Unread'),
            onDeleted: () => ref.read(searchProvider.notifier).clearReadFilter(),
            deleteIconColor: Colors.white70,
            labelStyle: const TextStyle(color: Colors.white),
            backgroundColor: Colors.white.withOpacity(0.2),
          ),
        if (state.filters.isStarred != null)
          Chip(
            label: const Text('Starred'),
            onDeleted: () => ref.read(searchProvider.notifier).clearStarredFilter(),
            deleteIconColor: Colors.white70,
            labelStyle: const TextStyle(color: Colors.white),
            backgroundColor: Colors.white.withOpacity(0.2),
          ),
        if (state.filters.dateFrom != null || state.filters.dateTo != null)
          Chip(
            label: Text(_getDateRangeLabel(state.filters.dateFrom, state.filters.dateTo)),
            onDeleted: () => ref.read(searchProvider.notifier).clearDateFilter(),
            deleteIconColor: Colors.white70,
            labelStyle: const TextStyle(color: Colors.white),
            backgroundColor: Colors.white.withOpacity(0.2),
          ),
        if (state.filters.feedIds?.isNotEmpty ?? false)
          Chip(
            label: Text('${state.filters.feedIds!.length} feeds'),
            onDeleted: () => ref.read(searchProvider.notifier).clearFeedFilter(),
            deleteIconColor: Colors.white70,
            labelStyle: const TextStyle(color: Colors.white),
            backgroundColor: Colors.white.withOpacity(0.2),
          ),
      ],
    );
  }
  
  Widget _buildSuggestions(AsyncValue<List<String>> suggestions) {
    return suggestions.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState('Start typing to search');
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final suggestion = items[index];
            return GlassContainer(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.history, color: Colors.white54),
                title: Text(
                  suggestion,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _searchController.text = suggestion;
                  ref.read(searchProvider.notifier).search(suggestion);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.north_west, color: Colors.white54),
                  onPressed: () {
                    _searchController.text = suggestion;
                  },
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      error: (_, __) => _buildEmptyState('Failed to load suggestions'),
    );
  }
  
  Widget _buildSearchResults(SearchState state) {
    if (state.isLoading && state.results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    
    if (state.error != null) {
      return _buildErrorState(state.error!);
    }
    
    if (state.results.isEmpty && state.query.isNotEmpty && !state.isLoading) {
      return _buildEmptyState('No results found for "${state.query}"');
    }
    
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Results count
        if (state.results.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${state.totalResults} results',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            ),
          ),
        
        // Search results
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == state.results.length) {
                  return state.hasMore
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      )
                    : const SizedBox.shrink();
                }
                
                final result = state.results[index];
                return SearchResultCard(
                  result: result,
                  onTap: () => _onResultTap(context, result),
                );
              },
              childCount: state.results.length + (state.hasMore ? 1 : 0),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'Search failed',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GlassButton(
            text: 'Retry',
            onPressed: () {
              ref.read(searchProvider.notifier).search(_searchController.text);
            },
            variant: GlassButtonVariant.elevated,
          ),
        ],
      ),
    );
  }
  
  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const SearchFiltersSheet(),
    );
  }
  
  void _onResultTap(BuildContext context, SearchResult result) {
    // Navigate to appropriate page based on result type
    switch (result.type) {
      case SearchResultType.article:
        // Navigate to article page
        break;
      case SearchResultType.feed:
        // Navigate to feed page
        break;
      case SearchResultType.highlight:
      case SearchResultType.annotation:
        // Navigate to article with highlight/annotation
        break;
    }
  }
  
  String _getSortLabel(SearchSortBy sort) {
    switch (sort) {
      case SearchSortBy.relevance:
        return 'Relevance';
      case SearchSortBy.date:
        return 'Date';
      case SearchSortBy.title:
        return 'Title';
    }
  }
  
  String _getDateRangeLabel(DateTime? from, DateTime? to) {
    if (from != null && to != null) {
      return '${_formatDate(from)} - ${_formatDate(to)}';
    } else if (from != null) {
      return 'From ${_formatDate(from)}';
    } else if (to != null) {
      return 'Until ${_formatDate(to)}';
    }
    return 'Date range';
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}