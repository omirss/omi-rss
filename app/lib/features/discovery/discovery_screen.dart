import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'discovery_service.dart';
import 'widgets/feed_suggestion_card.dart';
import 'widgets/category_filter_chips.dart';
import 'widgets/custom_feed_generator.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;
  String _selectedTimeframe = 'week';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final discoveryService = context.read<DiscoveryService>();
      discoveryService.loadCategories();
      discoveryService.discoverFeeds();
      discoveryService.getTrendingFeeds(timeframe: _selectedTimeframe);
      discoveryService.getRecommendations();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            floating: true,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('Discover Feeds'),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.explore,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Find new feeds to follow',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'For You', icon: Icon(Icons.star)),
                Tab(text: 'Trending', icon: Icon(Icons.trending_up)),
                Tab(text: 'Search', icon: Icon(Icons.search)),
                Tab(text: 'Generate', icon: Icon(Icons.auto_awesome)),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildForYouTab(),
            _buildTrendingTab(),
            _buildSearchTab(),
            _buildGenerateTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildForYouTab() {
    return Consumer<DiscoveryService>(
      builder: (context, service, _) {
        if (service.isLoading && service.suggestions.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (service.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load suggestions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => service.discoverFeeds(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => service.discoverFeeds(
            categories: _selectedCategory != null ? [_selectedCategory!] : null,
          ),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: CategoryFilterChips(
                  categories: service.categories,
                  selectedCategory: _selectedCategory,
                  onCategorySelected: (category) {
                    setState(() {
                      _selectedCategory = category;
                    });
                    service.discoverFeeds(
                      categories: category != null ? [category] : null,
                    );
                  },
                ),
              ),
              if (service.recommendations.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Based on your reading',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => FeedSuggestionCard(
                      suggestion: service.recommendations[index],
                      onSubscribe: () => _subscribeFeed(service.recommendations[index]),
                    ),
                    childCount: service.recommendations.length.clamp(0, 5),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Suggested for you',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => FeedSuggestionCard(
                    suggestion: service.suggestions[index],
                    onSubscribe: () => _subscribeFeed(service.suggestions[index]),
                  ),
                  childCount: service.suggestions.length,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrendingTab() {
    return Consumer<DiscoveryService>(
      builder: (context, service, _) {
        if (service.isLoading && service.trendingFeeds.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: () => service.getTrendingFeeds(
            timeframe: _selectedTimeframe,
            category: _selectedCategory,
          ),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Text(
                        'Trending',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'day', label: Text('Today')),
                          ButtonSegment(value: 'week', label: Text('Week')),
                          ButtonSegment(value: 'month', label: Text('Month')),
                        ],
                        selected: {_selectedTimeframe},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _selectedTimeframe = selection.first;
                          });
                          service.getTrendingFeeds(timeframe: _selectedTimeframe);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => FeedSuggestionCard(
                    suggestion: service.trendingFeeds[index],
                    onSubscribe: () => _subscribeFeed(service.trendingFeeds[index]),
                    showPopularity: true,
                  ),
                  childCount: service.trendingFeeds.length,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchTab() {
    return Consumer<DiscoveryService>(
      builder: (context, service, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search for feeds...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            service.clearSearchResults();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (query) {
                  if (query.isNotEmpty) {
                    service.searchFeeds(query, category: _selectedCategory);
                  }
                },
              ),
            ),
            CategoryFilterChips(
              categories: service.categories,
              selectedCategory: _selectedCategory,
              onCategorySelected: (category) {
                setState(() {
                  _selectedCategory = category;
                });
                if (_searchController.text.isNotEmpty) {
                  service.searchFeeds(
                    _searchController.text,
                    category: category,
                  );
                }
              },
            ),
            Expanded(
              child: service.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : service.searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                    ? 'Enter a search term'
                                    : 'No feeds found',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: service.searchResults.length,
                          itemBuilder: (context, index) => FeedSuggestionCard(
                            suggestion: service.searchResults[index],
                            onSubscribe: () =>
                                _subscribeFeed(service.searchResults[index]),
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGenerateTab() {
    return CustomFeedGenerator(
      onFeedGenerated: (suggestions) {
        // Handle generated feed suggestions
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Text(
                        'Generated Feeds',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) => FeedSuggestionCard(
                      suggestion: suggestions[index],
                      onSubscribe: () => _subscribeFeed(suggestions[index]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _subscribeFeed(FeedSuggestion suggestion) async {
    // TODO: Implement feed subscription
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Subscribed to ${suggestion.title}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // TODO: Implement undo
          },
        ),
      ),
    );
  }
}