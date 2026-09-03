import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import '../core/database/database.dart';
import '../core/models/category.dart';
import 'database_provider.dart';

final categoriesProvider = StateNotifierProvider<CategoryNotifier, List<Category>>((ref) {
  return CategoryNotifier(ref);
});

class CategoryNotifier extends StateNotifier<List<Category>> {
  final Ref ref;

  CategoryNotifier(this.ref) : super([]) {
    _load();
  }

  Future<void> _load() async {
    final database = ref.read(databaseProvider);
    final entries = await database.categoryDao.getAllCategories();
    state = entries.map(_toModel).toList();
  }

  Category _toModel(CategoryEntry entry) {
    return Category(
      id: entry.id,
      name: entry.name,
      parentId: entry.parentId,
      color: entry.color,
      icon: entry.icon,
      sortOrder: entry.sortOrder,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
    );
  }

  Future<void> createCategory(Category category) async {
    final database = ref.read(databaseProvider);
    await database.into(database.categoriesTable).insert(
          CategoriesTableCompanion.insert(
            id: category.id,
            name: category.name,
            parentId: Value(category.parentId),
            color: Value(category.color),
            icon: Value(category.icon),
            sortOrder: Value(category.sortOrder),
          ),
        );
    await _load();
  }

  Future<void> updateCategory(Category category) async {
    final database = ref.read(databaseProvider);
    await (database.update(database.categoriesTable)
          ..where((c) => c.id.equals(category.id)))
        .write(CategoriesTableCompanion(
      name: Value(category.name),
      parentId: Value(category.parentId),
      color: Value(category.color),
      icon: Value(category.icon),
      sortOrder: Value(category.sortOrder),
    ));
    await _load();
  }

  Future<void> deleteCategory(String categoryId) async {
    final database = ref.read(databaseProvider);
    await database.categoryDao.deleteCategory(categoryId);
    await _load();
  }
}
