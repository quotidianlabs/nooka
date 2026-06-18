import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/category_with_tasks.dart';
import '../services/database/database_providers.dart' show todoDaoProvider;
import '../services/database/todo_dao.dart';

part 'todo_repository.g.dart';

/// The data-layer seam for all to-do data. View models depend on this, never on
/// the DAO directly. Commands that need the current time inject it here so the
/// DAO stays deterministic for tests.
class TodoRepository {
  TodoRepository(this._dao);
  final TodoDao _dao;

  Stream<List<CategoryWithTasks>> watchCategoriesWithTasks() =>
      _dao.watchCategoriesWithTasks();

  Future<int> createCategory({
    required String name,
    required int color,
    String? emoji,
  }) => _dao.createCategory(name: name, color: color, emoji: emoji);
  Future<void> renameCategory(int id, String name) =>
      _dao.renameCategory(id, name);
  Future<void> setCategoryColor(int id, int color) =>
      _dao.setCategoryColor(id, color);
  Future<void> setCategoryEmoji(int id, String? emoji) =>
      _dao.setCategoryEmoji(id, emoji);
  Future<void> setCollapsed(int id, bool collapsed) =>
      _dao.setCollapsed(id, collapsed);
  Future<void> reorderCategories(List<int> orderedIds) =>
      _dao.reorderCategories(orderedIds);
  Future<void> deleteCategory(int id) => _dao.deleteCategory(id);

  Future<int> createTask({required int categoryId, required String name}) =>
      _dao.createTask(categoryId: categoryId, name: name);
  Future<void> renameTask(int id, String name) => _dao.renameTask(id, name);
  Future<void> moveTask(int id, int newCategoryId) =>
      _dao.moveTask(id, newCategoryId);
  Future<void> completeTask(int id) => _dao.completeTask(id, DateTime.now());
  Future<void> restoreTask(int id) => _dao.restoreTask(id);
  Future<void> reorderTasks(List<int> orderedIds) =>
      _dao.reorderTasks(orderedIds);
  Future<void> moveTaskToCategoryAt(
    int taskId,
    int newCategoryId,
    List<int> orderedTargetIds,
  ) => _dao.moveTaskToCategoryAt(taskId, newCategoryId, orderedTargetIds);
  Future<int> purgeExpired() => _dao.purgeExpired(DateTime.now());
  Future<int> clearArchive() => _dao.clearArchive();
}

@Riverpod(keepAlive: true)
TodoRepository todoRepository(Ref ref) =>
    TodoRepository(ref.watch(todoDaoProvider));
