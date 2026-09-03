import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_text_field.dart';
import '../components/glass_switch.dart';
import '../components/glass_snack_bar.dart';
import '../components/glass_dialog.dart';
import '../../providers/feed_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/opml_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Settings provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

class AppSettings {
  final bool autoUpdateFeeds;
  final int updateInterval; // minutes
  final bool showNotifications;
  final bool enableSync;
  final bool useDarkTheme;
  final bool showReadArticles;
  final int articlesPerFeed;
  final bool enableOfflineMode;
  final bool enableSmartCategorization;
  final String corsProxy;
  
  AppSettings({
    this.autoUpdateFeeds = true,
    this.updateInterval = 30,
    this.showNotifications = true,
    this.enableSync = true,
    this.useDarkTheme = true,
    this.showReadArticles = true,
    this.articlesPerFeed = 50,
    this.enableOfflineMode = true,
    this.enableSmartCategorization = false,
    this.corsProxy = 'https://api.allorigins.win/raw?url=',
  });
  
  AppSettings copyWith({
    bool? autoUpdateFeeds,
    int? updateInterval,
    bool? showNotifications,
    bool? enableSync,
    bool? useDarkTheme,
    bool? showReadArticles,
    int? articlesPerFeed,
    bool? enableOfflineMode,
    bool? enableSmartCategorization,
    String? corsProxy,
  }) {
    return AppSettings(
      autoUpdateFeeds: autoUpdateFeeds ?? this.autoUpdateFeeds,
      updateInterval: updateInterval ?? this.updateInterval,
      showNotifications: showNotifications ?? this.showNotifications,
      enableSync: enableSync ?? this.enableSync,
      useDarkTheme: useDarkTheme ?? this.useDarkTheme,
      showReadArticles: showReadArticles ?? this.showReadArticles,
      articlesPerFeed: articlesPerFeed ?? this.articlesPerFeed,
      enableOfflineMode: enableOfflineMode ?? this.enableOfflineMode,
      enableSmartCategorization: enableSmartCategorization ?? this.enableSmartCategorization,
      corsProxy: corsProxy ?? this.corsProxy,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(AppSettings()) {
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      autoUpdateFeeds: prefs.getBool('autoUpdateFeeds') ?? true,
      updateInterval: prefs.getInt('updateInterval') ?? 30,
      showNotifications: prefs.getBool('showNotifications') ?? true,
      enableSync: prefs.getBool('enableSync') ?? true,
      useDarkTheme: prefs.getBool('useDarkTheme') ?? true,
      showReadArticles: prefs.getBool('showReadArticles') ?? true,
      articlesPerFeed: prefs.getInt('articlesPerFeed') ?? 50,
      enableOfflineMode: prefs.getBool('enableOfflineMode') ?? true,
      enableSmartCategorization: prefs.getBool('enableSmartCategorization') ?? false,
      corsProxy: prefs.getString('corsProxy') ?? 'https://api.allorigins.win/raw?url=',
    );
  }
  
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoUpdateFeeds', state.autoUpdateFeeds);
    await prefs.setInt('updateInterval', state.updateInterval);
    await prefs.setBool('showNotifications', state.showNotifications);
    await prefs.setBool('enableSync', state.enableSync);
    await prefs.setBool('useDarkTheme', state.useDarkTheme);
    await prefs.setBool('showReadArticles', state.showReadArticles);
    await prefs.setInt('articlesPerFeed', state.articlesPerFeed);
    await prefs.setBool('enableOfflineMode', state.enableOfflineMode);
    await prefs.setBool('enableSmartCategorization', state.enableSmartCategorization);
    await prefs.setString('corsProxy', state.corsProxy);
  }
  
  void setAutoUpdateFeeds(bool value) {
    state = state.copyWith(autoUpdateFeeds: value);
    _saveSettings();
  }
  
  void setUpdateInterval(int minutes) {
    state = state.copyWith(updateInterval: minutes);
    _saveSettings();
  }
  
  void setShowNotifications(bool value) {
    state = state.copyWith(showNotifications: value);
    _saveSettings();
  }
  
  void setEnableSync(bool value) {
    state = state.copyWith(enableSync: value);
    _saveSettings();
  }
  
  void setUseDarkTheme(bool value) {
    state = state.copyWith(useDarkTheme: value);
    _saveSettings();
  }
  
  void setShowReadArticles(bool value) {
    state = state.copyWith(showReadArticles: value);
    _saveSettings();
  }
  
  void setArticlesPerFeed(int count) {
    state = state.copyWith(articlesPerFeed: count);
    _saveSettings();
  }
  
  void setEnableOfflineMode(bool value) {
    state = state.copyWith(enableOfflineMode: value);
    _saveSettings();
  }
  
  void setEnableSmartCategorization(bool value) {
    state = state.copyWith(enableSmartCategorization: value);
    _saveSettings();
  }
  
