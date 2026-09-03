import 'package:drift/drift.dart';
import '../database/database.dart';

@DataClassName('Folder')
class FoldersTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  TextColumn get description => text().nullable()();
  IntColumn get userId => integer()();
  IntColumn get parentId => integer().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get isShared => boolean().withDefault(const Constant(false))();
  BoolColumn get isPublic => boolean().withDefault(const Constant(false))();
  TextColumn get permissions => text().nullable()(); // JSON
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastModified => dateTime()();
  
  @override
  Set<Column> get primaryKey => {id};
}

class Folder {
  final int id;
  final String name;
  final String? description;
  final int userId;
  final int? parentId;
  final String? color;
  final String? icon;
  final int position;
  final bool isShared;
  final bool isPublic;
  final Map<String, dynamic>? permissions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastModified;
  
  // Navigation
  List<Folder> children = [];
  List<int> feedIds = [];
  
  Folder({
    required this.id,
    required this.name,
    this.description,
    required this.userId,
    this.parentId,
    this.color,
    this.icon,
    required this.position,
    required this.isShared,
    required this.isPublic,
    this.permissions,
    required this.createdAt,
    required this.updatedAt,
    required this.lastModified,
  });
  
  // Helper methods
  bool get isRoot => parentId == null;
  
  bool hasPermission(String permission) {
    if (permissions == null) return false;
    return permissions![permission] == true;
  }
  
  // Create a copy with updated fields
  Folder copyWith({
    int? id,
    String? name,
    String? description,
    int? userId,
    int? parentId,
    String? color,
    String? icon,
    int? position,
    bool? isShared,
    bool? isPublic,
    Map<String, dynamic>? permissions,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastModified,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      userId: userId ?? this.userId,
      parentId: parentId ?? this.parentId,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      position: position ?? this.position,
      isShared: isShared ?? this.isShared,
      isPublic: isPublic ?? this.isPublic,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastModified: lastModified ?? this.lastModified,
    );
  }
  
  // Convert to/from JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'userId': userId,
    'parentId': parentId,
    'color': color,
    'icon': icon,
    'position': position,
    'isShared': isShared,
    'isPublic': isPublic,
    'permissions': permissions,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastModified': lastModified.toIso8601String(),
  };
  
  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    userId: json['userId'],
    parentId: json['parentId'],
    color: json['color'],
    icon: json['icon'],
    position: json['position'] ?? 0,
    isShared: json['isShared'] ?? false,
    isPublic: json['isPublic'] ?? false,
    permissions: json['permissions'],
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
    lastModified: DateTime.parse(json['lastModified']),
  );
}

// Folder-Feed relationship table
@DataClassName('FolderFeed')
class FolderFeedsTable extends Table {
  IntColumn get folderId => integer()();
  IntColumn get feedId => integer()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime()();
  
  @override
  Set<Column> get primaryKey => {folderId, feedId};
}

// Folder member table for shared folders
@DataClassName('FolderMember')
class FolderMembersTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get folderId => integer()();
  IntColumn get userId => integer()();
  TextColumn get role => text()(); // owner, editor, contributor, viewer
  TextColumn get permissions => text().nullable()(); // JSON for custom permissions
  DateTimeColumn get joinedAt => dateTime()();
  DateTimeColumn get lastAccessed => dateTime().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

// Folder activity log
@DataClassName('FolderActivity')
class FolderActivitiesTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get folderId => integer()();
  IntColumn get userId => integer()();
  TextColumn get action => text()(); // created, updated, added_feed, removed_feed, etc.
  TextColumn get details => text().nullable()(); // JSON
  DateTimeColumn get timestamp => dateTime()();
  
  @override
  Set<Column> get primaryKey => {id};
}