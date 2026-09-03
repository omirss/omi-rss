import 'package:drift/drift.dart';
import '../database.dart';
import '../../models/folder.dart';

part 'folder_dao.g.dart';

@DriftAccessor(tables: [FoldersTable, FolderFeedsTable])
class FolderDao extends DatabaseAccessor<AppDatabase> with _$FolderDaoMixin {
  FolderDao(AppDatabase db) : super(db);

  Stream<List<Folder>> watchAllFolders() {
    return _orderedFolders()
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  Future<List<Folder>> getAllFolders() async {
    final rows = await _orderedFolders().get();
    return rows.map(_toModel).toList();
  }

  Future<Folder?> getFolderById(String folderId) async {
    final row = await (select(foldersTable)
          ..where((f) => f.id.equals(folderId)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<List<Folder>> getFolderHierarchy() {
    return getAllFolders().then(_buildHierarchy);
  }

  Future<Folder> insertFolder(Folder folder) async {
    await into(foldersTable).insert(
      FoldersTableCompanion.insert(
        id: folder.id,
        name: folder.name,
        description: Value(folder.description),
        parentId: Value(folder.parentId),
        color: Value(folder.color),
        icon: Value(folder.icon),
        position: Value(folder.position),
      ),
      mode: InsertMode.insertOrReplace,
    );
    return folder;
  }

  Future<bool> updateFolder(Folder folder) =>
      update(foldersTable).replace(_toEntry(folder));

  Future<bool> deleteFolder(String folderId) async {
    await (delete(folderFeedsTable)
          ..where((ff) => ff.folderId.equals(folderId)))
        .go();
    final deleted = await (delete(foldersTable)
          ..where((f) => f.id.equals(folderId)))
        .go();
    return deleted > 0;
  }

  Future<void> addFeedToFolder(String folderId, String feedId,
      {int? position}) async {
    final pos = position ?? await _getNextPosition(folderId);
    await into(folderFeedsTable).insert(
      FolderFeedsTableCompanion.insert(
        folderId: folderId,
        feedId: feedId,
        position: Value(pos),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<bool> removeFeedFromFolder(String folderId, String feedId) async {
    final deleted = await (delete(folderFeedsTable)
          ..where((ff) =>
              ff.folderId.equals(folderId) & ff.feedId.equals(feedId)))
        .go();
    return deleted > 0;
  }

  Future<List<String>> getFeedsInFolder(String folderId) async {
    final query = select(folderFeedsTable)
      ..where((ff) => ff.folderId.equals(folderId))
      ..orderBy([(ff) => OrderingTerm.asc(ff.position)]);
    final rows = await query.get();
    return rows.map((row) => row.feedId).toList();
  }

  Future<void> reorderFeedsInFolder(
      String folderId, List<String> feedIds) async {
    await transaction(() async {
      for (int i = 0; i < feedIds.length; i++) {
        await (update(folderFeedsTable)
              ..where((ff) =>
                  ff.folderId.equals(folderId) & ff.feedId.equals(feedIds[i])))
            .write(FolderFeedsTableCompanion(position: Value(i)));
      }
    });
  }

  Future<List<Folder>> getModifiedSince(DateTime? since) async {
    if (since == null) {
      return getAllFolders();
    }
    final rows = await (select(foldersTable)
          ..where((f) => f.updatedAt.isBiggerOrEqualValue(since)))
        .get();
    return rows.map(_toModel).toList();
  }

  SimpleSelectStatement<$FoldersTableTable, FolderEntry> _orderedFolders() {
    final query = select(foldersTable);
    query.orderBy([(f) => OrderingTerm.asc(f.position)]);
    return query;
  }

  Future<int> _getNextPosition(String folderId) async {
    final query = selectOnly(folderFeedsTable)
      ..addColumns([folderFeedsTable.position.max()])
      ..where(folderFeedsTable.folderId.equals(folderId));
    final result = await query.getSingle();
    final maxPosition = result.read(folderFeedsTable.position.max());
    return (maxPosition ?? -1) + 1;
  }

  List<Folder> _buildHierarchy(List<Folder> folders) {
    final folderMap = {for (var folder in folders) folder.id: folder};
    final rootFolders = <Folder>[];

    for (final folder in folders) {
      if (folder.parentId == null) {
        rootFolders.add(folder);
      } else {
        final parent = folderMap[folder.parentId];
        parent?.children.add(folder);
      }
    }

    return rootFolders;
  }

  Folder _toModel(FolderEntry row) {
    return Folder(
      id: row.id,
      name: row.name,
      description: row.description,
      parentId: row.parentId,
      color: row.color,
      icon: row.icon,
      position: row.position,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  FolderEntry _toEntry(Folder folder) {
    return FolderEntry(
      id: folder.id,
      name: folder.name,
      description: folder.description,
      parentId: folder.parentId,
      color: folder.color,
      icon: folder.icon,
      position: folder.position,
      createdAt: folder.createdAt,
      updatedAt: folder.updatedAt,
    );
  }
}
