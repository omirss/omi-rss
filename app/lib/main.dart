import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/api_config.dart';
import 'config/app_info.dart';
import 'core/models/article.dart';
import 'core/models/feed.dart';
import 'core/models/folder.dart';
import 'ui/glass_theme.dart';
import 'ui/tokens/glass_tokens.dart';
import '../providers/theme_settings_provider.dart';
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
import 'ui/components/article_card.dart';
import 'ui/components/empty_state.dart';
import 'ui/components/error_state.dart';
import 'ui/components/skeleton.dart';
import 'ui/screens/article_reader_screen.dart';
import 'providers/database_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/article_actions_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/opml_provider.dart';
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/settings/user_settings_screen.dart';
import 'ui/screens/offline_articles_screen.dart';
import 'ui/screens/feed_statistics_screen.dart';
import 'ui/screens/statistics_screen.dart';
import 'ui/screens/discover_screen.dart';
import 'ui/screens/saved_articles_screen.dart';
import 'features/analytics/analytics_dashboard.dart';
import 'features/search/search_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.load();
  runApp(
    const ProviderScope(
      child: OmiRssApp(),
    ),
  );
}

class OmiRssApp extends ConsumerStatefulWidget {
  const OmiRssApp({super.key});

  @override
  ConsumerState<OmiRssApp> createState() => _OmiRssAppState();
}

class _OmiRssAppState extends ConsumerState<OmiRssApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ensure database is initialized
      await ref.read(databaseInitializationProvider.future);
    });
  }

  @override
  Widget build(BuildContext context) {
    final materialThemes = ref.watch(materialThemesProvider);
    final themeMode = ref.watch(materialThemeModeProvider);

    return MaterialApp(
      title: appName,
      theme: materialThemes.light,
      darkTheme: materialThemes.dark,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthenticationWrapper(),
        '/login': (context) => const GlassThemeShell(
              child: LoginScreen(),
            ),
        '/home': (context) => const GlassThemeShell(
              child: GlassSnackBarManager(
                child: HomePage(),
              ),
            ),
      },
    );
  }
}

/// Resolves the brightness the user's mode selection implies, following the
/// platform brightness when set to system.
Brightness resolvedBrightness(AppThemeMode mode, BuildContext context) {
  switch (mode) {
    case AppThemeMode.system:
      return MediaQuery.platformBrightnessOf(context);
    case AppThemeMode.light:
      return Brightness.light;
    case AppThemeMode.dark:
      return Brightness.dark;
  }
}

/// Wraps a subtree in GlassTheme data built from the active preset and mode.
class GlassThemeShell extends ConsumerWidget {
  final Widget child;

  const GlassThemeShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsProvider);
    final preset = ref.watch(themePresetProvider);
    final tokens = preset.resolve(resolvedBrightness(settings.mode, context));

    return GlassTheme(
      data: GlassThemeData.fromTokens(tokens),
      child: child,
    );
  }
}

class AuthenticationWrapper extends ConsumerWidget {
  const AuthenticationWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    if (authState.isAuthenticated || ref.watch(localModeProvider)) {
      return const GlassThemeShell(
        child: GlassSnackBarManager(
          child: HomePage(),
        ),
      );
    } else {
      return const GlassThemeShell(
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
        builder: (context) => const GlassThemeShell(
          child: SearchPage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the sync engine (server pull + per-feed refresh schedule)
    // alive while the home shell is on screen.
    ref.watch(feedSyncProvider);
    // Warm the drawer's unread-count/folder streams.
    ref.watch(unreadCountProvider);
    ref.watch(folderUnreadCountsProvider);
    ref.watch(foldersProvider);

    final settings = ref.watch(themeSettingsProvider);
    final preset = ref.watch(themePresetProvider);
    final tokens = preset.resolve(resolvedBrightness(settings.mode, context));

    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: ParticleBackground(
        particleCount: 60,
        backgroundGradient: tokens.backgroundGradient,
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

  void _clearSearch() {
    _searchController.clear();
    if (_searchQuery.isNotEmpty) {
      setState(() {
        _searchQuery = '';
      });
    }
  }

  Widget _buildLeftPanel() {
    final tokens = GlassTheme.colorsOf(context);
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
                      color: tokens.textMedium,
                      size: 48,
                    ),
                    const SizedBox(width: 40), // Balance the layout
                  ],
                ),
                const SizedBox(height: GlassSpacing.md),
                Text(
                  'RSS Reader',
                  style: GlassTypeScale.displaySmall
                      .copyWith(color: tokens.textHigh),
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
                                  data: (articles) =>
                                      articles.where((a) => !a.isRead).length,
                                  orElse: () => 0,
                                );
                                return _buildCategoryItem(
                                  'All Feeds',
                                  Icons.inbox,
                                  unreadCount,
                                  selectedFeedId == null &&
                                      !ref.watch(showStarredProvider),
                                  onTap: () {
                                    _clearSearch();
                                    ref
                                        .read(selectedFeedProvider.notifier)
                                        .state = null;
                                    ref
                                        .read(showStarredProvider.notifier)
                                        .state = false;
                                    ref
                                        .read(articleFilterProvider.notifier)
                                        .showAll();
                                  },
                                );
                              },
                            ),

