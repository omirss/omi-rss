import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/opml_service.dart';
import '../core/models/feed.dart';
import '../core/models/folder.dart';
import 'database_provider.dart';
import 'feed_provider.dart';
import 'settings_provider.dart'
    show sanitizeArticleLimit, persistedArticleLimit;
import 'sync_provider.dart' show LibraryOwner, activeLibraryOwner;

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
  final folderFeedIds = <String, List<String>>{};
  for (final folder in folders) {
    folderFeedIds[folder.id] =
        await database.folderDao.getFeedsInFolder(folder.id);
  }

  // Generate OPML
  return await opmlService.exportOPML(
    feeds: feeds,
    folders: folders,
    folderFeedIds: folderFeedIds,
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

          Feed feed;
          if (existingFeed == null) {
            // Subscribe parses the feed; persist the row before anything
            // references it.
            feed = await feedService.subscribeFeed(opmlFeed.xmlUrl);
            if (opmlFeed.title != feed.title) {
              feed = feed.copyWith(customTitle: opmlFeed.title);
            }
            await database.feedDao.insertFeed(feed);
            // Provenance: locally imported URLs may later be pushed by
            // the account that is actively signed in (if any). Without
            // this record the sync engine treats them like legacy
            // local-only rows and never uploads them.
            final owner = await activeLibraryOwner(ref);
            if (owner != null) {
              await LibraryOwner.addPendingCreate(owner, opmlFeed.xmlUrl);
            }
          } else {
            feed = existingFeed;
            final effectiveTitle = feed.customTitle ?? feed.title;
            if (opmlFeed.title != effectiveTitle) {
              feed = feed.copyWith(customTitle: opmlFeed.title);
              await database.feedDao.updateFeed(feed);
            }
          }

          // Folder membership lives in the join table, never in
          // category_id (folder ids are not category ids).
          final importedFolderId = opmlFeed.folderId == null
              ? null
              : folderIdMap[opmlFeed.folderId!];
          if (importedFolderId != null) {
            await database.folderDao.addFeedToFolder(
              importedFolderId,
              feed.id,
            );
          }

          importedCount++;
          state = state.copyWith(importedFeeds: importedCount);

          // Fetch initial articles; persist the refreshed feed, its
          // articles and the retention cap together.
          final refreshResult = await feedService.refreshFeed(feed);
          await database.commitPublisherRefresh(
            refreshResult.feed,
            refreshResult.upsertArticles,
            sanitizeArticleLimit(await persistedArticleLimit()),
          );
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