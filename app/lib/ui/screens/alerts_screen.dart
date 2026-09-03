import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/alert.dart';
import '../../providers/alert_provider.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../components/glass_dialog.dart';
import '../animations/loading_animation.dart';
import 'alert_settings_screen.dart';

/// Main alerts screen
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});
  
  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'all';
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final alerts = ref.watch(activeAlertsProvider);
    final unreadCount = ref.watch(unreadAlertCountProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Alerts'),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.accentColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  unreadCount.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
            tooltip: 'Alert Settings',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mark_all_read',
                child: ListTile(
                  leading: Icon(Icons.done_all),
                  title: Text('Mark All as Read'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear_all',
                child: ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('Clear All'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active', icon: Icon(Icons.notifications_active)),
            Tab(text: 'History', icon: Icon(Icons.history)),
          ],
          indicatorColor: theme.accentColor,
        ),
      ),
      body: Column(
        children: [
          // Filter chips
          _buildFilterChips(theme),
          
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildActiveAlertsTab(alerts, theme),
                _buildHistoryTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilterChips(GlassThemeData theme) {
    final categories = [
      'all',
      'feed',
      'article',
      'portfolio',
      'system',
    ];
    
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == _selectedFilter;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(category == 'all' ? 'All' : category.toUpperCase()),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedFilter = category);
                }
              },
              selectedColor: theme.primaryColor,
              backgroundColor: Colors.white.withOpacity(0.1),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildActiveAlertsTab(List<Alert> alerts, GlassThemeData theme) {
    // Filter alerts
    final filteredAlerts = _selectedFilter == 'all'
        ? alerts
        : alerts.where((a) => a.category.name.startsWith(_selectedFilter)).toList();
    
    if (filteredAlerts.isEmpty) {
      return _buildEmptyState(theme);
    }
    
    // Group alerts by date
    final groupedAlerts = _groupAlertsByDate(filteredAlerts);
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedAlerts.length,
      itemBuilder: (context, index) {
        final group = groupedAlerts[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                group.date,
                style: theme.titleSmall.copyWith(
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),
            
            // Alerts
            ...group.alerts.map((alert) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildAlertCard(alert, theme)
                  .animate(delay: (group.alerts.indexOf(alert) * 50).ms)
                  .fadeIn()
                  .slideX(),
            )),
          ],
        );
      },
    );
  }
  
  Widget _buildAlertCard(Alert alert, GlassThemeData theme) {
    final isUnread = alert.readAt == null;
    
    return GlassCard(
      onTap: () => _handleAlertTap(alert),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getAlertColor(alert.type).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getAlertIcon(alert),
              color: _getAlertColor(alert.type),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        alert.title,
                        style: theme.titleSmall.copyWith(
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isUnread)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.7),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                
                // Actions and time
                Row(
                  children: [
                    // Time
                    Text(
                      _formatTime(alert.createdAt),
                      style: theme.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // Actions
                    if (alert.actions != null && alert.actions!.isNotEmpty)
                      ...alert.actions!.take(2).map((action) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: GlassButton(
                          text: action.label,
                          onPressed: () => _handleAlertAction(alert, action),
                          variant: action.isPrimary
                              ? GlassButtonVariant.elevated
                              : GlassButtonVariant.text,
                          size: GlassButtonSize.small,
                        ),
                      )),
                  ],
                ),
              ],
            ),
          ),
          
          // Dismiss button
          IconButton(
            icon: Icon(
              Icons.close,
              color: Colors.white.withOpacity(0.5),
              size: 18,
            ),
            onPressed: () => _dismissAlert(alert),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHistoryTab(GlassThemeData theme) {
    final history = ref.watch(alertHistoryProvider);
    
    return history.when(
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Text(
              'No alert history',
              style: theme.bodyLarge.copyWith(
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _buildHistoryCard(entry, theme);
          },
        );
      },
      loading: () => const Center(child: LoadingAnimation()),
      error: (error, stack) => Center(
        child: Text(
          'Error loading history: $error',
          style: TextStyle(color: Colors.red.shade300),
        ),
      ),
    );
  }
  
  Widget _buildHistoryCard(AlertHistory entry, GlassThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassContainer(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _getHistoryIcon(entry.action),
              color: _getHistoryColor(entry.action),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getHistoryText(entry),
                style: theme.bodySmall,
              ),
            ),
            Text(
              _formatTime(entry.timestamp),
              style: theme.bodySmall.copyWith(
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyState(GlassThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No alerts',
            style: theme.headlineSmall.copyWith(
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'re all caught up!',
            style: theme.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          GlassButton(
            text: 'Configure Alerts',
            onPressed: _navigateToSettings,
            icon: const Icon(Icons.settings),
            variant: GlassButtonVariant.elevated,
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }
  
  List<AlertGroup> _groupAlertsByDate(List<Alert> alerts) {
    final groups = <String, List<Alert>>{};
    final now = DateTime.now();
    
    for (final alert in alerts) {
      final date = alert.createdAt;
      String dateKey;
      
      if (date.day == now.day && 
          date.month == now.month && 
          date.year == now.year) {
        dateKey = 'Today';
      } else if (date.day == now.day - 1 && 
                 date.month == now.month && 
                 date.year == now.year) {
        dateKey = 'Yesterday';
      } else {
        dateKey = '${date.month}/${date.day}/${date.year}';
      }
      
      groups.putIfAbsent(dateKey, () => []).add(alert);
    }
    
    return groups.entries
        .map((e) => AlertGroup(date: e.key, alerts: e.value))
        .toList();
  }
  
  void _handleAlertTap(Alert alert) {
    // Mark as read
    ref.read(alertServiceProvider).markAsRead(alert.id);
    
    // Navigate based on deepLink
    if (alert.deepLink != null) {
      // TODO: Handle navigation
    } else {
      // Show alert details
      _showAlertDetails(alert);
    }
  }
  
  void _handleAlertAction(Alert alert, AlertAction action) {
    ref.read(alertServiceProvider).handleAction(alert.id, action.id);
    
    // Handle navigation if needed
    if (action.deepLink != null) {
      // TODO: Handle navigation
    }
  }
  
  void _dismissAlert(Alert alert) async {
    await ref.read(alertServiceProvider).dismissAlert(alert.id);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Alert dismissed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // TODO: Implement undo
          },
        ),
      ),
    );
  }
  
  void _showAlertDetails(Alert alert) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getAlertColor(alert.type).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getAlertIcon(alert),
                    color: _getAlertColor(alert.type),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatFullTime(alert.createdAt),
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
            const SizedBox(height: 16),
            Text(alert.message),
            
            if (alert.actions != null && alert.actions!.isNotEmpty) ...[
              const SizedBox(height: 24),
              ...alert.actions!.map((action) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassButton(
                  text: action.label,
                  onPressed: () {
                    Navigator.pop(context);
                    _handleAlertAction(alert, action);
                  },
                  variant: action.isPrimary
                      ? GlassButtonVariant.elevated
                      : GlassButtonVariant.outlined,
                  width: double.infinity,
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
  
  void _handleMenuAction(String action) async {
    switch (action) {
      case 'mark_all_read':
        final alerts = ref.read(activeAlertsProvider);
        for (final alert in alerts) {
          await ref.read(alertServiceProvider).markAsRead(alert.id);
        }
        break;
        
      case 'clear_all':
        final confirmed = await showGlassConfirmDialog(
          context: context,
          title: 'Clear All Alerts',
          message: 'Are you sure you want to clear all alerts?',
          confirmText: 'Clear',
          destructive: true,
        );
        
        if (confirmed == true) {
          await ref.read(alertServiceProvider).clearAllAlerts();
        }
        break;
    }
  }
  
  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AlertSettingsScreen(),
      ),
    );
  }
  
  Color _getAlertColor(AlertType type) {
    switch (type) {
      case AlertType.info:
        return Colors.blue;
      case AlertType.warning:
        return Colors.orange;
      case AlertType.error:
        return Colors.red;
      case AlertType.success:
        return Colors.green;
      case AlertType.notification:
        return Colors.purple;
    }
  }
  
  IconData _getAlertIcon(Alert alert) {
    switch (alert.category) {
      case AlertCategory.feed_update:
        return Icons.rss_feed;
      case AlertCategory.feed_error:
      case AlertCategory.feed_health:
        return Icons.warning;
      case AlertCategory.article_keyword:
      case AlertCategory.article_author:
      case AlertCategory.article_topic:
        return Icons.article;
      case AlertCategory.portfolio_price:
      case AlertCategory.portfolio_gain_loss:
        return Icons.trending_up;
      case AlertCategory.portfolio_news:
        return Icons.newspaper;
      case AlertCategory.portfolio_dividend:
        return Icons.attach_money;
      case AlertCategory.system_update:
      case AlertCategory.system_maintenance:
      case AlertCategory.system_error:
        return Icons.settings;
      case AlertCategory.user_achievement:
      case AlertCategory.user_milestone:
        return Icons.emoji_events;
      case AlertCategory.user_reminder:
        return Icons.alarm;
    }
  }
  
  IconData _getHistoryIcon(AlertHistoryAction action) {
    switch (action) {
      case AlertHistoryAction.created:
        return Icons.add_circle_outline;
      case AlertHistoryAction.delivered:
        return Icons.send;
      case AlertHistoryAction.read:
        return Icons.visibility;
      case AlertHistoryAction.dismissed:
        return Icons.close;
      case AlertHistoryAction.action_taken:
        return Icons.touch_app;
      case AlertHistoryAction.failed:
        return Icons.error_outline;
    }
  }
  
  Color _getHistoryColor(AlertHistoryAction action) {
    switch (action) {
      case AlertHistoryAction.created:
        return Colors.blue;
      case AlertHistoryAction.delivered:
        return Colors.green;
      case AlertHistoryAction.read:
        return Colors.white70;
      case AlertHistoryAction.dismissed:
        return Colors.orange;
      case AlertHistoryAction.action_taken:
        return Colors.purple;
      case AlertHistoryAction.failed:
        return Colors.red;
    }
  }
  
  String _getHistoryText(AlertHistory entry) {
    switch (entry.action) {
      case AlertHistoryAction.created:
        return 'Alert created';
      case AlertHistoryAction.delivered:
        return 'Notification sent';
      case AlertHistoryAction.read:
        return 'Marked as read';
      case AlertHistoryAction.dismissed:
        return 'Dismissed';
      case AlertHistoryAction.action_taken:
        return 'Action taken';
      case AlertHistoryAction.failed:
        return 'Failed to deliver';
    }
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${time.month}/${time.day}';
    }
  }
  
  String _formatFullTime(DateTime time) {
    final now = DateTime.now();
    final isToday = time.day == now.day && 
                    time.month == now.month && 
                    time.year == now.year;
    
    if (isToday) {
      return 'Today at ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.month}/${time.day}/${time.year} at ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}

/// Alert group for display
class AlertGroup {
  final String date;
  final List<Alert> alerts;
  
  AlertGroup({required this.date, required this.alerts});
}