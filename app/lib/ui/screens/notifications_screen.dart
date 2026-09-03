import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_app_bar.dart';
import '../components/glass_text_field.dart';
import '../components/glass_snack_bar.dart';
import '../components/glass_dialog.dart';
import '../components/empty_state.dart';
import '../../providers/notification_provider.dart';
import '../../features/notifications/slack_discord_notifications.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final configs = ref.watch(notificationConfigsProvider);
    
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
                title: 'Notifications',
                leading: GlassButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                  variant: GlassButtonVariant.icon,
                ),
                actions: [
                  GlassButton(
                    icon: Icons.add,
                    onPressed: () => _showAddNotificationDialog(context),
                    variant: GlassButtonVariant.icon,
                  ),
                ],
              ),
              
              // Content
              Expanded(
                child: configs.isEmpty
                  ? EmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: 'No notifications configured',
                      subtitle: 'Add Slack or Discord webhooks to receive notifications',
                      action: GlassButton(
                        text: 'Add Notification',
                        icon: Icons.add,
                        onPressed: () => _showAddNotificationDialog(context),
                        variant: GlassButtonVariant.elevated,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: configs.length,
                      itemBuilder: (context, index) {
                        final config = configs[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildNotificationCard(config)
                            .animate()
                            .fadeIn(duration: 300.ms, delay: (index * 50).ms)
                            .slideY(begin: 0.1, end: 0),
                        );
                      },
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildNotificationCard(NotificationConfig config) {
    return GlassContainer(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              config.type == 'slack' ? Icons.tag : Icons.discord,
              color: config.enabled ? Colors.white : Colors.white.withOpacity(0.5),
            ),
            title: Text(
              config.name,
              style: TextStyle(
                color: config.enabled ? Colors.white : Colors.white.withOpacity(0.5),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              config.type.toUpperCase(),
              style: TextStyle(
                color: config.enabled 
                  ? Colors.white.withOpacity(0.7) 
                  : Colors.white.withOpacity(0.3),
                fontSize: 14,
              ),
            ),
            trailing: Switch(
              value: config.enabled,
              onChanged: (_) => _toggleNotification(config.id),
              activeColor: GlassTheme.primaryColor,
            ),
          ),
          
          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: GlassButton(
                    text: 'Test',
                    icon: Icons.send,
                    onPressed: config.enabled ? () => _testNotification(config) : null,
                    variant: GlassButtonVariant.text,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GlassButton(
                    text: 'Configure',
                    icon: Icons.settings,
                    onPressed: () => _showConfigureDialog(context, config),
                    variant: GlassButtonVariant.text,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GlassButton(
                    text: 'Delete',
                    icon: Icons.delete,
                    onPressed: () => _confirmDelete(context, config),
                    variant: GlassButtonVariant.text,
                  ),
                ),
              ],
            ),
          ),
          
          // Triggers summary
          if (config.enabled) ...[
            const Divider(color: Colors.white24),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTriggerChip('New Articles', config.triggers.newArticles),
                  _buildTriggerChip('Starred', config.triggers.starredArticles),
                  _buildTriggerChip('Milestones', config.triggers.milestones),
                  _buildTriggerChip('Errors', config.triggers.errors),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildTriggerChip(String label, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: enabled 
          ? GlassTheme.primaryColor.withOpacity(0.2)
          : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled
            ? GlassTheme.primaryColor.withOpacity(0.5)
            : Colors.white.withOpacity(0.2),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white.withOpacity(0.5),
          fontSize: 12,
        ),
      ),
    );
  }
  
  void _showAddNotificationDialog(BuildContext context) {
    showGlassDialog(
      context: context,
      title: const Text('Add Notification'),
      content: const AddNotificationDialog(),
      size: GlassDialogSize.large,
    );
  }
  
  void _showConfigureDialog(BuildContext context, NotificationConfig config) {
    showGlassDialog(
      context: context,
      title: const Text('Configure Notification'),
      content: ConfigureNotificationDialog(config: config),
      size: GlassDialogSize.large,
    );
  }
  
  void _toggleNotification(String id) async {
    await ref.read(notificationConfigsProvider.notifier).toggleConfig(id);
  }
  
  void _testNotification(NotificationConfig config) async {
    try {
      final success = await ref.read(notificationConfigsProvider.notifier).testConfig(config);
      if (mounted) {
        if (success) {
          context.showSuccessSnackBar('Test notification sent successfully');
        } else {
          context.showErrorSnackBar('Failed to send test notification');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Error: ${e.toString()}');
      }
    }
  }
  
  void _confirmDelete(BuildContext context, NotificationConfig config) {
    showGlassDialog(
      context: context,
      title: const Text('Delete Notification'),
      content: Text(
        'Are you sure you want to delete "${config.name}"?',
        style: TextStyle(color: Colors.white.withOpacity(0.8)),
      ),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.pop(context),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Delete',
          onPressed: () async {
            Navigator.pop(context);
            await ref.read(notificationConfigsProvider.notifier).removeConfig(config.id);
            if (mounted) {
              context.showSuccessSnackBar('Notification deleted');
            }
          },
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
}

class AddNotificationDialog extends ConsumerStatefulWidget {
  const AddNotificationDialog({super.key});

  @override
  ConsumerState<AddNotificationDialog> createState() => _AddNotificationDialogState();
}

class _AddNotificationDialogState extends ConsumerState<AddNotificationDialog> {
  String _selectedType = 'slack';
  final _nameController = TextEditingController();
  final _webhookController = TextEditingController();
  bool _isLoading = false;
  
  @override
  void dispose() {
    _nameController.dispose();
    _webhookController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Type selector
        Row(
          children: [
            Expanded(
              child: GlassButton(
                text: 'Slack',
                icon: Icons.tag,
                onPressed: () => setState(() => _selectedType = 'slack'),
                variant: _selectedType == 'slack' 
                  ? GlassButtonVariant.elevated 
                  : GlassButtonVariant.text,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GlassButton(
                text: 'Discord',
                icon: Icons.discord,
                onPressed: () => setState(() => _selectedType = 'discord'),
                variant: _selectedType == 'discord' 
                  ? GlassButtonVariant.elevated 
                  : GlassButtonVariant.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Name field
        GlassTextField(
          controller: _nameController,
          labelText: 'Name',
          hintText: 'e.g., My Workspace',
          prefixIcon: Icons.label,
        ),
        const SizedBox(height: 16),
        
        // Webhook URL field
        GlassTextField(
          controller: _webhookController,
          labelText: 'Webhook URL',
          hintText: _selectedType == 'slack'
            ? 'https://hooks.slack.com/services/...'
            : 'https://discord.com/api/webhooks/...',
          prefixIcon: Icons.link,
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        
        // Help text
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, 
                color: Colors.blue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedType == 'slack'
                    ? 'To get a Slack webhook URL:\n'
                      '1. Go to your Slack workspace settings\n'
                      '2. Apps > Incoming Webhooks\n'
                      '3. Add new webhook and copy the URL'
                    : 'To get a Discord webhook URL:\n'
                      '1. Go to Server Settings > Integrations\n'
                      '2. Create Webhook\n'
                      '3. Copy the webhook URL',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Actions
        Row(
          children: [
            Expanded(
              child: GlassButton(
                text: 'Cancel',
                onPressed: () => Navigator.pop(context),
                variant: GlassButtonVariant.text,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GlassButton(
                text: _isLoading ? 'Adding...' : 'Add & Test',
                icon: _isLoading ? null : Icons.add,
                onPressed: _isLoading ? null : _addNotification,
                variant: GlassButtonVariant.elevated,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  void _addNotification() async {
    final name = _nameController.text.trim();
    final webhook = _webhookController.text.trim();
    
    if (name.isEmpty || webhook.isEmpty) {
      context.showErrorSnackBar('Please fill in all fields');
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final config = ref.read(createNotificationConfigProvider)(
        type: _selectedType,
        webhookUrl: webhook,
        name: name,
      );
      
      // Test connection
      final success = await ref.read(notificationConfigsProvider.notifier).testConfig(config);
      
      if (!success) {
        throw Exception('Failed to connect to webhook');
      }
      
      // Add config
      await ref.read(notificationConfigsProvider.notifier).addConfig(config);
      
      if (mounted) {
        Navigator.pop(context);
        context.showSuccessSnackBar('Notification added successfully');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Error: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class ConfigureNotificationDialog extends ConsumerStatefulWidget {
  final NotificationConfig config;
  
  const ConfigureNotificationDialog({
    super.key,
    required this.config,
  });

  @override
  ConsumerState<ConfigureNotificationDialog> createState() => _ConfigureNotificationDialogState();
}

class _ConfigureNotificationDialogState extends ConsumerState<ConfigureNotificationDialog> {
  late NotificationTriggers _triggers;
  late TextEditingController _minArticlesController;
  
  @override
  void initState() {
    super.initState();
    _triggers = widget.config.triggers;
    _minArticlesController = TextEditingController(
      text: _triggers.minArticlesForNotification.toString()
    );
  }
  
  @override
  void dispose() {
    _minArticlesController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notification Triggers',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        
        SwitchListTile(
          title: Text(
            'New Articles',
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          subtitle: Text(
            'Notify when new articles are found',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
          value: _triggers.newArticles,
          onChanged: (value) => setState(() {
            _triggers = _triggers.copyWith(newArticles: value);
          }),
          activeColor: GlassTheme.primaryColor,
        ),
        
        if (_triggers.newArticles) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Minimum articles to notify:',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: GlassTextField(
                    controller: _minArticlesController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (value) {
                      final num = int.tryParse(value);
                      if (num != null && num > 0) {
                        setState(() {
                          _triggers = _triggers.copyWith(
                            minArticlesForNotification: num
                          );
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
        
        SwitchListTile(
          title: Text(
            'Starred Articles',
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          subtitle: Text(
            'Notify when an article is starred',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
          value: _triggers.starredArticles,
          onChanged: (value) => setState(() {
            _triggers = _triggers.copyWith(starredArticles: value);
          }),
          activeColor: GlassTheme.primaryColor,
        ),
        
        SwitchListTile(
          title: Text(
            'Milestones',
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          subtitle: Text(
            'Notify about reading milestones and achievements',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
          value: _triggers.milestones,
          onChanged: (value) => setState(() {
            _triggers = _triggers.copyWith(milestones: value);
          }),
          activeColor: GlassTheme.primaryColor,
        ),
        
        SwitchListTile(
          title: Text(
            'Errors',
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          subtitle: Text(
            'Notify about feed errors and issues',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
          value: _triggers.errors,
          onChanged: (value) => setState(() {
            _triggers = _triggers.copyWith(errors: value);
          }),
          activeColor: GlassTheme.primaryColor,
        ),
        
        const SizedBox(height: 24),
        
        Row(
          children: [
            Expanded(
              child: GlassButton(
                text: 'Cancel',
                onPressed: () => Navigator.pop(context),
                variant: GlassButtonVariant.text,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GlassButton(
                text: 'Save',
                icon: Icons.save,
                onPressed: _saveConfiguration,
                variant: GlassButtonVariant.elevated,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  void _saveConfiguration() async {
    final updatedConfig = widget.config.copyWith(triggers: _triggers);
    await ref.read(notificationConfigsProvider.notifier).updateConfig(updatedConfig);
    
    if (mounted) {
      Navigator.pop(context);
      context.showSuccessSnackBar('Configuration saved');
    }
  }
}