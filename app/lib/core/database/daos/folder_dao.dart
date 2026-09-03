import 'package:drift/drift.dart';
import '../database.dart';
import '../../models/folder.dart';

part 'folder_dao.g.dart';

@DriftAccessor(tables: [FoldersTable, FolderFeedsTable, FolderMembersTable, FolderActivitiesTable])
class FolderDao extends DatabaseAccessor<AppDatabase> with _$FolderDaoMixin {
  FolderDao(AppDatabase db) : super(db);

  // Create folder
  Future<int> createFolder(FoldersTableCompanion folder) async {
    return await into(foldersTable).insert(folder);
  }

  // Get all folders for user
  Future<List<Folder>> getUserFolders(int userId) async {
    final query = select(foldersTable)
      ..where((f) => f.userId.equals(userId))
      ..orderBy([(f) => OrderingTerm.asc(f.position)]);
    
    final results = await query.get();
    return results.map((row) => _mapRowToFolder(row)).toList();
  }

  // Get folder by ID
  Future<Folder?> getFolderById(int folderId) async {
    final query = select(foldersTable)
      ..where((f) => f.id.equals(folderId));
    
    final result = await query.getSingleOrNull();
    return result != null ? _mapRowToFolder(result) : null;
  }

  // Get folders with hierarchy
  Future<List<Folder>> getFolderHierarchy(int userId) async {
    final folders = await getUserFolders(userId);
    return _buildHierarchy(folders);
  }

  // Update folder
  Future<bool> updateFolder(int folderId, FoldersTableCompanion folder) async {
    final updated = await (update(foldersTable)
      ..where((f) => f.id.equals(folderId)))
      .write(folder);
    return updated > 0;
  }

  // Delete folder
  Future<bool> deleteFolder(int folderId) async {
    // Delete folder-feed relationships
    await (delete(folderFeedsTable)
      ..where((ff) => ff.folderId.equals(folderId)))
      .go();
    
    // Delete folder members
    await (delete(folderMembersTable)
      ..where((fm) => fm.folderId.equals(folderId)))
      .go();
    
    // Delete folder activities
    await (delete(folderActivitiesTable)
      ..where((fa) => fa.folderId.equals(folderId)))
      .go();
    
    // Delete the folder
    final deleted = await (delete(foldersTable)
      ..where((f) => f.id.equals(folderId)))
      .go();
    
    return deleted > 0;
  }

  // Add feed to folder
  Future<void> addFeedToFolder(int folderId, int feedId, {int? position}) async {
    final pos = position ?? await _getNextPosition(folderId);
    
    await into(folderFeedsTable).insert(
      FolderFeedsTableCompanion(
        folderId: Value(folderId),
        feedId: Value(feedId),
        position: Value(pos),
        addedAt: Value(DateTime.now()),
      ),
      mode: InsertMode.insertOrReplace,
    );
    
    // Update folder's last modified
    await _updateLastModified(folderId);
  }

  // Remove feed from folder
  Future<bool> removeFeedFromFolder(int folderId, int feedId) async {
    final deleted = await (delete(folderFeedsTable)
      ..where((ff) => ff.folderId.equals(folderId) & ff.feedId.equals(feedId)))
      .go();
    
    if (deleted > 0) {
      await _updateLastModified(folderId);
    }
    
    return deleted > 0;
  }

  // Get feeds in folder
  Future<List<int>> getFeedsInFolder(int folderId) async {
    final query = select(folderFeedsTable)
      ..where((ff) => ff.folderId.equals(folderId))
      ..orderBy([(ff) => OrderingTerm.asc(ff.position)]);
    
    final results = await query.get();
    return results.map((row) => row.feedId).toList();
  }

  // Reorder feeds in folder
  Future<void> reorderFeedsInFolder(int folderId, List<int> feedIds) async {
    await transaction(() async {
      for (int i = 0; i < feedIds.length; i++) {
        await (update(folderFeedsTable)
          ..where((ff) => ff.folderId.equals(folderId) & ff.feedId.equals(feedIds[i])))
          .write(FolderFeedsTableCompanion(position: Value(i)));
      }
    });
    
    await _updateLastModified(folderId);
  }

