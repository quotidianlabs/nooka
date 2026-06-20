import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/todo_repository.dart';
import '../../domain/models/category_with_tasks.dart';
import '../core/category_colors.dart';

part 'home_view_model.g.dart';

/// Streams every category with its tasks and exposes mutation commands.
/// Depends only on [TodoRepository].
@riverpod
class HomeViewModel extends _$HomeViewModel {
  @override
  Stream<List<CategoryWithTasks>> build() =>
      ref.watch(todoRepositoryProvider).watchCategoriesWithTasks();

  TodoRepository get _repo => ref.read(todoRepositoryProvider);

  Future<void> addCategory(
    String name, {
    int color = kDefaultCategoryColor,
    String? emoji,
  }) => _repo.createCategory(name: name, color: color, emoji: emoji);
  Future<void> renameCategory(int id, String name) =>
      _repo.renameCategory(id, name);
  Future<void> setCategoryColor(int id, int color) =>
      _repo.setCategoryColor(id, color);
  Future<void> setCategoryEmoji(int id, String? emoji) =>
      _repo.setCategoryEmoji(id, emoji);
  Future<void> updateCategory({
    required int id,
    required String name,
    required int color,
    required String? emoji,
  }) => _repo.updateCategory(id: id, name: name, color: color, emoji: emoji);
  Future<void> toggleCollapsed(int id, bool collapsed) =>
      _repo.setCollapsed(id, collapsed);
  Future<void> reorderCategories(List<int> orderedIds) =>
      _repo.reorderCategories(orderedIds);
  Future<void> deleteCategory(int id) => _repo.deleteCategory(id);

  Future<void> addTask(int categoryId, String name) =>
      _repo.createTask(categoryId: categoryId, name: name);
  Future<void> renameTask(int id, String name) => _repo.renameTask(id, name);
  Future<void> moveTask(int id, int categoryId) =>
      _repo.moveTask(id, categoryId);
  Future<void> completeTask(int id) => _repo.completeTask(id);
  Future<void> restoreTask(int id) => _repo.restoreTask(id);
  Future<void> reorderTasks(List<int> orderedIds) =>
      _repo.reorderTasks(orderedIds);
  Future<void> moveTaskToCategoryAt(
    int taskId,
    int newCategoryId,
    List<int> orderedTargetIds,
  ) => _repo.moveTaskToCategoryAt(taskId, newCategoryId, orderedTargetIds);
  Future<void> purgeExpired() => _repo.purgeExpired();
  Future<void> clearArchive() => _repo.clearArchive();
}
