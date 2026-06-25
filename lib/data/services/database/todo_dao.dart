import 'package:drift/drift.dart';

import '../../../domain/archive.dart';
import '../../../domain/models/backup_data.dart';
import '../../../domain/models/category_with_tasks.dart';
import 'database.dart';
import 'tables.dart';

part 'todo_dao.g.dart';

@DriftAccessor(tables: [Categories, Tasks])
class TodoDao extends DatabaseAccessor<AppDatabase> with _$TodoDaoMixin {
  TodoDao(super.db);

  // ---- Categories ----

  Future<int> createCategory({
    required String name,
    required int color,
    String? emoji,
  }) async {
    final existing = await select(categories).get();
    final nextOrder = existing.isEmpty
        ? 0
        : existing.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    return into(categories).insert(
      CategoriesCompanion.insert(
        name: name,
        color: color,
        emoji: Value(emoji),
        sortOrder: nextOrder,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Writes a category's name, color and emoji in a single update — the edit
  /// dialog's three fields, batched so the stream rebuilds once.
  Future<void> updateCategory({
    required int id,
    required String name,
    required int color,
    required String? emoji,
  }) => (update(categories)..where((c) => c.id.equals(id))).write(
    CategoriesCompanion(
      name: Value(name),
      color: Value(color),
      emoji: Value(emoji),
    ),
  );

  Future<void> setCollapsed(int id, bool collapsed) =>
      (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(collapsed: Value(collapsed)),
      );

  /// Persists a new order by writing each id's index in [orderedIds] as its
  /// sortOrder, in one transaction.
  ///
  /// Callers MUST pass the complete set of category ids. Ids omitted from
  /// [orderedIds] keep their old sortOrder and may then collide with the
  /// renumbered rows; unknown ids are silently ignored.
  Future<void> reorderCategories(List<int> orderedIds) async {
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(categories)..where((c) => c.id.equals(orderedIds[i])))
            .write(CategoriesCompanion(sortOrder: Value(i)));
      }
    });
  }

  Future<void> deleteCategory(int id) =>
      (delete(categories)..where((c) => c.id.equals(id))).go();

  // ---- Tasks ----

  Future<int> _nextTaskOrder(int categoryId) async {
    final active =
        await (select(tasks)..where(
              (t) => t.categoryId.equals(categoryId) & t.archivedAt.isNull(),
            ))
            .get();
    return active.isEmpty
        ? 0
        : active.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<int> createTask({
    required int categoryId,
    required String name,
  }) async {
    return into(tasks).insert(
      TasksCompanion.insert(
        categoryId: categoryId,
        name: name,
        sortOrder: await _nextTaskOrder(categoryId),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> renameTask(int id, String name) => (update(
    tasks,
  )..where((t) => t.id.equals(id))).write(TasksCompanion(name: Value(name)));

  /// Renames [id] and, when [newCategoryId] is non-null, moves it — both in one
  /// transaction, so a failed move rolls back the rename (no partial edit).
  Future<void> renameAndMove(int id, String name, int? newCategoryId) =>
      transaction(() async {
        await renameTask(id, name);
        if (newCategoryId != null) await moveTask(id, newCategoryId);
      });

  Future<void> moveTask(int id, int newCategoryId) async {
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        categoryId: Value(newCategoryId),
        sortOrder: Value(await _nextTaskOrder(newCategoryId)),
      ),
    );
  }

  Future<void> completeTask(int id, DateTime now) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(archivedAt: Value(now)),
      );

  Future<void> restoreTask(int id) async {
    final task = await (select(
      tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (task == null) return;
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        archivedAt: const Value(null),
        sortOrder: Value(await _nextTaskOrder(task.categoryId)),
      ),
    );
  }

  /// Persists a new order by writing each id's index in [orderedIds] as its
  /// sortOrder, in one transaction.
  ///
  /// Callers MUST pass the complete set of active task ids for the category
  /// being reordered. Ids omitted from [orderedIds] keep their old sortOrder
  /// and may then collide with the renumbered rows; unknown ids are silently
  /// ignored.
  Future<void> reorderTasks(List<int> orderedIds) async {
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(tasks)..where((t) => t.id.equals(orderedIds[i]))).write(
          TasksCompanion(sortOrder: Value(i)),
        );
      }
    });
  }

  /// Moves [taskId] into [newCategoryId] and renumbers that category's active
  /// tasks from [orderedTargetIds] (which MUST include [taskId] at its drop
  /// position), in one transaction. The source category is not renumbered:
  /// removing a task leaves a sortOrder gap but preserves relative order.
  Future<void> moveTaskToCategoryAt(
    int taskId,
    int newCategoryId,
    List<int> orderedTargetIds,
  ) async {
    await transaction(() async {
      await (update(tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(categoryId: Value(newCategoryId)),
      );
      for (var i = 0; i < orderedTargetIds.length; i++) {
        await (update(tasks)..where((t) => t.id.equals(orderedTargetIds[i])))
            .write(TasksCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Deletes every archived task whose retention window has elapsed as of [now].
  Future<int> purgeExpired(DateTime now) =>
      (delete(tasks)..where(
            (t) =>
                t.archivedAt.isNotNull() &
                t.archivedAt.isSmallerOrEqualValue(archiveCutoff(now)),
          ))
          .go();

  /// Deletes every archived task regardless of age (manual "Clear archive").
  Future<int> clearArchive() =>
      (delete(tasks)..where((t) => t.archivedAt.isNotNull())).go();

  List<CategoryWithTasks> _group(List<TypedResult> rows) {
    final byId = <int, CategoryWithTasks>{};
    final order = <int>[];
    for (final row in rows) {
      final category = row.readTable(categories);
      if (!byId.containsKey(category.id)) {
        byId[category.id] = CategoryWithTasks(category, <Task>[]);
        order.add(category.id);
      }
      final task = row.readTableOrNull(tasks);
      if (task != null) byId[category.id]!.tasks.add(task);
    }
    return [for (final id in order) byId[id]!];
  }

  /// One-shot read of every category with all its tasks (active + archived),
  /// ordered identically to [watchCategoriesWithTasks]. Used to build a backup.
  Future<List<CategoryWithTasks>> exportSnapshot() {
    final q =
        select(categories).join([
          leftOuterJoin(tasks, tasks.categoryId.equalsExp(categories.id)),
        ])..orderBy([
          OrderingTerm(expression: categories.sortOrder),
          OrderingTerm(expression: categories.id),
          OrderingTerm(expression: tasks.sortOrder),
          OrderingTerm(expression: tasks.id),
        ]);
    return q.get().then(_group);
  }

  /// Replaces the entire database with [data] in one transaction: clears tasks
  /// then categories, then re-inserts each category (capturing its new id) and
  /// its tasks under that id. A mid-import failure rolls back to the prior state.
  Future<void> importReplace(List<BackupCategory> data) async {
    await transaction(() async {
      await delete(tasks).go();
      await delete(categories).go();
      for (final c in data) {
        final categoryId = await into(categories).insert(
          CategoriesCompanion.insert(
            name: c.name,
            color: c.color,
            emoji: Value(c.emoji),
            collapsed: Value(c.collapsed),
            sortOrder: c.sortOrder,
            createdAt: c.createdAt,
          ),
        );
        for (final t in c.tasks) {
          await into(tasks).insert(
            TasksCompanion.insert(
              categoryId: categoryId,
              name: t.name,
              sortOrder: t.sortOrder,
              createdAt: t.createdAt,
              archivedAt: Value(t.archivedAt),
            ),
          );
        }
      }
    });
  }

  /// Reactive stream of every category with its tasks, categories ordered by
  /// sortOrder and tasks by sortOrder. Emits on any change to either table.
  Stream<List<CategoryWithTasks>> watchCategoriesWithTasks() {
    final q =
        select(categories).join([
          leftOuterJoin(tasks, tasks.categoryId.equalsExp(categories.id)),
        ])..orderBy([
          // Group keys by table: the category-level tiebreak (id) must come
          // before any task key. Otherwise a category sortOrder collision is
          // resolved by task contents (rows interleave) instead of by id.
          OrderingTerm(expression: categories.sortOrder),
          OrderingTerm(expression: categories.id),
          OrderingTerm(expression: tasks.sortOrder),
          OrderingTerm(expression: tasks.id),
        ]);
    return q.watch().map(_group);
  }
}
