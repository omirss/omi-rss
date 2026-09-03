import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/alert.dart';
import '../../providers/alert_provider.dart';
import '../../providers/settings_provider.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_card.dart';
import '../components/glass_button.dart';
import '../components/glass_dialog.dart';

/// Alert settings screen
class AlertSettingsScreen extends ConsumerStatefulWidget {
  const AlertSettingsScreen({super.key});
  
  @override
  ConsumerState<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends ConsumerState<AlertSettingsScreen> {
  bool _notificationsEnabled = true;
  AlertPriority _minPriority = AlertPriority.medium;
  final Map<AlertCategory, bool> _categorySettings = {};
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  void _loadSettings() {
    final settings = ref.read(settingsServiceProvider);
    
    setState(() {
      _notificationsEnabled = settings.getSetting('notifications_enabled', true);
      
      final minPriorityStr = settings.getSetting('min_notification_priority', 'medium');
      _minPriority = AlertPriority.values.firstWhere(
        (p) => p.name == minPriorityStr,
        orElse: () => AlertPriority.medium,
      );
      
      // Load category settings
      for (final category in AlertCategory.values) {
        _categorySettings[category] = settings.getSetting(
          'notification_${category.name}',
          true,
        );
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final stats = ref.watch(alertStatisticsProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Alert Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Statistics
          _buildStatisticsCard(stats, theme),
          
          const SizedBox(height: 24),
          
          // Master switch
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.notifications,
                  color: _notificationsEnabled ? theme.accentColor : Colors.white30,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Push Notifications',
                        style: theme.titleMedium,
                      ),
                      Text(
                        'Receive alerts as push notifications',
                        style: theme.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() => _notificationsEnabled = value);
                    _saveSetting('notifications_enabled', value);
                  },
                  activeColor: theme.accentColor,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Priority filter
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.priority_high),
                    const SizedBox(width: 12),
                    Text(
                      'Minimum Priority',
                      style: theme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Only show notifications for alerts with this priority or higher',
                  style: theme.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 16),
                _buildPrioritySelector(theme),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Category settings
          Text(
            'Alert Categories',
            style: theme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose which types of alerts you want to receive',
            style: theme.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          
          _buildCategorySection('Feed Alerts', [
            AlertCategory.feed_update,
            AlertCategory.feed_error,
            AlertCategory.feed_health,
          ], theme),
          
          _buildCategorySection('Article Alerts', [
            AlertCategory.article_keyword,
            AlertCategory.article_author,
            AlertCategory.article_topic,
          ], theme),
          
          _buildCategorySection('Portfolio Alerts', [
            AlertCategory.portfolio_price,
            AlertCategory.portfolio_gain_loss,
            AlertCategory.portfolio_news,
            AlertCategory.portfolio_dividend,
          ], theme),
          
          _buildCategorySection('System Alerts', [
            AlertCategory.system_update,
            AlertCategory.system_maintenance,
            AlertCategory.system_error,
          ], theme),
          
          _buildCategorySection('User Alerts', [
            AlertCategory.user_achievement,
            AlertCategory.user_milestone,
            AlertCategory.user_reminder,
          ], theme),
          
          const SizedBox(height: 24),
          
          // Subscription management
          Text(
            'Alert Subscriptions',
            style: theme.titleLarge,
          ),
          const SizedBox(height: 16),
          
          GlassButton(
            text: 'Manage Feed Alerts',
            onPressed: _manageFeedAlerts,
            icon: const Icon(Icons.rss_feed),
            variant: GlassButtonVariant.outlined,
            width: double.infinity,
          ),
          
          const SizedBox(height: 8),
          
          GlassButton(
            text: 'Manage Portfolio Alerts',
            onPressed: _managePortfolioAlerts,
            icon: const Icon(Icons.account_balance_wallet),
            variant: GlassButtonVariant.outlined,
            width: double.infinity,
          ),
          
          const SizedBox(height: 8),
          
          GlassButton(
            text: 'Manage Keyword Alerts',
            onPressed: _manageKeywordAlerts,
            icon: const Icon(Icons.label),
            variant: GlassButtonVariant.outlined,
            width: double.infinity,
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatisticsCard(AlertStatistics stats, GlassThemeData theme) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alert Activity',
            style: theme.titleMedium,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Active',
                stats.totalActive.toString(),
                Icons.notifications_active,
                Colors.blue,
                theme,
              ),
              _buildStatItem(
                'Unread',
                stats.unreadCount.toString(),
                Icons.markunread,
                Colors.orange,
                theme,
              ),
              _buildStatItem(
                'Today',
                stats.alertsLast24h.toString(),
                Icons.today,
                Colors.green,
                theme,
              ),
              _buildStatItem(
                'This Week',
                stats.alertsLast7d.toString(),
                Icons.date_range,
                Colors.purple,
                theme,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
    GlassThemeData theme,
  ) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.bodySmall.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPrioritySelector(GlassThemeData theme) {
    return Row(
      children: AlertPriority.values.map((priority) {
        final isSelected = priority == _minPriority;
        final isEnabled = priority.index >= _minPriority.index;
        
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GlassButton(
              text: priority.name.toUpperCase(),
              onPressed: () {
                setState(() => _minPriority = priority);
                _saveSetting('min_notification_priority', priority.name);
              },
              variant: isSelected
                  ? GlassButtonVariant.elevated
                  : GlassButtonVariant.outlined,
              size: GlassButtonSize.small,
            ),
          ),
        );
      }).toList(),
    );
  }
  
  Widget _buildCategorySection(
    String title,
    List<AlertCategory> categories,
    GlassThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.titleSmall,
            ),
            const SizedBox(height: 12),
            ...categories.map((category) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _getCategoryDisplayName(category),
                      style: theme.bodyMedium,
                    ),
                  ),
                  Switch(
                    value: _categorySettings[category] ?? true,
                    onChanged: _notificationsEnabled ? (value) {
                      setState(() => _categorySettings[category] = value);
                      _saveSetting('notification_${category.name}', value);
                    } : null,
                    activeColor: theme.accentColor,
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
  
  String _getCategoryDisplayName(AlertCategory category) {
    switch (category) {
      case AlertCategory.feed_update:
        return 'New Articles';
      case AlertCategory.feed_error:
        return 'Feed Errors';
      case AlertCategory.feed_health:
        return 'Feed Health Issues';
      case AlertCategory.article_keyword:
        return 'Keyword Matches';
      case AlertCategory.article_author:
        return 'Author Updates';
      case AlertCategory.article_topic:
        return 'Topic Alerts';
      case AlertCategory.portfolio_price:
        return 'Price Alerts';
      case AlertCategory.portfolio_gain_loss:
        return 'Gain/Loss Alerts';
      case AlertCategory.portfolio_news:
        return 'Portfolio News';
      case AlertCategory.portfolio_dividend:
        return 'Dividend Notifications';
      case AlertCategory.system_update:
        return 'App Updates';
      case AlertCategory.system_maintenance:
        return 'Maintenance Notices';
      case AlertCategory.system_error:
        return 'System Errors';
      case AlertCategory.user_achievement:
        return 'Achievements';
      case AlertCategory.user_milestone:
        return 'Milestones';
      case AlertCategory.user_reminder:
        return 'Reminders';
    }
  }
  
  void _saveSetting(String key, dynamic value) {
    ref.read(settingsServiceProvider).setSetting(key, value);
  }
  
  void _manageFeedAlerts() {
    // TODO: Navigate to feed alert management
    showGlassDialog(
      context: context,
      title: const Text('Feed Alerts'),
      content: const Text('Configure alerts for your RSS feeds'),
      actions: [
        GlassButton(
          text: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
  
  void _managePortfolioAlerts() {
    // TODO: Navigate to portfolio alert management
    showGlassDialog(
      context: context,
      title: const Text('Portfolio Alerts'),
      content: const Text('Set up price and performance alerts'),
      actions: [
        GlassButton(
          text: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
  
  void _manageKeywordAlerts() {
    _showKeywordAlertDialog();
  }
  
  void _showKeywordAlertDialog() {
    final keywordController = TextEditingController();
    final keywords = <String>[];
    
    showGlassDialog(
      context: context,
      title: const Text('Keyword Alerts'),
      content: StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keywordController,
              decoration: InputDecoration(
                labelText: 'Add Keywords',
                hintText: 'Enter keywords to monitor',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    if (keywordController.text.isNotEmpty) {
                      setState(() {
                        keywords.add(keywordController.text);
                        keywordController.clear();
                      });
                    }
                  },
                ),
              ),
              style: const TextStyle(color: Colors.white),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  setState(() {
                    keywords.add(value);
                    keywordController.clear();
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            if (keywords.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                children: keywords.map((keyword) => Chip(
                  label: Text(keyword),
                  onDeleted: () {
                    setState(() => keywords.remove(keyword));
                  },
                )).toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Create Alert',
          onPressed: keywords.isEmpty ? null : () async {
            Navigator.of(context).pop();
            
            // Create keyword alert subscription
            await ref.read(createKeywordAlertSubscriptionProvider(
              keywords: keywords,
              configs: [
                AlertConfig(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: 'Keyword Match',
                  triggerType: AlertTriggerType.keyword_match,
                  conditions: {'keywords': keywords},
                  category: AlertCategory.article_keyword,
                ),
              ],
            ).future);
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Keyword alert created'),
                backgroundColor: Colors.green,
              ),
            );
          },
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
}