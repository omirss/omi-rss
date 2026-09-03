import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/glass_theme.dart';
import 'ui/animations/particle_background.dart';
import 'ui/layouts/three_column_layout.dart';
import 'ui/components/glass_container.dart';
import 'ui/components/glass_card.dart';
import 'ui/components/glass_button.dart';
import 'ui/components/glass_text_field.dart';
import 'ui/components/glass_dialog.dart';
import 'ui/components/glass_snack_bar.dart';
import 'ui/components/glass_drawer.dart';
import 'ui/components/glass_tooltip.dart';
import 'ui/screens/extension_popup_screen.dart';
import 'ui/screens/article_reader_screen.dart';
import 'core/services/extension_service.dart';
import 'providers/database_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/api_feed_provider.dart';
import 'providers/opml_provider.dart';
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/sync_screen.dart';
import 'ui/screens/article_reader_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/statistics_screen.dart';
import 'ui/screens/feed_generation_screen.dart';
import 'ui/screens/ai_dashboard_screen.dart';
import 'ui/screens/market_dashboard_screen.dart';
import 'ui/screens/discover_screen.dart';
import 'ui/screens/saved_articles_screen.dart';
import 'features/analytics/analytics_dashboard.dart';
import 'features/search/search_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:html' as html;

// Starred providers for tracking current view
final showStarredProvider = StateProvider<bool>((ref) => false);

void main() {
  runApp(
    const ProviderScope(
      child: RSSGlassmorphismReaderApp(),
    ),
  );
}

class RSSGlassmorphismReaderApp extends ConsumerStatefulWidget {
  const RSSGlassmorphismReaderApp({super.key});

  @override
  ConsumerState<RSSGlassmorphismReaderApp> createState() => _RSSGlassmorphismReaderAppState();
}

class _RSSGlassmorphismReaderAppState extends ConsumerState<RSSGlassmorphismReaderApp> {
  @override
  void initState() {
    super.initState();
    // Initialize extension service if running on web
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(extensionServiceProvider).initialize();
      });
    }
    
    // Initialize database and sample feeds
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ensure database is initialized
      await ref.read(databaseInitializationProvider.future);
      
      // Initialize sample feeds if none exist
      ref.read(initializeSampleFeedsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Check if running as extension popup
    bool isExtensionPopup = false;
    if (kIsWeb) {
      final extensionService = ref.watch(extensionServiceProvider);
      isExtensionPopup = html.window.location.pathname.contains('popup.html') ||
          (extensionService.isRunningInExtension && 
           html.window.innerWidth! <= 400 && 
           html.window.innerHeight! <= 600);
    }

    return MaterialApp(
      title: 'RSS Glassmorphism Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => isExtensionPopup
            ? const ExtensionPopupScreen()
            : const AuthenticationWrapper(),
        '/login': (context) => const GlassTheme(
              data: GlassThemeData.defaultTheme,
              child: LoginScreen(),
            ),
        '/home': (context) => const GlassTheme(
              data: GlassThemeData.defaultTheme,
              child: GlassSnackBarManager(
                child: HomePage(),
              ),
            ),
      },
    );
  }
}

