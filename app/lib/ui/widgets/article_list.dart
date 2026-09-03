import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../core/models/article.dart';
import '../../core/models/feed.dart';
import '../components/glass_card.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../glass_theme.dart';

enum ArticleViewMode {
  card,
  list,
  magazine,
  compact,
}

enum ArticleSortOption {
  date,
  title,
  source,
  readStatus,
}

class ArticleListFilter {
  final bool showRead;
  final bool showUnread;
  final bool showStarred;
  final String? feedId;
  final String? categoryId;
  final DateTime? startDate;
  final DateTime? endDate;
  
  const ArticleListFilter({
    this.showRead = true,
    this.showUnread = true,
    this.showStarred = false,
    this.feedId,
    this.categoryId,
    this.startDate,
    this.endDate,
  });
  
  ArticleListFilter copyWith({
    bool? showRead,
    bool? showUnread,
    bool? showStarred,
    String? feedId,
    String? categoryId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return ArticleListFilter(
      showRead: showRead ?? this.showRead,
      showUnread: showUnread ?? this.showUnread,
      showStarred: showStarred ?? this.showStarred,
      feedId: feedId ?? this.feedId,
      categoryId: categoryId ?? this.categoryId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }
}

class ArticleList extends ConsumerStatefulWidget {
  final List<Article> articles;
  final Map<String, Feed> feeds;
  final ArticleViewMode viewMode;
  final ArticleSortOption sortOption;
  final ArticleListFilter filter;
  final bool ascending;
  final Function(Article)? onArticleTap;
  final Function(Article)? onArticleRead;
  final Function(Article)? onArticleStar;
  final Function(Article)? onArticleShare;
  final Function(List<Article>)? onArticlesSelected;
  final bool enableSelection;
  final bool enableVirtualization;
  final ScrollController? scrollController;
  
  const ArticleList({
    super.key,
    required this.articles,
    required this.feeds,
    this.viewMode = ArticleViewMode.card,
    this.sortOption = ArticleSortOption.date,
    this.filter = const ArticleListFilter(),
    this.ascending = false,
    this.onArticleTap,
    this.onArticleRead,
    this.onArticleStar,
    this.onArticleShare,
    this.onArticlesSelected,
    this.enableSelection = false,
    this.enableVirtualization = true,
    this.scrollController,
  });

  @override
  ConsumerState<ArticleList> createState() => _ArticleListState();
}

class _ArticleListState extends ConsumerState<ArticleList> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  final Set<String> _selectedArticleIds = {};
  bool _isSelectionMode = false;
  
  List<Article> get _filteredSortedArticles {
    // Apply filters
    var filtered = widget.articles.where((article) {
      if (!widget.filter.showRead && article.isRead) return false;
      if (!widget.filter.showUnread && !article.isRead) return false;
      if (widget.filter.showStarred && !article.isStarred) return false;
      if (widget.filter.feedId != null && article.feedId != widget.filter.feedId) return false;
      if (widget.filter.startDate != null && article.publishedAt.isBefore(widget.filter.startDate!)) return false;
      if (widget.filter.endDate != null && article.publishedAt.isAfter(widget.filter.endDate!)) return false;
      return true;
    }).toList();
    
    // Apply sorting
    switch (widget.sortOption) {
      case ArticleSortOption.date:
        filtered.sort((a, b) => widget.ascending 
            ? a.publishedAt.compareTo(b.publishedAt)
            : b.publishedAt.compareTo(a.publishedAt));
        break;
      case ArticleSortOption.title:
        filtered.sort((a, b) => widget.ascending
            ? a.title.compareTo(b.title)
            : b.title.compareTo(a.title));
        break;
      case ArticleSortOption.source:
        filtered.sort((a, b) {
          final feedA = widget.feeds[a.feedId]?.name ?? '';
          final feedB = widget.feeds[b.feedId]?.name ?? '';
          return widget.ascending
              ? feedA.compareTo(feedB)
              : feedB.compareTo(feedA);
        });
        break;
      case ArticleSortOption.readStatus:
        filtered.sort((a, b) {
          if (a.isRead == b.isRead) return 0;
          return widget.ascending
              ? (a.isRead ? 1 : -1)
              : (b.isRead ? -1 : 1);
        });
        break;
    }
    
    return filtered;
  }
  
  @override
  Widget build(BuildContext context) {
    final articles = _filteredSortedArticles;
    
    if (articles.isEmpty) {
      return _buildEmptyState();
    }
    
    if (widget.enableVirtualization && articles.length > 50) {
      return _buildVirtualizedList(articles);
    } else {
      return _buildRegularList(articles);
    }
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: GlassContainer(
        width: 300,
        height: 200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 48,
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No articles found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildVirtualizedList(List<Article> articles) {
    return ScrollablePositionedList.builder(
      itemCount: articles.length,
      itemBuilder: (context, index) => _buildArticleItem(articles[index], index),
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
    );
  }
  
  Widget _buildRegularList(List<Article> articles) {
    return AnimationLimiter(
      child: ListView.builder(
        controller: widget.scrollController,
        itemCount: articles.length,
        itemBuilder: (context, index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: _buildArticleItem(articles[index], index),
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildArticleItem(Article article, int index) {
    switch (widget.viewMode) {
      case ArticleViewMode.card:
        return _buildCardView(article, index);
      case ArticleViewMode.list:
        return _buildListView(article, index);
      case ArticleViewMode.magazine:
        return _buildMagazineView(article, index);
      case ArticleViewMode.compact:
        return _buildCompactView(article, index);
    }
  }
  
  Widget _buildCardView(Article article, int index) {
    final feed = widget.feeds[article.feedId];
    final isSelected = _selectedArticleIds.contains(article.id);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GlassCard(
        onTap: () => _handleArticleTap(article),
        onLongPress: widget.enableSelection ? () => _toggleSelection(article) : null,
        borderColor: isSelected ? Theme.of(context).primaryColor : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  article.imageUrl!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (feed != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            feed.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _formatDate(article.publishedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      const Spacer(),
                      if (!article.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: article.isRead
                          ? Colors.white.withOpacity(0.7)
                          : Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      article.description!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildActionRow(article),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildListView(Article article, int index) {
    final feed = widget.feeds[article.feedId];
    final isSelected = _selectedArticleIds.contains(article.id);
    
    return Dismissible(
      key: Key(article.id),
      direction: DismissDirection.horizontal,
      background: _buildSwipeBackground(true),
      secondaryBackground: _buildSwipeBackground(false),
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) {
          widget.onArticleRead?.call(article);
        } else {
          widget.onArticleStar?.call(article);
        }
      },
      child: GlassContainer(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        borderColor: isSelected ? Theme.of(context).primaryColor : null,
        onTap: () => _handleArticleTap(article),
        onLongPress: widget.enableSelection ? () => _toggleSelection(article) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  article.imageUrl!,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 80,
                    height: 80,
                    color: Colors.white.withOpacity(0.1),
                    child: const Icon(Icons.image, color: Colors.white30),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (feed != null)
                        Text(
                          feed.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        _formatDate(article.publishedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: article.isRead
                          ? Colors.white.withOpacity(0.7)
                          : Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      article.description!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                if (!article.isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(height: 8),
                if (article.isStarred)
                  Icon(
                    Icons.star,
                    size: 16,
                    color: Colors.amber,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMagazineView(Article article, int index) {
    final feed = widget.feeds[article.feedId];
    final isSelected = _selectedArticleIds.contains(article.id);
    
    // Alternate between large and small cards
    final isLarge = index % 3 == 0;
    
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: index == 0 ? 16 : 8,
        bottom: 8,
      ),
      child: GlassCard(
        onTap: () => _handleArticleTap(article),
        onLongPress: widget.enableSelection ? () => _toggleSelection(article) : null,
        borderColor: isSelected ? Theme.of(context).primaryColor : null,
        child: isLarge
            ? _buildLargeMagazineCard(article, feed)
            : _buildSmallMagazineCard(article, feed),
      ),
    );
  }
  
  Widget _buildLargeMagazineCard(Article article, Feed? feed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (article.imageUrl != null)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Image.network(
              article.imageUrl!,
              width: double.infinity,
              height: 250,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (feed != null)
                Text(
                  feed.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                article.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (article.author != null) ...[
                    Text(
                      'By ${article.author}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Text(
                    _formatDate(article.publishedAt),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
              if (article.description != null) ...[
                const SizedBox(height: 16),
                Text(
                  article.description!,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.8),
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildSmallMagazineCard(Article article, Feed? feed) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (article.imageUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              article.imageUrl!,
              width: 120,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 120,
                height: 120,
                color: Colors.white.withOpacity(0.1),
                child: const Icon(Icons.image, color: Colors.white30),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (feed != null)
                  Text(
                    feed.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  article.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDate(article.publishedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildCompactView(Article article, int index) {
    final feed = widget.feeds[article.feedId];
    final isSelected = _selectedArticleIds.contains(article.id);
    
    return InkWell(
      onTap: () => _handleArticleTap(article),
      onLongPress: widget.enableSelection ? () => _toggleSelection(article) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.1),
              width: 0.5,
            ),
          ),
          color: isSelected ? Colors.white.withOpacity(0.05) : null,
        ),
        child: Row(
          children: [
            if (!article.isRead)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: TextStyle(
                      fontSize: 14,
                      color: article.isRead
                          ? Colors.white.withOpacity(0.7)
                          : Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (feed != null) ...[
                        Text(
                          feed.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _formatDate(article.publishedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (article.isStarred)
              Icon(
                Icons.star,
                size: 16,
                color: Colors.amber.withOpacity(0.8),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionRow(Article article) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _buildActionButton(
              icon: article.isRead ? Icons.visibility : Icons.visibility_off,
              onTap: () => widget.onArticleRead?.call(article),
              tooltip: article.isRead ? 'Mark as unread' : 'Mark as read',
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              icon: article.isStarred ? Icons.star : Icons.star_border,
              onTap: () => widget.onArticleStar?.call(article),
              tooltip: article.isStarred ? 'Unstar' : 'Star',
              color: article.isStarred ? Colors.amber : null,
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              icon: Icons.share,
              onTap: () => widget.onArticleShare?.call(article),
              tooltip: 'Share',
            ),
          ],
        ),
        if (_isSelectionMode)
          Checkbox(
            value: _selectedArticleIds.contains(article.id),
            onChanged: (_) => _toggleSelection(article),
            fillColor: MaterialStateProperty.all(
              Theme.of(context).primaryColor.withOpacity(0.8),
            ),
          ),
      ],
    );
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 20,
            color: color ?? Colors.white.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
  
  Widget _buildSwipeBackground(bool isLeft) {
    return Container(
      color: isLeft ? Colors.green.withOpacity(0.3) : Colors.amber.withOpacity(0.3),
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(
        isLeft ? Icons.done : Icons.star,
        color: Colors.white,
        size: 28,
      ),
    );
  }
  
  void _handleArticleTap(Article article) {
    if (_isSelectionMode) {
      _toggleSelection(article);
    } else {
      widget.onArticleTap?.call(article);
    }
  }
  
  void _toggleSelection(Article article) {
    setState(() {
      if (_selectedArticleIds.contains(article.id)) {
        _selectedArticleIds.remove(article.id);
        if (_selectedArticleIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedArticleIds.add(article.id);
        if (!_isSelectionMode) {
          _isSelectionMode = true;
          HapticFeedback.mediumImpact();
        }
      }
    });
    
    if (widget.onArticlesSelected != null) {
      final selectedArticles = widget.articles
          .where((a) => _selectedArticleIds.contains(a.id))
          .toList();
      widget.onArticlesSelected!(selectedArticles);
    }
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

// View mode selector widget
class ArticleViewModeSelector extends StatelessWidget {
  final ArticleViewMode currentMode;
  final ValueChanged<ArticleViewMode> onModeChanged;
  
  const ArticleViewModeSelector({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });
  
  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            context,
            ArticleViewMode.card,
            Icons.view_agenda,
            'Card view',
          ),
          _buildModeButton(
            context,
            ArticleViewMode.list,
            Icons.view_list,
            'List view',
          ),
          _buildModeButton(
            context,
            ArticleViewMode.magazine,
            Icons.view_quilt,
            'Magazine view',
          ),
          _buildModeButton(
            context,
            ArticleViewMode.compact,
            Icons.view_headline,
            'Compact view',
          ),
        ],
      ),
    );
  }
  
  Widget _buildModeButton(
    BuildContext context,
    ArticleViewMode mode,
    IconData icon,
    String tooltip,
  ) {
    final isSelected = currentMode == mode;
    
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onModeChanged(mode),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withOpacity(0.2) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}

// Sort options widget
class ArticleSortSelector extends StatelessWidget {
  final ArticleSortOption currentSort;
  final bool ascending;
  final ValueChanged<ArticleSortOption> onSortChanged;
  final VoidCallback onToggleAscending;
  
  const ArticleSortSelector({
    super.key,
    required this.currentSort,
    required this.ascending,
    required this.onSortChanged,
    required this.onToggleAscending,
  });
  
  @override
  Widget build(BuildContext context) {
    return GlassButton(
      onPressed: () => _showSortMenu(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sort,
            size: 18,
            color: Colors.white.withOpacity(0.8),
          ),
          const SizedBox(width: 4),
          Text(
            _getSortLabel(currentSort),
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            ascending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
            color: Colors.white.withOpacity(0.6),
          ),
        ],
      ),
    );
  }
  
  void _showSortMenu(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(100, 100, 0, 0),
      items: ArticleSortOption.values.map((option) {
        return PopupMenuItem(
          value: option,
          child: Row(
            children: [
              Icon(
                _getSortIcon(option),
                size: 20,
                color: currentSort == option
                    ? Theme.of(context).primaryColor
                    : Colors.white70,
              ),
              const SizedBox(width: 12),
              Text(
                _getSortLabel(option),
                style: TextStyle(
                  color: currentSort == option
                      ? Theme.of(context).primaryColor
                      : Colors.white,
                ),
              ),
            ],
          ),
        );
      }).toList()
        ..add(
          const PopupMenuItem(
            enabled: false,
            child: Divider(),
          ),
        )
        ..add(
          PopupMenuItem(
            onTap: onToggleAscending,
            child: Row(
              children: [
                Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 20,
                  color: Colors.white70,
                ),
                const SizedBox(width: 12),
                Text(
                  ascending ? 'Ascending' : 'Descending',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      color: Colors.grey[900],
      elevation: 8,
    ).then((value) {
      if (value != null && value is ArticleSortOption) {
        onSortChanged(value);
      }
    });
  }
  
  String _getSortLabel(ArticleSortOption option) {
    switch (option) {
      case ArticleSortOption.date:
        return 'Date';
      case ArticleSortOption.title:
        return 'Title';
      case ArticleSortOption.source:
        return 'Source';
      case ArticleSortOption.readStatus:
        return 'Read Status';
    }
  }
  
  IconData _getSortIcon(ArticleSortOption option) {
    switch (option) {
      case ArticleSortOption.date:
        return Icons.calendar_today;
      case ArticleSortOption.title:
        return Icons.sort_by_alpha;
      case ArticleSortOption.source:
        return Icons.source;
      case ArticleSortOption.readStatus:
        return Icons.visibility;
    }
  }
}