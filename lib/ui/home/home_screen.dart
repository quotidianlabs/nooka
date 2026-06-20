import 'dart:async';

import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../data/services/database/database.dart';
import '../../domain/board_reorder.dart';
import '../../domain/models/category_with_tasks.dart';
import '../../domain/reorder.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_screen.dart';
import '../widgets/category_dialog.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/task_dialog.dart';
import 'home_view_model.dart';
import 'widgets/category_header_content.dart';
import 'widgets/category_section.dart';
import 'widgets/task_row_content.dart';

enum _View { active, archive }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _View _view = _View.active;
  int? _lastCategoryId; // remembered default for quick add
  Timer? _toastTimer;

  static const _toastDuration = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    // Seed the quick-add default from the persisted last-used category so it
    // survives app restarts.
    _lastCategoryId = ref.read(settingsRepositoryProvider).readLastCategoryId();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  HomeViewModel get _vm => ref.read(homeViewModelProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(homeViewModelProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          if (_view == _View.archive)
            IconButton(
              key: const Key('clear-archive-button'),
              icon: const Icon(Icons.delete_sweep),
              onPressed: () => _clearArchive(state.value ?? const []),
            ),
          IconButton(
            key: const Key('add-category-button'),
            icon: const Icon(Icons.create_new_folder),
            onPressed: _addCategory,
          ),
          IconButton(
            key: const Key('settings-button'),
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<_View>(
              segments: [
                ButtonSegment(value: _View.active, label: Text(l10n.activeTab)),
                ButtonSegment(
                  value: _View.archive,
                  label: Text(l10n.archiveTab),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) {
                setState(() => _view = s.first);
                if (s.first == _View.archive) _guard(() => _vm.purgeExpired());
              },
            ),
          ),
        ),
      ),
      floatingActionButton: _view == _View.active
          ? FloatingActionButton(
              key: const Key('add-task-fab'),
              onPressed: () => _addTask(state.value ?? const []),
              child: const Icon(Icons.add),
            )
          : null,
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(AppLocalizations.of(context).errorLoading)),
        data: (cats) => _body(cats, now),
      ),
    );
  }

  Widget _body(List<CategoryWithTasks> cats, DateTime now) {
    final l10n = AppLocalizations.of(context);
    if (cats.isEmpty) {
      return Center(child: Text(l10n.emptyNoCategories));
    }
    final archived = _view == _View.archive;
    final visible = archived
        ? [
            for (final cwt in cats)
              if (cwt.archivedTasks.isNotEmpty) cwt,
          ]
        : cats;
    if (archived && visible.isEmpty) {
      return Center(child: Text(l10n.emptyArchive));
    }
    if (archived) {
      return ListView(
        children: [
          for (final cwt in visible)
            CategorySection(
              category: cwt.category,
              tasks: cwt.archivedTasks,
              archived: true,
              now: now,
              onToggleCollapsed: () => _guard(
                () => _vm.toggleCollapsed(
                  cwt.category.id,
                  !cwt.category.collapsed,
                ),
              ),
              onHeaderMenu: () => _categoryMenu(cwt),
              onTaskTap: _restore,
              onTaskMenu: null,
            ),
          const SizedBox(height: 80),
        ],
      );
    }
    return _board(visible, now);
  }

  Widget _board(List<CategoryWithTasks> cats, DateTime now) {
    return DragAndDropLists(
      listPadding: EdgeInsets.zero,
      itemDragOnLongPress: true,
      listDragOnLongPress: true,
      onListReorder: (oldIndex, newIndex) {
        final ids = [for (final c in cats) c.category.id];
        _guard(
          () => _vm.reorderCategories(reorderedIds(ids, oldIndex, newIndex)),
        );
      },
      onItemReorder: (oldItemIndex, oldListIndex, newItemIndex, newListIndex) {
        _onItemReorder(oldItemIndex, oldListIndex, newItemIndex, newListIndex);
      },
      children: [for (final cwt in cats) _dragList(cwt, cats, now)],
    );
  }

  DragAndDropList _dragList(
    CategoryWithTasks cwt,
    List<CategoryWithTasks> cats,
    DateTime now,
  ) {
    final color = Color(cwt.category.color);
    return DragAndDropList(
      canDrag: true,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CategoryHeaderContent(
            category: cwt.category,
            taskCount: cwt.activeTasks.length,
            onToggleCollapsed: () => _onExpandToggle(cwt.category),
            onHeaderMenu: () => _categoryMenu(cwt),
          ),
          Container(
            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 2),
            height: 2,
            color: color.withValues(alpha: 0.25),
          ),
        ],
      ),
      contentsWhenEmpty: const SizedBox(height: 12),
      children: cwt.category.collapsed
          ? const []
          : [
              for (final task in cwt.activeTasks)
                DragAndDropItem(
                  child: Dismissible(
                    key: ValueKey('dismiss-${task.id}'),
                    direction: DismissDirection.startToEnd,
                    background: Container(
                      color: color,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 24),
                      child: const Icon(Icons.check, color: Colors.white),
                    ),
                    confirmDismiss: (_) async {
                      HapticFeedback.mediumImpact();
                      _complete(task);
                      return false;
                    },
                    child: TaskRowContent(
                      task: task,
                      color: color,
                      archived: false,
                      now: now,
                      onTaskTap: (_) => _complete(task),
                      onTaskMenu: (_) => _taskMenu(cats, task),
                    ),
                  ),
                ),
            ],
    );
  }

  void _onItemReorder(
    int oldItemIndex,
    int oldListIndex,
    int newItemIndex,
    int newListIndex,
  ) {
    // H4: never trust the build-time snapshot — the watch stream may have
    // emitted mid-drag. Re-read live state and let planReorder validate it.
    final cats = ref.read(homeViewModelProvider).value;
    if (cats == null) return;
    final plan = planReorder(
      cats,
      oldItemIndex,
      oldListIndex,
      newItemIndex,
      newListIndex,
    );
    switch (plan) {
      case ReorderNoop():
        return;
      case ReorderWithin(:final orderedIds):
        _guard(() => _vm.reorderTasks(orderedIds));
      case ReorderAcross(
        :final movedId,
        :final toCategoryId,
        :final orderedTargetIds,
        :final expandCategoryId,
      ):
        _guard(
          () =>
              _vm.moveTaskToCategoryAt(movedId, toCategoryId, orderedTargetIds),
        );
        // H3: a collapsed destination renders no items, so the dropped task
        // would be hidden. Auto-expand it.
        if (expandCategoryId != null) {
          _guard(() => _vm.toggleCollapsed(expandCategoryId, false));
        }
    }
  }

  void _onExpandToggle(Category category) {
    final expanding = category.collapsed; // currently collapsed -> expanding
    _guard(() => _vm.toggleCollapsed(category.id, !category.collapsed));
    if (expanding) {
      _lastCategoryId = category.id;
      ref.read(settingsRepositoryProvider).writeLastCategoryId(category.id);
    }
  }

  /// Runs an imperative mutation, surfacing any failure as a localized
  /// SnackBar instead of an unhandled async error. Bundles B and C route their
  /// edited/new mutations through this same guard.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).actionFailed)),
      );
    }
  }

  // ---- commands + toasts ----

  /// Shows a floating undo toast that reliably auto-dismisses. The built-in
  /// SnackBar timer only arms after the entrance animation completes, so on
  /// devices with animations disabled it never fires and the toast lingers
  /// forever. We add a backstop timer that closes it regardless of animation.
  void _showUndoToast(String message, VoidCallback onUndo) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    _toastTimer?.cancel();
    final controller = messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: _toastDuration,
        content: Text(message),
        action: SnackBarAction(label: l10n.undoAction, onPressed: onUndo),
      ),
    );
    var closed = false;
    controller.closed.then((_) => closed = true);
    _toastTimer = Timer(_toastDuration + const Duration(milliseconds: 300), () {
      if (!closed) controller.close();
    });
  }

  Future<void> _complete(Task task) async {
    final message = AppLocalizations.of(context).undoCompleteMessage;
    await _vm.completeTask(task.id);
    if (!mounted) return;
    _showUndoToast(message, () => _guard(() => _vm.restoreTask(task.id)));
  }

  Future<void> _restore(Task task) async {
    final message = AppLocalizations.of(context).undoRestoreMessage;
    await _vm.restoreTask(task.id);
    if (!mounted) return;
    _showUndoToast(message, () => _guard(() => _vm.completeTask(task.id)));
  }

  Future<void> _addTask(List<CategoryWithTasks> cats) async {
    if (cats.isEmpty) return;
    final ids = {for (final c in cats) c.category.id};
    final initial = (_lastCategoryId != null && ids.contains(_lastCategoryId))
        ? _lastCategoryId!
        : cats.first.category.id;
    await showQuickAddDialog(
      context,
      categories: [for (final c in cats) c.category],
      initialCategoryId: initial,
      onAdd: (name, categoryId) async {
        _lastCategoryId = categoryId;
        await ref
            .read(settingsRepositoryProvider)
            .writeLastCategoryId(categoryId);
        await _vm.addTask(categoryId, name);
      },
    );
  }

  Future<void> _clearArchive(List<CategoryWithTasks> cats) async {
    final count = cats.fold<int>(0, (sum, c) => sum + c.archivedTasks.length);
    if (count == 0) return;
    final ok = await confirmClearArchive(context, count: count);
    if (ok) await _vm.clearArchive();
  }

  Future<void> _addCategory() async {
    final result = await showCategoryDialog(context);
    if (result != null) {
      await _vm.addCategory(
        result.name,
        color: result.color,
        emoji: result.emoji,
      );
    }
  }

  Future<void> _categoryMenu(CategoryWithTasks cwt) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l10n.editCategory),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.addTask),
              onTap: () => Navigator.pop(context, 'add'),
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(l10n.delete),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        final r = await showCategoryDialog(
          context,
          initialName: cwt.category.name,
          initialColor: cwt.category.color,
          initialEmoji: cwt.category.emoji,
        );
        if (r != null) {
          await _vm.renameCategory(cwt.category.id, r.name);
          await _vm.setCategoryColor(cwt.category.id, r.color);
          await _vm.setCategoryEmoji(cwt.category.id, r.emoji);
        }
      case 'add':
        await showQuickAddDialog(
          context,
          categories: [cwt.category],
          initialCategoryId: cwt.category.id,
          onAdd: (name, categoryId) => _vm.addTask(categoryId, name),
        );
      case 'delete':
        final ok = await confirmDeleteCategory(
          context,
          name: cwt.category.name,
          itemCount: cwt.tasks.length,
        );
        if (ok) await _vm.deleteCategory(cwt.category.id);
    }
  }

  Future<void> _taskMenu(List<CategoryWithTasks> cats, Task task) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l10n.editTask),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice != 'edit') return;
    final r = await showTaskDialog(
      context,
      categories: [for (final c in cats) c.category],
      initialCategoryId: task.categoryId,
      initialName: task.name,
    );
    if (r != null) {
      await _vm.renameTask(task.id, r.name);
      if (r.categoryId != task.categoryId) {
        await _vm.moveTask(task.id, r.categoryId);
      }
    }
  }
}
