# Delete an Active Task — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user permanently delete an individual active task from the per-task menu, with an undo toast — no schema change.

**Architecture:** Hard-delete the row in the DAO and re-insert the captured `Task` on undo (the widget already holds it). Thread two new pass-throughs (`deleteTask`, `insertTask`) up through repository → view model as `CommandOutcome` intents, and wire a "Delete" item into the existing `_taskMenu` bottom sheet that reuses the existing `_showUndoToast` machinery — exactly the complete/restore pattern. No Drift schema change, no migration, no build_runner.

**Tech Stack:** Flutter, Drift (SQLite), Riverpod, Flutter gen-l10n (ARB), `flutter_test`.

## Global Constraints

- **Scope:** active tasks only. Do not touch archived-task lifecycle, category deletion, or complete/restore.
- **No schema change:** no new column, no `schemaVersion` bump, no migration. Tasks table stays as-is.
- **i18n:** every user-facing string comes from an ARB key in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_ru.arb`; regenerate with `flutter gen-l10n`. The menu label reuses the existing `delete` key.
- **The VM never owns undo:** undo is layered in the widget over two inverse intents (`deleteTask` / `restoreDeletedTask`), matching the existing complete/restore design.
- **Coverage is gated at 100%** (`just coverage`): every new line needs a test. Cover the widget's delete success path, undo path, AND failure (early-return) path.
- **Pre-commit gate is `just lint-ci`** (not `just lint`): it runs `dart format --set-exit-if-changed`, `flutter analyze`, and `planning/index.py --check`. Verify a clean, already-committed tree last.
- **Generated `*.g.dart` is committed.** Adding plain methods to `TodoDao` / `HomeViewModel` does NOT require build_runner (no `@riverpod`/table/Drift-query annotation changes). Only the ARB change regenerates code (gen-l10n).

---

### Task 1: DAO — `deleteTask` and `insertTask`

**Files:**
- Modify: `lib/data/services/database/todo_dao.dart` (add two methods in the `// ---- Tasks ----` section, e.g. just after `restoreTask`, around line 139)
- Test: `test/data/todo_dao_test.dart` (add tests inside the existing `group('task lifecycle', ...)`)

**Interfaces:**
- Produces:
  - `Future<void> deleteTask(int id)` — hard-deletes the task row with that id. No `sortOrder` renumber.
  - `Future<void> insertTask(Task task)` — re-inserts a full `Task` row (preserves `id`, `categoryId`, `name`, `sortOrder`, `createdAt`, `archivedAt`). `Task` is Drift's generated row data class (from `database.dart`), and it is `Insertable<Task>`.

- [ ] **Step 1: Write the failing tests**

Add to `test/data/todo_dao_test.dart` inside `group('task lifecycle', () { ... })`:

```dart
    test('deleteTask removes only that task, no cascade to category', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final keep = await db.todoDao.createTask(categoryId: cat, name: 'keep');
      final gone = await db.todoDao.createTask(categoryId: cat, name: 'gone');

      await db.todoDao.deleteTask(gone);

      final rows = await db.select(db.tasks).get();
      expect(rows.map((t) => t.id), [keep]);
      // Category itself is untouched.
      final cats = await db.select(db.categories).get();
      expect(cats.map((c) => c.id), [cat]);
    });

    test('deleteTask leaves siblings sortOrder untouched (gap, no renumber)',
        () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t1 = await db.todoDao.createTask(categoryId: cat, name: 't1'); // 0
      final t2 = await db.todoDao.createTask(categoryId: cat, name: 't2'); // 1
      final t3 = await db.todoDao.createTask(categoryId: cat, name: 't3'); // 2

      await db.todoDao.deleteTask(t2);

      Future<int> orderOf(int id) async => (await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle()).sortOrder;
      expect(await orderOf(t1), 0);
      expect(await orderOf(t3), 2); // gap at 1, not renumbered
    });

    test('insertTask restores a deleted task in its original position',
        () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t1 = await db.todoDao.createTask(categoryId: cat, name: 't1');
      final t2 = await db.todoDao.createTask(categoryId: cat, name: 't2');
      final t3 = await db.todoDao.createTask(categoryId: cat, name: 't3');

      // Capture the full row (as the widget does), delete it, then re-insert.
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(t2))).getSingle();
      await db.todoDao.deleteTask(t2);
      await db.todoDao.insertTask(row);

      final restored = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(t2))).getSingle();
      expect(restored.id, t2); // same id preserved
      expect(restored.sortOrder, row.sortOrder); // same slot
      expect(restored.archivedAt, isNull);
      // Active order is back to t1, t2, t3.
      final active = (await db.todoDao.watchCategoriesWithTasks().first)
          .first
          .activeTasks
          .map((t) => t.id)
          .toList();
      expect(active, [t1, t2, t3]);
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/todo_dao_test.dart`
Expected: FAIL — `deleteTask`/`insertTask` are not defined on `TodoDao`.

