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
import '../../providers/opml_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_settings_provider.dart';
import '../../providers/database_provider.dart';
import '../../ui/tokens/glass_presets.dart';
import '../../config/app_info.dart';

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
            // Theme Settings
            _buildSectionHeader('Theme'),
            _buildThemeSection(ref),
            const SizedBox(height: 24),

            // General Settings
            _buildSectionHeader('General Settings'),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
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
                    'Default refresh interval for new feeds (minutes)',
                    Icons.schedule,
                    settings.updateInterval,
                    (value) => ref.read(settingsProvider.notifier).setUpdateInterval(value),
                    min: 5,
                    max: 120,
                    step: 5,
                    enabled: settings.autoUpdateFeeds,
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 100.ms),

            const SizedBox(height: 24),

            // Sync Settings
            _buildSectionHeader('Server & Sync'),
            GlassContainer(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildTextSetting(
                    'Server URL',
                    'Self-hosted server API URL (empty for local-only mode)',
                    Icons.dns,
                    settings.serverUrl,
                    (value) => ref.read(settingsProvider.notifier).setServerUrl(value),
                    hintText: 'http://localhost:8080',
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildSwitchTile(
                    'Enable Sync',
                    'Sync data between devices',
                    Icons.sync,
                    settings.enableSync,
                    (value) => ref.read(settingsProvider.notifier).setEnableSync(value),
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
                  _buildActionTile(
                    'Clear Cache',
                    'Delete read, unstarred articles older than 30 days',
                    Icons.delete_outline,
                    () => _clearCache(context, ref),
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
                        appVersion,
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
                        'Source',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        appRepositoryUrl.replaceFirst('https://', ''),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
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

  Widget _buildThemeSection(WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preset',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: GlassPresets.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final preset = GlassPresets.all[index];
                return _buildPresetCard(
                  context,
                  ref,
                  preset,
                  preset.id == themeSettings.presetId,
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Mode',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildModeChip(
                  ref,
                  'System',
                  Icons.brightness_auto,
                  themeSettings.mode == AppThemeMode.system,
                  () => ref
                      .read(themeSettingsProvider.notifier)
                      .setMode(AppThemeMode.system),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeChip(
                  ref,
                  'Light',
                  Icons.light_mode,
                  themeSettings.mode == AppThemeMode.light,
                  () => ref
                      .read(themeSettingsProvider.notifier)
                      .setMode(AppThemeMode.light),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeChip(
                  ref,
                  'Dark',
                  Icons.dark_mode,
                  themeSettings.mode == AppThemeMode.dark,
                  () => ref
                      .read(themeSettingsProvider.notifier)
                      .setMode(AppThemeMode.dark),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildPresetCard(
    BuildContext context,
    WidgetRef ref,
    GlassThemePreset preset,
    bool isSelected,
  ) {
    final tokens = preset.dark;

    return InkWell(
      onTap: () =>
          ref.read(themeSettingsProvider.notifier).setPreset(preset.id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? tokens.accent
                : Colors.white.withValues(alpha: 0.15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: tokens.backgroundGradient,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: Center(
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: tokens.primaryGradient,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              preset.name,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip(
    WidgetRef ref,
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final accent = ref.watch(themePresetProvider).dark.accent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
    Function(String) onChanged, {
    String hintText = 'Enter URL',
  }) {
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
          hintText: hintText,
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

  void _clearCache(BuildContext context, WidgetRef ref) {
    showGlassDialog(
      context: context,
      title: const Text('Clear Cache'),
      content: const Text('Delete read, unstarred articles older than 30 days? Starred articles are kept. This action cannot be undone.'),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Clear',
          onPressed: () async {
            Navigator.of(context).pop();
            final database = ref.read(databaseProvider);
            final cutoff = DateTime.now().subtract(const Duration(days: 30));
            final deleted =
                await database.articleDao.deleteOldArticles(cutoff);
            PaintingBinding.instance.imageCache.clear();
            if (context.mounted) {
              context.showSuccessSnackBar('$deleted cached articles cleared');
            }
          },
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }

  void _exportData(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(exportOPMLProvider.future);
      context.showSuccessSnackBar('Data exported successfully');
    } catch (e) {
      context.showErrorSnackBar('Failed to export data');
    }
  }

  void _resetSettings(BuildContext context, WidgetRef ref) {
    showGlassDialog(
      context: context,
      title: const Text('Reset Settings'),
      content: const Text('Are you sure you want to reset all settings to their default values?'),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Reset',
          onPressed: () async {
            Navigator.of(context).pop();
            await ref.read(settingsProvider.notifier).resetToDefaults();
            if (context.mounted) {
              context.showSuccessSnackBar('Settings reset to defaults');
            }
          },
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: appName,
      applicationVersion: appVersion,
    );
  }
}
