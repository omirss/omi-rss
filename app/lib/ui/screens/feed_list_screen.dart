import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rss_glassmorphism_reader/ui/glass_theme.dart';
import 'package:rss_glassmorphism_reader/ui/components/glass_container.dart';
import 'package:rss_glassmorphism_reader/providers/feed_provider.dart';
import 'package:rss_glassmorphism_reader/core/models/feed.dart';

class FeedListScreen extends ConsumerWidget {
  final bool isCompact;

  const FeedListScreen({
    super.key,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = GlassTheme.of(context);
    
    // Use real feed data from provider
    final feedsAsync = ref.watch(feedsProvider);
    
    return feedsAsync.when(
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
              'Failed to load feeds',
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
      data: (feeds) {
        if (feeds.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.rss_feed,
                    size: isCompact ? 48 : 64,
                    color: Colors.white30,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No feeds subscribed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 16 : 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add feeds to start reading',
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
          itemCount: feeds.length,
          itemBuilder: (context, index) {
            final feed = feeds[index];
            
            // Get unread count for this feed
            final articlesAsync = ref.watch(articlesByFeedProvider(feed.id));
            final unreadCount = articlesAsync.maybeWhen(
              data: (articles) => articles.where((a) => !a.isRead).length,
              orElse: () => 0,
            );
            
            return Padding(
              padding: EdgeInsets.only(bottom: isCompact ? 8 : 12),
              child: GlassContainer(
                onTap: () {
                  // Navigate to feed articles
                  ref.read(articleFilterProvider.notifier).showFeed(feed.id);
                  Navigator.pushNamed(context, '/articles');
                },
                padding: EdgeInsets.all(isCompact ? 12 : 16),
                child: Row(
                  children: [
                    Container(
                      width: isCompact ? 32 : 40,
                      height: isCompact ? 32 : 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: GlassColors.primaryGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(isCompact ? 8 : 10),
                      ),
                      child: feed.faviconUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(isCompact ? 8 : 10),
                              child: Image.network(
                                feed.faviconUrl!,
                                width: isCompact ? 32 : 40,
                                height: isCompact ? 32 : 40,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.rss_feed,
                                    color: Colors.white,
                                    size: isCompact ? 16 : 20,
                                  );
                                },
                              ),
                            )
                          : Icon(
                              Icons.rss_feed,
                              color: Colors.white,
                              size: isCompact ? 16 : 20,
                            ),
                    ),
                    SizedBox(width: isCompact ? 8 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            feed.customTitle ?? feed.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isCompact ? 14 : 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      if (!isCompact) ...[
                        const SizedBox(height: 4),
                        Text(
                          feed.url,
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (unreadCount > 0)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 6 : 8,
                      vertical: isCompact ? 2 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$unreadCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isCompact ? 11 : 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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