- [ ] **Step 3: Implement the two methods**

In `lib/data/services/database/todo_dao.dart`, add after `restoreTask` (after line 139):

```dart
  /// Hard-deletes the active task [id]. No sortOrder renumber: the ordering key
  /// is (sortOrder, id), so the gap left behind is harmless and keeps the slot
  /// open for an undo re-insert. Idempotent: deleting an absent id is a no-op.
  Future<void> deleteTask(int id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  /// Re-inserts a previously-deleted [task], preserving its id, category,
  /// sortOrder, createdAt and archivedAt — the inverse of [deleteTask] used by
  /// the widget's undo toast. `Task` is Insertable, so the explicit id (just
  /// freed by the delete) and the original position are restored exactly.
  Future<void> insertTask(Task task) => into(tasks).insert(task);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/todo_dao_test.dart`
Expected: PASS (all three new tests + existing).

- [ ] **Step 5: Commit**

```bash
git add lib/data/services/database/todo_dao.dart test/data/todo_dao_test.dart
git commit -m "feat(dao): deleteTask + insertTask for active-task delete/undo"
```

---

### Task 2: Repository + ViewModel intents

**Files:**
- Modify: `lib/data/repositories/todo_repository.dart` (add two pass-throughs in the tasks section, near `restoreTask`, line 54)
- Modify: `lib/ui/home/home_view_model.dart` (add two intents in the `// ---- Tasks ----` section, near `restoreTask`, line 145)
- Test: `test/ui/home_view_model_test.dart` (add a `group('delete / restore-deleted', ...)`; add one failure test)

**Interfaces:**
- Consumes: `TodoDao.deleteTask(int id)`, `TodoDao.insertTask(Task task)` (Task 1).
- Produces:
  - `TodoRepository.deleteTask(int id) → Future<void>`, `TodoRepository.insertTask(Task task) → Future<void>`.
  - `HomeViewModel.deleteTask(int id) → Future<CommandOutcome>`.
  - `HomeViewModel.restoreDeletedTask(Task task) → Future<CommandOutcome>`.

- [ ] **Step 1: Write the failing tests**

Add to `test/ui/home_view_model_test.dart`. First, a throwing repo near the other test doubles at the top (after `_ThrowingMutationRepo`, line 27):

```dart
/// deleteTask always throws; the watch stream stays real so the board loads.
class _ThrowingDeleteTaskRepo extends TodoRepository {
  _ThrowingDeleteTaskRepo(super.dao);
  @override
  Future<void> deleteTask(int id) => Future.error(Exception('db locked'));
}
```

Then add a new group (e.g. after the `complete / restore` group, line 270):

```dart
  group('delete / restore-deleted', () {
    test('deleteTask removes the task from the board', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
      final (_, vm) = await build();

      final outcome = await vm.deleteTask(t);

      expect(outcome, CommandOutcome.success);
      expect((await snapshot()).first.activeTasks, isEmpty);
      expect((await snapshot()).first.archivedTasks, isEmpty); // not archived
    });

    test('restoreDeletedTask re-inserts a deleted task in place', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
      final (_, vm) = await build();
      // Capture the row, delete it (as the widget would), then restore.
      final row = (await snapshot()).first.activeTasks.single;
      await vm.deleteTask(t);

      final outcome = await vm.restoreDeletedTask(row);

      expect(outcome, CommandOutcome.success);
      final active = (await snapshot()).first.activeTasks;
      expect(active.map((x) => x.id), [t]);
      expect(active.single.name, 'Sweep');
    });

    test('a throwing deleteTask returns CommandOutcome.failure', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
      final (_, vm) = await build(repo: _ThrowingDeleteTaskRepo(db.todoDao));

      expect(await vm.deleteTask(1), CommandOutcome.failure);
      // Nothing was deleted: the task is still active.
      expect((await snapshot()).first.activeTasks.single.name, 'Sweep');
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/home_view_model_test.dart`
Expected: FAIL — `deleteTask`/`restoreDeletedTask` not defined on `HomeViewModel` (and `TodoRepository`).

