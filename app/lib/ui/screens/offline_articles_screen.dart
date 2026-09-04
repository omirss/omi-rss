import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/offline/offline_storage.dart';
import '../../providers/offline_provider.dart';
import '../components/article_card.dart';
import '../components/glass_app_bar.dart';
import '../components/glass_button.dart';
import '../components/glass_container.dart';
import '../components/glass_dialog.dart';
import '../components/glass_snack_bar.dart';
import '../tokens/glass_tokens.dart';
import 'article_reader_screen.dart';
import 'glass_screen.dart';

class OfflineArticlesScreen extends ConsumerWidget {
  const OfflineArticlesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offlineArticles = ref.watch(offlineArticlesProvider);
    final statistics = ref.watch(offlineStatisticsProvider);
    final tokens = screenTokensOf(context, ref);

    return GlassScreen(
      body: Column(
        children: [
          GlassAppBar(
            title: Text(
              'Offline Articles',
              style: GlassTypeScale.title.copyWith(
                color: tokens.textHigh,
                fontWeight: FontWeight.w700,
              ),
            ),
            leading: GlassButton(
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).pop(),
              variant: GlassButtonVariant.icon,
            ),
            actions: [
              GlassButton(
                icon: Icons.settings,
                onPressed: () => _showOfflineSettings(context, ref, tokens),
                variant: GlassButtonVariant.icon,
              ),
              const SizedBox(width: GlassSpacing.sm),
              GlassButton(
                icon: Icons.delete_sweep,
                onPressed: () =>
                    _confirmClearOfflineData(context, ref),
                variant: GlassButtonVariant.icon,
              ),
            ],
          ),

          statistics.when(
            data: (stats) => _buildStatisticsBar(stats, tokens),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          Expanded(
            child: offlineArticles.when(
              data: (articles) {
                if (articles.isEmpty) {
                  return ScreenEmptyState(
                    icon: Icons.offline_pin_outlined,
                    title: 'No offline articles',
                    subtitle:
                        'Save articles for offline reading from the article view',
                    tokens: tokens,
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(GlassSpacing.lg),
                  itemCount: articles.length,
                  itemBuilder: (context, index) {
                    final article = articles[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: GlassSpacing.lg),
                      child: ArticleCard(
                        article: article,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ArticleReaderScreen(article: article),
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: tokens.textHigh,
                          ),
                          onPressed: () => _confirmDeleteOfflineArticle(
                              context, ref, article.id),
                        ),
                      ).animate()
                        .fadeIn(duration: 300.ms, delay: (index * 50).ms)
                        .slideY(begin: 0.1, end: 0, duration: 300.ms, delay: (index * 50).ms),
                    );
                  },
                );
              },
              loading: () => ScreenLoading(tokens: tokens),
              error: (error, _) => ScreenErrorState(
                message: error.toString(),
                onRetry: () => ref.refresh(offlineArticlesProvider),
                tokens: tokens,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsBar(OfflineStatistics stats, GlassColorTokens tokens) {
    return Padding(
      padding: const EdgeInsets.all(GlassSpacing.lg),
      child: GlassContainer(
        padding: const EdgeInsets.all(GlassSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              icon: Icons.article,
              label: 'Articles',
              value: stats.articleCount.toString(),
              tokens: tokens,
            ),
            _buildStatItem(
              icon: Icons.storage,
              label: 'Storage',
              value: stats.formattedSize,
              tokens: tokens,
            ),
            if (stats.lastSync != null)
              _buildStatItem(
                icon: Icons.sync,
                label: 'Last sync',
                value: _formatLastSync(stats.lastSync!),
                tokens: tokens,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required GlassColorTokens tokens,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: tokens.textMedium, size: 20),
        const SizedBox(height: GlassSpacing.xs),
        Text(
          value,
          style: GlassTypeScale.body.copyWith(
            color: tokens.textHigh,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: GlassTypeScale.caption.copyWith(color: tokens.textMedium),
        ),
      ],
    );
  }

  String _formatLastSync(DateTime lastSync) {
    final difference = DateTime.now().difference(lastSync);
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _showOfflineSettings(
      BuildContext context, WidgetRef ref, GlassColorTokens tokens) {
    showGlassDialog(
      context: context,
      title: const Text('Offline Settings'),
      content: OfflineSettingsDialog(tokens: tokens),
      size: GlassDialogSize.medium,
    );
  }

  void _confirmClearOfflineData(BuildContext context, WidgetRef ref) {
    showGlassDialog(
      context: context,
      title: const Text('Clear Offline Data'),
      content: const Text(
        'Are you sure you want to delete all offline articles? This action cannot be undone.',
      ),
      actions: [
        GlassButton(
          text: 'Cancel',
          onPressed: () => Navigator.pop(context),
          variant: GlassButtonVariant.text,
        ),
        GlassButton(
          text: 'Clear All',
          onPressed: () async {
            Navigator.pop(context);
            try {
              final storage = ref.read(offlineStorageProvider);
              await storage.clearOfflineData();
              ref.invalidate(offlineArticlesProvider);
              ref.invalidate(offlineStatisticsProvider);
              if (context.mounted) {
                context.showSuccessSnackBar('Offline data cleared');
              }
            } catch (e) {
              if (context.mounted) {
                context.showErrorSnackBar('Failed to clear offline data');
              }
            }
          },
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }

  void _confirmDeleteOfflineArticle(
      BuildContext context, WidgetRef ref, String articleId) {
    showGlassDialog(
      context: context,
      title: const Text('Delete Offline Article'),
      content: const Text('Remove this article from offline storage?'),
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
            try {
              await ref
                  .read(offlineArticlesProvider.notifier)
                  .deleteOfflineArticle(articleId);
              ref.invalidate(offlineStatisticsProvider);
              if (context.mounted) {
                context.showSuccessSnackBar(
                    'Article removed from offline storage');
              }
            } catch (e) {
              if (context.mounted) {
                context.showErrorSnackBar('Failed to delete offline article');
              }
            }
          },
          variant: GlassButtonVariant.elevated,
        ),
      ],
    );
  }
}

class OfflineSettingsDialog extends ConsumerWidget {
  final GlassColorTokens tokens;

  const OfflineSettingsDialog({super.key, required this.tokens});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(offlineSettingsProvider);
    final settingsNotifier = ref.read(offlineSettingsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          title: Text(
            'Auto-download starred articles',
            style: GlassTypeScale.label.copyWith(color: tokens.textHigh),
          ),
          value: settings.autoDownloadStarred,
          onChanged: (_) => settingsNotifier.toggleAutoDownloadStarred(),
          activeThumbColor: tokens.accent,
        ),
        SwitchListTile(
          title: Text(
            'Auto-download unread articles',
            style: GlassTypeScale.label.copyWith(color: tokens.textHigh),
          ),
          value: settings.autoDownloadUnread,
          onChanged: (_) => settingsNotifier.toggleAutoDownloadUnread(),
          activeThumbColor: tokens.accent,
        ),
        SwitchListTile(
          title: Text(
            'Download images',
            style: GlassTypeScale.label.copyWith(color: tokens.textHigh),
          ),
          subtitle: Text(
            'Include images in offline articles',
            style:
                GlassTypeScale.caption.copyWith(color: tokens.textMedium),
          ),
          value: settings.downloadImages,
          onChanged: (_) => settingsNotifier.toggleDownloadImages(),
          activeThumbColor: tokens.accent,
        ),
        SwitchListTile(
          title: Text(
            'Wi-Fi only',
            style: GlassTypeScale.label.copyWith(color: tokens.textHigh),
          ),
          subtitle: Text(
            'Download articles only on Wi-Fi',
            style:
                GlassTypeScale.caption.copyWith(color: tokens.textMedium),
          ),
          value: settings.wifiOnly,
          onChanged: (_) => settingsNotifier.toggleWifiOnly(),
          activeThumbColor: tokens.accent,
        ),
        const SizedBox(height: GlassSpacing.lg),
        _buildSliderSetting(
          title: 'Max offline articles',
          value: settings.maxOfflineArticles.toDouble(),
          min: 10,
          max: 500,
          divisions: 49,
          label: settings.maxOfflineArticles.toString(),
          onChanged: (value) =>
              settingsNotifier.setMaxOfflineArticles(value.toInt()),
        ),
        const SizedBox(height: GlassSpacing.lg),
        _buildSliderSetting(
          title: 'Max storage size (MB)',
          value: settings.maxStorageSizeMB.toDouble(),
          min: 50,
          max: 2000,
          divisions: 39,
          label: '${settings.maxStorageSizeMB} MB',
          onChanged: (value) => settingsNotifier.setMaxStorageSize(value.toInt()),
        ),
        const SizedBox(height: GlassSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: GlassButton(
            text: 'Close',
            onPressed: () => Navigator.pop(context),
            variant: GlassButtonVariant.elevated,
          ),
        ),
      ],
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GlassTypeScale.body.copyWith(color: tokens.textHigh),
            ),
            Text(
              label,
              style:
                  GlassTypeScale.label.copyWith(color: tokens.textMedium),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
          activeColor: tokens.accent,
          inactiveColor: tokens.glassStroke,
        ),
      ],
    );
  }
}
