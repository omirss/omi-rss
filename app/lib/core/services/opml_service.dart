import 'dart:async';
import 'dart:convert';
import 'package:xml/xml.dart';
import '../models/feed.dart';
import '../models/category.dart';
import 'feed_service.dart';
import '../database/database.dart';

/// Service for importing and exporting OPML files with progress tracking
class OpmlService {
  final FeedService? _feedService;
  final AppDatabase? _database;
  
  // Progress tracking
  final _importProgressController = StreamController<OpmlImportProgress>.broadcast();
  Stream<OpmlImportProgress> get importProgress => _importProgressController.stream;
  
  OpmlService({
    FeedService? feedService,
    AppDatabase? database,
  }) : _feedService = feedService,
        _database = database;
  /// Import feeds from OPML content
  Future<OpmlImportResult> importOpml(String opmlContent) async {
    try {
      final document = XmlDocument.parse(opmlContent);
      final opml = document.findElements('opml').first;
      final body = opml.findElements('body').first;
      
      final feeds = <OpmlFeed>[];
      final categories = <OpmlCategory>[];
      final categoryMap = <String, String>{}; // name -> id
      
      // Process outlines recursively
      _processOutlines(
        body.findElements('outline'),
        feeds,
        categories,
        categoryMap,
        null,
      );
      
      return OpmlImportResult(
        feeds: feeds,
        categories: categories,
        success: true,
      );
    } catch (e) {
      return OpmlImportResult(
        feeds: [],
        categories: [],
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Import feeds from OPML with progress tracking and feed validation
  Future<OpmlImportResult> importOpmlWithProgress(
    String opmlContent, {
    bool validateFeeds = true,
    bool skipInvalidFeeds = true,
    int concurrency = 3,
  }) async {
    try {
      // Parse OPML
      _importProgressController.add(OpmlImportProgress(
        phase: OpmlImportPhase.parsing,
        message: 'Parsing OPML file...',
      ));
      
      final parseResult = await importOpml(opmlContent);
      if (!parseResult.success) {
        _importProgressController.add(OpmlImportProgress(
          phase: OpmlImportPhase.error,
          message: 'Failed to parse OPML: ${parseResult.error}',
        ));
        return parseResult;
      }
      
      // Create categories in database
      if (_database != null && parseResult.categories.isNotEmpty) {
        _importProgressController.add(OpmlImportProgress(
          phase: OpmlImportPhase.creatingCategories,
          message: 'Creating ${parseResult.categories.length} categories...',
          totalCategories: parseResult.categories.length,
        ));
        
        final categoryMapping = <String, String>{}; // old id -> new id
        
        for (int i = 0; i < parseResult.categories.length; i++) {
          final opmlCategory = parseResult.categories[i];
          final newCategory = await _database!.createCategory(Category(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: opmlCategory.name,
            parentId: opmlCategory.parentId != null 
                ? categoryMapping[opmlCategory.parentId] 
                : null,
            createdAt: DateTime.now(),
          ));
          
          categoryMapping[opmlCategory.id] = newCategory.id;
          
          _importProgressController.add(OpmlImportProgress(
            phase: OpmlImportPhase.creatingCategories,
            message: 'Created category: ${opmlCategory.name}',
            totalCategories: parseResult.categories.length,
            processedCategories: i + 1,
          ));
        }
      }
      
      // Import feeds
      final importedFeeds = <Feed>[];
      final failedFeeds = <OpmlFeed>[];
      final errors = <String, String>{};
      
      if (_feedService != null && parseResult.feeds.isNotEmpty) {
        _importProgressController.add(OpmlImportProgress(
          phase: OpmlImportPhase.importingFeeds,
          message: 'Importing ${parseResult.feeds.length} feeds...',
          totalFeeds: parseResult.feeds.length,
        ));
        
        // Process feeds in batches
        final feedQueue = List<OpmlFeed>.from(parseResult.feeds);
        final activeTasks = <Future<void>>[];
        int processed = 0;
        
        while (feedQueue.isNotEmpty || activeTasks.isNotEmpty) {
          // Start new tasks up to concurrency limit
          while (activeTasks.length < concurrency && feedQueue.isNotEmpty) {
            final opmlFeed = feedQueue.removeAt(0);
            final task = _importSingleFeed(
              opmlFeed,
              importedFeeds,
              failedFeeds,
              errors,
              validateFeeds,
              skipInvalidFeeds,
            ).then((_) {
              processed++;
              _importProgressController.add(OpmlImportProgress(
                phase: OpmlImportPhase.importingFeeds,
                message: 'Imported: ${opmlFeed.title}',
                totalFeeds: parseResult.feeds.length,
                processedFeeds: processed,
                importedFeeds: importedFeeds.length,
                failedFeeds: failedFeeds.length,
              ));
            });
            activeTasks.add(task);
          }
          
          // Wait for at least one task to complete
          if (activeTasks.isNotEmpty) {
            await Future.any(activeTasks);
            activeTasks.removeWhere((task) => task.isCompleted);
          }
        }
      }
      
      // Save to database if available
      if (_database != null && importedFeeds.isNotEmpty) {
        _importProgressController.add(OpmlImportProgress(
          phase: OpmlImportPhase.saving,
          message: 'Saving feeds to database...',
        ));
        
        for (final feed in importedFeeds) {
          await _database!.insertFeed(feed);
        }
      }
      
      // Complete
      _importProgressController.add(OpmlImportProgress(
        phase: OpmlImportPhase.complete,
        message: 'Import complete!',
        totalFeeds: parseResult.feeds.length,
        processedFeeds: parseResult.feeds.length,
        importedFeeds: importedFeeds.length,
        failedFeeds: failedFeeds.length,
      ));
      
      return OpmlImportResult(
        feeds: parseResult.feeds,
        categories: parseResult.categories,
        success: true,
        importedFeeds: importedFeeds,
        failedFeeds: failedFeeds,
        errors: errors,
      );
    } catch (e) {
      _importProgressController.add(OpmlImportProgress(
        phase: OpmlImportPhase.error,
        message: 'Import failed: $e',
      ));
      
      return OpmlImportResult(
        feeds: [],
        categories: [],
        success: false,
        error: e.toString(),
      );
    }
  }
  
  Future<void> _importSingleFeed(
    OpmlFeed opmlFeed,
    List<Feed> importedFeeds,
    List<OpmlFeed> failedFeeds,
    Map<String, String> errors,
    bool validateFeeds,
    bool skipInvalidFeeds,
  ) async {
    try {
      if (_feedService == null) {
        failedFeeds.add(opmlFeed);
        errors[opmlFeed.xmlUrl] = 'Feed service not available';
        return;
      }
      
      // Subscribe to the feed
      final feed = await _feedService!.subscribeFeed(opmlFeed.xmlUrl);
      
      // Update feed with OPML metadata
      final updatedFeed = feed.copyWith(
        customTitle: opmlFeed.title != feed.title ? opmlFeed.title : null,
        siteUrl: opmlFeed.htmlUrl,
        categoryId: opmlFeed.categoryId,
      );
      
      importedFeeds.add(updatedFeed);
    } catch (e) {
      failedFeeds.add(opmlFeed);
      errors[opmlFeed.xmlUrl] = e.toString();
      
      if (!skipInvalidFeeds) {
        rethrow;
      }
    }
  }
  
  /// Export feeds to OPML format
  Future<String> exportOpml({
    required List<Feed> feeds,
    required List<Category> categories,
    String title = 'RSS Reader Subscriptions',
  }) async {
    final builder = XmlBuilder();
    
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('opml', attributes: {'version': '2.0'}, nest: () {
      // Head
      builder.element('head', nest: () {
        builder.element('title', nest: title);
        builder.element('dateCreated', nest: DateTime.now().toIso8601String());
        builder.element('ownerName', nest: 'RSS Glassmorphism Reader');
      });
      
      // Body
      builder.element('body', nest: () {
        // Build category tree
        final categoryTree = _buildCategoryTree(categories);
        final feedsByCategory = _groupFeedsByCategory(feeds);
        
        // Export root categories
        for (final rootCategory in categoryTree.where((c) => c.parentId == null)) {
          _exportCategoryOutline(
            builder,
            rootCategory,
            categoryTree,
            feedsByCategory,
          );
        }
        
        // Export uncategorized feeds
        final uncategorizedFeeds = feedsByCategory['uncategorized'] ?? [];
        for (final feed in uncategorizedFeeds) {
          _exportFeedOutline(builder, feed);
        }
      });
    });
    
    return builder.buildDocument().toXmlString(pretty: true);
  }
  
  /// Process outline elements recursively
  void _processOutlines(
    Iterable<XmlElement> outlines,
    List<OpmlFeed> feeds,
    List<OpmlCategory> categories,
    Map<String, String> categoryMap,
    String? parentCategoryId,
  ) {
    for (final outline in outlines) {
      final type = outline.getAttribute('type')?.toLowerCase();
      final xmlUrl = outline.getAttribute('xmlUrl');
      
      if (xmlUrl != null && xmlUrl.isNotEmpty) {
        // This is a feed
        feeds.add(OpmlFeed(
          title: outline.getAttribute('title') ?? 
                 outline.getAttribute('text') ?? 
                 'Untitled Feed',
          xmlUrl: xmlUrl,
          htmlUrl: outline.getAttribute('htmlUrl'),
          description: outline.getAttribute('description'),
          categoryId: parentCategoryId,
        ));
      } else {
        // This is a category
        final categoryName = outline.getAttribute('title') ?? 
                           outline.getAttribute('text') ?? 
                           'Untitled Category';
        final categoryId = 'cat_${DateTime.now().millisecondsSinceEpoch}_${categories.length}';
        
        categories.add(OpmlCategory(
          id: categoryId,
          name: categoryName,
          parentId: parentCategoryId,
        ));
        
        categoryMap[categoryName] = categoryId;
        
        // Process child outlines
        _processOutlines(
          outline.findElements('outline'),
          feeds,
          categories,
          categoryMap,
          categoryId,
        );
      }
    }
  }
  
  /// Build category tree for export
  List<Category> _buildCategoryTree(List<Category> categories) {
    return categories;
  }
  
  /// Group feeds by category
  Map<String, List<Feed>> _groupFeedsByCategory(List<Feed> feeds) {
    final grouped = <String, List<Feed>>{};
    
    for (final feed in feeds) {
      final categoryId = feed.categoryId ?? 'uncategorized';
      grouped.putIfAbsent(categoryId, () => []).add(feed);
    }
    
    return grouped;
  }
  
  /// Export category outline
  void _exportCategoryOutline(
    XmlBuilder builder,
    Category category,
    List<Category> allCategories,
    Map<String, List<Feed>> feedsByCategory,
  ) {
    builder.element('outline', attributes: {
      'text': category.name,
      'title': category.name,
    }, nest: () {
      // Export child categories
      final childCategories = allCategories.where((c) => c.parentId == category.id);
      for (final childCategory in childCategories) {
        _exportCategoryOutline(
          builder,
          childCategory,
          allCategories,
          feedsByCategory,
        );
      }
      
      // Export feeds in this category
      final feeds = feedsByCategory[category.id] ?? [];
      for (final feed in feeds) {
        _exportFeedOutline(builder, feed);
      }
    });
  }
  
  /// Export feed outline
  void _exportFeedOutline(XmlBuilder builder, Feed feed) {
    final attributes = <String, String>{
      'type': 'rss',
      'text': feed.customTitle ?? feed.title,
      'title': feed.customTitle ?? feed.title,
      'xmlUrl': feed.url,
    };
    
    if (feed.siteUrl != null) {
      attributes['htmlUrl'] = feed.siteUrl!;
    }
    
    if (feed.description != null) {
      attributes['description'] = feed.description!;
    }
    
    builder.element('outline', attributes: attributes);
  }
  
  /// Validate OPML content
  bool validateOpml(String opmlContent) {
    try {
      final document = XmlDocument.parse(opmlContent);
      final opml = document.findElements('opml').firstOrNull;
      final body = opml?.findElements('body').firstOrNull;
      
      return opml != null && body != null;
    } catch (e) {
      return false;
    }
  }
  
  /// Get OPML info without full import
  OpmlInfo? getOpmlInfo(String opmlContent) {
    try {
      final document = XmlDocument.parse(opmlContent);
      final opml = document.findElements('opml').first;
      final head = opml.findElements('head').firstOrNull;
      final body = opml.findElements('body').first;
      
      // Count feeds and categories
      int feedCount = 0;
      int categoryCount = 0;
      
      void countOutlines(Iterable<XmlElement> outlines) {
        for (final outline in outlines) {
          final xmlUrl = outline.getAttribute('xmlUrl');
          
          if (xmlUrl != null && xmlUrl.isNotEmpty) {
            feedCount++;
          } else {
            categoryCount++;
            countOutlines(outline.findElements('outline'));
          }
        }
      }
      
      countOutlines(body.findElements('outline'));
      
      return OpmlInfo(
        title: head?.findElements('title').firstOrNull?.text,
        dateCreated: head?.findElements('dateCreated').firstOrNull?.text,
        ownerName: head?.findElements('ownerName').firstOrNull?.text,
        feedCount: feedCount,
        categoryCount: categoryCount,
      );
    } catch (e) {
      return null;
    }
  }
}

/// OPML import result
class OpmlImportResult {
  final List<OpmlFeed> feeds;
  final List<OpmlCategory> categories;
  final bool success;
  final String? error;
  final List<Feed>? importedFeeds;
  final List<OpmlFeed>? failedFeeds;
  final Map<String, String>? errors;
  
  OpmlImportResult({
    required this.feeds,
    required this.categories,
    required this.success,
    this.error,
    this.importedFeeds,
    this.failedFeeds,
    this.errors,
  });
}

/// OPML feed data
class OpmlFeed {
  final String title;
  final String xmlUrl;
  final String? htmlUrl;
  final String? description;
  final String? categoryId;
  
  OpmlFeed({
    required this.title,
    required this.xmlUrl,
    this.htmlUrl,
    this.description,
    this.categoryId,
  });
}

/// OPML category data
class OpmlCategory {
  final String id;
  final String name;
  final String? parentId;
  
  OpmlCategory({
    required this.id,
    required this.name,
    this.parentId,
  });
}

/// OPML file info
class OpmlInfo {
  final String? title;
  final String? dateCreated;
  final String? ownerName;
  final int feedCount;
  final int categoryCount;
  
  OpmlInfo({
    this.title,
    this.dateCreated,
    this.ownerName,
    required this.feedCount,
    required this.categoryCount,
  });
}

/// OPML import progress
class OpmlImportProgress {
  final OpmlImportPhase phase;
  final String message;
  final int? totalFeeds;
  final int? processedFeeds;
  final int? importedFeeds;
  final int? failedFeeds;
  final int? totalCategories;
  final int? processedCategories;
  
  OpmlImportProgress({
    required this.phase,
    required this.message,
    this.totalFeeds,
    this.processedFeeds,
    this.importedFeeds,
    this.failedFeeds,
    this.totalCategories,
    this.processedCategories,
  });
  
  double get progress {
    if (phase == OpmlImportPhase.parsing || 
        phase == OpmlImportPhase.error ||
        phase == OpmlImportPhase.complete) {
      return phase == OpmlImportPhase.complete ? 1.0 : 0.0;
    }
    
    if (phase == OpmlImportPhase.creatingCategories) {
      if (totalCategories != null && totalCategories! > 0) {
        return (processedCategories ?? 0) / totalCategories!;
      }
    }
    
    if (phase == OpmlImportPhase.importingFeeds) {
      if (totalFeeds != null && totalFeeds! > 0) {
        return (processedFeeds ?? 0) / totalFeeds!;
      }
    }
    
    return 0.0;
  }
}

/// OPML import phases
enum OpmlImportPhase {
  parsing,
  creatingCategories,
  importingFeeds,
  saving,
  complete,
  error,
}