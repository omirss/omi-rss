import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/import/pocket_instapaper_import.dart';
import 'database_provider.dart';
import '../core/models/feed.dart';
import '../core/models/article.dart';
import 'feed_provider.dart';

// Import service provider
final importServiceProvider = Provider<ImportService>((ref) {
  return ImportService();
});

// Import status provider
final importStatusProvider = StateNotifierProvider<ImportStatusNotifier, ImportStatus>((ref) {
  return ImportStatusNotifier();
});

enum ImportState {
  idle,
  importing,
  processing,
  completed,
  error,
}

class ImportStatus {
  final ImportState state;
  final String? currentStep;
  final int totalArticles;
  final int processedArticles;
  final String? errorMessage;
  
  ImportStatus({
    this.state = ImportState.idle,
    this.currentStep,
    this.totalArticles = 0,
    this.processedArticles = 0,
    this.errorMessage,
  });
  
  double get progress => totalArticles > 0 ? processedArticles / totalArticles : 0.0;
  
  ImportStatus copyWith({
    ImportState? state,
    String? currentStep,
    int? totalArticles,
    int? processedArticles,
    String? errorMessage,
  }) {
    return ImportStatus(
      state: state ?? this.state,
      currentStep: currentStep ?? this.currentStep,
      totalArticles: totalArticles ?? this.totalArticles,
      processedArticles: processedArticles ?? this.processedArticles,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ImportStatusNotifier extends StateNotifier<ImportStatus> {
  ImportStatusNotifier() : super(ImportStatus());
  
  void startImport(String step) {
    state = state.copyWith(
      state: ImportState.importing,
      currentStep: step,
      processedArticles: 0,
      errorMessage: null,
    );
  }
  
  void updateProgress(String step, int processed, int total) {
    state = state.copyWith(
      currentStep: step,
      processedArticles: processed,
      totalArticles: total,
    );
  }
  
  void startProcessing(int totalArticles) {
    state = state.copyWith(
      state: ImportState.processing,
      currentStep: 'Processing articles...',
      totalArticles: totalArticles,
      processedArticles: 0,
    );
  }
  
  void completeImport() {
    state = state.copyWith(
      state: ImportState.completed,
      currentStep: 'Import completed successfully',
    );
  }
  
  void setError(String error) {
    state = state.copyWith(
      state: ImportState.error,
      errorMessage: error,
    );
  }
  
  void reset() {
    state = ImportStatus();
  }
}

// Import manager
final importManagerProvider = Provider<ImportManager>((ref) {
  return ImportManager(ref);
});

class ImportManager {
  final Ref ref;

  ImportManager(this.ref);

  Future<void> _persistImported(String source, List<ImportedArticle> importedArticles) async {
    final importService = ref.read(importServiceProvider);
    final statusNotifier = ref.read(importStatusProvider.notifier);
    final database = ref.read(databaseProvider);

    statusNotifier.startProcessing(importedArticles.length);

    final feed = importService.createImportedFeed(source, importedArticles);
    await database.feedDao.insertFeed(feed);

    final articles = importService.convertToArticles(feed.id, importedArticles);
    await database.articleDao.insertArticles(articles);

    statusNotifier.completeImport();
  }

  Future<void> importFromPocketFile(File file) async {
    final importService = ref.read(importServiceProvider);
    final statusNotifier = ref.read(importStatusProvider.notifier);

    try {
      statusNotifier.startImport('Reading Pocket export file...');

      final importedArticles = await importService.importFromPocketFile(file);

      if (importedArticles.isEmpty) {
        throw Exception('No articles found in the export file');
      }

      await _persistImported('Pocket', importedArticles);
    } catch (e) {
      statusNotifier.setError(e.toString());
      rethrow;
    }
  }

  Future<void> importFromPocketApi(String consumerKey, String accessToken) async {
    final importService = ref.read(importServiceProvider);
    final statusNotifier = ref.read(importStatusProvider.notifier);

    try {
      statusNotifier.startImport('Connecting to Pocket API...');

      final importedArticles = await importService.importFromPocketApi(
        consumerKey,
        accessToken,
      );

      if (importedArticles.isEmpty) {
        throw Exception('No articles found in your Pocket account');
      }

      await _persistImported('Pocket', importedArticles);
    } catch (e) {
      statusNotifier.setError(e.toString());
      rethrow;
    }
  }

  Future<void> importFromInstapaperFile(File file) async {
    final importService = ref.read(importServiceProvider);
    final statusNotifier = ref.read(importStatusProvider.notifier);

    try {
      statusNotifier.startImport('Reading Instapaper export file...');

      final importedArticles = await importService.importFromInstapaperFile(file);

      if (importedArticles.isEmpty) {
        throw Exception('No articles found in the export file');
      }

      await _persistImported('Instapaper', importedArticles);
    } catch (e) {
      statusNotifier.setError(e.toString());
      rethrow;
    }
  }

  Future<void> importFromInstapaperApi(String username, String password) async {
    final importService = ref.read(importServiceProvider);
    final statusNotifier = ref.read(importStatusProvider.notifier);

    try {
      statusNotifier.startImport('Connecting to Instapaper API...');

      final importedArticles = await importService.importFromInstapaperApi(
        username,
        password,
      );

      if (importedArticles.isEmpty) {
        throw Exception('No articles found in your Instapaper account');
      }

      await _persistImported('Instapaper', importedArticles);
    } catch (e) {
      statusNotifier.setError(e.toString());
      rethrow;
    }
  }
}
