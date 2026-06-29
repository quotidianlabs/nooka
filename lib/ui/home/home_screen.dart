import 'dart:async';

import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/database/database.dart';
import '../../domain/models/category_with_tasks.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  _View _view = _View.active;
  Timer? _toastTimer;

  static const _toastDuration = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Rebuild on resume so the archive "auto-removes in N days" countdown
    // recomputes `now` instead of showing a value stale across midnight.
    if (state == AppLifecycleState.resumed) setState(() {});
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
                if (s.first == _View.archive) _dispatch(_vm.purgeExpired());
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
              onToggleCollapsed: () => _dispatch(
                _vm.toggleCollapsed(cwt.category.id, !cwt.category.collapsed),
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
      // Pass the rendered snapshot's ids so the reorder resolves against what
      // the user dragged, not whatever live state has since become.
      onListReorder: (oldIndex, newIndex) => _dispatch(
        _vm.reorderCategories(cats.categoryIds, oldIndex, newIndex),
      ),
      onItemReorder: (oldItemIndex, oldListIndex, newItemIndex, newListIndex) =>
          _dispatch(
            _vm.dropTask(
              oldItemIndex,
              oldListIndex,
              newItemIndex,
              newListIndex,
            ),
          ),
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
            onToggleCollapsed: () => _dispatch(
              _vm.toggleActiveCategory(cwt.category.id, cwt.category.collapsed),
            ),
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
                      now: now,
                      onTaskTap: (_) => _complete(task),
                      onTaskMenu: (_) => _taskMenu(cats, task),
                    ),
                  ),
                ),
            ],
    );
  }

  /// Awaits a VM command and surfaces a [CommandOutcome.failure] as the
  /// localized `actionFailed` SnackBar — the single place outcomes map to UI.
  /// Returns the outcome so callers can gate follow-up UI (e.g. an undo toast)
  /// on success; fire-and-forget callers may discard it. The VM logs the
  /// underlying error, so it is never surfaced raw here.
  Future<CommandOutcome> _dispatch(Future<CommandOutcome> command) async {
    final outcome = await command;
    if (outcome == CommandOutcome.failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).actionFailed)),
      );
    }
    return outcome;
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
    // Offer undo only when the complete actually succeeded.
    if (await _dispatch(_vm.completeTask(task.id)) != CommandOutcome.success) {
      return;
    }
    if (!mounted) return;
    _showUndoToast(message, () => _dispatch(_vm.restoreTask(task.id)));
  }

  Future<void> _restore(Task task) async {
    final message = AppLocalizations.of(context).undoRestoreMessage;
    if (await _dispatch(_vm.restoreTask(task.id)) != CommandOutcome.success) {
      return;
    }
    if (!mounted) return;
    _showUndoToast(message, () => _dispatch(_vm.completeTask(task.id)));
  }

  Future<void> _deleteTask(Task task) async {
    final message = AppLocalizations.of(context).undoDeleteMessage;
    // Offer undo only when the delete actually succeeded.
    if (await _dispatch(_vm.deleteTask(task.id)) != CommandOutcome.success) {
      return;
    }
    if (!mounted) return;
    _showUndoToast(message, () => _dispatch(_vm.restoreDeletedTask(task)));
  }

  Future<void> _addTask(List<CategoryWithTasks> cats) async {
    if (cats.isEmpty) return;
    // Resolve the default against the exact list the dialog will show, so the
    // preselected id is always one of the dialog's categories. cats is
    // non-empty here, so the rule always returns an id.
    final initial = _vm.quickAddDefault(cats.categoryIds)!;
    await showQuickAddDialog(
      context,
      categories: [for (final c in cats) c.category],
      initialCategoryId: initial,
      // addTask remembers the category on success; nothing to persist here.
      onAdd: (name, categoryId) => _dispatch(_vm.addTask(categoryId, name)),
    );
  }

  Future<void> _clearArchive(List<CategoryWithTasks> cats) async {
    final count = cats.fold<int>(0, (sum, c) => sum + c.archivedTasks.length);
    if (count == 0) return;
    final ok = await confirmClearArchive(context, count: count);
    if (ok) await _dispatch(_vm.clearArchive());
  }

  Future<void> _addCategory() async {
    final result = await showCategoryDialog(context);
    if (result != null) {
      await _dispatch(
        _vm.addCategory(result.name, color: result.color, emoji: result.emoji),
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
          await _dispatch(
            _vm.updateCategory(
              id: cwt.category.id,
              name: r.name,
              color: r.color,
              emoji: r.emoji,
            ),
          );
        }
      case 'add':
        await showQuickAddDialog(
          context,
          categories: [cwt.category],
          initialCategoryId: cwt.category.id,
          onAdd: (name, categoryId) => _dispatch(_vm.addTask(categoryId, name)),
        );
      case 'delete':
        final ok = await confirmDeleteCategory(
          context,
          name: cwt.category.name,
          itemCount: cwt.tasks.length,
        );
        // deleteCategory forgets the remembered default internally if needed.
        if (ok) await _dispatch(_vm.deleteCategory(cwt.category.id));
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
        final r = await showTaskDialog(
          context,
          categories: [for (final c in cats) c.category],
          initialCategoryId: task.categoryId,
          initialName: task.name,
        );
        if (r != null) {
          // Pass the seed category (task.categoryId at dialog open) as `from`,
          // so a concurrent move is not silently undone.
          await _dispatch(
            _vm.editTask(task.id, r.name, task.categoryId, r.categoryId),
          );
        }
      case 'delete':
        await _deleteTask(task);
    }
  }
}
