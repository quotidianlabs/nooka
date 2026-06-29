---
summary: Added a per-task Delete action for active tasks (menu + undo toast); hard-delete with re-insert on undo, no schema change.
---

# Design: Delete an active task

## Summary

Add a way to permanently delete an individual **active** task, via a new
"Delete" item in the existing per-task bottom-sheet menu. Deletion is immediate
with an **undo toast** (no confirmation dialog), mirroring the complete/restore
UX. Implemented as a hard delete plus a re-insert on undo — no schema change, no
migration, no backup-format impact. Archived/completed tasks and category
deletion are unchanged.

## Motivation

Today an active task can only be *completed*, which soft-deletes it via
`archivedAt` and parks it in the Archive view for 30 days before auto-purge. The
only way to truly remove a task is to delete its entire category (cascade) or
wait out the archive lifecycle after completing it. There is no affordance to
remove a single active task that was added by mistake or is no longer wanted
without marking it "done" — which is semantically wrong and clutters the
Archive. The only explicit "delete" in the app is on categories.

## Non-goals

- Deleting **archived** tasks individually — out of scope; archived tasks keep
  their existing 30-day auto-purge and the "Clear archive" bulk action.
- A swipe-to-delete gesture — swipe-right is already complete; a swipe-left
  delete adds accidental-delete risk and gesture complexity (YAGNI).
- A confirmation dialog for task delete — the undo toast is the chosen recovery
  path; a dialog on every single-task delete is heavier than warranted.
- Any change to category deletion, complete/restore, or the archive lifecycle.

## Design

### 1. UI affordance — extend the existing task menu

`_taskMenu` (`lib/ui/home/home_screen.dart`) is a bottom sheet that today holds
only "Edit task". Add a second `ListTile` **"Delete"** (icon `Icons.delete`,
label reuses `l10n.delete`), exactly mirroring the category menu's Edit/Delete
layout. The menu is only wired on the Active view (`onTaskMenu` is `null` on the
Archive view today), so Delete is naturally active-only with no extra gating.

Choosing "Delete" calls a new widget handler `_deleteTask(Task task)`:

```dart
Future<void> _deleteTask(Task task) async {
  final message = AppLocalizations.of(context).undoDeleteMessage;
  if (await _dispatch(_vm.deleteTask(task.id)) != CommandOutcome.success) {
    return;
  }
  if (!mounted) return;
  _showUndoToast(message, () => _dispatch(_vm.restoreDeletedTask(task)));
}
```

This reuses the existing `_showUndoToast` + `_dispatch` machinery verbatim, so
the toast timing, the `actionFailed` SnackBar on failure, and the reactive
re-render all behave identically to complete/restore. The widget already holds
the full `Task` object, so undo needs no extra lookup.

### 2. Data flow — hard delete + re-insert (no schema change)

The deleted task must **not** appear in the Archive view, so we cannot reuse
`archivedAt`. Instead the row is hard-deleted and re-inserted on undo. The
widget retains the `Task`, so the original row can be reconstructed exactly.

**DAO** (`lib/data/services/database/todo_dao.dart`):

```dart
Future<void> deleteTask(int id) =>
    (delete(tasks)..where((t) => t.id.equals(id))).go();

Future<void> insertTask(Task task) => into(tasks).insert(task);
```

- `deleteTask` removes only the target row. **No `sortOrder` renumber:** the
  ordering key is `(sortOrder, id)`, so the gap left behind is harmless and the
  slot stays open for an undo to drop the task back into its exact position.
- `insertTask` re-inserts the full row. `Task` (Drift's generated row data
  class) is `Insertable<Task>`, so the original `id`, `categoryId`, `name`,
  `sortOrder`, `createdAt`, and `archivedAt` (null) are all preserved — undo
  restores the task identically, in place.

**Repository** (`lib/data/repositories/todo_repository.dart`): thin
pass-throughs `deleteTask(int id)` and `insertTask(Task task)`.

**ViewModel** (`lib/ui/home/home_view_model.dart`):

```dart
Future<CommandOutcome> deleteTask(int id) =>
    _run(() => _repo.deleteTask(id));

Future<CommandOutcome> restoreDeletedTask(Task task) =>
    _run(() => _repo.insertTask(task));
```

Both run through `_run`, so a throw is caught, logged, and returned as
`failure` — the raw error never crosses the seam. Consistent with the existing
rule that **the VM has no undo concept**; undo is pure widget UX layered over
the two inverse intents (exactly like complete/restore).

### 3. i18n

- Menu label: reuse the existing `l10n.delete`.
- New `undoDeleteMessage` ARB key (e.g. EN "Task deleted", RU "Задача удалена"),
  added to both `app_en.arb` and `app_ru.arb`, then regenerate localizations.

## Operations

None. No infra, no external accounts, no DB migration.

## Out of scope

See Non-goals. A future swipe-left-to-delete or individual archived-task delete
can build on these DAO/VM seams if ever wanted.

## Testing

TDD — a failing test precedes each piece.

- **DAO** (`test/data/todo_dao_test.dart`): `deleteTask` removes only the target
  task, does **not** cascade to its category, and leaves sibling tasks'
  `sortOrder` untouched; `insertTask` restores a previously-deleted task with
  the same `id`, `categoryId`, `sortOrder`, and `createdAt`, landing in its
  original ordered position.
- **ViewModel** (`test/ui/home_view_model_test.dart`): `deleteTask` and
  `restoreDeletedTask` return `success` on the happy path and `failure` when the
  repository throws.
- **Widget** (home screen test): the active task menu shows a "Delete" item;
  selecting it removes the row and shows the undo toast; tapping "Undo" restores
  the row in place. Delete is absent on the Archive view.
- `just test` and `just coverage` (gated %) pass; `just lint-ci` clean.

## Risk

- **Undo after the task's category was deleted mid-toast** (low likelihood ×
  low impact): the re-insert violates the `categoryId` FK (cascade) constraint,
  `_run` catches it, returns `failure`, and the widget shows the localized
  `actionFailed` SnackBar; the stream renders the actual truth. Acceptable.
- **Double-delete by id** (e.g. rapid taps): delete-by-id is an idempotent
  no-op `success`.
- **Re-inserting an explicit primary key**: the id was just freed by the delete,
  so there is no collision; `autoIncrement` does not reuse it for new rows.

## Architecture docs to update (same PR)

- `architecture/data-model.md` — individual active-task hard delete; delete
  leaves a `sortOrder` gap (no renumber); re-insert restores exact position.
- `architecture/home-coordination.md` — new `deleteTask` / `restoreDeletedTask`
  intents; widget-layered undo toast, same pattern as complete/restore.
- `architecture/archive.md` — one line: delete is distinct from archive; a
  deleted task never enters the Archive view.