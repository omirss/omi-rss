import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../components/glass_container.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../animations/particle_background.dart';
import '../../providers/feed_provider.dart';
import '../../core/models/feed.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCategory = 'All';
  
  final List<String> _categories = [
    'All',
    'Technology',
    'Science',
    'Business',
    'Entertainment',
    'Sports',
    'Health',
    'Politics',
    'Gaming',
    'Education',
  ];
  
  final Map<String, List<DiscoverFeed>> _discoverFeeds = {
    'Technology': [
      DiscoverFeed(
        title: 'Hacker News',
        description: 'Links for the intellectually curious, ranked by readers',
        url: 'https://news.ycombinator.com/rss',
        category: 'Technology',
        subscribers: 500000,
        imageUrl: 'https://news.ycombinator.com/favicon.ico',
      ),
      DiscoverFeed(
        title: 'TechCrunch',
        description: 'The latest technology news and information on startups',
        url: 'https://techcrunch.com/feed/',
        category: 'Technology',
        subscribers: 350000,
        imageUrl: 'https://techcrunch.com/wp-content/uploads/2015/02/cropped-cropped-favicon-gradient.png',
      ),
      DiscoverFeed(
        title: 'The Verge',
        description: 'Technology, science, art, and culture',
        url: 'https://www.theverge.com/rss/index.xml',
        category: 'Technology',
        subscribers: 280000,
        imageUrl: 'https://cdn.vox-cdn.com/uploads/chorus_asset/file/7395361/favicon.ico',
      ),
      DiscoverFeed(
        title: 'Ars Technica',
        description: 'The PC enthusiast\'s resource',
        url: 'https://feeds.arstechnica.com/arstechnica/index',
        category: 'Technology',
        subscribers: 220000,
        imageUrl: 'https://cdn.arstechnica.net/favicon.ico',
      ),
    ],
    'Science': [
      DiscoverFeed(
        title: 'Science Daily',
        description: 'Breaking science news and articles on global warming, extrasolar planets, stem cells, and more',
        url: 'https://www.sciencedaily.com/rss/all.xml',
        category: 'Science',
        subscribers: 180000,
        imageUrl: 'https://www.sciencedaily.com/favicon.ico',
      ),
      DiscoverFeed(
        title: 'NASA Breaking News',
        description: 'A RSS news feed containing the latest NASA news articles and press releases',
        url: 'https://www.nasa.gov/rss/dyn/breaking_news.rss',
        category: 'Science',
        subscribers: 150000,
        imageUrl: 'https://www.nasa.gov/favicon.ico',
      ),
      DiscoverFeed(
        title: 'Nature News',
        description: 'The latest science news from Nature',
        url: 'https://www.nature.com/nature.rss',
        category: 'Science',
        subscribers: 120000,
        imageUrl: 'https://www.nature.com/favicon.ico',
      ),
    ],
    'Business': [
      DiscoverFeed(
        title: 'Wall Street Journal',
        description: 'Business and financial news',
        url: 'https://feeds.a.dj.com/rss/WSJcomUSBusiness.xml',
        category: 'Business',
        subscribers: 400000,
        imageUrl: 'https://www.wsj.com/favicon.ico',
      ),
      DiscoverFeed(
        title: 'Financial Times',
        description: 'Global business news and analysis',
        url: 'https://www.ft.com/?format=rss',
        category: 'Business',
        subscribers: 320000,
        imageUrl: 'https://www.ft.com/favicon.ico',
      ),
      DiscoverFeed(
        title: 'Bloomberg',
        description: 'Breaking news on business, finance, and economics',
        url: 'https://feeds.bloomberg.com/markets/news.rss',
        category: 'Business',
        subscribers: 380000,
        imageUrl: 'https://www.bloomberg.com/favicon.ico',
      ),
    ],
    'Entertainment': [
      DiscoverFeed(
        title: 'The Hollywood Reporter',
        description: 'Entertainment news from Hollywood',
        url: 'https://www.hollywoodreporter.com/feed',
        category: 'Entertainment',
        subscribers: 150000,
        imageUrl: 'https://www.hollywoodreporter.com/favicon.ico',
      ),
      DiscoverFeed(
        title: 'Variety',
        description: 'Entertainment news, film reviews, awards, and more',
        url: 'https://variety.com/feed/',
        category: 'Entertainment',
        subscribers: 130000,
        imageUrl: 'https://variety.com/favicon.ico',
      ),
    ],
    'Sports': [
      DiscoverFeed(
        title: 'ESPN',
        description: 'Latest sports news from ESPN',
        url: 'https://www.espn.com/espn/rss/news',
        category: 'Sports',
        subscribers: 450000,
        imageUrl: 'https://www.espn.com/favicon.ico',
      ),
      DiscoverFeed(
        title: 'The Athletic',
        description: 'In-depth sports coverage',
        url: 'https://theathletic.com/rss/feed.rss',
        category: 'Sports',
        subscribers: 200000,
        imageUrl: 'https://theathletic.com/favicon.ico',
      ),
    ],
    'Health': [
      DiscoverFeed(
        title: 'WebMD Health',
        description: 'Medical news and health information',
        url: 'https://rssfeeds.webmd.com/rss/rss.aspx?RSSSource=RSS_PUBLIC',
        category: 'Health',
        subscribers: 180000,
        imageUrl: 'https://www.webmd.com/favicon.ico',
      ),
      DiscoverFeed(
        title: 'Harvard Health',
        description: 'Health information from Harvard Medical School',
        url: 'https://www.health.harvard.edu/blog/feed',
        category: 'Health',
        subscribers: 120000,
        imageUrl: 'https://www.health.harvard.edu/favicon.ico',
      ),
    ],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<DiscoverFeed> get _filteredFeeds {
    if (_selectedCategory == 'All') {
      return _discoverFeeds.values.expand((list) => list).toList()
        ..sort((a, b) => b.subscribers.compareTo(a.subscribers));
    }
    return _discoverFeeds[_selectedCategory] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Particle background
          const ParticleBackground(
            particleCount: 100,
            connectDistance: 150,
            particleSpeed: 0.3,
          ),
          
          // Main content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 16),
                          const Text(
                            'Discover Feeds',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Find and subscribe to popular RSS feeds',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0),
                
                // Tabs
                Container(
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).primaryColor.withOpacity(0.7),
                        ],
                      ),
                    ),
                    tabs: const [
                      Tab(text: 'Popular'),
                      Tab(text: 'Trending'),
                      Tab(text: 'New'),
                    ],
                  ),
                ),
                
                // Category filters
                Container(
                  height: 50,
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = _selectedCategory == category;
                      
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: FilterChip(
                          label: Text(category),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategory = category;
                            });
                          },
                          backgroundColor: Colors.white.withOpacity(0.1),
                          selectedColor: Theme.of(context).primaryColor.withOpacity(0.3),
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected 
                                ? Theme.of(context).primaryColor 
                                : Colors.white.withOpacity(0.2),
                            ),
                          ),
                        ).animate().scale(
                          delay: (index * 50).ms,
                          duration: 300.ms,
                        ),
                      );
                    },
                  ),
                ),
                
                // Feed list
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Popular feeds
                      _buildFeedList(_filteredFeeds),
                      
                      // Trending feeds (mock data for now)
                      _buildFeedList(_filteredFeeds.reversed.toList()),
                      
                      // New feeds (mock data for now)
                      _buildFeedList(_filteredFeeds.take(5).toList()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedList(List<DiscoverFeed> feeds) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: feeds.length,
      itemBuilder: (context, index) {
        final feed = feeds[index];
        
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).primaryColor.withOpacity(0.2),
              ),
              child: feed.imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      feed.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.rss_feed,
                          color: Theme.of(context).primaryColor,
                        );
                      },
                    ),
                  )
                : Icon(
                    Icons.rss_feed,
                    color: Theme.of(context).primaryColor,
                  ),
            ),
            title: Text(
              feed.title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  feed.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        feed.category,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.people,
                      size: 16,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatNumber(feed.subscribers)} subscribers',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: Consumer(
              builder: (context, ref, child) {
                final feeds = ref.watch(feedProvider);
                final isSubscribed = feeds.any((f) => f.url == feed.url);
                
                return GlassButton(
                  onPressed: () async {
                    if (!isSubscribed) {
                      await ref.read(feedProvider.notifier).addFeed(
                        name: feed.title,
                        url: feed.url,
                        categoryId: null,
                      );
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Subscribed to ${feed.title}'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(isSubscribed ? 'Subscribed' : 'Subscribe'),
                  variant: isSubscribed ? GlassButtonVariant.secondary : GlassButtonVariant.primary,
                );
              },
            ),
          ),
        ).animate().fadeIn(
          delay: (index * 100).ms,
          duration: 300.ms,
        ).slideX(
          begin: 0.2,
          end: 0,
          delay: (index * 100).ms,
        );
      },
    );
  }
  
  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toString();
  }
}

class DiscoverFeed {
  final String title;
  final String description;
  final String url;
  final String category;
  final int subscribers;
  final String? imageUrl;

  DiscoverFeed({
    required this.title,
    required this.description,
    required this.url,
    required this.category,
    required this.subscribers,
    this.imageUrl,
  });
}