class AuthenticationWrapper extends ConsumerWidget {
  const AuthenticationWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    
    if (authState.isAuthenticated) {
      return const GlassTheme(
        data: GlassThemeData.defaultTheme,
        child: GlassSnackBarManager(
          child: HomePage(),
        ),
      );
    } else {
      return const GlassTheme(
        data: GlassThemeData.defaultTheme,
        child: LoginScreen(),
      );
    }
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  void _showAdvancedSearch(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const GlassTheme(
          data: GlassThemeData.defaultTheme,
          child: SearchPage(),
        ),
      ),
    );
  }
  
  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return 'Unknown time';
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} minutes ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${(difference.inDays / 7).floor()} weeks ago';
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ParticleBackground(
        particleCount: 60,
        backgroundGradient: const [
          Color(0xFF667eea),
          Color(0xFF764ba2),
          Color(0xFFf093fb),
          Color(0xFFf5576c),
        ],
        child: ThreeColumnLayout(
          leftPanel: _buildLeftPanel(),
          middlePanel: _buildMiddlePanel(),
          rightPanel: _buildRightPanel(),
          leftConfig: const ColumnConfig(
            minWidth: 200,
            maxWidth: 400,
            initialWidth: 280,
          ),
          middleConfig: const ColumnConfig(
            minWidth: 300,
            maxWidth: 800,
            initialWidth: 400,
          ),
          rightConfig: const ColumnConfig(
            minWidth: 400,
            maxWidth: double.infinity,
            initialWidth: 600,
          ),
        ),
      ),
    );
  }
  
  Widget _buildLeftPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          // Logo and title with menu button
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GlassButton(
                      icon: Icons.menu,
                      onPressed: () => _showDrawer(context),
                      variant: GlassButtonVariant.icon,
                      width: 40,
                      height: 40,
                    ).glassTooltip('Open menu'),
                    Icon(
                      Icons.rss_feed,
                      color: Colors.white.withOpacity(0.9),
                      size: 48,
                    ),
                    const SizedBox(width: 40), // Balance the layout
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'RSS Reader',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Add feed button
          GlassButton(
            text: 'Add Feed',
            icon: Icons.add,
            onPressed: () => _showAddFeedDialog(context),
            variant: GlassButtonVariant.elevated,
          ),
          const SizedBox(height: 8),
          // Refresh feeds button
          GlassButton(
            text: 'Refresh All',
            icon: Icons.refresh,
            onPressed: () => _refreshAllFeeds(context),
            variant: GlassButtonVariant.outlined,
          ),
          const SizedBox(height: 16),
          // Feed categories
          Expanded(
            child: ListView(
              children: [
                Consumer(
                  builder: (context, ref, child) {
                    final feedsAsync = ref.watch(feedsProvider);
                    final articlesAsync = ref.watch(articlesProvider(ArticleQuery()));
                    final selectedFeedId = ref.watch(selectedFeedProvider);
                    
                    return feedsAsync.when(
                      data: (feeds) {
                        return Column(
                          children: [
                            // All Feeds
                            Consumer(
                              builder: (context, ref, child) {
                                final allArticles = ref.watch(articlesProvider);
                                final unreadCount = allArticles.maybeWhen(
                                  data: (articles) => articles.where((a) => !a.isRead).length,
                                  orElse: () => 0,
                                );
                                return _buildCategoryItem(
                                  'All Feeds', 
                                  Icons.inbox, 
                                  unreadCount, 
                                  selectedFeedId == null && !ref.watch(showStarredProvider),
                                  onTap: () {
                                    ref.read(selectedFeedProvider.notifier).state = null;
                                    ref.read(showStarredProvider.notifier).state = false;
                                    ref.read(articleFilterProvider.notifier).all();
                                  },
                                );
                              },
                            ),
                            
                            // Individual feeds
                            ...feeds.map((feed) {
                              return Consumer(
                                builder: (context, ref, child) {
                                  final feedArticles = ref.watch(
                                    articlesProvider(ArticleQuery(feedId: int.tryParse(feed.id))),
                                  );
                                  final unreadCount = feedArticles.maybeWhen(
                                    data: (articles) => articles.where((a) => !a.isRead).length,
                                    orElse: () => 0,
                                  );
                                  return _buildCategoryItem(
                                    feed.customTitle ?? feed.title,
                                    Icons.rss_feed,
                                    unreadCount,
                                    selectedFeedId == feed.id,
                                    onTap: () => ref.read(selectedFeedProvider.notifier).state = feed.id,
                                  );
                                },
                              );
                            }),
                            
                            // Starred
                            Consumer(
                              builder: (context, ref, child) {
                                // Temporarily set filter to starred to get count
                                final currentFilter = ref.watch(articleFilterProvider);
                                
                                // Watch all articles to get starred count
                                final allArticles = ref.watch(articlesProvider);
                                final count = allArticles.maybeWhen(
                                  data: (articles) => articles.where((a) => a.isStarred).length,
                                  orElse: () => 0,
                                );
                                final isShowingStarred = ref.watch(showStarredProvider);
                                return _buildCategoryItem(
                                  'Starred', 
                                  Icons.star, 
                                  count, 
                                  isShowingStarred,
                                  onTap: () {
                                    ref.read(selectedFeedProvider.notifier).state = null;
                                    ref.read(showStarredProvider.notifier).state = true;
                                    ref.read(articleFilterProvider.notifier).starred();
                                  },
                                );
                              },
                            ),
                          ],
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, stack) => const SizedBox.shrink(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCategoryItem(String title, IconData icon, int count, bool isSelected, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          gradientColors: isSelected
              ? [
                  GlassColors.accentGradient[0].withOpacity(0.2),
                  GlassColors.accentGradient[1].withOpacity(0.1),
                ]
              : null,
          child: Row(
            children: [
              Icon(
                icon,
                color: Colors.white.withOpacity(0.8),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                  ),
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: count > 0 
                      ? GlassColors.accentGradient[0].withOpacity(0.3)
                      : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildMiddlePanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 32),
          // Search bar
          Row(
            children: [
              Expanded(
                child: GlassTextField(
                  controller: _searchController,
                  hintText: 'Search articles...',
                  isSearch: true,
                  enableClearButton: true,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              GlassButton(
                icon: Icons.search_outlined,
                onPressed: () => _showAdvancedSearch(context),
                variant: GlassButtonVariant.icon,
                width: 48,
                height: 48,
              ).glassTooltip('Advanced Search'),
            ],
          ),
          const SizedBox(height: 16),
          // Article list
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final selectedFeedId = ref.watch(selectedFeedProvider);
                final showStarred = ref.watch(showStarredProvider);
                
                // Apply search filter if needed
                if (_searchQuery.isNotEmpty) {
                  ref.read(articleFilterProvider.notifier).search(_searchQuery);
                }
                
                final articlesAsync = ref.watch(articlesProvider);
                
                return articlesAsync.when(
                  data: (articles) {
                    if (articles.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 64,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No articles found',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add some feeds to get started',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    return ListView.builder(
                      itemCount: articles.length,
                      itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Dismissible(
                    key: Key(articles[index].id),
                    direction: DismissDirection.horizontal,
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.endToStart) {
                        // Mark as read
                        if (!articles[index].isRead) {
                          await ref.read(articleActionsProvider).markAsRead(articles[index].id);
                        }
                        return false; // Don't actually dismiss
                      } else if (direction == DismissDirection.startToEnd) {
                        // Toggle star
                        await ref.read(articleActionsProvider).toggleStarred(articles[index].id);
                        return false; // Don't actually dismiss
                      }
                      return false;
                    },
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amber.withOpacity(0.3), Colors.amber.withOpacity(0.1)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.star, color: Colors.amber, size: 28),
                    ),
                    secondaryBackground: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.withOpacity(0.1), Colors.green.withOpacity(0.3)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.check, color: Colors.green, size: 28),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GlassTheme(
                              data: GlassThemeData.defaultTheme,
                              child: ArticleReaderScreen(article: articles[index]),
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: GlassCard(
                        elevation: 2,
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: GlassColors.primaryGradient[0].withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.article,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    articles[index].title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${articles[index].feedTitle ?? 'Unknown Source'} • ${_formatTime(articles[index].publishedAt)}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          articles[index].content ?? articles[index].description ?? 'No preview available',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                            height: 1.5,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildArticleAction(
                              articles[index].isRead ? Icons.mark_email_read : Icons.mark_email_unread,
                              () => _toggleArticleRead(articles[index]),
                              color: articles[index].isRead ? Colors.green : null,
                            ).glassTooltip(articles[index].isRead ? 'Mark as unread' : 'Mark as read'),
                            const SizedBox(width: 8),
                            _buildArticleAction(
                              articles[index].isStarred ? Icons.star : Icons.star_outline,
                              () => _toggleArticleStarred(articles[index]),
                              color: articles[index].isStarred ? Colors.amber : null,
                            ).glassTooltip(articles[index].isStarred ? 'Unstar' : 'Star'),
                            const SizedBox(width: 8),
                            _buildArticleAction(Icons.share, () {
                              _shareArticle(articles[index]);
                            }).glassTooltip('Share'),
                            const SizedBox(width: 8),
                            _buildArticleAction(Icons.open_in_browser, () {
                              _openArticleInBrowser(articles[index]);
                            }).glassTooltip('Open in browser'),
                          ],
                        ),
                      ],
                    ),
                    ),
                  ),
                );
              },
            );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
                  error: (error, stack) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading articles',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error.toString(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildArticleAction(IconData icon, VoidCallback onTap, {Color? color}) {
    return GlassButton(
      icon: icon,
      onPressed: onTap,
      variant: GlassButtonVariant.icon,
      width: 32,
      height: 32,
      iconColor: color,
    );
  }
  
  Widget _buildRightPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          // Article content header
          GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome to RSS Glassmorphism Reader',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Select an article from the list to start reading',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    GlassButton(
                      text: 'Get Started',
                      onPressed: () {
                        // Navigate to discover screen to help users find feeds
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DiscoverScreen(),
                          ),
                        );
                      },
                      variant: GlassButtonVariant.elevated,
                    ),
                    const SizedBox(width: 12),
                    GlassButton(
                      text: 'Learn More',
                      onPressed: () {
                        // Show a dialog with information about the app
                        showDialog(
                          context: context,
                          builder: (context) => GlassDialog(
                            title: 'About Omi RSS Reader',
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Omi RSS Reader is a modern, AI-powered RSS reader with beautiful glassmorphism design.',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Key Features:',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildFeatureItem(Icons.psychology, 'AI-powered article analysis'),
                                _buildFeatureItem(Icons.trending_up, 'Real-time market data integration'),
                                _buildFeatureItem(Icons.auto_awesome, 'Smart feed generation'),
                                _buildFeatureItem(Icons.sync, 'Cross-device synchronization'),
                                _buildFeatureItem(Icons.folder_shared, 'Collaborative folders'),
                                _buildFeatureItem(Icons.lock, 'End-to-end encryption'),
                                const SizedBox(height: 16),
                                const Text(
                                  'Version: 1.0.0',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              GlassButton(
                                text: 'Documentation',
                                onPressed: () {
                                  launchUrl(Uri.parse('https://github.com/yourusername/omi-rss'));
                                },
                                variant: GlassButtonVariant.secondary,
                              ),
                              GlassButton(
                                text: 'Close',
                                onPressed: () => Navigator.pop(context),
                                variant: GlassButtonVariant.primary,
                              ),
                            ],
                          ),
                        );
                      },
                      variant: GlassButtonVariant.outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Feature cards
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _buildFeatureCard(
                  'AI Perspectives',
                  'Get multiple viewpoints on any article',
                  Icons.psychology,
                  GlassColors.primaryGradient,
                ),
                _buildFeatureCard(
                  'Market Data',
                  'Real-time financial information',
                  Icons.trending_up,
                  GlassColors.secondaryGradient,
                ),
                _buildFeatureCard(
                  'Full Text',
                  'Extract complete articles',
                  Icons.article,
                  GlassColors.accentGradient,
                ),
                _buildFeatureCard(
                  'Sync Everywhere',
                  'Access your feeds on any device',
                  Icons.sync,
                  GlassColors.auroraColors.sublist(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFeatureCard(String title, String description, IconData icon, List<Color> gradient) {
    return GlassCard(
      elevation: 3,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  void _showDrawer(BuildContext context) {
    final authState = ref.read(authProvider);
    final user = authState.user;
    
    showGlassDrawer(
      context: context,
      header: GlassDrawerHeader(
        userName: user?.username ?? user?.email?.split('@').first ?? 'User',
        userEmail: user?.email ?? 'Not logged in',
        onProfileTap: () {
          Navigator.of(context).pop();
          context.showGlassSnackBar('Profile settings coming soon');
        },
      ),
      items: [
        GlassDrawerItem(
          id: 'feeds',
          title: 'Feeds',
          icon: Icons.rss_feed,
          selected: true,
          children: [
            GlassDrawerItem(
              id: 'all-feeds',
              title: 'All Feeds',
              icon: Icons.inbox,
              badge: '156',
              selected: true,
            ),
            GlassDrawerItem(
              id: 'tech',
              title: 'Technology',
              icon: Icons.computer,
              badge: '42',
            ),
            GlassDrawerItem(
              id: 'news',
              title: 'News',
              icon: Icons.newspaper,
              badge: '67',
            ),
          ],
        ),
        GlassDrawerItem(
          id: 'saved',
          title: 'Saved Articles',
          icon: Icons.bookmark,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const GlassTheme(
                  data: GlassThemeData.defaultTheme,
                  child: SavedArticlesScreen(),
                ),
              ),
            );
          },
        ),
        GlassDrawerItem(
          id: 'search',
          title: 'Advanced Search',
          icon: Icons.search,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const GlassTheme(
                  data: GlassThemeData.defaultTheme,
                  child: SearchPage(),
                ),
              ),
            );
          },
        ),
        GlassDrawerItem(
          id: 'discover',
          title: 'Discover',
          icon: Icons.explore,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DiscoverScreen(),
              ),
            );
          },
        ),
        GlassDrawerItem(
          id: 'generate',
          title: 'Generate Feed',
          icon: Icons.auto_awesome,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const FeedGenerationScreen(),
              ),
            );
          },
        ),
        GlassDrawerItem(
          id: 'ai',
          title: 'AI Analysis',
          icon: Icons.psychology,
          badge: 'NEW',
          badgeColor: Colors.green,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AIDashboardScreen(),
              ),
            );
          },
        ),
        GlassDrawerItem(
          id: 'market',
          title: 'Market Data',
          icon: Icons.trending_up,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MarketDashboardScreen(),
              ),
            );
          },
        ),
        GlassDrawerItem(
          id: 'analytics',
          title: 'Analytics',
          icon: Icons.analytics,
          badge: 'NEW',
          badgeColor: Colors.purple,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AnalyticsDashboard(),
              ),
            );
          },
        ),
      ],
      footer: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                Icons.download,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              title: Text(
                'Import OPML',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _importOPML(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.upload,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              title: Text(
                'Export OPML',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _exportOPML(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.sync,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              title: Text(
                'Sync & Backup',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GlassTheme(
                      data: GlassThemeData.defaultTheme,
                      child: SyncScreen(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.bar_chart,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              title: Text(
                'Statistics',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GlassTheme(
                      data: GlassThemeData.defaultTheme,
                      child: StatisticsScreen(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.settings,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              title: Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GlassTheme(
                      data: GlassThemeData.defaultTheme,
                      child: SettingsScreen(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              title: Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                final confirm = await showGlassConfirmDialog(
                  context: context,
                  title: 'Logout',
                  message: 'Are you sure you want to logout?',
                  confirmText: 'Logout',
                  destructive: true,
                );
                if (confirm == true) {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) {
                    context.showWarningSnackBar('Logged out successfully');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddFeedDialog(BuildContext context) async {
    final urlController = TextEditingController();
    final result = await showGlassDialog<bool>(
      context: context,
      title: const Text('Add RSS Feed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Enter the URL of an RSS, Atom, or JSON feed',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          GlassTextField(
            controller: urlController,
            hintText: 'https://example.com/feed.xml',
            enableClearButton: true,
          ),
        ],
      ),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Add Feed',
          onPressed: () => Navigator.of(context).pop(true),
          variant: GlassButtonVariant.elevated,
        ),
      ],
      size: GlassDialogSize.small,
    );

    if (result == true && urlController.text.isNotEmpty) {
      try {
        await ref.read(subscribeFeedProvider(urlController.text).future);
        if (context.mounted) {
          context.showSuccessSnackBar('Feed added successfully!');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to add feed: $e');
        }
      }
    }
    urlController.dispose();
  }

  void _showArticleOptions(BuildContext context, int index) async {
    final result = await showGlassDialog<String>(
      context: context,
      title: Text('Article ${index + 1} Options'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOption(context, Icons.bookmark, 'Save for later', 'save'),
          _buildOption(context, Icons.archive, 'Archive', 'archive'),
          _buildOption(context, Icons.open_in_browser, 'Open in browser', 'browser'),
          _buildOption(context, Icons.content_copy, 'Copy link', 'copy'),
          _buildOption(context, Icons.delete_outline, 'Delete', 'delete', isDestructive: true),
        ],
      ),
      size: GlassDialogSize.small,
      dismissible: true,
    );

    if (result != null) {
      switch (result) {
        case 'save':
          context.showSuccessSnackBar('Article saved for later');
          break;
        case 'archive':
          context.showSuccessSnackBar('Article archived');
          break;
        case 'browser':
          context.showGlassSnackBar('Opening in browser...', type: GlassSnackBarType.info);
          break;
        case 'copy':
          context.showSuccessSnackBar('Link copied to clipboard');
          break;
        case 'delete':
          final confirm = await showGlassConfirmDialog(
            context: context,
            title: 'Delete Article',
            message: 'Are you sure you want to delete this article?',
            confirmText: 'Delete',
            destructive: true,
          );
          if (confirm == true) {
            context.showWarningSnackBar('Article deleted');
          }
          break;
      }
    }
  }

  Widget _buildOption(BuildContext context, IconData icon, String label, String value, {bool isDestructive = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? Colors.red : Colors.white.withOpacity(0.8),
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isDestructive ? Colors.red : Colors.white.withOpacity(0.9),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _importOPML(BuildContext context) async {
    try {
      await ref.read(importOPMLFromFileProvider.future);
      
      // Show import progress dialog
      if (context.mounted) {
        showGlassDialog(
          context: context,
          dismissible: false,
          title: const Text('Importing OPML'),
          content: Consumer(
            builder: (context, ref, child) {
              final importState = ref.watch(opmlImportProvider);
              
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!importState.isComplete) ...[
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      importState.progressText,
                      style: TextStyle(color: Colors.white.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: importState.progress,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        GlassColors.accentGradient[0],
                      ),
                    ),
                  ] else ...[
                    Icon(
                      importState.failedFeeds == 0 ? Icons.check_circle : Icons.warning,
                      color: importState.failedFeeds == 0 ? Colors.green : Colors.orange,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Import Complete!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${importState.importedFeeds} feeds imported successfully',
                      style: TextStyle(color: Colors.white.withOpacity(0.8)),
                    ),
                    if (importState.failedFeeds > 0) ...[
                      Text(
                        '${importState.failedFeeds} feeds failed',
                        style: TextStyle(color: Colors.orange.withOpacity(0.8)),
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
          actions: [
            Consumer(
              builder: (context, ref, child) {
                final importState = ref.watch(opmlImportProvider);
                
                if (importState.isComplete) {
                  return GlassButton(
                    text: 'Done',
                    onPressed: () {
                      ref.read(opmlImportProvider.notifier).reset();
                      Navigator.of(context).pop();
                    },
                    variant: GlassButtonVariant.elevated,
                  );
                }
                
                return const SizedBox.shrink();
              },
            ),
          ],
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Failed to import OPML: $e');
      }
    }
  }

  void _exportOPML(BuildContext context) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final filename = 'omi-rss-feeds-$timestamp.opml';
      
      await ref.read(exportOPMLToFileProvider(filename).future);
      
      if (context.mounted) {
        context.showSuccessSnackBar('OPML exported successfully!');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Failed to export OPML: $e');
      }
    }
  }

  void _refreshAllFeeds(BuildContext context) async {
    context.showGlassSnackBar('Refreshing all feeds...', type: GlassSnackBarType.info);
    
    try {
      await ref.read(feedRefreshProvider.notifier).refreshAllFeeds();
      
      if (context.mounted) {
        final progress = ref.read(feedRefreshProvider).value;
        if (progress != null && progress.isComplete) {
          context.showSuccessSnackBar('All feeds refreshed!');
        }
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Failed to refresh feeds: $e');
      }
    }
  }

  void _toggleArticleRead(Article article) async {
    try {
      final actions = ref.read(articleActionsProvider);
      if (article.isRead) {
        await actions.markAsUnread(article.id);
      } else {
        await actions.markAsRead(article.id);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to update article: $e');
      }
    }
  }

  void _toggleArticleStarred(Article article) async {
    try {
      final actions = ref.read(articleActionsProvider);
      await actions.toggleStarred(article.id);
      
      if (mounted) {
        context.showSuccessSnackBar(
          article.isStarred ? 'Article unstarred' : 'Article starred'
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to update article: $e');
      }
    }
  }

  void _shareArticle(Article article) async {
    try {
      await Share.share(
        '${article.title}\n\n${article.url}',
        subject: article.title,
      );
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to share article: $e');
      }
    }
  }

  void _openArticleInBrowser(Article article) async {
    try {
      final uri = Uri.parse(article.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        throw 'Could not launch ${article.url}';
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to open article: $e');
      }
    }
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}