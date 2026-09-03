import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/feeds_table.dart';

part 'category_dao.g.dart';

/// Data Access Object for categories
@DriftAccessor(tables: [CategoriesTable, FeedsTable])
class CategoryDao extends DatabaseAccessor<AppDatabase> with _$CategoryDaoMixin {
  CategoryDao(AppDatabase db) : super(db);
  
  /// Get all categories
  Future<List<CategoryEntry>> getAllCategories() {
    return (select(categoriesTable)..orderBy([(c) => OrderingTerm(expression: c.sortOrder)])).get();
  }
  
  /// Get root categories (no parent)
  Future<List<CategoryEntry>> getRootCategories() {
    return (select(categoriesTable)
      ..where((c) => c.parentId.isNull())
      ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
      .get();
  }
  
  /// Get subcategories
  Future<List<CategoryEntry>> getSubcategories(String parentId) {
    return (select(categoriesTable)
      ..where((c) => c.parentId.equals(parentId))
      ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
      .get();
  }
  
  /// Get category by ID
  Future<CategoryEntry?> getCategoryById(String id) {
    return (select(categoriesTable)..where((c) => c.id.equals(id))).getSingleOrNull();
  }
  
  /// Get categories with feed count
  Future<List<CategoryWithCount>> getCategoriesWithFeedCount() async {
    // Get all categories
    final categories = await getAllCategories();
    final categoriesWithCount = <CategoryWithCount>[];
    
    for (final category in categories) {
      // Count feeds in this category
      final countQuery = selectOnly(feedsTable)
        ..addColumns([feedsTable.id.count()])
        ..where(feedsTable.categoryId.equals(category.id));
      
      final count = await countQuery.map((row) => row.read(feedsTable.id.count())!).getSingle();
      
      categoriesWithCount.add(CategoryWithCount(
        category: category,
        feedCount: count,
      ));
    }
    
    return categoriesWithCount;
  }
  
  /// Insert category
  Future<void> insertCategory(CategoryEntry category) => into(categoriesTable).insert(category);
  
  /// Update category
  Future<bool> updateCategory(CategoryEntry category) => update(categoriesTable).replace(category);
  
  /// Delete category
  Future<void> deleteCategory(String categoryId) async {
    await transaction(() async {
      // Move feeds to uncategorized
      await (update(feedsTable)..where((f) => f.categoryId.equals(categoryId)))
        .write(const FeedsTableCompanion(
          categoryId: Value('uncategorized'),
        ));
      
      // Move subcategories to root
      await (update(categoriesTable)..where((c) => c.parentId.equals(categoryId)))
        .write(const CategoriesTableCompanion(
          parentId: Value(null),
        ));
      
      // Delete the category
      await (delete(categoriesTable)..where((c) => c.id.equals(categoryId))).go();
    });
  }
  
  /// Reorder categories
  Future<void> reorderCategories(List<String> categoryIds) async {
    await transaction(() async {
      for (int i = 0; i < categoryIds.length; i++) {
        await (update(categoriesTable)..where((c) => c.id.equals(categoryIds[i])))
          .write(CategoriesTableCompanion(
            sortOrder: Value(i),
          ));
      }
    });
  }
  
  /// Get category tree
  Future<List<CategoryNode>> getCategoryTree() async {
    final allCategories = await getAllCategories();
    final categoryMap = {for (var cat in allCategories) cat.id: cat};
    final rootNodes = <CategoryNode>[];
    final nodeMap = <String, CategoryNode>{};
    
    // Create nodes
    for (final category in allCategories) {
      nodeMap[category.id] = CategoryNode(
        category: category,
        children: [],
      );
    }
    
    // Build tree
    for (final category in allCategories) {
      final node = nodeMap[category.id]!;
      
      if (category.parentId == null) {
        rootNodes.add(node);
      } else {
        final parent = nodeMap[category.parentId];
        parent?.children.add(node);
      }
    }
    
    return rootNodes;
  }
}

/// Category with feed count
class CategoryWithCount {
  final CategoryEntry category;
  final int feedCount;
  
  CategoryWithCount({
    required this.category,
    required this.feedCount,
  });
}

/// Category tree node
class CategoryNode {
  final CategoryEntry category;
  final List<CategoryNode> children;
  
  CategoryNode({
    required this.category,
    required this.children,
  });
}