- [ ] **Step 3: Implement the repository pass-throughs**

In `lib/data/repositories/todo_repository.dart`, add after `restoreTask` (line 54). Note `Task` is already in scope via `database.dart` re-export; if the analyzer flags it, add `import '../services/database/database.dart';` at the top.

```dart
  Future<void> deleteTask(int id) => _dao.deleteTask(id);
  Future<void> insertTask(Task task) => _dao.insertTask(task);
```

- [ ] **Step 4: Implement the ViewModel intents**

In `lib/ui/home/home_view_model.dart`, add after `restoreTask` (line 145). Add `import '../../data/services/database/database.dart';` at the top if `Task` is not already resolvable.

```dart
  /// Permanently deletes active task [id]. Undo is layered in the widget via
  /// [restoreDeletedTask]; the VM holds no undo state (mirrors complete/restore).
  Future<CommandOutcome> deleteTask(int id) =>
      _run(() => _repo.deleteTask(id));

  /// Re-inserts a just-deleted [task] (the inverse of [deleteTask]), restoring
  /// its id and position. The widget passes the Task it captured before delete.
  Future<CommandOutcome> restoreDeletedTask(Task task) =>
      _run(() => _repo.insertTask(task));
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/ui/home_view_model_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/todo_repository.dart lib/ui/home/home_view_model.dart test/ui/home_view_model_test.dart
git commit -m "feat(vm): deleteTask + restoreDeletedTask intents"
```

---

### Task 3: i18n — `undoDeleteMessage`

**Files:**
- Modify: `lib/l10n/app_en.arb` (add key near `undoCompleteMessage`, line 49)
- Modify: `lib/l10n/app_ru.arb` (add key near `undoCompleteMessage`, line 31)
- Generated (committed): `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_ru.dart` (produced by gen-l10n)

**Interfaces:**
- Produces: `AppLocalizations.undoDeleteMessage` (String getter). The "Delete" menu label reuses the existing `AppLocalizations.delete`.

- [ ] **Step 1: Add the English key**

In `lib/l10n/app_en.arb`, add after the `undoRestoreMessage` line (line 50):

```json
  "undoDeleteMessage": "Item deleted",
```

- [ ] **Step 2: Add the Russian key**

In `lib/l10n/app_ru.arb`, add after the `undoRestoreMessage` line (line 32):