  // Shared folder methods
  Future<void> addMemberToFolder(int folderId, int userId, String role) async {
    await into(folderMembersTable).insert(
      FolderMembersTableCompanion(
        folderId: Value(folderId),
        userId: Value(userId),
        role: Value(role),
        joinedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<bool> removeMemberFromFolder(int folderId, int userId) async {
    final deleted = await (delete(folderMembersTable)
      ..where((fm) => fm.folderId.equals(folderId) & fm.userId.equals(userId)))
      .go();
    return deleted > 0;
  }

  Future<List<FolderMember>> getFolderMembers(int folderId) async {
    final query = select(folderMembersTable)
      ..where((fm) => fm.folderId.equals(folderId));
    return await query.get();
  }

  Future<String?> getUserRoleInFolder(int folderId, int userId) async {
    final query = select(folderMembersTable)
      ..where((fm) => fm.folderId.equals(folderId) & fm.userId.equals(userId));
    
    final result = await query.getSingleOrNull();
    return result?.role;
  }

  // Activity logging
  Future<void> logActivity(int folderId, int userId, String action, {Map<String, dynamic>? details}) async {
    await into(folderActivitiesTable).insert(
      FolderActivitiesTableCompanion(
        folderId: Value(folderId),
        userId: Value(userId),
        action: Value(action),
        details: Value(details?.toString()),
        timestamp: Value(DateTime.now()),
      ),
    );
  }

  Future<List<FolderActivity>> getFolderActivities(int folderId, {int limit = 50}) async {
    final query = select(folderActivitiesTable)
      ..where((fa) => fa.folderId.equals(folderId))
      ..orderBy([(fa) => OrderingTerm.desc(fa.timestamp)])
      ..limit(limit);
    
    return await query.get();
  }

  // Get folders modified since a date (for sync)
  Future<List<Folder>> getModifiedSince(DateTime? since) async {
    if (since == null) {
      return await (select(foldersTable)..orderBy([(f) => OrderingTerm.asc(f.position)])).get()
          .then((rows) => rows.map(_mapRowToFolder).toList());
    }
    
    final query = select(foldersTable)
      ..where((f) => f.lastModified.isBiggerOrEqualValue(since))
      ..orderBy([(f) => OrderingTerm.asc(f.position)]);
    
    final results = await query.get();
    return results.map((row) => _mapRowToFolder(row)).toList();
  }

  // Helper methods
  Future<int> _getNextPosition(int folderId) async {
    final query = selectOnly(folderFeedsTable)
      ..addColumns([folderFeedsTable.position.max()])
      ..where(folderFeedsTable.folderId.equals(folderId));
    
    final result = await query.getSingle();
    final maxPosition = result.read(folderFeedsTable.position.max());
    return (maxPosition ?? -1) + 1;
  }

  Future<void> _updateLastModified(int folderId) async {
    await (update(foldersTable)
      ..where((f) => f.id.equals(folderId)))
      .write(FoldersTableCompanion(
        lastModified: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));
  }

  List<Folder> _buildHierarchy(List<Folder> folders) {
    final folderMap = {for (var folder in folders) folder.id: folder};
    final rootFolders = <Folder>[];
    
    for (final folder in folders) {
      if (folder.parentId == null) {
        rootFolders.add(folder);
      } else {
        final parent = folderMap[folder.parentId];
        if (parent != null) {
          parent.children.add(folder);
        }
      }
    }
    
    return rootFolders;
  }

  Folder _mapRowToFolder(FoldersTableData row) {
    return Folder(
      id: row.id,
      name: row.name,
      description: row.description,
      userId: row.userId,
      parentId: row.parentId,
      color: row.color,
      icon: row.icon,
      position: row.position,
      isShared: row.isShared,
      isPublic: row.isPublic,
      permissions: row.permissions != null 
          ? Map<String, dynamic>.from(row.permissions as Map) 
          : null,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastModified: row.lastModified,
    );
  }
}