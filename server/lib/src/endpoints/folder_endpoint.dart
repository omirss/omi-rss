import 'package:serverpod/serverpod.dart';
import '../generated/protocol.dart';

class FolderEndpoint extends Endpoint {
  // Get all folders for the authenticated user
  Future<List<Folder>> getAllFolders(Session session) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      return await Folder.find(
        session,
        where: (t) => t.userId.equals(userId),
        orderBy: (t) => t.name,
      );
    } catch (e) {
      session.log('Error fetching folders: $e', level: LogLevel.error);
      throw Exception('Failed to fetch folders');
    }
  }
  
  // Get a specific folder by ID
  Future<Folder?> getFolder(Session session, int folderId) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      final folder = await Folder.findById(session, folderId);
      
      // Verify ownership
      if (folder != null && folder.userId != userId) {
        throw Exception('Folder not found');
      }
      
      return folder;
    } catch (e) {
      session.log('Error fetching folder: $e', level: LogLevel.error);
      throw Exception('Failed to fetch folder');
    }
  }
  
  // Create a new folder
  Future<Folder> createFolder(Session session, String name, String? description, int? parentId) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    // Validate input
    if (name.trim().isEmpty) {
      throw Exception('Folder name cannot be empty');
    }
    
    if (name.length > 100) {
      throw Exception('Folder name too long (max 100 characters)');
    }
    
    // Check for duplicate names in same parent
    final existingFolders = await Folder.find(
      session,
      where: (t) => t.userId.equals(userId) & 
                    t.name.equals(name) & 
                    (parentId == null ? t.parentId.isNull : t.parentId.equals(parentId)),
    );
    
    if (existingFolders.isNotEmpty) {
      throw Exception('A folder with this name already exists in the same location');
    }
    
    // Verify parent folder ownership if provided
    if (parentId != null) {
      final parentFolder = await Folder.findById(session, parentId);
      if (parentFolder == null || parentFolder.userId != userId) {
        throw Exception('Parent folder not found');
      }
    }
    
    try {
      final folder = Folder(
        name: name.trim(),
        description: description?.trim(),
        userId: userId,
        parentId: parentId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      return await folder.insert(session);
    } catch (e) {
      session.log('Error creating folder: $e', level: LogLevel.error);
      throw Exception('Failed to create folder');
    }
  }
  
  // Update a folder
  Future<Folder> updateFolder(
    Session session, 
    int folderId, 
    String? name, 
    String? description,
    int? parentId,
  ) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    // Fetch the folder
    final folder = await Folder.findById(session, folderId);
    if (folder == null || folder.userId != userId) {
      throw Exception('Folder not found');
    }
    
    // Update fields if provided
    if (name != null) {
      if (name.trim().isEmpty) {
        throw Exception('Folder name cannot be empty');
      }
      if (name.length > 100) {
        throw Exception('Folder name too long (max 100 characters)');
      }
      
      // Check for duplicate names in same parent
      final existingFolders = await Folder.find(
        session,
        where: (t) => t.userId.equals(userId) & 
                      t.name.equals(name) & 
                      t.id.notEquals(folderId) &
                      (folder.parentId == null ? t.parentId.isNull : t.parentId.equals(folder.parentId)),
      );
      
      if (existingFolders.isNotEmpty) {
        throw Exception('A folder with this name already exists in the same location');
      }
      
      folder.name = name.trim();
    }
    
    if (description != null) {
      folder.description = description.trim().isEmpty ? null : description.trim();
    }
    
    if (parentId != null) {
      // Prevent moving folder into itself or its descendants
      if (parentId == folderId) {
        throw Exception('Cannot move folder into itself');
      }
      
      // Check if the new parent is a descendant of this folder
      if (await _isDescendant(session, parentId, folderId)) {
        throw Exception('Cannot move folder into its own subfolder');
      }
      
      // Verify parent folder ownership
      final parentFolder = await Folder.findById(session, parentId);
      if (parentFolder == null || parentFolder.userId != userId) {
        throw Exception('Parent folder not found');
      }
      
      folder.parentId = parentId;
    }
    
    folder.updatedAt = DateTime.now();
    
    try {
      return await folder.update(session);
    } catch (e) {
      session.log('Error updating folder: $e', level: LogLevel.error);
      throw Exception('Failed to update folder');
    }
  }
  
  // Delete a folder
  Future<bool> deleteFolder(Session session, int folderId, bool deleteContents) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    // Fetch the folder
    final folder = await Folder.findById(session, folderId);
    if (folder == null || folder.userId != userId) {
      throw Exception('Folder not found');
    }
    
    try {
      if (deleteContents) {
        // Delete all contents recursively
        await _deleteFolderContents(session, folderId, userId);
      } else {
        // Check if folder has contents
        final hasSubfolders = await _hasSubfolders(session, folderId);
        final hasFeeds = await _hasFeeds(session, folderId);
        
        if (hasSubfolders || hasFeeds) {
          throw Exception('Folder is not empty. Use deleteContents=true to delete all contents');
        }
      }
      
      // Delete the folder
      await Folder.deleteRow(session, folder);
      return true;
    } catch (e) {
      session.log('Error deleting folder: $e', level: LogLevel.error);
      throw Exception('Failed to delete folder: ${e.toString()}');
    }
  }
  
  // Move feeds to a folder
  Future<bool> moveFeedsToFolder(Session session, int folderId, List<int> feedIds) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    // Verify folder ownership
    final folder = await Folder.findById(session, folderId);
    if (folder == null || folder.userId != userId) {
      throw Exception('Folder not found');
    }
    
    try {
      // Verify and update each feed
      for (final feedId in feedIds) {
        final feedSubscription = await FeedSubscription.find(
          session,
          where: (t) => t.feedId.equals(feedId) & t.userId.equals(userId),
        );
        
        if (feedSubscription.isEmpty) {
          continue; // Skip feeds user doesn't subscribe to
        }
        
        feedSubscription.first.folderId = folderId;
        await feedSubscription.first.update(session);
      }
      
      return true;
    } catch (e) {
      session.log('Error moving feeds to folder: $e', level: LogLevel.error);
      throw Exception('Failed to move feeds');
    }
  }
  
  // Get folder tree structure
  Future<List<FolderTree>> getFolderTree(Session session) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    try {
      // Get all folders for the user
      final folders = await Folder.find(
        session,
        where: (t) => t.userId.equals(userId),
        orderBy: (t) => t.name,
      );
      
      // Build tree structure
      return _buildFolderTree(folders, null);
    } catch (e) {
      session.log('Error building folder tree: $e', level: LogLevel.error);
      throw Exception('Failed to get folder tree');
    }
  }
  
  // Helper method to build folder tree
  List<FolderTree> _buildFolderTree(List<Folder> folders, int? parentId) {
    final tree = <FolderTree>[];
    
    for (final folder in folders.where((f) => f.parentId == parentId)) {
      final children = _buildFolderTree(folders, folder.id);
      
      tree.add(FolderTree(
        folder: folder,
        children: children,
        feedCount: 0, // Will be populated separately if needed
      ));
    }
    
    return tree;
  }
  
  // Check if a folder is a descendant of another
  Future<bool> _isDescendant(Session session, int folderId, int ancestorId) async {
    var currentId = folderId;
    final visited = <int>{};
    
    while (currentId != ancestorId) {
      if (visited.contains(currentId)) {
        break; // Prevent infinite loop
      }
      visited.add(currentId);
      
      final folder = await Folder.findById(session, currentId);
      if (folder == null || folder.parentId == null) {
        return false;
      }
      
      currentId = folder.parentId!;
    }
    
    return currentId == ancestorId;
  }
  
  // Delete folder contents recursively
  Future<void> _deleteFolderContents(Session session, int folderId, int userId) async {
    // Delete all feeds in this folder
    final feedSubscriptions = await FeedSubscription.find(
      session,
      where: (t) => t.folderId.equals(folderId) & t.userId.equals(userId),
    );
    
    for (final subscription in feedSubscriptions) {
      await FeedSubscription.deleteRow(session, subscription);
    }
    
    // Delete all subfolders recursively
    final subfolders = await Folder.find(
      session,
      where: (t) => t.parentId.equals(folderId) & t.userId.equals(userId),
    );
    
    for (final subfolder in subfolders) {
      await _deleteFolderContents(session, subfolder.id!, userId);
      await Folder.deleteRow(session, subfolder);
    }
  }
  
  // Check if folder has subfolders
  Future<bool> _hasSubfolders(Session session, int folderId) async {
    final subfolders = await Folder.find(
      session,
      where: (t) => t.parentId.equals(folderId),
      limit: 1,
    );
    
    return subfolders.isNotEmpty;
  }
  
  // Check if folder has feeds
  Future<bool> _hasFeeds(Session session, int folderId) async {
    final feeds = await FeedSubscription.find(
      session,
      where: (t) => t.folderId.equals(folderId),
      limit: 1,
    );
    
    return feeds.isNotEmpty;
  }
  
  // Get folder statistics
  Future<FolderStats> getFolderStats(Session session, int folderId) async {
    session.requireAuth();
    final userId = session.authenticatedUserId!;
    
    // Verify folder ownership
    final folder = await Folder.findById(session, folderId);
    if (folder == null || folder.userId != userId) {
      throw Exception('Folder not found');
    }
    
    try {
      // Get direct feed count
      final directFeeds = await FeedSubscription.count(
        session,
        where: (t) => t.folderId.equals(folderId) & t.userId.equals(userId),
      );
      
      // Get total feeds including subfolders
      final allFolderIds = await _getAllDescendantFolderIds(session, folderId, userId);
      allFolderIds.add(folderId);
      
      final totalFeeds = await FeedSubscription.count(
        session,
        where: (t) => t.folderId.inSet(allFolderIds) & t.userId.equals(userId),
      );
      
      // Get unread article count
      final unreadCount = await _getUnreadCountForFolders(session, allFolderIds, userId);
      
      return FolderStats(
        folderId: folderId,
        directFeedCount: directFeeds,
        totalFeedCount: totalFeeds,
        unreadArticleCount: unreadCount,
        lastUpdated: folder.updatedAt,
      );
    } catch (e) {
      session.log('Error getting folder stats: $e', level: LogLevel.error);
      throw Exception('Failed to get folder statistics');
    }
  }
  
  // Get all descendant folder IDs
  Future<List<int>> _getAllDescendantFolderIds(Session session, int folderId, int userId) async {
    final descendantIds = <int>[];
    final queue = [folderId];
    
    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      
      final subfolders = await Folder.find(
        session,
        where: (t) => t.parentId.equals(currentId) & t.userId.equals(userId),
      );
      
      for (final subfolder in subfolders) {
        descendantIds.add(subfolder.id!);
        queue.add(subfolder.id!);
      }
    }
    
    return descendantIds;
  }
  
  // Get unread count for folders
  Future<int> _getUnreadCountForFolders(Session session, List<int> folderIds, int userId) async {
    // This would typically join with articles and read status
    // For now, returning a placeholder
    return 0;
  }
}

// Data classes for folder operations
class FolderTree {
  final Folder folder;
  final List<FolderTree> children;
  final int feedCount;
  
  FolderTree({
    required this.folder,
    required this.children,
    required this.feedCount,
  });
  
  Map<String, dynamic> toJson() => {
    'folder': folder.toJson(),
    'children': children.map((c) => c.toJson()).toList(),
    'feedCount': feedCount,
  };
}

class FolderStats {
  final int folderId;
  final int directFeedCount;
  final int totalFeedCount;
  final int unreadArticleCount;
  final DateTime lastUpdated;
  
  FolderStats({
    required this.folderId,
    required this.directFeedCount,
    required this.totalFeedCount,
    required this.unreadArticleCount,
    required this.lastUpdated,
  });
  
  Map<String, dynamic> toJson() => {
    'folderId': folderId,
    'directFeedCount': directFeedCount,
    'totalFeedCount': totalFeedCount,
    'unreadArticleCount': unreadArticleCount,
    'lastUpdated': lastUpdated.toIso8601String(),
  };
}