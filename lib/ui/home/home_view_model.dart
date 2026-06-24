import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/remembered_category.dart';
import '../../data/repositories/todo_repository.dart';
import '../../data/services/database/database.dart';
import '../../domain/board_reorder.dart';
import '../../domain/default_category.dart';
import '../../domain/models/category_with_tasks.dart';
import '../../domain/reorder.dart';
import '../core/category_colors.dart';

part 'home_view_model.g.dart';

/// The result of a mutating command. The widget maps [failure] to a localized
/// SnackBar; the raw error never crosses the seam (it is logged here instead).
enum CommandOutcome { success, failure }

/// Streams every category with its tasks and owns the home screen's command
/// coordination: it issues mutations, gates remembered-category persistence on
/// success, resolves drag-board drops against its own live state, and reports
/// every command's [CommandOutcome]. The widget collects input and renders
/// outcomes; all coordination lives here.
@riverpod
class HomeViewModel extends _$HomeViewModel {
  @override
  Stream<List<CategoryWithTasks>> build() =>
      ref.watch(todoRepositoryProvider).watchCategoriesWithTasks();

  TodoRepository get _repo => ref.read(todoRepositoryProvider);
  RememberedCategory get _remembered => ref.read(rememberedCategoryProvider);

  /// Runs [action], returning [CommandOutcome.success] or — on any throw —
  /// logging the error and returning [CommandOutcome.failure]. The error is
  /// never surfaced raw; the widget shows a generic localized message.
  Future<CommandOutcome> _run(Future<void> Function() action) async {
    try {
      await action();
      return CommandOutcome.success;
    } catch (e, st) {
      debugPrint('VM command failed: $e\n$st');
      return CommandOutcome.failure;
    }
  }

  Task? _findTask(List<CategoryWithTasks> cats, int id) {
    for (final cwt in cats) {
      for (final t in cwt.tasks) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  // ---- Categories ----

  Future<CommandOutcome> addCategory(
    String name, {
    int color = kDefaultCategoryColor,
    String? emoji,
  }) => _run(() => _repo.createCategory(name: name, color: color, emoji: emoji));

  Future<CommandOutcome> updateCategory({
    required int id,
    required String name,
    required int color,
    required String? emoji,
  }) => _run(
    () => _repo.updateCategory(id: id, name: name, color: color, emoji: emoji),
  );

  Future<CommandOutcome> toggleCollapsed(int id, bool collapsed) =>
      _run(() => _repo.setCollapsed(id, collapsed));

  /// Toggles category [id], which is currently [collapsed]. Expanding it
  /// (collapsed → expanded) also remembers it as the quick-add default — the
  /// "expanding a category sets the add-task default" rule. Collapsing does not.
  Future<CommandOutcome> toggleActiveCategory(int id, bool collapsed) async {
    final outcome = await _run(() => _repo.setCollapsed(id, !collapsed));
    if (outcome == CommandOutcome.success && collapsed) {
      await _remembered.write(id); // was collapsed → now expanding
    }
    return outcome;
  }

  /// Reorders the category at [oldIndex] to [newIndex] against live state.
  Future<CommandOutcome> reorderCategories(int oldIndex, int newIndex) {
    final cats = state.value;
    if (cats == null) return Future.value(CommandOutcome.success);
    final ids = [for (final c in cats) c.category.id];
    return _run(() => _repo.reorderCategories(reorderedIds(ids, oldIndex, newIndex)));
  }

  /// Deletes [id] and, if it was the remembered quick-add default, forgets it.
  Future<CommandOutcome> deleteCategory(int id) async {
    final outcome = await _run(() => _repo.deleteCategory(id));
    if (outcome == CommandOutcome.success && _remembered.read() == id) {
      await _remembered.forget();
    }
    return outcome;
  }

  // ---- Tasks ----

  /// Adds a task and, on success, remembers its category as the quick-add
  /// default. A failed add never persists the remembered category.
  Future<CommandOutcome> addTask(int categoryId, String name) async {
    final outcome = await _run(
      () => _repo.createTask(categoryId: categoryId, name: name),
    );
    if (outcome == CommandOutcome.success) {
      await _remembered.write(categoryId);
    }
    return outcome;
  }

  /// Renames [id] and moves it to [categoryId] only when that differs from its
  /// current category (avoiding a needless re-sort). Not transactional; a
  /// partial failure self-heals visually via the stream.
  Future<CommandOutcome> editTask(int id, String name, int categoryId) {
    final cats = state.value;
    final current = cats == null ? null : _findTask(cats, id);
    return _run(() async {
      await _repo.renameTask(id, name);
      if (current != null && current.categoryId != categoryId) {
        await _repo.moveTask(id, categoryId);
      }
    });
  }

  Future<CommandOutcome> completeTask(int id) =>
      _run(() => _repo.completeTask(id));
  Future<CommandOutcome> restoreTask(int id) =>
      _run(() => _repo.restoreTask(id));

  /// Resolves a drag-board drop against live state (re-read here, never trusted
  /// from a build-time snapshot) and issues the within/across mutation. A
  /// collapsed destination is auto-expanded after a successful move so the
  /// dropped task is never hidden. A stale/out-of-range drop is a no-op.
  Future<CommandOutcome> dropTask(
    int oldItemIndex,
    int oldListIndex,
    int newItemIndex,
    int newListIndex,
  ) {
    final cats = state.value;
    if (cats == null) return Future.value(CommandOutcome.success);
    final plan = planReorder(
      cats,
      oldItemIndex,
      oldListIndex,
      newItemIndex,
      newListIndex,
    );
    switch (plan) {
      case ReorderNoop():
        return Future.value(CommandOutcome.success);
      case ReorderWithin(:final orderedIds):
        return _run(() => _repo.reorderTasks(orderedIds));
      case ReorderAcross(
        :final movedId,
        :final toCategoryId,
        :final orderedTargetIds,
        :final expandCategoryId,
      ):
        return _run(() async {
          await _repo.moveTaskToCategoryAt(
            movedId,
            toCategoryId,
            orderedTargetIds,
          );
          if (expandCategoryId != null) {
            await _repo.setCollapsed(expandCategoryId, false);
          }
        });
    }
  }

  // ---- Archive ----

  Future<CommandOutcome> purgeExpired() => _run(() => _repo.purgeExpired());
  Future<CommandOutcome> clearArchive() => _run(() => _repo.clearArchive());

  // ---- Reads ----

  /// The category id to preselect for quick-add against live state, or null
  /// when there are no categories.
  int? quickAddDefault() {
    final cats = state.value;
    if (cats == null) return null;
    final ids = [for (final c in cats) c.category.id];
    return defaultCategoryId(_remembered.read(), ids);
  }
}
