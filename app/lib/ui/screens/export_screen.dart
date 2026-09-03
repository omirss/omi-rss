import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../glass_theme.dart';
import '../components/glass_container.dart';
import '../components/glass_button.dart';
import '../components/glass_app_bar.dart';
import '../components/glass_snack_bar.dart';
import '../../providers/export_provider.dart';
import '../../providers/feed_provider.dart';

class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exportStatus = ref.watch(exportStatusProvider);
    
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
                title: 'Export Articles',
                leading: GlassButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                  variant: GlassButtonVariant.icon,
                ),
              ),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Export status
                      if (exportStatus.state != ExportState.idle) ...[
                        _buildExportStatus(context, ref, exportStatus),
                        const SizedBox(height: 24),
                      ],
                      
                      // Notion export section
                      _buildExportSection(
                        icon: Icons.table_chart,
                        title: 'Export to Notion',
                        subtitle: 'Export articles as CSV for easy import into Notion databases',
                        exports: [
                          ExportOption(
                            title: 'All Articles',
                            description: 'Export all articles from all feeds',
                            icon: Icons.all_inclusive,
                            onExport: () => _exportAllToNotion(context, ref),
                          ),
                          ExportOption(
                            title: 'Starred Articles',
                            description: 'Export only your starred articles',
                            icon: Icons.star,
                            onExport: () => _exportStarredToNotion(context, ref),
                          ),
                        ],
                      ).animate()
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.1, end: 0),
                      
                      const SizedBox(height: 24),
                      
                      // Obsidian export section
                      _buildExportSection(
                        icon: Icons.note,
                        title: 'Export to Obsidian',
                        subtitle: 'Export articles as Markdown files for your Obsidian vault',
                        exports: [
                          ExportOption(
                            title: 'All Articles',
                            description: 'Export all articles organized by feed',
                            icon: Icons.all_inclusive,
                            onExport: () => _exportAllToObsidian(context, ref),
                          ),
                          ExportOption(
                            title: 'Starred Articles',
                            description: 'Export only your starred articles',
                            icon: Icons.star,
                            onExport: () => _exportStarredToObsidian(context, ref),
                          ),
                        ],
                      ).animate()
                        .fadeIn(duration: 300.ms, delay: 100.ms)
                        .slideY(begin: 0.1, end: 0),
                      
                      const SizedBox(height: 24),
                      
                      // Export info
                      GlassContainer(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, 
                                  color: Colors.white.withOpacity(0.7),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Export Information',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '• Notion exports create CSV files that can be imported into Notion databases\n'
                              '• Obsidian exports create Markdown files with proper frontmatter\n'
                              '• All exports include metadata like tags, read status, and publish dates\n'
                              '• Exported files can be shared via your device\'s share menu',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ).animate()
                        .fadeIn(duration: 300.ms, delay: 200.ms),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildExportStatus(BuildContext context, WidgetRef ref, ExportStatus status) {
    IconData icon;
    Color color;
    
    switch (status.state) {
      case ExportState.exporting:
        icon = Icons.sync;
        color = Colors.blue;
        break;
      case ExportState.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case ExportState.error:
        icon = Icons.error;
        color = Colors.red;
        break;
      default:
        icon = Icons.info;
        color = Colors.white;
    }
    
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(icon, color: color, size: 48)
            .animate(
              onPlay: (controller) {
                if (status.state == ExportState.exporting) {
                  controller.repeat();
                }
              },
            )
            .rotate(duration: 2.seconds),
          const SizedBox(height: 16),
          Text(
            status.currentStep ?? 'Ready to export',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (status.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              status.errorMessage!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (status.state == ExportState.completed && status.filePath != null) ...[
            const SizedBox(height: 16),
            GlassButton(
              text: 'Share Export',
              icon: Icons.share,
              onPressed: () => _shareExport(context, ref, status.filePath!),
              variant: GlassButtonVariant.elevated,
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildExportSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<ExportOption> exports,
  }) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.9), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...exports.map((export) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildExportOption(export),
          )),
        ],
      ),
    );
  }
  
  Widget _buildExportOption(ExportOption option) {
    return GlassButton(
      onPressed: option.onExport,
      variant: GlassButtonVariant.text,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(option.icon, color: Colors.white.withOpacity(0.8)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withOpacity(0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _exportAllToNotion(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref.read(exportManagerProvider).exportAllArticlesToNotion();
      if (file != null && context.mounted) {
        context.showSuccessSnackBar('Articles exported to Notion CSV');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: ${e.toString()}');
      }
    }
  }
  
  Future<void> _exportStarredToNotion(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref.read(exportManagerProvider).exportStarredArticlesToNotion();
      if (file != null && context.mounted) {
        context.showSuccessSnackBar('Starred articles exported to Notion CSV');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: ${e.toString()}');
      }
    }
  }
  
  Future<void> _exportAllToObsidian(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(exportManagerProvider).exportAllArticlesToObsidian();
      if (context.mounted) {
        context.showSuccessSnackBar('Articles exported to Obsidian vault');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: ${e.toString()}');
      }
    }
  }
  
  Future<void> _exportStarredToObsidian(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref.read(exportManagerProvider).exportStarredArticlesToObsidian();
      if (file != null && context.mounted) {
        context.showSuccessSnackBar('Starred articles exported to Obsidian vault');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: ${e.toString()}');
      }
    }
  }
  
  Future<void> _shareExport(BuildContext context, WidgetRef ref, String filePath) async {
    try {
      await ref.read(exportManagerProvider).shareExportedFile(filePath);
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Failed to share export');
      }
    }
  }
}

class ExportOption {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onExport;
  
  ExportOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.onExport,
  });
}