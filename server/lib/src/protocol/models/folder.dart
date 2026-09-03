import 'package:serverpod/serverpod.dart';

class Folder extends TableRow {
  int? id;
  String name;
  String? description;
  int userId;
  int? parentId;
  DateTime createdAt;
  DateTime updatedAt;

  Folder({
    this.id,
    required this.name,
    this.description,
    required this.userId,
    this.parentId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  static final t = FolderTable();

  static const db = FolderRepository._();

  @override
  String get tableName => 'folders';

  @override
  void setColumn(String columnName, value) {
    switch (columnName) {
      case 'id':
        id = value;
        return;
      case 'name':
        name = value;
        return;
      case 'description':
        description = value;
        return;
      case 'user_id':
        userId = value;
        return;
      case 'parent_id':
        parentId = value;
        return;
      case 'created_at':
        createdAt = value;
        return;
      case 'updated_at':
        updatedAt = value;
        return;
      default:
        throw UnimplementedError();
    }
  }

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'] as int?,
      name: json['name'] as String,
      description: json['description'] as String?,
      userId: json['userId'] as int,
      parentId: json['parentId'] as int?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      if (description != null) 'description': description,
      'userId': userId,
      if (parentId != null) 'parentId': parentId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'user_id': userId,
      'parent_id': parentId,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class FolderTable extends Table {
  FolderTable() : super(tableName: 'folders');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final name = ColumnString('name', this);
  late final description = ColumnString('description', this);
  late final userId = ColumnInt('user_id', this);
  late final parentId = ColumnInt('parent_id', this);
  late final createdAt = ColumnDateTime('created_at', this, hasDefault: true);
  late final updatedAt = ColumnDateTime('updated_at', this, hasDefault: true);

  @override
  List<Column> get columns => [
    id,
    name,
    description,
    userId,
    parentId,
    createdAt,
    updatedAt,
  ];
}

class FolderInclude extends IncludeObject {
  FolderInclude._({
    UserInclude? user,
    FolderInclude? parent,
    FolderIncludeList? children,
    FeedIncludeList? feeds,
  }) : super(includes: {
    if (user != null) 'user': user,
    if (parent != null) 'parent': parent,
    if (children != null) 'children': children,
    if (feeds != null) 'feeds': feeds,
  });

  static final i = FolderInclude._();

  FolderInclude user() {
    return FolderInclude._(user: UserInclude.i);
  }

  FolderInclude parent() {
    return FolderInclude._(parent: FolderInclude.i);
  }

  FolderInclude children({FolderInclude? include}) {
    return FolderInclude._(children: FolderIncludeList(include));
  }

  FolderInclude feeds({FeedInclude? include}) {
    return FolderInclude._(feeds: FeedIncludeList(include));
  }
}

class FolderIncludeList extends IncludeList {
  FolderIncludeList([FolderInclude? include]) 
    : super(include ?? FolderInclude._());
}

class FolderRepository {
  const FolderRepository._();

  Future<List<Folder>> findByUserId(
    Session session,
    int userId, {
    Transaction? transaction,
  }) async {
    return session.db.find<Folder>(
      where: (t) => t.userId.equals(userId),
      orderBy: (t) => t.name,
      transaction: transaction,
    );
  }

  Future<List<Folder>> findByParentId(
    Session session,
    int userId,
    int? parentId, {
    Transaction? transaction,
  }) async {
    return session.db.find<Folder>(
      where: (t) => t.userId.equals(userId) & 
                   (parentId == null ? t.parentId.equals(null) : t.parentId.equals(parentId)),
      orderBy: (t) => t.name,
      transaction: transaction,
    );
  }

  Future<Folder?> findByName(
    Session session,
    int userId,
    String name,
    int? parentId, {
    Transaction? transaction,
  }) async {
    final folders = await session.db.find<Folder>(
      where: (t) => t.userId.equals(userId) & 
                   t.name.equals(name) & 
                   (parentId == null ? t.parentId.equals(null) : t.parentId.equals(parentId)),
      limit: 1,
      transaction: transaction,
    );
    return folders.isNotEmpty ? folders.first : null;
  }
}