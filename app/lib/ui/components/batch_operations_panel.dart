import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/feed.dart';
import '../../core/models/category.dart';
import '../../core/services/feed_service.dart';
import '../glass_theme.dart';
import 'glass_container.dart';
import 'glass_button.dart';
import 'glass_dialog.dart';
import 'glass_snack_bar.dart';

/// Enhanced batch operations panel for feed management
class BatchOperationsPanel extends ConsumerStatefulWidget {
  final List<Feed> selectedFeeds;
  final VoidCallback onClearSelection;
  final Function(List<Feed>)? onOperationComplete;
  
  const BatchOperationsPanel({
    super.key,
    required this.selectedFeeds,
    required this.onClearSelection,
    this.onOperationComplete,
  });

  @override
  ConsumerState<BatchOperationsPanel> createState() => _BatchOperationsPanelState();
}

class _BatchOperationsPanelState extends ConsumerState<BatchOperationsPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  bool _isExpanded = false;
  bool _isProcessing = false;
  double _progress = 0.0;
  String _currentOperation = '';
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    if (widget.selectedFeeds.isNotEmpty) {
      _animationController.forward();
    }
  }
  
  @override
  void didUpdateWidget(BatchOperationsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedFeeds.isNotEmpty && oldWidget.selectedFeeds.isEmpty) {
      _animationController.forward();
    } else if (widget.selectedFeeds.isEmpty && oldWidget.selectedFeeds.isNotEmpty) {
      _animationController.reverse();
    }
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (widget.selectedFeeds.isEmpty) return const SizedBox.shrink();
    
    final theme = GlassTheme.of(context);
    
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 100 * (1 - _slideAnimation.value)),
          child: Opacity(
            opacity: _slideAnimation.value,
            child: GlassContainer(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              gradientColors: [
                theme.primaryColor.withOpacity(0.1),
                theme.secondaryColor.withOpacity(0.05),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.accentColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.selectedFeeds.length} feeds selected',
                        style: theme.titleMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white.withOpacity(0.7),
                        ),
                        onPressed: () {
                          setState(() => _isExpanded = !_isExpanded);
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: Colors.white.withOpacity(0.7),
                        ),
                        onPressed: widget.onClearSelection,
                      ),
                    ],
                  ),
                  
                  // Progress indicator
                  if (_isProcessing) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentOperation,
                      style: theme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                  
                  // Quick actions
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildQuickAction(
                          icon: Icons.refresh,
                          label: 'Refresh',
                          onTap: _refreshSelectedFeeds,
                          theme: theme,
                        ),
                        const SizedBox(width: 8),
                        _buildQuickAction(
                          icon: Icons.done_all,
                          label: 'Mark Read',
                          onTap: _markSelectedAsRead,
                          theme: theme,
                        ),
                        const SizedBox(width: 8),
                        _buildQuickAction(
                          icon: Icons.folder_outlined,
                          label: 'Move',
                          onTap: _moveToCategory,
                          theme: theme,
                        ),
                        const SizedBox(width: 8),
                        _buildQuickAction(
                          icon: Icons.pause_circle_outline,
                          label: 'Disable',
                          onTap: _toggleSelectedFeeds,
                          theme: theme,
                        ),
                        const SizedBox(width: 8),
                        _buildQuickAction(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          onTap: _deleteSelectedFeeds,
                          theme: theme,
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ),
                  
                  // Expanded options
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _buildExpandedOptions(theme),
                    crossFadeState: _isExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required GlassThemeData theme,
    Color? color,
  }) {
    return GlassButton(
      onPressed: _isProcessing ? null : onTap,
      variant: GlassButtonVariant.outlined,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: color ?? Colors.white.withOpacity(0.9),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.bodySmall.copyWith(
              color: color ?? Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildExpandedOptions(GlassThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text(
          'Advanced Operations',
          style: theme.titleSmall.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildAdvancedOption(
              icon: Icons.update,
              label: 'Update Frequency',
              description: 'Change how often feeds update',
              onTap: _changeUpdateFrequency,
              theme: theme,
            ),
            _buildAdvancedOption(
              icon: Icons.label_outline,
              label: 'Bulk Tag',
              description: 'Add tags to selected feeds',
              onTap: _bulkTag,
              theme: theme,
            ),
            _buildAdvancedOption(
              icon: Icons.file_download,
              label: 'Export Selected',
              description: 'Export as OPML',
              onTap: _exportSelected,
              theme: theme,
            ),
            _buildAdvancedOption(
              icon: Icons.analytics_outlined,
              label: 'View Statistics',
              description: 'Analyze feed performance',
              onTap: _viewStatistics,
              theme: theme,
            ),
            _buildAdvancedOption(
              icon: Icons.cleaning_services,
              label: 'Clean Articles',
              description: 'Remove old articles',
              onTap: _cleanArticles,
              theme: theme,
            ),
            _buildAdvancedOption(
              icon: Icons.merge_type,
              label: 'Merge Feeds',
              description: 'Combine into one feed',
              onTap: _mergeFeeds,
              theme: theme,
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildAdvancedOption({
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback onTap,
    required GlassThemeData theme,
  }) {
    return GlassContainer(
      width: 150,
      padding: const EdgeInsets.all(12),
      onTap: _isProcessing ? null : onTap,
      enableHover: !_isProcessing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.bodySmall.copyWith(
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _refreshSelectedFeeds() async {
    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _currentOperation = 'Refreshing feeds...';
    });
    
    try {
      final feedService = ref.read(feedServiceProvider);
      
      for (int i = 0; i < widget.selectedFeeds.length; i++) {
        setState(() {
          _progress = (i + 1) / widget.selectedFeeds.length;
          _currentOperation = 'Refreshing ${widget.selectedFeeds[i].title}...';
        });
        
        await feedService.refreshFeed(widget.selectedFeeds[i]);
      }
      
      if (mounted) {
        context.showSuccessSnackBar('All feeds refreshed successfully');
        widget.onOperationComplete?.call(widget.selectedFeeds);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to refresh some feeds: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progress = 0.0;
          _currentOperation = '';
        });
      }
    }
  }
  
  Future<void> _markSelectedAsRead() async {
    final confirmed = await showGlassConfirmDialog(
      context: context,
      title: 'Mark as Read',
      message: 'Mark all articles in ${widget.selectedFeeds.length} feeds as read?',
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Marking articles as read...';
    });
    
    try {
      final feedService = ref.read(feedServiceProvider);
      await feedService.markFeedsAsRead(
        widget.selectedFeeds.map((f) => f.id).toList(),
      );
      
      if (mounted) {
        context.showSuccessSnackBar('All articles marked as read');
        widget.onOperationComplete?.call(widget.selectedFeeds);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to mark as read: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
  
  Future<void> _moveToCategory() async {
    final categories = ref.read(categoriesProvider);
    final selectedCategory = await showGlassDialog<Category>(
      context: context,
      title: const Text('Move to Category'),
      content: SizedBox(
        width: 300,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(category.name),
              onTap: () => Navigator.of(context).pop(category),
            );
          },
        ),
      ),
    );
    
    if (selectedCategory == null) return;
    
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Moving feeds to ${selectedCategory.name}...';
    });
    
    try {
      for (final feed in widget.selectedFeeds) {
        await ref.read(feedsProvider.notifier).updateFeed(
          feed.copyWith(categoryId: selectedCategory.id),
        );
      }
      
      if (mounted) {
        context.showSuccessSnackBar(
          'Moved ${widget.selectedFeeds.length} feeds to ${selectedCategory.name}',
        );
        widget.onOperationComplete?.call(widget.selectedFeeds);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to move feeds: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
  
  Future<void> _toggleSelectedFeeds() async {
    final anyActive = widget.selectedFeeds.any((f) => f.isActive);
    final action = anyActive ? 'disable' : 'enable';
    
    setState(() {
      _isProcessing = true;
      _currentOperation = '${action.substring(0, 1).toUpperCase()}${action.substring(1)}ing feeds...';
    });
    
    try {
      for (final feed in widget.selectedFeeds) {
        await ref.read(feedsProvider.notifier).updateFeed(
          feed.copyWith(isActive: !anyActive),
        );
      }
      
      if (mounted) {
        context.showSuccessSnackBar(
          '${widget.selectedFeeds.length} feeds ${action}d',
        );
        widget.onOperationComplete?.call(widget.selectedFeeds);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to $action feeds: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
  
  Future<void> _deleteSelectedFeeds() async {
    final confirmed = await showGlassConfirmDialog(
      context: context,
      title: 'Delete Feeds',
      message: 'Are you sure you want to delete ${widget.selectedFeeds.length} feeds? This action cannot be undone.',
      confirmText: 'Delete',
      destructive: true,
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Deleting feeds...';
    });
    
    try {
      for (final feed in widget.selectedFeeds) {
        await ref.read(feedsProvider.notifier).deleteFeed(feed.id);
      }
      
      if (mounted) {
        context.showSuccessSnackBar(
          '${widget.selectedFeeds.length} feeds deleted',
        );
        widget.onClearSelection();
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to delete feeds: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
  
  Future<void> _changeUpdateFrequency() async {
    final minutes = await showGlassDialog<int>(
      context: context,
      title: const Text('Update Frequency'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select update frequency for selected feeds:'),
          const SizedBox(height: 16),
          ...const [15, 30, 60, 120, 360, 720, 1440].map((minutes) {
            final hours = minutes ~/ 60;
            final label = minutes < 60
                ? '$minutes minutes'
                : hours == 1
                    ? '1 hour'
                    : '$hours hours';
            
            return ListTile(
              title: Text(label),
              onTap: () => Navigator.of(context).pop(minutes),
            );
          }),
        ],
      ),
    );
    
    if (minutes == null) return;
    
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Updating frequency...';
    });
    
    try {
      for (final feed in widget.selectedFeeds) {
        await ref.read(feedsProvider.notifier).updateFeed(
          feed.copyWith(updateFrequency: minutes * 60),
        );
      }
      
      if (mounted) {
        context.showSuccessSnackBar('Update frequency changed');
        widget.onOperationComplete?.call(widget.selectedFeeds);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to update frequency: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
  
  Future<void> _bulkTag() async {
    // TODO: Implement bulk tagging
    context.showGlassSnackBar('Bulk tagging coming soon', type: GlassSnackBarType.info);
  }
  
  Future<void> _exportSelected() async {
    // TODO: Implement export selected
    context.showGlassSnackBar('Export selected coming soon', type: GlassSnackBarType.info);
  }
  
  Future<void> _viewStatistics() async {
    // TODO: Navigate to statistics screen
    context.showGlassSnackBar('Statistics view coming soon', type: GlassSnackBarType.info);
  }
  
  Future<void> _cleanArticles() async {
    final days = await showGlassDialog<int>(
      context: context,
      title: const Text('Clean Articles'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Remove articles older than:'),
          const SizedBox(height: 16),
          ...const [7, 14, 30, 60, 90].map((days) {
            return ListTile(
              title: Text('$days days'),
              onTap: () => Navigator.of(context).pop(days),
            );
          }),
        ],
      ),
    );
    
    if (days == null) return;
    
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Cleaning old articles...';
    });
    
    try {
      final feedService = ref.read(feedServiceProvider);
      await feedService.cleanupOldArticles(
        feedIds: widget.selectedFeeds.map((f) => f.id).toList(),
        olderThanDays: days,
      );
      
      if (mounted) {
        context.showSuccessSnackBar('Old articles removed');
        widget.onOperationComplete?.call(widget.selectedFeeds);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to clean articles: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
  
  Future<void> _mergeFeeds() async {
    if (widget.selectedFeeds.length < 2) {
      context.showWarningSnackBar('Select at least 2 feeds to merge');
      return;
    }
    
    // TODO: Implement feed merging
    context.showGlassSnackBar('Feed merging coming soon', type: GlassSnackBarType.info);
  }
}