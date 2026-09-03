import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_app_bar.dart';
import '../components/glass_snack_bar.dart';
import '../components/glass_dialog.dart';
import '../components/article_card.dart';
import '../components/empty_state.dart';
import '../components/error_state.dart';
import '../../providers/offline_provider.dart';
import '../../features/offline/offline_storage.dart';
import 'article_reader_screen.dart';

class OfflineArticlesScreen extends ConsumerWidget {
  const OfflineArticlesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offlineArticles = ref.watch(offlineArticlesProvider);
    final statistics = ref.watch(offlineStatisticsProvider);
    
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
                title: 'Offline Articles',
                leading: GlassButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                  variant: GlassButtonVariant.icon,
                ),
                actions: [
                  GlassButton(
                    icon: Icons.settings,
                    onPressed: () => _showOfflineSettings(context, ref),
                    variant: GlassButtonVariant.icon,
                  ),
                  const SizedBox(width: 8),
                  GlassButton(
                    icon: Icons.delete_sweep,
                    onPressed: () => _confirmClearOfflineData(context, ref),
                    variant: GlassButtonVariant.icon,
                  ),
                ],
              ),
              
              // Statistics bar
              statistics.when(
                data: (stats) => _buildStatisticsBar(stats),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              
              // Articles list
              Expanded(
                child: offlineArticles.when(
                  data: (articles) {
                    if (articles.isEmpty) {
                      return EmptyState(
                        icon: Icons.offline_pin_outlined,
                        title: 'No offline articles',
                        subtitle: 'Save articles to read them offline',
                      );
                    }
                    
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: articles.length,
                      itemBuilder: (context, index) {
                        final article = articles[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: ArticleCard(
                            article: article,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ArticleReaderScreen(article: article),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white),
                              onPressed: () => _confirmDeleteOfflineArticle(context, ref, article.id),
                            ),
                          ).animate()
                            .fadeIn(duration: 300.ms, delay: (index * 50).ms)
                            .slideY(begin: 0.1, end: 0, duration: 300.ms, delay: (index * 50).ms),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: GlassTheme.primaryColor,
                    ),
                  ),
                  error: (error, _) => ErrorState(
                    error: error.toString(),
                    onRetry: () => ref.refresh(offlineArticlesProvider),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatisticsBar(OfflineStatistics stats) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              icon: Icons.article,
              label: 'Articles',
              value: stats.articleCount.toString(),
            ),
            _buildStatItem(
              icon: Icons.storage,
              label: 'Storage',
              value: stats.formattedSize,
            ),
            if (stats.lastSync != null)
              _buildStatItem(
                icon: Icons.sync,
                label: 'Last sync',
                value: _formatLastSync(stats.lastSync!),
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
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.7), size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
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
  
  void _showOfflineSettings(BuildContext context, WidgetRef ref) {
    showGlassDialog(
      context: context,
      title: const Text('Offline Settings'),
      content: const OfflineSettingsDialog(),
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
  
  void _confirmDeleteOfflineArticle(BuildContext context, WidgetRef ref, String articleId) {
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
              await ref.read(offlineArticlesProvider.notifier).deleteOfflineArticle(articleId);
              ref.invalidate(offlineStatisticsProvider);
              if (context.mounted) {
                context.showSuccessSnackBar('Article removed from offline storage');
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
  const OfflineSettingsDialog({super.key});

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
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          value: settings.autoDownloadStarred,
          onChanged: (_) => settingsNotifier.toggleAutoDownloadStarred(),
          activeColor: Theme.of(context).colorScheme.primary,
        ),
        SwitchListTile(
          title: Text(
            'Auto-download unread articles',
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          value: settings.autoDownloadUnread,
          onChanged: (_) => settingsNotifier.toggleAutoDownloadUnread(),
          activeColor: Theme.of(context).colorScheme.primary,
        ),
        SwitchListTile(
          title: Text(
            'Download images',
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          subtitle: Text(
            'Include images in offline articles',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
          ),
          value: settings.downloadImages,
          onChanged: (_) => settingsNotifier.toggleDownloadImages(),
          activeColor: Theme.of(context).colorScheme.primary,
        ),
        SwitchListTile(
          title: Text(
            'Wi-Fi only',
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          subtitle: Text(
            'Download articles only on Wi-Fi',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
          ),
          value: settings.wifiOnly,
          onChanged: (_) => settingsNotifier.toggleWifiOnly(),
          activeColor: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        _buildSliderSetting(
          title: 'Max offline articles',
          value: settings.maxOfflineArticles.toDouble(),
          min: 10,
          max: 500,
          divisions: 49,
          label: settings.maxOfflineArticles.toString(),
          onChanged: (value) => settingsNotifier.setMaxOfflineArticles(value.toInt()),
        ),
        const SizedBox(height: 16),
        _buildSliderSetting(
          title: 'Max storage size (MB)',
          value: settings.maxStorageSizeMB.toDouble(),
          min: 50,
          max: 2000,
          divisions: 39,
          label: '${settings.maxStorageSizeMB} MB',
          onChanged: (value) => settingsNotifier.setMaxStorageSize(value.toInt()),
        ),
        const SizedBox(height: 16),
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
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
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
          activeColor: GlassTheme.primaryColor,
          inactiveColor: Colors.white.withOpacity(0.3),
        ),
      ],
    );
  }
}