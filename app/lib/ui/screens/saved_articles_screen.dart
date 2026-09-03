import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_app_bar.dart';
import '../components/glass_snack_bar.dart';
import '../components/glass_dialog.dart';
import '../components/glass_text_field.dart';
import '../widgets/article_list.dart';
import '../../providers/feed_provider.dart';
import '../../providers/article_actions_provider.dart';
import '../../core/models/article.dart';
import 'article_reader_screen.dart';

class SavedArticlesScreen extends ConsumerStatefulWidget {
  const SavedArticlesScreen({super.key});

  @override
  ConsumerState<SavedArticlesScreen> createState() => _SavedArticlesScreenState();
}

class _SavedArticlesScreenState extends ConsumerState<SavedArticlesScreen> {
  String _searchQuery = '';
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
    ref.read(articleFilterProvider.notifier).starred();
    final articlesAsync = ref.watch(articlesProvider);
    
    return Scaffold(
      backgroundColor: GlassTheme.backgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              GlassTheme.primaryColor.withOpacity(0.1),
              GlassTheme.accentColor.withOpacity(0.1),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              GlassAppBar(
                title: 'Saved Articles',
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
                  const SizedBox(width: 8),
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Search bar
                    GlassTextField(
                      controller: _searchController,
                      hintText: 'Search saved articles...',
                      prefixIcon: Icons.search,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    
                    // Sort options
                    Row(
                      children: [
                        Text(
                          'Sort by:',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildSortChip('Date', 'date'),
                        const SizedBox(width: 8),
                        _buildSortChip('Title', 'title'),
                        const SizedBox(width: 8),
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
                      return _buildEmptyState();
                    }
                    
                    // Sort articles
                    final sortedArticles = _sortArticles(articles);
                    
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: sortedArticles.length,
                      itemBuilder: (context, index) {
                        final article = sortedArticles[index];
                        return _buildArticleCard(article).animate()
                          .fadeIn(delay: Duration(milliseconds: index * 50))
                          .slideX(begin: 0.1, end: 0);
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  error: (error, stack) => Center(
                    child: GlassContainer(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red.withOpacity(0.8),
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load saved articles',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.toString(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
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
    final isSelected = _sortBy == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _sortBy = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
            ? GlassTheme.primaryColor.withOpacity(0.3)
            : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
              ? GlassTheme.primaryColor
              : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: GlassContainer(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No saved articles',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Articles you star will appear here',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            GlassButton(
              text: 'Browse Articles',
              icon: Icons.explore,
              onPressed: () => Navigator.pop(context),
              variant: GlassButtonVariant.elevated,
            ),
          ],
        ),
      ),
    ).animate()
      .fadeIn(duration: 300.ms)
      .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1));
  }
  
  Widget _buildArticleCard(Article article) {
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openArticle(article),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Feed name and date
              Row(
                children: [
                  Icon(
                    Icons.rss_feed,
                    size: 16,
                    color: GlassTheme.primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      article.feedTitle ?? 'Unknown Feed',
                      style: TextStyle(
                        color: GlassTheme.primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _formatDate(article.publishedAt ?? article.createdAt),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Title
              Text(
                article.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              // Summary
              if (article.summary != null) ...[
                const SizedBox(height: 8),
                Text(
                  article.summary!,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              
              // Actions
              const SizedBox(height: 12),
              Row(
                children: [
                  // Read time
                  if (article.estimatedReadTime > 0) ...[
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${article.estimatedReadTime} min',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  
                  // Tags
                  if (article.categories?.isNotEmpty ?? false) ...[
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: article.categories!.take(3).map((tag) => 
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ).toList(),
                      ),
                    ),
                  ],
                  
                  const Spacer(),
                  
                  // Unstar button
                  GlassButton(
                    icon: Icons.bookmark,
                    onPressed: () => _unstarArticle(article),
                    variant: GlassButtonVariant.icon,
                    width: 32,
                    height: 32,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatisticsBar(List<Article> articles) {
    final feedCounts = <String, int>{};
    for (final article in articles) {
      final feedName = article.feedTitle ?? 'Unknown';
      feedCounts[feedName] = (feedCounts[feedName] ?? 0) + 1;
    }
    
    return GlassContainer(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
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
        ],
      ),
    );
  }
  
  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(
          icon,
          color: GlassTheme.primaryColor,
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
  
  List<Article> _sortArticles(List<Article> articles) {
    switch (_sortBy) {
      case 'title':
        return List.from(articles)..sort((a, b) => a.title.compareTo(b.title));
      case 'feed':
        return List.from(articles)..sort((a, b) => 
          (a.feedTitle ?? '').compareTo(b.feedTitle ?? ''));
      case 'date':
      default:
        return List.from(articles)..sort((a, b) => 
          (b.publishedAt ?? b.createdAt).compareTo(a.publishedAt ?? a.createdAt));
    }
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} weeks ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
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
    showGlassDialog(
      context: context,
      title: const Text('Clear All Saved Articles'),
      content: const Text(
        'Are you sure you want to remove all saved articles? This action cannot be undone.',
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
            ref.read(articleFilterProvider.notifier).starred();
            final articles = await ref.read(articlesProvider.future);
            
            for (final article in articles) {
              await ref.read(articleActionsProvider).toggleStarred(article.id);
            }
            
            if (mounted) {
              context.showSuccessSnackBar('All saved articles cleared');
            }
          },
          variant: GlassButtonVariant.elevated,
          color: Colors.red,
        ),
      ],
    );
  }
}