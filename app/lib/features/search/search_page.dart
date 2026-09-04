import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import '../../ui/glass_theme.dart';
import '../../ui/tokens/glass_tokens.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/glass_text_field.dart';
import '../../ui/components/glass_button.dart';
import '../../ui/components/empty_state.dart';
import '../../ui/components/error_state.dart';
import '../../ui/components/skeleton.dart';
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

  GlassColorTokens get _tokens => GlassTheme.colorsOf(context);

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final suggestions = ref.watch(searchSuggestionsProvider);

    return Scaffold(
      backgroundColor: GlassTheme.colorsOf(context).bgBase,
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
    final tokens = _tokens;
    return GlassContainer(
      margin: const EdgeInsets.all(GlassSpacing.lg),
      padding: const EdgeInsets.all(GlassSpacing.lg),
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
              const SizedBox(width: GlassSpacing.sm),

              // Search field
              Expanded(
                child: GlassTextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  hintText: 'Search articles, feeds, annotations...',
                  prefixIcon: Icons.search,
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: tokens.textLow),
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
              const SizedBox(width: GlassSpacing.sm),

              // Filter button
              GlassButton(
                icon: Icons.filter_list,
                onPressed: () => _showFilterSheet(context),
                variant: GlassButtonVariant.icon,
              ),
            ],
          ),

          // Search options
          if (state.query.isNotEmpty) ...[
            const SizedBox(height: GlassSpacing.md),
            _buildSearchOptions(state),
          ],

          // Active filters
          if (state.hasActiveFilters) ...[
            const SizedBox(height: GlassSpacing.md),
            _buildActiveFilters(state),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchOptions(SearchState state) {
    final tokens = _tokens;
    return Wrap(
      spacing: GlassSpacing.sm,
      children: [
        _buildOptionChip(
          label: 'Semantic',
          selected: state.options.semanticSearch,
          onSelected: (_) =>
              ref.read(searchProvider.notifier).toggleSemanticSearch(),
        ),
        _buildOptionChip(
          label: 'Fuzzy',
          selected: state.options.fuzzySearch,
          onSelected: (_) =>
              ref.read(searchProvider.notifier).toggleFuzzySearch(),
        ),
        // Sort by dropdown
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: GlassSpacing.md),
          decoration: BoxDecoration(
            color: tokens.glassFill,
            borderRadius: BorderRadius.circular(GlassRadii.md),
            border: Border.all(color: tokens.glassStroke),
          ),
          child: DropdownButton<SearchSortBy>(
            value: state.options.sortBy,
            underline: const SizedBox(),
            icon: Icon(Icons.arrow_drop_down,
                color: tokens.textMedium, size: 20),
            style: GlassTypeScale.label.copyWith(color: tokens.textHigh),
            dropdownColor: tokens.isDark ? tokens.bgBase : tokens.bgBase,
            items: SearchSortBy.values
                .map((sort) => DropdownMenuItem(
                      value: sort,
                      child: Text(_getSortLabel(sort)),
                    ))
                .toList(),
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

  Widget _buildOptionChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final tokens = _tokens;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      backgroundColor: tokens.glassFill,
      side: BorderSide(color: tokens.glassStroke),
      selectedColor: tokens.accentSoft,
      checkmarkColor: tokens.accent,
      labelStyle: GlassTypeScale.caption.copyWith(
        color: selected ? tokens.textHigh : tokens.textMedium,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassRadii.md),
      ),
    );
  }

  Widget _buildActiveFilters(SearchState state) {
    final tokens = _tokens;
    Widget filterChip(String label, VoidCallback onDeleted) {
      return Chip(
        label: Text(label),
        onDeleted: onDeleted,
        deleteIconColor: tokens.textMedium,
        labelStyle: GlassTypeScale.caption.copyWith(color: tokens.textHigh),
        backgroundColor: tokens.glassFill,
        side: BorderSide(color: tokens.glassStroke),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassRadii.md),
        ),
      );
    }

    return Wrap(
      spacing: GlassSpacing.sm,
      runSpacing: GlassSpacing.sm,
      children: [
        if (state.filters.isRead != null)
          filterChip(
            state.filters.isRead! ? 'Read' : 'Unread',
            () => ref.read(searchProvider.notifier).clearReadFilter(),
          ),
        if (state.filters.isStarred != null)
          filterChip(
            'Starred',
            () => ref.read(searchProvider.notifier).clearStarredFilter(),
          ),
        if (state.filters.dateFrom != null || state.filters.dateTo != null)
          filterChip(
            _getDateRangeLabel(state.filters.dateFrom, state.filters.dateTo),
            () => ref.read(searchProvider.notifier).clearDateFilter(),
          ),
        if (state.filters.feedIds?.isNotEmpty ?? false)
          filterChip(
            '${state.filters.feedIds!.length} feeds',
            () => ref.read(searchProvider.notifier).clearFeedFilter(),
          ),
      ],
    );
  }

  Widget _buildSuggestions(AsyncValue<List<String>> suggestions) {
    final tokens = _tokens;
    return suggestions.when(
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(title: 'Start typing to search');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(GlassSpacing.lg),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final suggestion = items[index];
            return GlassContainer(
              margin: const EdgeInsets.only(bottom: GlassSpacing.sm),
              child: ListTile(
                leading: Icon(Icons.history, color: tokens.textLow),
                title: Text(
                  suggestion,
                  style:
                      GlassTypeScale.body.copyWith(color: tokens.textHigh),
                ),
                onTap: () {
                  _searchController.text = suggestion;
                  ref.read(searchProvider.notifier).search(suggestion);
                },
                trailing: IconButton(
                  icon: Icon(Icons.north_west, color: tokens.textLow),
                  onPressed: () {
                    _searchController.text = suggestion;
                  },
                ),
              ),
            );
          },
        );
      },
      loading: () => const GlassSkeletonList(itemCount: 4),
      error: (_, __) => ErrorState(
        error: 'Failed to load suggestions',
        onRetry: () => ref.invalidate(searchSuggestionsProvider),
      ),
    );
  }

  Widget _buildSearchResults(SearchState state) {
    final tokens = _tokens;
    if (state.isLoading && state.results.isEmpty) {
      return const GlassSkeletonList();
    }

    if (state.error != null) {
      return ErrorState(
        error: state.error!,
        title: 'Search failed',
        onRetry: () => ref
            .read(searchProvider.notifier)
            .search(_searchController.text),
      );
    }

    if (state.results.isEmpty && state.query.isNotEmpty && !state.isLoading) {
      return EmptyState(
        title: 'No results found for "${state.query}"',
        subtitle: 'Try different keywords or adjust your filters',
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Results count
        if (state.results.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(GlassSpacing.lg, 0, GlassSpacing.lg, GlassSpacing.sm),
              child: Text(
                '${state.totalResults} results',
                style: GlassTypeScale.label
                    .copyWith(color: tokens.textMedium),
              ),
            ),
          ),

        // Search results
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: GlassSpacing.lg),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == state.results.length) {
                  return state.hasMore
                      ? const Padding(
                          padding: EdgeInsets.all(GlassSpacing.lg),
                          child: Center(
                            child: CircularProgressIndicator(),
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