  void setCorsProxy(String proxy) {
    state = state.copyWith(corsProxy: proxy);
    _saveSettings();
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // General Settings
            _buildSectionHeader('General Settings'),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildSwitchTile(
                    'Dark Theme',
                    'Use dark theme throughout the app',
                    Icons.dark_mode,
                    settings.useDarkTheme,
                    (value) => ref.read(settingsProvider.notifier).setUseDarkTheme(value),
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildSwitchTile(
                    'Show Read Articles',
                    'Display articles marked as read',
                    Icons.visibility,
                    settings.showReadArticles,
                    (value) => ref.read(settingsProvider.notifier).setShowReadArticles(value),
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildNumberSetting(
                    'Articles Per Feed',
                    'Maximum articles to keep per feed',
                    Icons.format_list_numbered,
                    settings.articlesPerFeed,
                    (value) => ref.read(settingsProvider.notifier).setArticlesPerFeed(value),
                    min: 10,
                    max: 200,
                    step: 10,
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms),
            
            const SizedBox(height: 24),
            
            // Feed Settings
            _buildSectionHeader('Feed Settings'),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildSwitchTile(
                    'Auto Update Feeds',
                    'Automatically refresh feeds in the background',
                    Icons.refresh,
                    settings.autoUpdateFeeds,
                    (value) => ref.read(settingsProvider.notifier).setAutoUpdateFeeds(value),
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildNumberSetting(
                    'Update Interval',
                    'How often to check for new articles (minutes)',
                    Icons.schedule,
                    settings.updateInterval,
                    (value) => ref.read(settingsProvider.notifier).setUpdateInterval(value),
                    min: 5,
                    max: 120,
                    step: 5,
                    enabled: settings.autoUpdateFeeds,
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildTextSetting(
                    'CORS Proxy',
                    'Proxy URL for fetching feeds (leave empty to disable)',
                    Icons.vpn_key,
                    settings.corsProxy,
                    (value) => ref.read(settingsProvider.notifier).setCorsProxy(value),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 100.ms),
            
            const SizedBox(height: 24),
            
            // Sync Settings
            _buildSectionHeader('Sync & Notifications'),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildSwitchTile(
                    'Enable Sync',
                    'Sync data between devices',
                    Icons.sync,
                    settings.enableSync,
                    (value) => ref.read(settingsProvider.notifier).setEnableSync(value),
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildSwitchTile(
                    'Show Notifications',
                    'Get notified about new articles',
                    Icons.notifications,
                    settings.showNotifications,
                    (value) => ref.read(settingsProvider.notifier).setShowNotifications(value),
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildSwitchTile(
                    'Offline Mode',
                    'Cache articles for offline reading',
                    Icons.download_for_offline,
                    settings.enableOfflineMode,
                    (value) => ref.read(settingsProvider.notifier).setEnableOfflineMode(value),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
            
            const SizedBox(height: 24),
            
            // Advanced Settings
            _buildSectionHeader('Advanced'),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildSwitchTile(
                    'Smart Categorization',
                    'Use AI to categorize articles (experimental)',
                    Icons.auto_awesome,
                    settings.enableSmartCategorization,
                    (value) => ref.read(settingsProvider.notifier).setEnableSmartCategorization(value),
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildActionTile(
                    'Clear Cache',
                    'Remove all cached data',
                    Icons.delete_outline,
                    () => _clearCache(context),
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildActionTile(
                    'Export Data',
                    'Export all feeds and settings',
                    Icons.download,
                    () => _exportData(context, ref),
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildActionTile(
                    'Reset to Defaults',
                    'Reset all settings to default values',
                    Icons.restore,
                    () => _resetSettings(context, ref),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 300.ms),
            
            const SizedBox(height: 24),
            
            // About Section
            _buildSectionHeader('About'),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Version',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '1.0.0',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Build',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Local-First Edition',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  GlassButton(
                    text: 'View Licenses',
                    onPressed: () => _showLicenses(context),
                    variant: GlassButtonVariant.text,
                    width: double.infinity,
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 400.ms),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
  
  Widget _buildSwitchTile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: GlassColors.primaryGradient[0].withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white70),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        GlassSwitch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
  
  Widget _buildNumberSetting(
    String title,
    String subtitle,
    IconData icon,
    int value,
    Function(int) onChanged, {
    required int min,
    required int max,
    required int step,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: GlassColors.primaryGradient[0].withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white70),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.remove, color: Colors.white.withOpacity(0.6)),
                onPressed: enabled && value > min
                    ? () => onChanged(value - step)
                    : null,
              ),
              Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              IconButton(
                icon: Icon(Icons.add, color: Colors.white.withOpacity(0.6)),
                onPressed: enabled && value < max
                    ? () => onChanged(value + step)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildTextSetting(
    String title,
    String subtitle,
    IconData icon,
    String value,
    Function(String) onChanged,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: GlassColors.primaryGradient[0].withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white70),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassTextField(
          hintText: 'Enter proxy URL',
          initialValue: value,
          onChanged: onChanged,
          textStyle: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
  
  Widget _buildActionTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: GlassColors.primaryGradient[0].withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white70),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: Colors.white.withOpacity(0.5),
          ),
        ],
      ),
    );
  }
  
  void _clearCache(BuildContext context) {
    showGlassDialog(
      context: context,
      title: 'Clear Cache',
      content: const Text('Are you sure you want to clear all cached data? This action cannot be undone.'),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Clear',
          onPressed: () {
            Navigator.of(context).pop();
            // TODO: Implement cache clearing
            context.showSuccessSnackBar('Cache cleared successfully');
          },
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
  
  void _exportData(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(opmlExportProvider.future);
      context.showSuccessSnackBar('Data exported successfully');
    } catch (e) {
      context.showErrorSnackBar('Failed to export data');
    }
  }
  
  void _resetSettings(BuildContext context, WidgetRef ref) {
    showGlassDialog(
      context: context,
      title: 'Reset Settings',
      content: const Text('Are you sure you want to reset all settings to their default values?'),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Reset',
          onPressed: () {
            Navigator.of(context).pop();
            // Reset to default settings
            ref.read(settingsProvider.notifier).state = AppSettings();
            context.showSuccessSnackBar('Settings reset to defaults');
          },
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
  
  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'RSS Glassmorphism Reader',
      applicationVersion: '1.0.0',
    );
  }
}