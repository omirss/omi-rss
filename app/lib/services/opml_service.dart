import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'dart:io' show File;
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart';
import '../core/models/feed.dart';
import '../core/models/folder.dart';

class OPMLService {
  final Logger _logger = Logger();

  // Export feeds to OPML
  Future<String> exportOPML({
    required List<Feed> feeds,
    required List<Folder> folders,
    String title = 'Omi RSS Feeds',
  }) async {
    try {
      final builder = XmlBuilder();
      
      builder.processing('xml', 'version="1.0" encoding="UTF-8"');
      builder.element('opml', attributes: {'version': '2.0'}, nest: () {
        // Head section
        builder.element('head', nest: () {
          builder.element('title', nest: title);
          builder.element('dateCreated', nest: DateTime.now().toUtc().toIso8601String());
          builder.element('docs', nest: 'http://opml.org/spec2.opml');
        });
        
        // Body section
        builder.element('body', nest: () {
          // Build folder hierarchy
          final rootFolders = folders.where((f) => f.parentId == null).toList();
          
          // Add feeds without folders
          final feedsWithoutFolder = feeds.where((f) => f.categoryId == null).toList();
          for (final feed in feedsWithoutFolder) {
            _buildOutlineElement(builder, feed);
          }
          
          // Add folders and their feeds
          for (final folder in rootFolders) {
            _buildFolderElement(builder, folder, folders, feeds);
          }
        });
      });
      
      final document = builder.buildDocument();
      return document.toXmlString(pretty: true);
    } catch (e, stackTrace) {
      _logger.e('Error exporting OPML', error: e, stackTrace: stackTrace);
      throw OPMLException('Failed to export OPML: ${e.toString()}');
    }
  }

  // Import OPML file
  Future<OPMLImportResult> importOPML(String opmlContent) async {
    try {
      final document = XmlDocument.parse(opmlContent);
      final opmlElement = document.findElements('opml').firstOrNull;
      
      if (opmlElement == null) {
        throw OPMLException('Invalid OPML: Missing opml element');
      }
      
      final bodyElement = opmlElement.findElements('body').firstOrNull;
      if (bodyElement == null) {
        throw OPMLException('Invalid OPML: Missing body element');
      }
      
      final result = OPMLImportResult();
      
      // Parse outlines recursively
      for (final outline in bodyElement.findElements('outline')) {
        _parseOutline(outline, null, result);
      }
      
      return result;
    } catch (e, stackTrace) {
      _logger.e('Error importing OPML', error: e, stackTrace: stackTrace);
      throw OPMLException('Failed to import OPML: ${e.toString()}');
    }
  }

  // Save OPML to file
  Future<void> saveOPMLToFile(String opmlContent, String filename) async {
    if (kIsWeb) {
      // Web platform
      final bytes = utf8.encode(opmlContent);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement()
        ..href = url
        ..download = filename
        ..style.display = 'none';
      
      html.document.body!.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    } else {
      // Desktop/Mobile platforms
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save OPML file',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['opml', 'xml'],
      );
      
      if (result != null) {
        final file = File(result);
        await file.writeAsString(opmlContent);
      }
    }
  }

  // Load OPML from file
  Future<String?> loadOPMLFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['opml', 'xml'],
        withData: true,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        if (file.bytes != null) {
          // Web platform
          return utf8.decode(file.bytes!);
        } else if (file.path != null) {
          // Desktop/Mobile platforms
          final fileContent = await File(file.path!).readAsString();
          return fileContent;
        }
      }
      
      return null;
    } catch (e, stackTrace) {
      _logger.e('Error loading OPML file', error: e, stackTrace: stackTrace);
      throw OPMLException('Failed to load OPML file: ${e.toString()}');
    }
  }

  // Build outline element for a feed
  void _buildOutlineElement(XmlBuilder builder, Feed feed) {
    final attributes = {
      'type': 'rss',
      'text': feed.customTitle ?? feed.title,
      'title': feed.title,
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

  // Build folder element with nested feeds
  void _buildFolderElement(
    XmlBuilder builder,
    Folder folder,
    List<Folder> allFolders,
    List<Feed> allFeeds,
  ) {
    builder.element('outline', 
      attributes: {
        'text': folder.name,
        'title': folder.name,
      },
      nest: () {
        // Add feeds in this folder
        final feedsInFolder = allFeeds.where((f) => f.categoryId == folder.id).toList();
        for (final feed in feedsInFolder) {
          _buildOutlineElement(builder, feed);
        }
        
        // Add subfolders
        final subfolders = allFolders.where((f) => f.parentId == folder.id).toList();
        for (final subfolder in subfolders) {
          _buildFolderElement(builder, subfolder, allFolders, allFeeds);
        }
      },
    );
  }

  // Parse outline element recursively
  void _parseOutline(XmlElement outline, String? parentFolderId, OPMLImportResult result) {
    final type = outline.getAttribute('type');
    final xmlUrl = outline.getAttribute('xmlUrl');
    
    if (type == 'rss' || xmlUrl != null) {
      // This is a feed
      final feed = OPMLFeed(
        title: outline.getAttribute('text') ?? outline.getAttribute('title') ?? 'Untitled Feed',
        xmlUrl: xmlUrl!,
        htmlUrl: outline.getAttribute('htmlUrl'),
        description: outline.getAttribute('description'),
        folderId: parentFolderId,
      );
      
      result.feeds.add(feed);
    } else {
      // This is a folder
      final folderName = outline.getAttribute('text') ?? outline.getAttribute('title') ?? 'Untitled Folder';
      final folderId = DateTime.now().millisecondsSinceEpoch.toString();
      
      result.folders.add(OPMLFolder(
        id: folderId,
        name: folderName,
        parentId: parentFolderId,
      ));
      
      // Parse nested outlines
      for (final child in outline.findElements('outline')) {
        _parseOutline(child, folderId, result);
      }
    }
  }
}

// OPML import result
class OPMLImportResult {
  final List<OPMLFeed> feeds = [];
  final List<OPMLFolder> folders = [];
  
  int get totalFeeds => feeds.length;
  int get totalFolders => folders.length;
}

// OPML feed data
class OPMLFeed {
  final String title;
  final String xmlUrl;
  final String? htmlUrl;
  final String? description;
  final String? folderId;
  
  OPMLFeed({
    required this.title,
    required this.xmlUrl,
    this.htmlUrl,
    this.description,
    this.folderId,
  });
}

// OPML folder data
class OPMLFolder {
  final String id;
  final String name;
  final String? parentId;
  
  OPMLFolder({
    required this.id,
    required this.name,
    this.parentId,
  });
}

// OPML exception
class OPMLException implements Exception {
  final String message;
  
  OPMLException(this.message);
  
  @override
  String toString() => 'OPMLException: $message';
}