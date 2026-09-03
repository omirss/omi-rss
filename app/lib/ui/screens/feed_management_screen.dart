import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/models/feed.dart';
import '../../core/models/category.dart';
import '../../core/services/feed_service.dart';
import '../../core/services/opml_service.dart';
import '../../providers/feed_provider.dart';
import '../../providers/category_provider.dart';
import '../glass_theme.dart';
import '../components/glass_card.dart';
import '../components/glass_dialog.dart';
import '../components/glass_snack_bar.dart';
import '../animations/loading_animation.dart';
import 'feed_health_screen.dart';

/// Feed management screen with FreshRSS features
class FeedManagementScreen extends ConsumerStatefulWidget {
  const FeedManagementScreen({super.key});

  @override
  ConsumerState<FeedManagementScreen> createState() => _FeedManagementScreenState();
}

class _FeedManagementScreenState extends ConsumerState<FeedManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategoryId;
  FeedSortOption _sortOption = FeedSortOption.alphabetical;
  bool _showInactiveFeeds = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final feeds = ref.watch(feedsProvider);
    final categories = ref.watch(categoriesProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Feed Management'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Feeds', icon: Icon(Icons.rss_feed)),
            Tab(text: 'Categories', icon: Icon(Icons.folder)),
            Tab(text: 'Import/Export', icon: Icon(Icons.import_export)),
          ],
          indicatorColor: theme.accentColor,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAllFeeds,
            tooltip: 'Refresh all feeds',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddFeedDialog,
            tooltip: 'Add feed',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFeedsTab(feeds, categories, theme),
          _buildCategoriesTab(categories, theme),
          _buildImportExportTab(theme),
        ],
      ),
    );
  }

  Widget _buildFeedsTab(
    List<Feed> feeds,
    List<Category> categories,
    GlassThemeData theme,
  ) {
    // Filter feeds
    var filteredFeeds = feeds.where((feed) {
      if (!_showInactiveFeeds && !feed.isActive) return false;
      if (_selectedCategoryId != null && feed.categoryId != _selectedCategoryId) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        return feed.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               (feed.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      }
      return true;
    }).toList();

    // Sort feeds
    switch (_sortOption) {
      case FeedSortOption.alphabetical:
        filteredFeeds.sort((a, b) => a.title.compareTo(b.title));
        break;
      case FeedSortOption.lastUpdated:
        filteredFeeds.sort((a, b) {
          final aTime = a.lastFetched ?? DateTime(1970);
          final bTime = b.lastFetched ?? DateTime(1970);
          return bTime.compareTo(aTime);
        });
        break;
      case FeedSortOption.articleCount:
        // Would need article count from database
        break;
      case FeedSortOption.health:
        filteredFeeds.sort((a, b) => b.successRate.compareTo(a.successRate));
        break;
    }

    return Column(
      children: [
        // Search and filters
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Search bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search feeds...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
              const SizedBox(height: 12),
              // Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Category filter
                    FilterChip(
                      label: Text(_selectedCategoryId == null
                          ? 'All Categories'
                          : categories.firstWhere((c) => c.id == _selectedCategoryId).name),
                      selected: _selectedCategoryId != null,
                      onSelected: (_) => _showCategoryFilter(categories),
                    ),
                    const SizedBox(width: 8),
                    // Sort options
                    FilterChip(
                      label: Text(_getSortLabel()),
                      onSelected: (_) => _showSortOptions(),
                    ),
                    const SizedBox(width: 8),
                    // Show inactive
                    FilterChip(
                      label: const Text('Show Inactive'),
                      selected: _showInactiveFeeds,
                      onSelected: (value) {
                        setState(() => _showInactiveFeeds = value);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Feed list
        Expanded(
          child: filteredFeeds.isEmpty
              ? Center(
                  child: Text(
                    'No feeds found',
                    style: theme.bodyLarge.copyWith(
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filteredFeeds.length,
                  itemBuilder: (context, index) {
                    return _buildFeedItem(filteredFeeds[index], theme);
                  },
                ),
        ),
        // Batch actions
        if (filteredFeeds.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh All'),
                  onPressed: () => _batchRefresh(filteredFeeds),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Mark All Read'),
                  onPressed: () => _markAllAsRead(filteredFeeds),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clean Up'),
                  onPressed: _showCleanupDialog,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFeedItem(Feed feed, GlassThemeData theme) {
    final isHealthy = feed.successRate > 0.8;
    
    return Dismissible(
      key: Key(feed.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red.withOpacity(0.2),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      confirmDismiss: (direction) async {
        return await GlassDialog.showConfirmation(
          context: context,
          title: 'Delete Feed',
          content: 'Are you sure you want to delete "${feed.title}"?',
          confirmText: 'Delete',
          confirmColor: Colors.red,
        );
      },
      onDismissed: (direction) {
        ref.read(feedsProvider.notifier).deleteFeed(feed.id);
        GlassSnackBar.showSuccess(
          context: context,
          message: 'Feed deleted',
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.white.withOpacity(0.05),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: feed.isActive
                ? (isHealthy ? Colors.green : Colors.orange)
                : Colors.grey,
            child: feed.faviconUrl != null
                ? ClipOval(
                    child: Image.network(
                      feed.faviconUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.rss_feed,
                          color: Colors.white.withOpacity(0.8),
                        );
                      },
                    ),
                  )
                : Icon(
                    Icons.rss_feed,
                    color: Colors.white.withOpacity(0.8),
                  ),
          ),
          title: Text(
            feed.customTitle ?? feed.title,
            style: theme.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: feed.isActive ? null : Colors.white.withOpacity(0.5),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (feed.description != null)
                Text(
                  feed.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    isHealthy ? Icons.check_circle : Icons.warning,
                    size: 16,
                    color: isHealthy ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(feed.successRate * 100).toStringAsFixed(0)}% success',
                    style: theme.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (feed.lastFetched != null)
                    Text(
                      'Updated ${_formatRelativeTime(feed.lastFetched!)}',
                      style: theme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => _handleFeedAction(value, feed),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'health',
                child: ListTile(
                  leading: Icon(Icons.monitor_heart),
                  title: Text('View Health'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: ListTile(
                  leading: Icon(feed.isActive ? Icons.pause : Icons.play_arrow),
                  title: Text(feed.isActive ? 'Disable' : 'Enable'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Refresh'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'markRead',
                child: ListTile(
                  leading: Icon(Icons.done_all),
                  title: Text('Mark All Read'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          onTap: () => _handleFeedAction('health', feed),
        ),
      ),
    );
  }

  Widget _buildCategoriesTab(List<Category> categories, GlassThemeData theme) {
    // Build category tree
    final rootCategories = categories.where((c) => c.parentId == null).toList();
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Add category button
        GlassCard(
          theme: theme,
          onTap: _showAddCategoryDialog,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add),
                SizedBox(width: 8),
                Text('Add Category'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Category tree
        ...rootCategories.map((category) => _buildCategoryItem(
          category,
          categories,
          theme,
          0,
        )),
      ],
    );
  }

  Widget _buildCategoryItem(
    Category category,
    List<Category> allCategories,
    GlassThemeData theme,
    int depth,
  ) {
    final childCategories = allCategories
        .where((c) => c.parentId == category.id)
        .toList();
    final feedCount = ref.watch(feedsProvider)
        .where((f) => f.categoryId == category.id)
        .length;
    
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 24.0),
          child: Card(
            color: Colors.white.withOpacity(0.05),
            child: ListTile(
              leading: Icon(
                childCategories.isNotEmpty
                    ? Icons.folder
                    : Icons.folder_outlined,
                color: theme.accentColor,
              ),
              title: Text(
                category.name,
                style: theme.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '$feedCount feeds',
                style: theme.bodySmall.copyWith(
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _handleCategoryAction(value, category),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Child categories
        ...childCategories.map((child) => _buildCategoryItem(
          child,
          allCategories,
          theme,
          depth + 1,
        )),
      ],
    );
  }

  Widget _buildImportExportTab(GlassThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Import section
        GlassCard(
          theme: theme,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.file_upload, color: theme.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      'Import OPML',
                      style: theme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Import your feeds from another RSS reader using OPML format.',
                  style: theme.bodyMedium.copyWith(
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.file_open),
                    label: const Text('Choose OPML File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _importOpml,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Export section
        GlassCard(
          theme: theme,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.file_download, color: theme.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      'Export OPML',
                      style: theme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Export your feeds to OPML format for backup or migration.',
                  style: theme.bodyMedium.copyWith(
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Export Feeds'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _exportOpml,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Backup section
        GlassCard(
          theme: theme,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.backup, color: theme.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      'Backup & Restore',
                      style: theme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Create a full backup including articles, read status, and settings.',
                  style: theme.bodyMedium.copyWith(
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.backup),
                      label: const Text('Create Backup'),
                      onPressed: _createBackup,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore Backup'),
                      onPressed: _restoreBackup,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddFeedDialog() {
    GlassDialog.show(
      context: context,
      title: const Text('Add Feed'),
      content: const AddFeedDialog(),
    );
  }

  void _showAddCategoryDialog() {
    GlassDialog.show(
      context: context,
      title: const Text('Add Category'),
      content: const AddCategoryDialog(),
    );
  }

  void _showCategoryFilter(List<Category> categories) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All Categories'),
              leading: const Icon(Icons.folder),
              selected: _selectedCategoryId == null,
              onTap: () {
                setState(() => _selectedCategoryId = null);
                Navigator.pop(context);
              },
            ),
            ...categories.map((category) => ListTile(
              title: Text(category.name),
              leading: const Icon(Icons.folder_outlined),
              selected: _selectedCategoryId == category.id,
              onTap: () {
                setState(() => _selectedCategoryId = category.id);
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: FeedSortOption.values.map((option) => ListTile(
            title: Text(_getSortLabel(option)),
            leading: Icon(_getSortIcon(option)),
            selected: _sortOption == option,
            onTap: () {
              setState(() => _sortOption = option);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showCleanupDialog() {
    GlassDialog.show(
      context: context,
      title: const Text('Clean Up Articles'),
      content: const CleanupDialog(),
    );
  }

  Future<void> _refreshAllFeeds() async {
    final feeds = ref.read(feedsProvider);
    GlassDialog.showLoading(
      context: context,
      message: 'Refreshing all feeds...',
    );
    
    try {
      await ref.read(feedServiceProvider).batchRefresh(feeds);
      if (mounted) {
        Navigator.pop(context);
        GlassSnackBar.showSuccess(
          context: context,
          message: 'All feeds refreshed',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        GlassSnackBar.showError(
          context: context,
          message: 'Failed to refresh feeds: $e',
        );
      }
    }
  }

  Future<void> _batchRefresh(List<Feed> feeds) async {
    GlassDialog.showLoading(
      context: context,
      message: 'Refreshing ${feeds.length} feeds...',
    );
    
    try {
      await ref.read(feedServiceProvider).batchRefresh(feeds);
      if (mounted) {
        Navigator.pop(context);
        GlassSnackBar.showSuccess(
          context: context,
          message: '${feeds.length} feeds refreshed',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        GlassSnackBar.showError(
          context: context,
          message: 'Failed to refresh feeds: $e',
        );
      }
    }
  }

  Future<void> _markAllAsRead(List<Feed> feeds) async {
    final confirmed = await GlassDialog.showConfirmation(
      context: context,
      title: 'Mark All as Read',
      content: 'Mark all articles in ${feeds.length} feeds as read?',
    );
    
    if (confirmed == true) {
      try {
        await ref.read(feedServiceProvider).markFeedsAsRead(
          feeds.map((f) => f.id).toList(),
        );
        if (mounted) {
          GlassSnackBar.showSuccess(
            context: context,
            message: 'All articles marked as read',
          );
        }
      } catch (e) {
        if (mounted) {
          GlassSnackBar.showError(
            context: context,
            message: 'Failed to mark as read: $e',
          );
        }
      }
    }
  }

  void _handleFeedAction(String action, Feed feed) {
    switch (action) {
      case 'edit':
        GlassDialog.show(
          context: context,
          title: const Text('Edit Feed'),
          content: EditFeedDialog(feed: feed),
        );
        break;
      case 'health':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FeedHealthScreen(
              feed: feed,
              feedService: ref.read(feedServiceProvider),
            ),
          ),
        );
        break;
      case 'toggle':
        ref.read(feedsProvider.notifier).updateFeed(
          feed.copyWith(isActive: !feed.isActive),
        );
        break;
      case 'refresh':
        _refreshSingleFeed(feed);
        break;
      case 'markRead':
        _markFeedAsRead(feed);
        break;
    }
  }

  void _handleCategoryAction(String action, Category category) {
    switch (action) {
      case 'edit':
        GlassDialog.show(
          context: context,
          title: const Text('Edit Category'),
          content: EditCategoryDialog(category: category),
        );
        break;
      case 'delete':
        _deleteCategory(category);
        break;
    }
  }

  Future<void> _refreshSingleFeed(Feed feed) async {
    try {
      await ref.read(feedServiceProvider).refreshFeed(feed);
      if (mounted) {
        GlassSnackBar.showSuccess(
          context: context,
          message: 'Feed refreshed',
        );
      }
    } catch (e) {
      if (mounted) {
        GlassSnackBar.showError(
          context: context,
          message: 'Failed to refresh feed: $e',
        );
      }
    }
  }

  Future<void> _markFeedAsRead(Feed feed) async {
    try {
      await ref.read(feedServiceProvider).markFeedAsRead(feed.id);
      if (mounted) {
        GlassSnackBar.showSuccess(
          context: context,
          message: 'All articles marked as read',
        );
      }
    } catch (e) {
      if (mounted) {
        GlassSnackBar.showError(
          context: context,
          message: 'Failed to mark as read: $e',
        );
      }
    }
  }

  Future<void> _deleteCategory(Category category) async {
    final hasFeeds = ref.read(feedsProvider)
        .any((f) => f.categoryId == category.id);
    
    if (hasFeeds) {
      GlassSnackBar.showError(
        context: context,
        message: 'Cannot delete category with feeds',
      );
      return;
    }
    
    final confirmed = await GlassDialog.showConfirmation(
      context: context,
      title: 'Delete Category',
      content: 'Are you sure you want to delete "${category.name}"?',
      confirmText: 'Delete',
      confirmColor: Colors.red,
    );
    
    if (confirmed == true) {
      ref.read(categoriesProvider.notifier).deleteCategory(category.id);
      GlassSnackBar.showSuccess(
        context: context,
        message: 'Category deleted',
      );
    }
  }

  Future<void> _importOpml() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['opml', 'xml'],
      );
      
      if (result != null && result.files.single.path != null) {
        // Show import progress dialog
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OpmlImportScreen(
                filePath: result.files.single.path!,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        GlassSnackBar.showError(
          context: context,
          message: 'Failed to import OPML: $e',
        );
      }
    }
  }

  Future<void> _exportOpml() async {
    try {
      final feeds = ref.read(feedsProvider);
      final categories = ref.read(categoriesProvider);
      final opmlService = ref.read(opmlServiceProvider);
      
      final opml = await opmlService.exportOpml(
        feeds: feeds,
        categories: categories,
      );
      
      // Save file
      final outputFile = await FilePicker.platform.saveFile(
        fileName: 'feeds_${DateTime.now().millisecondsSinceEpoch}.opml',
        type: FileType.custom,
        allowedExtensions: ['opml'],
      );
      
      if (outputFile != null) {
        // Write OPML content to file
        // Implementation depends on platform
        if (mounted) {
          GlassSnackBar.showSuccess(
            context: context,
            message: 'Feeds exported successfully',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        GlassSnackBar.showError(
          context: context,
          message: 'Failed to export feeds: $e',
        );
      }
    }
  }

  Future<void> _createBackup() async {
    // TODO: Implement full backup
    GlassSnackBar.showInfo(
      context: context,
      message: 'Backup feature coming soon',
    );
  }

  Future<void> _restoreBackup() async {
    // TODO: Implement restore
    GlassSnackBar.showInfo(
      context: context,
      message: 'Restore feature coming soon',
    );
  }

  String _getSortLabel([FeedSortOption? option]) {
    switch (option ?? _sortOption) {
      case FeedSortOption.alphabetical:
        return 'Alphabetical';
      case FeedSortOption.lastUpdated:
        return 'Last Updated';
      case FeedSortOption.articleCount:
        return 'Article Count';
      case FeedSortOption.health:
        return 'Health Status';
    }
  }

  IconData _getSortIcon(FeedSortOption option) {
    switch (option) {
      case FeedSortOption.alphabetical:
        return Icons.sort_by_alpha;
      case FeedSortOption.lastUpdated:
        return Icons.update;
      case FeedSortOption.articleCount:
        return Icons.format_list_numbered;
      case FeedSortOption.health:
        return Icons.monitor_heart;
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

/// Feed sort options
enum FeedSortOption {
  alphabetical,
  lastUpdated,
  articleCount,
  health,
}

// Dialog widgets would be implemented separately
class AddFeedDialog extends StatelessWidget {
  const AddFeedDialog({super.key});
  
  @override
  Widget build(BuildContext context) {
    // TODO: Implement add feed dialog
    return const Text('Add feed dialog');
  }
}

class EditFeedDialog extends StatelessWidget {
  final Feed feed;
  
  const EditFeedDialog({super.key, required this.feed});
  
  @override
  Widget build(BuildContext context) {
    // TODO: Implement edit feed dialog
    return const Text('Edit feed dialog');
  }
}

class AddCategoryDialog extends StatelessWidget {
  const AddCategoryDialog({super.key});
  
  @override
  Widget build(BuildContext context) {
    // TODO: Implement add category dialog
    return const Text('Add category dialog');
  }
}

class EditCategoryDialog extends StatelessWidget {
  final Category category;
  
  const EditCategoryDialog({super.key, required this.category});
  
  @override
  Widget build(BuildContext context) {
    // TODO: Implement edit category dialog
    return const Text('Edit category dialog');
  }
}

class CleanupDialog extends StatelessWidget {
  const CleanupDialog({super.key});
  
  @override
  Widget build(BuildContext context) {
    // TODO: Implement cleanup dialog
    return const Text('Cleanup dialog');
  }
}

class OpmlImportScreen extends StatelessWidget {
  final String filePath;
  
  const OpmlImportScreen({super.key, required this.filePath});
  
  @override
  Widget build(BuildContext context) {
    // TODO: Implement OPML import progress screen
    return Scaffold(
      appBar: AppBar(title: const Text('Import OPML')),
      body: const Center(child: Text('Importing...')),
    );
  }
}