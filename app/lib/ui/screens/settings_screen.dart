import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_info.dart';
import '../../providers/database_provider.dart';
import '../../providers/opml_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_settings_provider.dart';
import '../components/glass_button.dart';
import '../components/glass_container.dart';
import '../components/glass_dialog.dart';
import '../components/glass_snack_bar.dart';
import '../components/glass_switch.dart';
import '../components/glass_text_field.dart';
import '../tokens/glass_presets.dart';
import '../tokens/glass_tokens.dart';
import 'glass_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final tokens = screenTokensOf(context, ref);

    return GlassScreen(
      title: 'Settings',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(GlassSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenSectionHeader(title: 'Theme', tokens: tokens),
            _buildThemeSection(context, ref, tokens),
            const SizedBox(height: GlassSpacing.xl),

            ScreenSectionHeader(title: 'General Settings', tokens: tokens),
            GlassContainer(
              padding: const EdgeInsets.all(GlassSpacing.xl),
              child: Column(
                children: [
                  ScreenListRow(
                    icon: Icons.visibility,
                    title: 'Show Read Articles',
                    subtitle: 'Display articles marked as read',
                    tokens: tokens,
                    trailing: GlassSwitch(
                      value: settings.showReadArticles,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setShowReadArticles(value),
                    ),
                  ),
                  Divider(
                      color: tokens.glassStroke, height: GlassSpacing.xxl),
                  _buildNumberSetting(
                    'Articles Per Feed',
                    'Maximum articles to keep per feed',
                    Icons.format_list_numbered,
                    settings.articlesPerFeed,
                    (value) => ref
                        .read(settingsProvider.notifier)
                        .setArticlesPerFeed(value),
                    tokens: tokens,
                    min: 10,
                    max: 200,
                    step: 10,
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms),

            const SizedBox(height: GlassSpacing.xl),

            ScreenSectionHeader(title: 'Feed Settings', tokens: tokens),
            GlassContainer(
              padding: const EdgeInsets.all(GlassSpacing.xl),
              child: Column(
                children: [
                  ScreenListRow(
                    icon: Icons.refresh,
                    title: 'Auto Update Feeds',
                    subtitle: 'Automatically refresh feeds in the background',
                    tokens: tokens,
                    trailing: GlassSwitch(
                      value: settings.autoUpdateFeeds,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setAutoUpdateFeeds(value),
                    ),
                  ),
                  Divider(
                      color: tokens.glassStroke, height: GlassSpacing.xxl),
                  _buildNumberSetting(
                    'Update Interval',
                    'Default refresh interval for new feeds (minutes)',
                    Icons.schedule,
                    settings.updateInterval,
                    (value) => ref
                        .read(settingsProvider.notifier)
                        .setUpdateInterval(value),
                    tokens: tokens,
                    min: 5,
                    max: 120,
                    step: 5,
                    enabled: settings.autoUpdateFeeds,
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 100.ms),

            const SizedBox(height: GlassSpacing.xl),

            ScreenSectionHeader(title: 'Server & Sync', tokens: tokens),
            GlassContainer(
              padding: const EdgeInsets.all(GlassSpacing.xl),
              child: Column(
                children: [
                  _buildTextSetting(
                    'Server URL',
                    'Self-hosted server API URL (empty for local-only mode)',
                    Icons.dns,
                    settings.serverUrl,
                    (value) => ref
                        .read(settingsProvider.notifier)
                        .setServerUrl(value),
                    tokens: tokens,
                    hintText: 'http://localhost:8080',
                  ),
                  Divider(
                      color: tokens.glassStroke, height: GlassSpacing.xxl),
                  ScreenListRow(
                    icon: Icons.sync,
                    title: 'Enable Sync',
                    subtitle: 'Sync data between devices',
                    tokens: tokens,
                    trailing: GlassSwitch(
                      value: settings.enableSync,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setEnableSync(value),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 200.ms),

            const SizedBox(height: GlassSpacing.xl),

            ScreenSectionHeader(title: 'Advanced', tokens: tokens),
            GlassContainer(
              padding: const EdgeInsets.all(GlassSpacing.xl),
              child: Column(
                children: [
                  ScreenListRow(
                    icon: Icons.delete_outline,
                    title: 'Clear Cache',
                    subtitle: 'Delete read, unstarred articles older than 30 days',
                    tokens: tokens,
                    onTap: () => _clearCache(context, ref),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: tokens.textLow,
                    ),
                  ),
                  Divider(
                      color: tokens.glassStroke, height: GlassSpacing.xxl),
                  ScreenListRow(
                    icon: Icons.download,
                    title: 'Export Data',
                    subtitle: 'Export all feeds and settings',
                    tokens: tokens,
                    onTap: () => _exportData(context, ref),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: tokens.textLow,
                    ),
                  ),
                  Divider(
                      color: tokens.glassStroke, height: GlassSpacing.xxl),
                  ScreenListRow(
                    icon: Icons.restore,
                    title: 'Reset to Defaults',
                    subtitle: 'Reset all settings to default values',
                    tokens: tokens,
                    onTap: () => _resetSettings(context, ref),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: tokens.textLow,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 300.ms),

            const SizedBox(height: GlassSpacing.xl),

            ScreenSectionHeader(title: 'About', tokens: tokens),
            GlassContainer(
              padding: const EdgeInsets.all(GlassSpacing.xl),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Version',
                        style: GlassTypeScale.body
                            .copyWith(color: tokens.textMedium),
                      ),
                      Text(
                        appVersion,
                        style: GlassTypeScale.body.copyWith(
                          color: tokens.textHigh,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GlassSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Source',
                        style: GlassTypeScale.body
                            .copyWith(color: tokens.textMedium),
                      ),
                      Text(
                        appRepositoryUrl.replaceFirst('https://', ''),
                        style: GlassTypeScale.label.copyWith(
                          color: tokens.textHigh,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GlassSpacing.xl),
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

  Widget _buildThemeSection(
      BuildContext context, WidgetRef ref, GlassColorTokens tokens) {
    final themeSettings = ref.watch(themeSettingsProvider);

    return GlassContainer(
      padding: const EdgeInsets.all(GlassSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preset',
            style: GlassTypeScale.body.copyWith(color: tokens.textHigh),
          ),
          const SizedBox(height: GlassSpacing.md),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: GlassPresets.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: GlassSpacing.md),
              itemBuilder: (context, index) {
                final preset = GlassPresets.all[index];
                return _buildPresetCard(
                  context,
                  ref,
                  preset,
                  preset.id == themeSettings.presetId,
                  tokens,
                );
              },
            ),
          ),
          const SizedBox(height: GlassSpacing.xl),
          Text(
            'Mode',
            style: GlassTypeScale.body.copyWith(color: tokens.textHigh),
          ),
          const SizedBox(height: GlassSpacing.md),
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
                  tokens,
                ),
              ),
              const SizedBox(width: GlassSpacing.sm),
              Expanded(
                child: _buildModeChip(
                  ref,
                  'Light',
                  Icons.light_mode,
                  themeSettings.mode == AppThemeMode.light,
                  () => ref
                      .read(themeSettingsProvider.notifier)
                      .setMode(AppThemeMode.light),
                  tokens,
                ),
              ),
              const SizedBox(width: GlassSpacing.sm),
              Expanded(
                child: _buildModeChip(
                  ref,
                  'Dark',
                  Icons.dark_mode,
                  themeSettings.mode == AppThemeMode.dark,
                  () => ref
                      .read(themeSettingsProvider.notifier)
                      .setMode(AppThemeMode.dark),
                  tokens,
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
    GlassColorTokens tokens,
  ) {
    final preview = preset.dark;

    return InkWell(
      onTap: () =>
          ref.read(themeSettingsProvider.notifier).setPreset(preset.id),
      borderRadius: BorderRadius.circular(GlassRadii.lg),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(GlassSpacing.sm),
        decoration: BoxDecoration(
          color: tokens.glassFill,
          borderRadius: BorderRadius.circular(GlassRadii.lg),
          border: Border.all(
            color: isSelected ? tokens.accent : tokens.glassStroke,
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
                  colors: preview.backgroundGradient,
                ),
                borderRadius: BorderRadius.circular(GlassRadii.sm + 2),
                border: Border.all(
                  color: tokens.glassStroke,
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
                      colors: preview.primaryGradient,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tokens.textHigh.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: GlassSpacing.sm),
            Text(
              preset.name,
              style: GlassTypeScale.label.copyWith(
                fontSize: 13,
                color: isSelected ? tokens.textHigh : tokens.textMedium,
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
    GlassColorTokens tokens,
  ) {
    final accent = tokens.accent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: GlassSpacing.md, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.2)
              : tokens.glassFill,
          borderRadius: BorderRadius.circular(GlassRadii.md),
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.6)
                : tokens.glassStroke,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? tokens.textHigh : tokens.textMedium,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: GlassTypeScale.label.copyWith(
                  fontSize: 13,
                  color: isSelected ? tokens.textHigh : tokens.textMedium,
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

  Widget _buildNumberSetting(
    String title,
    String subtitle,
    IconData icon,
    int value,
    Function(int) onChanged, {
    required GlassColorTokens tokens,
    required int min,
    required int max,
    required int step,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: ScreenListRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        tokens: tokens,
        trailing: Row(
          children: [
            IconButton(
              icon: Icon(Icons.remove, color: tokens.textMedium),
              onPressed: enabled && value > min
                  ? () => onChanged(value - step)
                  : null,
            ),
            Text(
              '$value',
              style: GlassTypeScale.body.copyWith(
                color: tokens.textHigh,
                fontWeight: FontWeight.w500,
              ),
            ),
            IconButton(
              icon: Icon(Icons.add, color: tokens.textMedium),
              onPressed: enabled && value < max
                  ? () => onChanged(value + step)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextSetting(
    String title,
    String subtitle,
    IconData icon,
    String value,
    Function(String) onChanged, {
    required GlassColorTokens tokens,
    String hintText = 'Enter URL',
  }) {
    return Column(
      children: [
        ScreenListRow(
          icon: icon,
          title: title,
          subtitle: subtitle,
          tokens: tokens,
        ),
        const SizedBox(height: GlassSpacing.md),
        GlassTextField(
          hintText: hintText,
          initialValue: value,
          onChanged: onChanged,
          textStyle: GlassTypeScale.label.copyWith(color: tokens.textHigh),
        ),
      ],
    );
  }

  void _clearCache(BuildContext context, WidgetRef ref) {
    showGlassDialog(
      context: context,
      title: const Text('Clear Cache'),
      content: const Text(
          'Delete read, unstarred articles older than 30 days? Starred articles are kept. This action cannot be undone.'),
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

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(exportOPMLProvider.future);
      if (context.mounted) {
        context.showSuccessSnackBar('Data exported successfully');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Failed to export data');
      }
    }
  }

  void _resetSettings(BuildContext context, WidgetRef ref) {
    showGlassDialog(
      context: context,
      title: const Text('Reset Settings'),
      content: const Text(
          'Are you sure you want to reset all settings to their default values?'),
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
