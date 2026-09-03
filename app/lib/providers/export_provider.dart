import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../features/export/notion_obsidian_export.dart';
import '../core/models/article.dart';
import '../core/models/feed.dart';
import 'feed_provider.dart';

// Export service provider
final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService();
});

// Export status provider
final exportStatusProvider = StateNotifierProvider<ExportStatusNotifier, ExportStatus>((ref) {
  return ExportStatusNotifier();
});

enum ExportState {
  idle,
  exporting,
  completed,
  error,
}

class ExportStatus {
  final ExportState state;
  final String? currentStep;
  final String? filePath;
  final String? errorMessage;
  
  ExportStatus({
    this.state = ExportState.idle,
    this.currentStep,
    this.filePath,
    this.errorMessage,
  });
  
  ExportStatus copyWith({
    ExportState? state,
    String? currentStep,
    String? filePath,
    String? errorMessage,
  }) {
    return ExportStatus(
      state: state ?? this.state,
      currentStep: currentStep ?? this.currentStep,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ExportStatusNotifier extends StateNotifier<ExportStatus> {
  ExportStatusNotifier() : super(ExportStatus());
  
  void startExport(String step) {
    state = state.copyWith(
      state: ExportState.exporting,
      currentStep: step,
      filePath: null,
      errorMessage: null,
    );
  }
  
  void completeExport(String filePath) {
    state = state.copyWith(
      state: ExportState.completed,
      currentStep: 'Export completed',
      filePath: filePath,
    );
  }
  
  void setError(String error) {
    state = state.copyWith(
      state: ExportState.error,
      errorMessage: error,
    );
  }
  
  void reset() {
    state = ExportStatus();
  }
}

// Export manager
final exportManagerProvider = Provider<ExportManager>((ref) {
  return ExportManager(ref);
});

class ExportManager {
  final Ref ref;
  
  ExportManager(this.ref);
  
  Future<String> _getExportDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${directory.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir.path;
  }
  
  String _generateFilename(String prefix, String extension) {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${prefix}_export_$timestamp.$extension';
  }
  
  Future<File?> exportArticlesToNotion(List<Article> articles) async {
    final statusNotifier = ref.read(exportStatusProvider.notifier);
    
    try {
      statusNotifier.startExport('Exporting articles to Notion CSV...');
      
      final exportService = ref.read(exportServiceProvider);
      final exportDir = await _getExportDirectory();
      final filename = _generateFilename('notion', 'csv');
      final outputPath = '$exportDir/$filename';
      
      final file = await exportService.exportToNotion(articles, outputPath);
      
      statusNotifier.completeExport(file.path);
      return file;
      
    } catch (e) {
      statusNotifier.setError(e.toString());
      return null;
    }
  }
  
  Future<File?> exportArticlesToObsidian(List<Article> articles) async {
    final statusNotifier = ref.read(exportStatusProvider.notifier);
    
    try {
      statusNotifier.startExport('Exporting articles to Obsidian vault...');
      
      final exportService = ref.read(exportServiceProvider);
      final exportDir = await _getExportDirectory();
      final dirname = _generateFilename('obsidian', '');
      final outputPath = '$exportDir/$dirname';
      
      final file = await exportService.exportToObsidian(articles, outputPath);
      
      statusNotifier.completeExport(outputPath);
      return file;
      
    } catch (e) {
      statusNotifier.setError(e.toString());
      return null;
    }
  }
  
  Future<void> exportAllArticlesToNotion() async {
    try {
      // Get all articles from all feeds
      final articles = await _getAllArticles();
      await exportArticlesToNotion(articles);
    } catch (e) {
      ref.read(exportStatusProvider.notifier).setError(e.toString());
    }
  }
  
  Future<void> exportAllArticlesToObsidian() async {
    try {
      // Get all feeds with their articles
      final feedsWithArticles = await _getFeedsWithArticles();
      
      final statusNotifier = ref.read(exportStatusProvider.notifier);
      statusNotifier.startExport('Exporting all feeds to Obsidian vault...');
      
      final exportService = ref.read(exportServiceProvider);
      final exportDir = await _getExportDirectory();
      final dirname = _generateFilename('obsidian_all', '');
      final outputPath = '$exportDir/$dirname';
      
      await exportService.exportFeedsToObsidian(feedsWithArticles, outputPath);
      
      statusNotifier.completeExport(outputPath);
      
    } catch (e) {
      ref.read(exportStatusProvider.notifier).setError(e.toString());
    }
  }
  
  Future<void> exportStarredArticlesToNotion() async {
    try {
      final articles = await _getStarredArticles();
      await exportArticlesToNotion(articles);
    } catch (e) {
      ref.read(exportStatusProvider.notifier).setError(e.toString());
    }
  }
  
  Future<void> exportStarredArticlesToObsidian() async {
    try {
      final articles = await _getStarredArticles();
      await exportArticlesToObsidian(articles);
    } catch (e) {
      ref.read(exportStatusProvider.notifier).setError(e.toString());
    }
  }
  
  Future<void> shareExportedFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'RSS Articles Export',
        );
      }
    } catch (e) {
      // Handle share error
    }
  }
  
  Future<List<Article>> _getAllArticles() async {
    final feeds = await ref.read(feedsProvider.future);
    final articles = <Article>[];
    
    for (final feed in feeds) {
      final feedArticles = await ref.read(articlesProvider(feed.id).future);
      articles.addAll(feedArticles);
    }
    
    return articles;
  }
  
  Future<List<Article>> _getStarredArticles() async {
    final allArticles = await _getAllArticles();
    return allArticles.where((article) => article.isStarred).toList();
  }
  
  Future<Map<Feed, List<Article>>> _getFeedsWithArticles() async {
    final feeds = await ref.read(feedsProvider.future);
    final feedsWithArticles = <Feed, List<Article>>{};
    
    for (final feed in feeds) {
      final articles = await ref.read(articlesProvider(feed.id).future);
      feedsWithArticles[feed] = articles;
    }
    
    return feedsWithArticles;
  }
}