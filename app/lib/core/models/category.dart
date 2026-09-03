import 'package:uuid/uuid.dart';

/// Category model for organizing feeds
class Category {
  final String id;
  final String name;
  final String? parentId;
  final String? color;
  final String? icon;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  Category({
    String? id,
    required this.name,
    this.parentId,
    this.color,
    this.icon,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
  
  /// Check if this is a root category
  bool get isRoot => parentId == null;
  
  /// Get the full path of the category (for nested categories)
  String getFullPath(List<Category> allCategories) {
    if (isRoot) return name;
    
    final parent = allCategories.firstWhere(
      (c) => c.id == parentId,
      orElse: () => Category(name: 'Unknown'),
    );
    
    if (parent.name == 'Unknown') return name;
    
    return '${parent.getFullPath(allCategories)} / $name';
  }
  
  Category copyWith({
    String? id,
    String? name,
    String? parentId,
    String? color,
    String? icon,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parentId': parentId,
      'color': color,
      'icon': icon,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
  
  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      parentId: json['parentId'] as String?,
      color: json['color'] as String?,
      icon: json['icon'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}