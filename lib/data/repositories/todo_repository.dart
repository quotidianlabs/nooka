import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/clock.dart';
import '../../domain/models/category_with_tasks.dart';
import '../services/database/database_providers.dart' show todoDaoProvider;
import '../services/database/todo_dao.dart';

part 'todo_repository.g.dart';

/// The data-layer seam (port) for all to-do data. View models depend on this,
/// never on the DAO directly; it is also the substitution point four test
/// doubles use to inject failures. It sources archive-lifecycle time
/// (`archivedAt`, the purge cutoff) from the injectable [Clock] seam, so those
/// ops are deterministic in tests. `createdAt` is non-injected write-only
/// metadata the DAO stamps directly.
class TodoRepository {
  TodoRepository(this._dao, {this._clock = const SystemClock()});
  final TodoDao _dao;
  final Clock _clock;

  Stream<List<CategoryWithTasks>> watchCategoriesWithTasks() =>
      _dao.watchCategoriesWithTasks();

  Future<int> createCategory({
    required String name,
    required int color,
    String? emoji,
  }) => _dao.createCategory(name: name, color: color, emoji: emoji);
  Future<void> updateCategory({
    required int id,
    required String name,
    required int color,
    required String? emoji,
  }) => _dao.updateCategory(id: id, name: name, color: color, emoji: emoji);
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
  Future<void> renameAndMove(int id, String name, int? newCategoryId) =>
      _dao.renameAndMove(id, name, newCategoryId);
  Future<void> completeTask(int id) => _dao.completeTask(id, _clock.now());
  Future<void> restoreTask(int id) => _dao.restoreTask(id);
  Future<void> reorderTasks(List<int> orderedIds) =>
      _dao.reorderTasks(orderedIds);
  Future<void> moveTaskToCategoryAt(
    int taskId,
    int newCategoryId,
    List<int> orderedTargetIds,
  ) => _dao.moveTaskToCategoryAt(taskId, newCategoryId, orderedTargetIds);
  Future<int> purgeExpired() => _dao.purgeExpired(_clock.now());
  Future<int> clearArchive() => _dao.clearArchive();
}

/// The app's time source. Overridden with a [FixedClock] in tests that need
/// deterministic archive-lifecycle time.
@Riverpod(keepAlive: true)
Clock clock(Ref ref) => const SystemClock();

@Riverpod(keepAlive: true)
TodoRepository todoRepository(Ref ref) =>
    TodoRepository(ref.watch(todoDaoProvider), clock: ref.watch(clockProvider));
