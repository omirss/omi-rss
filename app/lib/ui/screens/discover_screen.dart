import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../animations/particle_background.dart';
import '../../providers/feed_provider.dart';
import '../../providers/database_provider.dart';
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
    final tokens = GlassTheme.colorsOf(context);
    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: Stack(
        children: [
          // Particle background
          ParticleBackground(
            particleCount: 100,
            backgroundGradient: tokens.backgroundGradient,
            child: const SizedBox.expand(),
          ),

          // Main content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(GlassSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GlassButton(
                            icon: Icons.arrow_back,
                            onPressed: () => Navigator.pop(context),
                            variant: GlassButtonVariant.icon,
                          ),
                          const SizedBox(width: GlassSpacing.lg),
                          Text(
                            'Discover Feeds',
                            style: GlassTypeScale.display
                                .copyWith(color: tokens.textHigh),
                          ),
                        ],
                      ),
                      const SizedBox(height: GlassSpacing.sm),
                      Text(
                        'Find and subscribe to popular RSS feeds',
                        style: GlassTypeScale.body
                            .copyWith(color: tokens.textMedium),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0),

                // Tabs
                Container(
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: GlassSpacing.xl),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: LinearGradient(
                        colors: tokens.primaryGradient,
                      ),
                    ),
                    labelColor: tokens.textHigh,
                    unselectedLabelColor: tokens.textMedium,
                    dividerColor: Colors.transparent,
                    indicatorColor: tokens.primary,
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
                  margin: const EdgeInsets.symmetric(vertical: GlassSpacing.lg),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: GlassSpacing.xl),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = _selectedCategory == category;

                      return Padding(
                        padding: const EdgeInsets.only(right: GlassSpacing.md),
                        child: FilterChip(
                          label: Text(category),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategory = category;
                            });
                          },
                          backgroundColor: tokens.glassFill,
                          selectedColor: tokens.accentSoft,
                          checkmarkColor: tokens.accent,
                          labelStyle: GlassTypeScale.label.copyWith(
                            color:
                                isSelected ? tokens.textHigh : tokens.textMedium,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(GlassRadii.lg),
                            side: BorderSide(
                              color: isSelected
                                  ? tokens.accent
                                  : tokens.glassStroke,
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
    final tokens = GlassTheme.colorsOf(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: GlassSpacing.xl),
      itemCount: feeds.length,
      itemBuilder: (context, index) {
        final feed = feeds[index];

        return GlassCard(
          margin: const EdgeInsets.only(bottom: GlassSpacing.lg),
          child: ListTile(
            contentPadding: const EdgeInsets.all(GlassSpacing.lg),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GlassRadii.md),
                color: tokens.accentSoft,
              ),
              child: feed.imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(GlassRadii.md),
                    child: Image.network(
                      feed.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.rss_feed,
                          color: tokens.accent,
                        );
                      },
                    ),
                  )
                : Icon(
                    Icons.rss_feed,
                    color: tokens.accent,
                  ),
            ),
            title: Text(
              feed.title,
              style: GlassTypeScale.body.copyWith(
                fontWeight: FontWeight.w700,
                color: tokens.textHigh,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: GlassSpacing.xs),
                Text(
                  feed.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GlassTypeScale.label
                      .copyWith(color: tokens.textMedium),
                ),
                const SizedBox(height: GlassSpacing.sm),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: GlassSpacing.sm, vertical: GlassSpacing.xs),
                      decoration: BoxDecoration(
                        color: tokens.glassFill,
                        borderRadius: BorderRadius.circular(GlassRadii.md),
                      ),
                      child: Text(
                        feed.category,
                        style: GlassTypeScale.caption
                            .copyWith(color: tokens.textMedium),
                      ),
                    ),
                    const SizedBox(width: GlassSpacing.md),
                    Icon(
                      Icons.people,
                      size: 16,
                      color: tokens.textLow,
                    ),
                    const SizedBox(width: GlassSpacing.xs),
                    Text(
                      '${_formatNumber(feed.subscribers)} subscribers',
                      style: GlassTypeScale.caption
                          .copyWith(color: tokens.textLow),
                    ),
                  ],
                ),
              ],
            ),
            trailing: Consumer(
              builder: (context, ref, child) {
                final feeds = ref.watch(feedsProvider).value ?? const <Feed>[];
                final isSubscribed = feeds.any((f) => f.url == feed.url);

                return GlassButton(
                  onPressed: () async {
                    if (!isSubscribed) {
                      try {
                        final feedService = ref.read(feedServiceProvider);
                        final database = ref.read(databaseProvider);
                        final newFeed =
                            await feedService.subscribeFeed(feed.url);
                        await database.feedDao.insertFeed(newFeed);
                        final refreshResult =
                            await feedService.refreshFeed(newFeed);
                        if (refreshResult.newArticles.isNotEmpty) {
                          await database.articleDao
                              .insertArticles(refreshResult.newArticles);
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Subscribed to ${feed.title}'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('Failed to subscribe: $e'),
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: Text(isSubscribed ? 'Subscribed' : 'Subscribe'),
                  variant: isSubscribed
                      ? GlassButtonVariant.secondary
                      : GlassButtonVariant.primary,
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