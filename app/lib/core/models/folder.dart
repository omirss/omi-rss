import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

@DataClassName('FolderEntry')
class FoldersTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  TextColumn get description => text().nullable()();
  TextColumn get parentId => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Folder {
  final String id;
  final String name;
  final String? description;
  final String? parentId;
  final String? color;
  final String? icon;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<Folder> children = [];
  List<String> feedIds = [];

  Folder({
    String? id,
    required this.name,
    this.description,
    this.parentId,
    this.color,
    this.icon,
    this.position = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isRoot => parentId == null;

  Folder copyWith({
    String? id,
    String? name,
    String? description,
    String? parentId,
    String? color,
    String? icon,
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      parentId: parentId ?? this.parentId,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'parentId': parentId,
    'color': color,
    'icon': icon,
    'position': position,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
    id: json['id']?.toString(),
    name: json['name'] as String,
    description: json['description'] as String?,
    parentId: json['parentId']?.toString(),
    color: json['color'] as String?,
    icon: json['icon'] as String?,
    position: (json['position'] as num?)?.toInt() ?? 0,
    createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
    updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
  );
}

@DataClassName('FolderFeedEntry')
class FolderFeedsTable extends Table {
  TextColumn get folderId => text()();
  TextColumn get feedId => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {folderId, feedId};
}