                            // Individual feeds
                            ...feeds.map((feed) {
                              return Consumer(
                                builder: (context, ref, child) {
                                  final feedArticles = ref.watch(
                                    articlesByFeedProvider(feed.id),
                                  );
                                  final unreadCount = feedArticles.maybeWhen(
                                    data: (articles) =>
                                        articles.where((a) => !a.isRead).length,
                                    orElse: () => 0,
                                  );
                                  return _buildCategoryItem(
                                    feed.customTitle ?? feed.title,
                                    Icons.rss_feed,
                                    unreadCount,
                                    selectedFeedId == feed.id,
                                    onTap: () {
                                      _clearSearch();
                                      ref
                                          .read(showStarredProvider.notifier)
                                          .state = false;
                                      ref
                                          .read(selectedFeedProvider.notifier)
                                          .state = feed.id;
                                      ref
                                          .read(articleFilterProvider.notifier)
                                          .showFeed(feed.id);
                                    },
                                  );
                                },
                              );
                            }),

                            // Starred
                            Consumer(
                              builder: (context, ref, child) {
                                // Watch all articles to get starred count
                                final allArticles = ref.watch(articlesProvider);
                                final count = allArticles.maybeWhen(
                                  data: (articles) =>
                                      articles.where((a) => a.isStarred).length,
                                  orElse: () => 0,
                                );
                                final isShowingStarred =
                                    ref.watch(showStarredProvider);
                                return _buildCategoryItem(
                                  'Starred',
                                  Icons.star,
                                  count,
                                  isShowingStarred,
                                  onTap: () {
                                    _clearSearch();
                                    ref
                                        .read(selectedFeedProvider.notifier)
                                        .state = null;
                                    ref
                                        .read(showStarredProvider.notifier)
                                        .state = true;
                                    ref
                                        .read(articleFilterProvider.notifier)
                                        .showStarred();
                                  },
                                );
                              },
                            ),
                          ],
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
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

  Widget _buildCategoryItem(
      String title, IconData icon, int count, bool isSelected,
      {VoidCallback? onTap}) {
    final tokens = GlassTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassSpacing.sm),
      child: GlassContainer(
        onTap: onTap,
        selected: isSelected,
        padding: const EdgeInsets.symmetric(
            horizontal: GlassSpacing.lg, vertical: GlassSpacing.md),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? tokens.accent : tokens.textMedium,
              size: 20,
            ),
            const SizedBox(width: GlassSpacing.md),
            Expanded(
              child: Text(
                title,
                style: GlassTypeScale.label.copyWith(
                  color:
                      isSelected ? tokens.textHigh : tokens.textMedium,
                ),
              ),
            ),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: GlassSpacing.sm, vertical: GlassSpacing.xs),
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(GlassRadii.md),
                ),
                child: Text(
                  count.toString(),
                  style: GlassTypeScale.caption.copyWith(
                    color: tokens.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
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
                    final filter = ref.read(articleFilterProvider.notifier);
                    if (value.isEmpty) {
                      if (ref.read(articleFilterProvider).type ==
                          ArticleFilterType.search) {
                        filter.showAll();
                      }
                    } else {
                      filter.search(value);
                    }
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
                final articlesAsync = ref.watch(articlesProvider);
                final feeds =
                    ref.watch(feedsProvider).valueOrNull ?? const <Feed>[];
                final favicons = <String, String?>{
                  for (final feed in feeds) feed.id: feed.faviconUrl,
                };

                return articlesAsync.when(
                  data: (articles) {
                    if (articles.isEmpty) {
                      final hasFeeds = feeds.isNotEmpty;
                      return EmptyState(
                        icon: Icons.article_outlined,
                        title: 'No articles found',
                        subtitle: hasFeeds
                            ? 'Try refreshing your feeds or adjusting filters'
                            : 'Add some feeds to get started',
                        actionLabel: hasFeeds ? 'Refresh All' : 'Discover feeds',
                        onAction: hasFeeds
                            ? () => _refreshAllFeeds(context)
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const GlassThemeShell(
                                      child: DiscoverScreen(),
                                    ),
                                  ),
                                );
                              },
                      );
                    }

                    return ListView.builder(
                      itemCount: articles.length,
                      itemBuilder: (context, index) {
                        final article = articles[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: GlassSpacing.md),
                          child: Dismissible(
                            key: Key(article.id),
                            direction: DismissDirection.horizontal,
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.endToStart) {
                                // Mark as read
                                if (!article.isRead) {
                                  await ref
                                      .read(articleActionsProvider)
                                      .markAsRead(article.id);
                                }
                                return false; // Don't actually dismiss
                              } else if (direction ==
                                  DismissDirection.startToEnd) {
                                // Toggle star
                                await ref
                                    .read(articleActionsProvider)
                                    .toggleStarred(article.id);
                                return false; // Don't actually dismiss
                              }
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              decoration: BoxDecoration(
                                color: GlassTheme.colorsOf(context)
                                    .warning
                                    .withValues(alpha: 0.25),
                                borderRadius:
                                    BorderRadius.circular(GlassRadii.lg),
                              ),
                              child: Icon(Icons.star,
                                  color: GlassTheme.colorsOf(context).warning,
                                  size: 28),
                            ),
                            secondaryBackground: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: GlassTheme.colorsOf(context)
                                    .success
                                    .withValues(alpha: 0.25),
                                borderRadius:
                                    BorderRadius.circular(GlassRadii.lg),
                              ),
                              child: Icon(Icons.check,
                                  color: GlassTheme.colorsOf(context).success,
                                  size: 28),
                            ),
                            child: ArticleCard(
                              article: article,
                              faviconUrl: favicons[article.feedId],
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => GlassThemeShell(
                                      child: ArticleReaderScreen(
                                          article: article),
                                    ),
                                  ),
                                );
                              },
                              onToggleRead: () => _toggleArticleRead(article),
                              onToggleStar: () => _toggleArticleStarred(article),
                              onShare: () => _shareArticle(article),
                              onOpenExternally: () =>
                                  _openArticleInBrowser(article),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const GlassSkeletonList(),
                  error: (error, stack) => ErrorState(
                    error: error.toString(),
                    title: 'Error loading articles',
                    onRetry: () => ref.invalidate(articlesProvider),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    final tokens = GlassTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(GlassSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: GlassSpacing.xxl),
          // Article content header
          GlassContainer(
            padding: const EdgeInsets.all(GlassSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to omi-rss',
                  style: GlassTypeScale.display
                      .copyWith(color: tokens.textHigh),
                ),
                const SizedBox(height: GlassSpacing.md),
                Text(
                  'Select an article from the list to start reading',
                  style: GlassTypeScale.body
                      .copyWith(color: tokens.textMedium),
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
                            builder: (context) => const GlassThemeShell(
                              child: DiscoverScreen(),
                            ),
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
                            title: const Text('About Omi RSS Reader'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Omi RSS Reader is a modern, local-first RSS reader with beautiful glassmorphism design.',
                                  style: GlassTypeScale.body.copyWith(
                                      color: GlassTheme.colorsOf(context)
                                          .textHigh),
                                ),
                                const SizedBox(height: GlassSpacing.lg),
                                Text(
                                  'Key Features:',
                                  style: GlassTypeScale.heading.copyWith(
                                      color: GlassTheme.colorsOf(context)
                                          .textHigh),
                                ),
                                const SizedBox(height: GlassSpacing.sm),
                                _buildFeatureItem(Icons.rss_feed,
                                    'Local-first feed subscriptions'),
                                _buildFeatureItem(
                                    Icons.article, 'Full-text article reading'),
                                _buildFeatureItem(Icons.download_for_offline,
                                    'Offline reading'),
                                _buildFeatureItem(
                                    Icons.star, 'Starred articles'),
                                _buildFeatureItem(Icons.import_export,
                                    'OPML import and export'),
                                _buildFeatureItem(
                                    Icons.bar_chart, 'Reading statistics'),
                                const SizedBox(height: GlassSpacing.lg),
                                Text(
                                  'Version: $appVersion',
                                  style: GlassTypeScale.label.copyWith(
                                      color: GlassTheme.colorsOf(context)
                                          .textMedium),
                                ),
                              ],
                            ),
                            actions: [
                              GlassButton(
                                text: 'Documentation',
                                onPressed: () {
                                  launchUrl(Uri.parse(appRepositoryUrl));
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
          const SizedBox(height: GlassSpacing.xl),
          // Feature cards
          Expanded(
            child: Builder(
              builder: (context) {
                final tokens = GlassTheme.colorsOf(context);
                return GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: GlassSpacing.lg,
                  crossAxisSpacing: GlassSpacing.lg,
                  children: [
                    _buildFeatureCard(
                      'All Your Feeds',
                      'Subscribe to any RSS, Atom, or JSON feed',
                      Icons.rss_feed,
                      tokens.primaryGradient,
                    ),
                    _buildFeatureCard(
                      'Full Text',
                      'Extract complete articles',
                      Icons.article,
                      tokens.accentGradient,
                    ),
                    _buildFeatureCard(
                      'Offline Reading',
                      'Save articles for later',
                      Icons.download_for_offline,
                      tokens.auroraColors.sublist(0, 2),
                    ),
                    _buildFeatureCard(
                      'Starred Articles',
                      'Keep track of what matters',
                      Icons.star,
                      tokens.auroraColors.sublist(2),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
      String title, String description, IconData icon, List<Color> gradient) {
    final tokens = GlassTheme.colorsOf(context);
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
              borderRadius: BorderRadius.circular(GlassRadii.lg),
            ),
            child: Icon(
              icon,
              color: tokens.textHigh,
              size: 32,
            ),
          ),
          const SizedBox(height: GlassSpacing.lg),
          Text(
            title,
            style: GlassTypeScale.heading.copyWith(color: tokens.textHigh),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GlassSpacing.sm),
          Text(
            description,
            style: GlassTypeScale.label.copyWith(color: tokens.textMedium),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showDrawer(BuildContext context) {
    final authState = ref.read(authProvider);
    final user = authState.user;

    // Folder rows come from the drift cache warmed by the home shell build;
    // unread badges watch their providers live via badgeWidget consumers.
    final folders = ref.read(foldersProvider).valueOrNull ?? const <Folder>[];

    showGlassDrawer(
      context: context,
      header: GlassDrawerHeader(
        userName: user?.username ?? user?.email.split('@').first ?? 'User',
        userEmail: user?.email ?? 'Not logged in',
        onProfileTap: () {
          Navigator.of(context).pop();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const GlassThemeShell(
                child: UserSettingsScreen(),
              ),
            ),
          );
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
              badgeWidget: const _DrawerTotalUnreadBadge(),
              selected: ref.read(selectedFeedProvider) == null &&
                  !ref.read(showStarredProvider),
              onTap: () {
                _clearSearch();
                ref.read(selectedFeedProvider.notifier).state = null;
                ref.read(showStarredProvider.notifier).state = false;
                ref.read(articleFilterProvider.notifier).showAll();
              },
            ),
            ...folders.map((folder) {
              return GlassDrawerItem(
                id: 'folder-${folder.id}',
                title: folder.name,
                icon: Icons.folder,
                badgeWidget: _DrawerFolderUnreadBadge(folderId: folder.id),
                onTap: () {
                  _clearSearch();
                  ref.read(selectedFeedProvider.notifier).state = null;
                  ref.read(showStarredProvider.notifier).state = false;
                  ref.read(articleFilterProvider.notifier)
                      .showFolder(folder.id);
                },
              );
            }),
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
                builder: (context) => const GlassThemeShell(
                  child: SavedArticlesScreen(),
                ),
              ),
            );
          },
        ),
        GlassDrawerItem(
          id: 'offline',
          title: 'Saved for offline',
          icon: Icons.offline_pin,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const OfflineArticlesScreen(),
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
                builder: (context) => const GlassThemeShell(
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
          id: 'analytics',
          title: 'Analytics',
          icon: Icons.analytics,
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
      footer: Builder(
        builder: (footerContext) {
          final footerTokens = GlassTheme.colorsOf(footerContext);
          return Container(
            padding: const EdgeInsets.all(GlassSpacing.lg),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: footerTokens.divider,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                _buildDrawerFooterTile(
                  footerContext,
                  icon: Icons.download,
                  label: 'Import OPML',
                  onTap: () {
                    Navigator.of(context).pop();
                    _importOPML(context);
                  },
                ),
                _buildDrawerFooterTile(
                  footerContext,
                  icon: Icons.upload,
                  label: 'Export OPML',
                  onTap: () {
                    Navigator.of(context).pop();
                    _exportOPML(context);
                  },
                ),
                _buildDrawerFooterTile(
                  footerContext,
                  icon: Icons.bar_chart,
                  label: 'Statistics',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GlassThemeShell(
                          child: StatisticsScreen(),
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerFooterTile(
                  footerContext,
                  icon: Icons.table_chart,
                  label: 'Feed Statistics',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GlassThemeShell(
                          child: FeedStatisticsScreen(),
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerFooterTile(
                  footerContext,
                  icon: Icons.settings,
                  label: 'Settings',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GlassThemeShell(
                          child: SettingsScreen(),
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerFooterTile(
                  footerContext,
                  icon: Icons.logout,
                  label: 'Logout',
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
                      await ref.read(localModeProvider.notifier).disable();
                      if (context.mounted) {
                        context.showWarningSnackBar('Logged out successfully');
                      }
                    }
                  },
                ),
                const SizedBox(height: GlassSpacing.sm),
                Text(
                  '$appName $appVersion',
                  style: GlassTypeScale.caption.copyWith(
                    color: footerTokens.textLow,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDrawerFooterTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final tokens = GlassTheme.colorsOf(context);
    return ListTile(
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, color: tokens.textMedium, size: 20),
      title: Text(
        label,
        style: GlassTypeScale.label.copyWith(color: tokens.textMedium),
      ),
      onTap: onTap,
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
            style: GlassTypeScale.label.copyWith(
                color: GlassTheme.colorsOf(context).textMedium),
          ),
          const SizedBox(height: GlassSpacing.lg),
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

  void _importOPML(BuildContext context) async {
    final settings = ref.read(themeSettingsProvider);
    final preset = ref.read(themePresetProvider);
    final tokens =
        preset.resolve(resolvedBrightness(settings.mode, context));

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
                    CircularProgressIndicator(color: tokens.accent),
                    const SizedBox(height: 16),
                    Text(
                      importState.progressText,
                      style: GlassTypeScale.label
                          .copyWith(color: tokens.textMedium),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: importState.progress,
                      backgroundColor: tokens.glassStroke,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(tokens.accent),
                    ),
                  ] else ...[
                    Icon(
                      importState.failedFeeds == 0
                          ? Icons.check_circle
                          : Icons.warning,
                      color: importState.failedFeeds == 0
                          ? tokens.success
                          : tokens.warning,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      importState.failedFeeds == 0
                          ? 'Import Complete!'
                          : 'Import Finished',
                      style: GlassTypeScale.title.copyWith(
                        color: tokens.textHigh,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${importState.importedFeeds} of ${importState.totalFeeds} feeds imported successfully',
                      style: GlassTypeScale.label
                          .copyWith(color: tokens.textMedium),
                    ),
                    if (importState.failedFeeds > 0) ...[
                      Text(
                        '${importState.failedFeeds} feeds failed',
                        style: GlassTypeScale.label
                            .copyWith(color: tokens.warning),
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
                      final summary = importState.failedFeeds == 0
                          ? '${importState.importedFeeds} feeds imported'
                          : '${importState.importedFeeds} imported, '
                              '${importState.failedFeeds} failed';
                      ref.read(opmlImportProvider.notifier).reset();
                      Navigator.of(context).pop();
                      if (importState.failedFeeds == 0) {
                        context.showSuccessSnackBar(summary);
                      } else {
                        context.showWarningSnackBar(summary);
                      }
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
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
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
    context.showGlassSnackBar('Refreshing all feeds...',
        type: GlassSnackBarType.info);

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
            article.isStarred ? 'Article unstarred' : 'Article starred');
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
    final tokens = GlassTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GlassSpacing.xs),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: tokens.primary,
          ),
          const SizedBox(width: GlassSpacing.md),
          Expanded(
            child: Text(
              text,
              style: GlassTypeScale.label.copyWith(color: tokens.textMedium),
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

/// Live total-unread badge for the drawer's All Feeds row.
class _DrawerTotalUnreadBadge extends ConsumerWidget {
  const _DrawerTotalUnreadBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return GlassDrawerBadge(count: count.toString());
  }
}

/// Live per-folder unread badge for the drawer's folder rows.
class _DrawerFolderUnreadBadge extends ConsumerWidget {
  final String folderId;

  const _DrawerFolderUnreadBadge({required this.folderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts =
        ref.watch(folderUnreadCountsProvider).valueOrNull ?? const <String, int>{};
    final count = counts[folderId] ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return GlassDrawerBadge(count: count.toString());
  }
}
