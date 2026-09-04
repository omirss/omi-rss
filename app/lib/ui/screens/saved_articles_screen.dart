import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../glass_theme.dart';
import '../tokens/glass_tokens.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_tooltip.dart';
import '../components/glass_app_bar.dart';
import '../components/glass_snack_bar.dart';
import '../components/glass_dialog.dart';
import '../components/glass_text_field.dart';
import '../components/article_card.dart';
import '../components/empty_state.dart';
import '../components/error_state.dart';
import '../components/skeleton.dart';
import '../../providers/article_actions_provider.dart';
import '../../providers/feed_provider.dart';
import '../../core/models/article.dart';
import 'article_reader_screen.dart';

class SavedArticlesScreen extends ConsumerStatefulWidget {
  const SavedArticlesScreen({super.key});

  @override
  ConsumerState<SavedArticlesScreen> createState() => _SavedArticlesScreenState();
}

class _SavedArticlesScreenState extends ConsumerState<SavedArticlesScreen> {
  String _sortBy = 'date';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get starred articles by setting the filter
    ref.read(articleFilterProvider.notifier).showStarred();
    final articlesAsync = ref.watch(articlesProvider);
    final tokens = GlassTheme.colorsOf(context);

    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tokens.backgroundGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              GlassAppBar(
                title: Text(
                  'Saved Articles',
                  style: GlassTypeScale.title.copyWith(color: tokens.textHigh),
                ),
                leading: GlassButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                  variant: GlassButtonVariant.icon,
                ),
                actions: [
                  // Export saved articles
                  GlassButton(
                    icon: Icons.download,
                    onPressed: () => _exportSavedArticles(context),
                    variant: GlassButtonVariant.icon,
                  ).glassTooltip('Export saved articles'),
                  const SizedBox(width: GlassSpacing.sm),
                  // Clear all saved
                  GlassButton(
                    icon: Icons.clear_all,
                    onPressed: () => _confirmClearAll(context),
                    variant: GlassButtonVariant.icon,
                  ).glassTooltip('Clear all saved'),
                ],
              ),

              // Search and filters
              Padding(
                padding: const EdgeInsets.all(GlassSpacing.lg),
                child: Column(
                  children: [
                    // Search bar
                    GlassTextField(
                      controller: _searchController,
                      hintText: 'Search saved articles...',
                      prefixIcon: Icons.search,
                    ),
                    const SizedBox(height: GlassSpacing.md),

                    // Sort options
                    Row(
                      children: [
                        Text(
                          'Sort by:',
                          style: GlassTypeScale.label
                              .copyWith(color: tokens.textMedium),
                        ),
                        const SizedBox(width: GlassSpacing.md),
                        _buildSortChip('Date', 'date'),
                        const SizedBox(width: GlassSpacing.sm),
                        _buildSortChip('Title', 'title'),
                        const SizedBox(width: GlassSpacing.sm),
                        _buildSortChip('Feed', 'feed'),
                      ],
                    ),
                  ],
                ),
              ),

              // Articles list
              Expanded(
                child: articlesAsync.when(
                  data: (articles) {
                    if (articles.isEmpty) {
                      return EmptyState(
                        title: 'No saved articles',
                        subtitle: 'Articles you star will appear here',
                        actionLabel: 'Browse articles',
                        onAction: () => Navigator.pop(context),
                      ).animate()
                          .fadeIn(duration: 300.ms)
                          .scale(
                            begin: const Offset(0.95, 0.95),
                            end: const Offset(1, 1),
                          );
                    }

                    // Sort articles
                    final sortedArticles = _sortArticles(articles);

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: GlassSpacing.lg),
                      itemCount: sortedArticles.length,
                      itemBuilder: (context, index) {
                        final article = sortedArticles[index];
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: GlassSpacing.md),
                          child: _buildArticleCard(article).animate()
                              .fadeIn(
                                  delay: Duration(milliseconds: index * 50))
                              .slideX(begin: 0.1, end: 0),
                        );
                      },
                    );
                  },
                  loading: () => const GlassSkeletonList(),
                  error: (error, stack) => ErrorState(
                    error: error.toString(),
                    title: 'Failed to load saved articles',
                    onRetry: () => ref.invalidate(articlesProvider),
                  ),
                ),
              ),

              // Statistics bar
              articlesAsync.maybeWhen(
                data: (articles) => _buildStatisticsBar(articles),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, String value) {
    final tokens = GlassTheme.colorsOf(context);
    final isSelected = _sortBy == value;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _sortBy = value;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
              horizontal: GlassSpacing.md, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? tokens.accentSoft : tokens.glassFill,
            borderRadius: BorderRadius.circular(GlassRadii.md),
            border: Border.all(
              color: isSelected ? tokens.accent : tokens.glassStroke,
            ),
          ),
          child: Text(
            label,
            style: GlassTypeScale.caption.copyWith(
              color: isSelected ? tokens.textHigh : tokens.textMedium,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArticleCard(Article article) {
    return ArticleCard(
      article: article,
      onTap: () => _openArticle(article),
      showSnippet: false,
      trailing: GlassButton(
        icon: Icons.bookmark_remove_outlined,
        onPressed: () => _unstarArticle(article),
        variant: GlassButtonVariant.icon,
        width: 32,
        height: 32,
      ).glassTooltip('Remove from saved'),
    );
  }

  Widget _buildStatisticsBar(List<Article> articles) {
    final feedCounts = <String, int>{};
    for (final article in articles) {
      final feedName = article.feedTitle ?? 'Unknown';
      feedCounts[feedName] = (feedCounts[feedName] ?? 0) + 1;
    }

    return GlassContainer(
      margin: const EdgeInsets.all(GlassSpacing.lg),
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            Icons.bookmark,
            articles.length.toString(),
            'Saved',
          ),
          _buildStatItem(
            Icons.rss_feed,
            feedCounts.length.toString(),
            'Feeds',
          ),
          _buildStatItem(
            Icons.schedule,
            '${articles.fold(0, (sum, a) => sum + a.estimatedReadTime)} min',
            'Read time',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    final tokens = GlassTheme.colorsOf(context);
    return Column(
      children: [
        Icon(
          icon,
          color: tokens.primary,
          size: 20,
        ),
        const SizedBox(height: GlassSpacing.xs),
        Text(
          value,
          style: GlassTypeScale.body.copyWith(
            fontWeight: FontWeight.w700,
            color: tokens.textHigh,
          ),
        ),
        Text(
          label,
          style: GlassTypeScale.caption.copyWith(color: tokens.textMedium),
        ),
      ],
    );
  }

  List<Article> _sortArticles(List<Article> articles) {
    switch (_sortBy) {
      case 'title':
        return List.from(articles)..sort((a, b) => a.title.compareTo(b.title));
      case 'feed':
        return List.from(articles)
          ..sort((a, b) =>
              (a.feedTitle ?? '').compareTo(b.feedTitle ?? ''));
      case 'date':
      default:
        return List.from(articles)
          ..sort((a, b) => (b.publishedAt ?? b.createdAt)
              .compareTo(a.publishedAt ?? a.createdAt));
    }
  }

  void _openArticle(Article article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArticleReaderScreen(article: article),
      ),
    );
  }

  void _unstarArticle(Article article) async {
    await ref.read(articleActionsProvider).toggleStarred(article.id);
    if (mounted) {
      context.showSuccessSnackBar('Article removed from saved');
    }
  }

  void _exportSavedArticles(BuildContext context) {
    Navigator.pushNamed(context, '/export');
  }

  void _confirmClearAll(BuildContext context) {
    final tokens = GlassTheme.colorsOf(context);
    showGlassDialog(
      context: context,
      title: const Text('Clear All Saved Articles'),
      content: Text(
        'Are you sure you want to remove all saved articles? This action cannot be undone.',
        style: GlassThemeData.fromTokens(tokens).bodyLarge,
      ),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.pop(context),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Clear All',
          onPressed: () async {
            Navigator.pop(context);
            // Get all starred articles and unstar them
            ref.read(articleFilterProvider.notifier).showStarred();
            final articles = await ref.read(articlesProvider.future);

            for (final article in articles) {
              await ref.read(articleActionsProvider).toggleStarred(article.id);
            }

            if (mounted) {
              context.showSuccessSnackBar('All saved articles cleared');
            }
          },
          variant: GlassButtonVariant.elevated,
          gradientColors: [
            tokens.error.withValues(alpha: 0.8),
            tokens.error.withValues(alpha: 0.6),
          ],
        ),
      ],
    );
  }
}
