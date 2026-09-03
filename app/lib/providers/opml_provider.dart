import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/opml_service.dart';
import '../core/models/feed.dart';
import '../core/models/folder.dart';
import 'database_provider.dart';
import 'feed_provider.dart';

/// OPML service provider
final opmlServiceProvider = Provider<OPMLService>((ref) {
  return OPMLService();
});

/// Export feeds to OPML
final exportOPMLProvider = FutureProvider<String>((ref) async {
  final database = ref.watch(databaseProvider);
  final opmlService = ref.watch(opmlServiceProvider);
  
  // Get all feeds and folders
  final feeds = await database.feedDao.getAllFeeds();
  final folders = await database.folderDao.getAllFolders();
  
  // Generate OPML
  return await opmlService.exportOPML(
    feeds: feeds,
    folders: folders,
    title: 'Omi RSS Reader Feeds',
  );
});

/// Import OPML state
class OPMLImportState {
  final bool isImporting;
  final int totalFeeds;
  final int importedFeeds;
  final int failedFeeds;
  final List<String> errors;
  final bool isComplete;
  
  OPMLImportState({
    this.isImporting = false,
    this.totalFeeds = 0,
    this.importedFeeds = 0,
    this.failedFeeds = 0,
    this.errors = const [],
    this.isComplete = false,
  });
  
  OPMLImportState copyWith({
    bool? isImporting,
    int? totalFeeds,
    int? importedFeeds,
    int? failedFeeds,
    List<String>? errors,
    bool? isComplete,
  }) {
    return OPMLImportState(
      isImporting: isImporting ?? this.isImporting,
      totalFeeds: totalFeeds ?? this.totalFeeds,
      importedFeeds: importedFeeds ?? this.importedFeeds,
      failedFeeds: failedFeeds ?? this.failedFeeds,
      errors: errors ?? this.errors,
      isComplete: isComplete ?? this.isComplete,
    );
  }
  
  double get progress => totalFeeds > 0 ? importedFeeds / totalFeeds : 0;
  String get progressText => '$importedFeeds / $totalFeeds feeds imported';
}

/// OPML import notifier
class OPMLImportNotifier extends StateNotifier<OPMLImportState> {
  final Ref ref;
  
  OPMLImportNotifier(this.ref) : super(OPMLImportState());
  
  Future<void> importOPML(String opmlContent) async {
    if (state.isImporting) return;
    
    state = OPMLImportState(isImporting: true);
    
    try {
      final opmlService = ref.read(opmlServiceProvider);
      final database = ref.read(databaseProvider);
      final feedService = ref.read(feedServiceProvider);
      
      // Parse OPML
      final result = await opmlService.importOPML(opmlContent);
      
      state = state.copyWith(
        totalFeeds: result.totalFeeds,
      );
      
      // Import folders first
      final folderIdMap = <String, String>{};
      for (final opmlFolder in result.folders) {
        final folder = Folder(
          name: opmlFolder.name,
          parentId: opmlFolder.parentId != null ? folderIdMap[opmlFolder.parentId!] : null,
        );
        
        final savedFolder = await database.folderDao.insertFolder(folder);
        folderIdMap[opmlFolder.id] = savedFolder.id;
      }
      
      // Import feeds
      final errors = <String>[];
      int importedCount = 0;
      int failedCount = 0;
      
      for (final opmlFeed in result.feeds) {
        try {
          // Check if feed already exists
          final existingFeed = await database.feedDao.getFeedByUrl(opmlFeed.xmlUrl);
          
          if (existingFeed != null) {
            // Skip existing feed
            importedCount++;
            state = state.copyWith(importedFeeds: importedCount);
            continue;
          }
          
          // Subscribe to new feed
          final feed = await feedService.subscribeFeed(opmlFeed.xmlUrl);
          
          // Update feed folder if needed
          if (opmlFeed.folderId != null && folderIdMap.containsKey(opmlFeed.folderId!)) {
            await database.feedDao.updateFeed(
              feed.copyWith(categoryId: folderIdMap[opmlFeed.folderId!]),
            );
          }
          
          // Custom title if different from parsed
          if (opmlFeed.title != feed.title) {
            await database.feedDao.updateFeed(
              feed.copyWith(customTitle: opmlFeed.title),
            );
          }
          
          importedCount++;
          state = state.copyWith(importedFeeds: importedCount);
          
          // Fetch initial articles
          final refreshResult = await feedService.refreshFeed(feed);
          if (refreshResult.newArticles.isNotEmpty) {
            await database.articleDao.insertArticles(refreshResult.newArticles);
          }
        } catch (e) {
          failedCount++;
          errors.add('${opmlFeed.title}: ${e.toString()}');
          state = state.copyWith(
            failedFeeds: failedCount,
            errors: errors,
          );
        }
      }
      
      state = state.copyWith(
        isComplete: true,
        isImporting: false,
      );
    } catch (e) {
      state = state.copyWith(
        isImporting: false,
        errors: [e.toString()],
      );
      rethrow;
    }
  }
  
  void reset() {
    state = OPMLImportState();
  }
}

/// OPML import provider
final opmlImportProvider = StateNotifierProvider<OPMLImportNotifier, OPMLImportState>((ref) {
  return OPMLImportNotifier(ref);
});

/// Load and import OPML from file
final importOPMLFromFileProvider = FutureProvider<void>((ref) async {
  final opmlService = ref.read(opmlServiceProvider);
  
  // Load OPML file
  final opmlContent = await opmlService.loadOPMLFromFile();
  
  if (opmlContent != null) {
    // Import OPML
    await ref.read(opmlImportProvider.notifier).importOPML(opmlContent);
  }
});

/// Export and save OPML to file
final exportOPMLToFileProvider = FutureProvider.family<void, String>((ref, filename) async {
  final opmlService = ref.read(opmlServiceProvider);
  
  // Generate OPML
  final opmlContent = await ref.read(exportOPMLProvider.future);
  
  // Save to file
  await opmlService.saveOPMLToFile(opmlContent, filename);
});