```json
  "undoDeleteMessage": "Дело удалено",
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: regenerates `lib/l10n/app_localizations*.dart` with a new `undoDeleteMessage` getter, no errors.

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/l10n`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/
git commit -m "i18n: add undoDeleteMessage (en, ru)"
```

---

### Task 4: Widget — "Delete" in the task menu + undo toast

**Files:**
- Modify: `lib/ui/home/home_screen.dart` — add a "Delete" `ListTile` to `_taskMenu` (lines 400-431) and a `_deleteTask(Task)` handler (place near `_complete`, after line 303)
- Test: `test/ui/home_screen_test.dart` (add two `testWidgets`; add a throwing repo double if not present)

**Interfaces:**
- Consumes: `HomeViewModel.deleteTask(int id)`, `HomeViewModel.restoreDeletedTask(Task task)` (Task 2); `AppLocalizations.undoDeleteMessage`, `AppLocalizations.delete` (Task 3); existing `_dispatch`, `_showUndoToast`.

- [ ] **Step 1: Write the failing widget tests**

In `test/ui/home_screen_test.dart`, ensure a throwing-delete repo double exists near the other doubles at the top of the file (mirror the existing `_ThrowingMutationRepo`):

```dart
class _ThrowingDeleteTaskRepo extends TodoRepository {
  _ThrowingDeleteTaskRepo(super.dao);
  @override
  Future<void> deleteTask(int id) => Future.error(Exception('db locked'));
}
```

Then add two tests (e.g. after the `task menu: edit renames the task` test, line 574):

```dart
  testWidgets('task menu: delete removes the row and undo restores it', (
    tester,
  ) async {
    final cat = await db.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await tester.pumpWidget(_app(db, prefs));
    await tester.pumpAndSettle();

    // Open the per-task menu and choose Delete.
    await tester.tap(find.byKey(const Key('task-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump(); // flush the deleteTask await
    await tester.pump(const Duration(milliseconds: 300)); // snackbar entrance

    expect(find.text('Sweep'), findsNothing); // row gone
    expect(find.text('Item deleted'), findsOneWidget); // undo toast

    // Undo brings it back in place.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);
  });

  testWidgets('task menu: a failing delete surfaces actionFailed, keeps the row',
      (tester) async {
    final cat = await db.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await tester.pumpWidget(
      _appWithRepo(_ThrowingDeleteTaskRepo(db.todoDao), prefs),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Couldn't complete that. Try again."), findsOneWidget);
    expect(find.text('Sweep'), findsOneWidget); // row remains
    expect(find.text('Item deleted'), findsNothing); // no undo toast
  });
```

Note: `_appWithRepo` already exists in this test file (used by the throwing-mutation test). Confirm the actionFailed text matches `app_en.arb`'s `actionFailed` value; if it differs, copy it verbatim from the ARB.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/home_screen_test.dart`
Expected: FAIL — there is no "Delete" item in the task menu, so `find.text('Delete')` finds nothing.

- [ ] **Step 3: Add the `_deleteTask` handler**

In `lib/ui/home/home_screen.dart`, add after `_restore` (after line 303):

```dart
  Future<void> _deleteTask(Task task) async {
    final message = AppLocalizations.of(context).undoDeleteMessage;
    // Offer undo only when the delete actually succeeded.
    if (await _dispatch(_vm.deleteTask(task.id)) != CommandOutcome.success) {
      return;
    }
    if (!mounted) return;
    _showUndoToast(message, () => _dispatch(_vm.restoreDeletedTask(task)));
  }
```

- [ ] **Step 4: Add the "Delete" item and route it**

In `lib/ui/home/home_screen.dart`, replace the `_taskMenu` body (lines 400-431) so the sheet has Edit + Delete and a switch routes both, mirroring `_categoryMenu`:

```dart
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/ui/home_screen_test.dart`
Expected: PASS (both new tests + existing, including `task menu: edit renames the task`).

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/home/home_screen.dart test/ui/home_screen_test.dart
git commit -m "feat(ui): delete an active task from its menu, with undo toast"
```

---

### Task 5: Promote to architecture docs + finalize the bundle

**Files:**
- Modify: `architecture/data-model.md`
- Modify: `architecture/home-coordination.md`
- Modify: `architecture/archive.md`
- Modify: `planning/changes/2026-06-29.01-delete-task/design.md` (finalize `summary:` to the realized result)

- [ ] **Step 1: Update `architecture/data-model.md`**

In the Tasks paragraph (around line 12), add a sentence: an individual active task can be hard-deleted (`deleteTask`); the delete leaves a `sortOrder` gap (no renumber), and undo re-inserts the captured row (`insertTask`) so it returns to its exact id and position.

- [ ] **Step 2: Update `architecture/home-coordination.md`**

In the intents list (around line 28, near `completeTask` / `restoreTask`), add: `deleteTask(id)` / `restoreDeletedTask(task)` — plain inverse intents; the undo toast is pure widget UX layered over them (the VM has no undo concept), identical to complete/restore. The widget captures the `Task` before delete so undo can re-insert it.

- [ ] **Step 3: Update `architecture/archive.md`**

Add one line distinguishing delete from archive: deleting an active task removes it outright — it never enters the Archive view (unlike completing, which sets `archivedAt`).

- [ ] **Step 4: Finalize the bundle summary**

In `planning/changes/2026-06-29.01-delete-task/design.md`, set the `summary:` frontmatter to the realized result, e.g.:
`summary: Added a per-task Delete action for active tasks (menu + undo toast); hard-delete with re-insert on undo, no schema change.`

- [ ] **Step 5: Validate planning + full gate**

Run: `just check-planning`
Expected: `planning: OK`

Run: `just lint-ci`
Expected: clean (format unchanged, analyze clean, planning OK).

Run: `just coverage`
Expected: coverage check passes at 100.

- [ ] **Step 6: Commit**

```bash
git add architecture/ planning/changes/2026-06-29.01-delete-task/design.md
git commit -m "docs(architecture): promote active-task delete behavior"
```

---

## Done criteria

- A user can delete an active task from its ⋮ menu; an "Item deleted" toast offers Undo for 4s; Undo restores the task in place.
- Deleting a task does not archive it (never appears in the Archive view) and does not cascade to its category.
- A failed delete shows `actionFailed` and leaves the task untouched.
- `flutter test` green; `just coverage` at 100; `just lint-ci` clean; `just check-planning` OK.
- `architecture/data-model.md`, `home-coordination.md`, and `archive.md` describe the new behavior; the bundle `summary:` states the shipped result.
