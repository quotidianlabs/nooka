# Home coordination

`HomeViewModel` (`ui/home/home_view_model.dart`) is the deep module behind the
home screen: it streams every category with its tasks **and** owns all command
coordination. The widget (`_HomeScreenState`) collects input (drop indices,
dialog results, taps), calls one VM intent, and renders the result. Everything
that needs a `BuildContext` — dialogs, bottom-sheets, SnackBars, the undo toast,
haptics, navigation — stays in the widget; everything else lives in the VM.

## Commands and outcomes

Every mutating intent returns a `CommandOutcome` (`success` | `failure`). The VM
runs each through a private `_run` helper that catches any throw, logs it
(`debugPrint`), and returns `failure` — the raw error never crosses the seam.
The widget has a single `_dispatch` that awaits a command and, on `failure`,
shows the localized `actionFailed` SnackBar (see [error handling](error-handling.md)).

The intents:

- `addCategory` / `updateCategory` / `deleteCategory` / `toggleCollapsed`.
- `addTask` — remembers its category as the quick-add default **on success**.
- `editTask(id, name, fromCategoryId, toCategoryId)` — renames, and moves only
  when `fromCategoryId != toCategoryId`. The move decision uses the dialog's
  seed (`fromCategoryId`, captured when the dialog opened), not live state, so a
  concurrent move is not silently undone. Atomic via the DAO's `renameAndMove`
  (one transaction), so a failed move never leaves a half-applied edit.
- `completeTask` / `restoreTask` — plain inverse intents. The undo toast is pure
  widget UX layered over them; the VM has no undo concept. Routing complete
  through the outcome path means a failed complete surfaces `actionFailed` and
  simply skips offering undo.
- `deleteTask(id)` / `restoreDeletedTask(task)` — plain inverse intents,
  identical pattern to complete/restore. The undo toast is pure widget UX; the
  VM has no undo concept. The widget captures the full `Task` before the delete
  so undo can re-insert it without a lookup.
- `dropTask(4 indices)` and `reorderCategories(oldIndex, newIndex)` — drag-board
  drops (below).
- `toggleActiveCategory(id, collapsed)` — the active-board header toggle;
  expanding also remembers the category (below).
- `purgeExpired` / `clearArchive`.

## Drag-board drops resolve against live state

`dropTask` re-reads the VM's own `state.value` at call time — never a
build-time snapshot the watch stream may have invalidated mid-drag (H4). It runs
the pure `planReorder` (`domain/board_reorder.dart`) and issues the within/across
mutation; an out-of-range or stale drop collapses to a no-op `success`. A drop
into a collapsed destination auto-expands it after the move succeeds, so the
moved task is never hidden (H3). `reorderCategories` instead takes the
*dragged* category-id snapshot from the widget and runs the pure `reorderedIds`
(`domain/reorder.dart`) on it: the indices and the list it reorders always agree,
where resolving against live state could reorder the wrong category after a
mid-drag emission. Both pure functions live in `domain/`; the VM only calls them.

## Remembered category (quick-add default)

The category last used when adding a to-do is remembered so the quick-add FAB
defaults to it across restarts. Three pieces:

- **Pure rule** `defaultCategoryId(stored, categoryIds)` (`domain/default_category.dart`):
  the stored id if it still exists, else the first category, else null.
- **Persistence** `RememberedCategory` (`data/repositories/remembered_category.dart`),
  a thin module over `SettingsRepository` (read / write / forget).
- **Coordination** in the VM: `addTask` and `toggleActiveCategory` (on expand)
  remember; `deleteCategory` forgets when the deleted category was the
  remembered one. The widget reads the default only through `quickAddDefault()`
  — it never touches `SettingsRepository` for this.
