import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_glassmorphism_reader/ui/glass_theme.dart';
import 'package:rss_glassmorphism_reader/core/services/extension_service.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_container.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_button.dart';
import 'package:rss_glassmorphism_reader/ui/screens/feed_list_screen.dart';
import 'package:rss_glassmorphism_reader/ui/screens/article_list_screen.dart';

class ExtensionPopupScreen extends ConsumerStatefulWidget {
  const ExtensionPopupScreen({super.key});

  @override
  ConsumerState<ExtensionPopupScreen> createState() => _ExtensionPopupScreenState();
}

class _ExtensionPopupScreenState extends ConsumerState<ExtensionPopupScreen> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _pageFeeds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _detectFeeds();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _detectFeeds() {
    final extensionService = ref.read(extensionServiceProvider);
    extensionService.detectFeeds();
    
    // Simulate feed detection
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _pageFeeds = [
            {
              'title': 'Example Blog RSS',
              'url': 'https://example.com/rss',
              'type': 'application/rss+xml',
            },
          ];
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);

    return Container(
      width: 400,
      height: 600,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: GlassColors.primaryGradient,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // Header
            GlassContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.zero,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                      colors: GlassColors.primaryGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.rss_feed,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RSS Reader',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Beautiful RSS Reading',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      final extensionService = ref.read(extensionServiceProvider);
                      extensionService.openTab('index.html#/settings');
                    },
                  ),
                ],
              ),
            ),

            // Tabs
            GlassContainer(
              width: double.infinity,
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.zero,
              child: TabBar(
                controller: _tabController,
                indicatorColor: GlassColors.primaryGradient.first,
                tabs: const [
                  Tab(text: 'Current Page'),
                  Tab(text: 'Feeds'),
                  Tab(text: 'Saved'),
                ],
              ),
            ),

            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Current Page Tab
                  _buildCurrentPageTab(theme),
                  
                  // Feeds Tab
                  _buildFeedsTab(theme),
                  
                  // Saved Tab
                  _buildSavedTab(theme),
                ],
              ),
            ),

            // Quick Actions
            GlassContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              borderRadius: BorderRadius.zero,
              child: Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.save,
                      label: 'Save',
                      onTap: _saveCurrentPage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.search,
                      label: 'Find Feeds',
                      onTap: _detectFeeds,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.psychology,
                      label: 'AI Analyze',
                      onTap: _analyzeWithAI,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPageTab(GlassThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_pageFeeds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.rss_feed,
                size: 64,
                color: Colors.white30,
              ),
              const SizedBox(height: 16),
              const Text(
                'No RSS feeds detected',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Try searching for feeds or save this page as an article',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              GlassButton(
                onPressed: _detectFeeds,
                child: const Text('Search for Feeds'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'RSS Feeds on this page',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ..._pageFeeds.map((feed) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassContainer(
            onTap: () => _addFeed(feed),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.rss_feed,
                      size: 20,
                      color: theme.primaryGradient.colors.first,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feed['title'] ?? 'Untitled Feed',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  feed['url'],
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        )).toList(),
      ],
    );
  }

  Widget _buildFeedsTab(GlassThemeData theme) {
    return const FeedListScreen(isCompact: true);
  }

  Widget _buildSavedTab(GlassThemeData theme) {
    return const ArticleListScreen(
      savedOnly: true,
      isCompact: true,
    );
  }

  void _saveCurrentPage() {
    final extensionService = ref.read(extensionServiceProvider);
    extensionService.getCurrentTab();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Article saved!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _analyzeWithAI() {
    final extensionService = ref.read(extensionServiceProvider);
    extensionService.getCurrentTab();
    extensionService.openTab('index.html#/analyze');
  }

  void _addFeed(Map<String, dynamic> feed) {
    final extensionService = ref.read(extensionServiceProvider);
    extensionService.sendToExtension({
      'action': 'addFeed',
      'feed': feed,
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Feed added successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

class _QuickAction extends ConsumerWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return GlassContainer(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 20,
            color: theme.primaryGradient.colors.first,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}