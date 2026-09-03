import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_glassmorphism_reader/ui/glass_theme.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_container.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_card.dart';
import 'package:rss_glassmorphism_reader/providers/feed_provider.dart';
import 'package:rss_glassmorphism_reader/core/models/article.dart';
import 'package:timeago/timeago.dart' as timeago;

class ArticleListScreen extends ConsumerWidget {
  final bool savedOnly;
  final bool isCompact;

  const ArticleListScreen({
    super.key,
    this.savedOnly = false,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = GlassTheme.of(context);
    
    // Use real article data from provider
    final articlesAsync = ref.watch(articlesProvider);
    
    if (savedOnly) {
      // Show only starred articles when savedOnly is true
      ref.read(articleFilterProvider.notifier).showStarred();
    }
    
    return articlesAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(
          color: GlassColors.primary,
        ),
      ),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: isCompact ? 48 : 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load articles',
              style: TextStyle(
                color: Colors.white,
                fontSize: isCompact ? 16 : 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: TextStyle(
                color: Colors.white60,
                fontSize: isCompact ? 12 : 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      data: (articles) {
        // Filter for saved/starred articles if needed
        final filteredArticles = savedOnly 
            ? articles.where((a) => a.isStarred).toList()
            : articles;

        if (filteredArticles.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    savedOnly ? Icons.bookmark_outline : Icons.article_outlined,
                    size: isCompact ? 48 : 64,
                    color: Colors.white30,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    savedOnly ? 'No saved articles' : 'No articles',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 16 : 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    savedOnly 
                        ? 'Save articles to read them later'
                        : 'Subscribe to feeds to see articles',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: isCompact ? 12 : 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          itemCount: filteredArticles.length,
          itemBuilder: (context, index) {
            final article = filteredArticles[index];
            final feedAsync = ref.watch(feedByIdProvider(article.feedId));
            final feed = feedAsync.value;
        return Padding(
          padding: EdgeInsets.only(bottom: isCompact ? 8 : 12),
          child: GlassCard(
            elevation: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isCompact)
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.bookmark,
                          color: Colors.orange,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feed?.title ?? 'Unknown Source',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        timeago.format(article.publishedAt),
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                if (!isCompact) const SizedBox(height: 12),
                Text(
                  article.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isCompact ? 14 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: isCompact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isCompact && article.summary != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    article.summary!,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (isCompact) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${feed?.title ?? "Unknown"} • ${timeago.format(article.publishedAt)}',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
      },
    );
  }
}