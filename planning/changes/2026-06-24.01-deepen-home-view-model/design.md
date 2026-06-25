---
summary: Move home-screen command coordination out of the widget into a deep HomeViewModel behind a small intent + CommandOutcome interface; split remembered-category into a pure rule + persistence module.
---

# Design: Deepen HomeViewModel — coordination behind one interface

## Summary

`HomeViewModel` is a 1:1 pass-through to `TodoRepository`; the real
view-model behaviour — success-gated persistence, drag-drop dispatch, undo
coordination, remembered-category — lives in `_HomeScreenState`
(`home_screen.dart`, 511 lines) and is only reachable through full-widget
`testWidgets`. This change moves that coordination into the VM behind a small
**intent + `CommandOutcome`** interface, splits remembered-category into a pure
rule plus a thin persistence module, and makes the VM the primary test surface.
The widget shrinks to collect input → call an intent → map the outcome to UI.

## Motivation

The whole-app hardening audit (`planning/audits/2026-06-20-whole-app-hardening.md`)
fixed M2, M4, H3, and H4 — every one of them a bug in *call-site coordination*
inside `_HomeScreenState`, not in any tested function:

- **M4** — `last_category` persisted before `addTask` resolved.
- **M2** — stale `last_category` not cleared on category delete.
- **H3/H4** — drop into a collapsed category / stale build-time snapshot.

Today `HomeViewModel` (`home_view_model.dart`, 52 lines) passes the deletion
test: delete it and the State would call `TodoRepository` directly, losing
nothing — it is shallow. There is no `home_view_model_test.dart` because there
is nothing in the VM to test. The coordination that *should* be the VM's job
has leaked into the widget, so it can only be exercised by pumping a
`MaterialApp`. Deepening the VM gives that logic locality and a real test
surface.

There is also a latent inconsistency to fix in passing: `_complete` calls
`completeTask` **unguarded** (a failure becomes a zone-logged async error) while
the undo `restoreTask` *is* guarded — so a failed complete shows nothing.

## Non-goals

- No new transactional DAO method for `editTask` — it coordinates the two
  existing repo calls (`renameTask`, then `moveTask`-if-changed); a partial
  failure self-heals visually via the stream. (Deferred: make edit atomic.)
- No `Clock` seam (Candidate 4) — out of scope here.
- No change to `TodoRepository`'s shape (Candidate 3) — out of scope here.
- No `CONTEXT.md` — this project's truth-home is `architecture/` prose; new
  concepts are documented there.

## Design

### 1. The seam

VM owns **command coordination**; the widget owns everything `BuildContext`-bound
(dialogs, bottom-sheets, `SnackBar`, the undo toast + its backstop `Timer`,
`HapticFeedback`, `Navigator`, rendering). The widget collects input (which
task, which drop indices, which dialog result), calls one VM intent, and reacts
to the returned outcome by drawing UI.

### 2. Outcome channel

```dart
enum CommandOutcome { success, failure }
```

Each mutating intent returns `Future<CommandOutcome>`. The VM gains a private
helper (today's `_guard`, moved down) that runs the action, and on throw logs
via `debugPrint` and returns `failure`:

```dart
Future<CommandOutcome> _run(Future<void> Function() action) async {
  try {
    await action();
    return CommandOutcome.success;
  } catch (e, st) {
    debugPrint('VM command failed: $e\n$st');
    return CommandOutcome.failure;
  }
}
```

The widget has **one** mapping: `failure → actionFailed` SnackBar. The raw
exception never crosses the seam (preserves the L6 rule — never show `'$e'`).
A bare enum is deliberate: nothing downstream reads the error, and a payload
would tempt a future caller to render it. Promoting to a sealed type later is a
localized change behind the same interface. The `dropTask` stale/noop case maps
to `success` (nothing failed; the widget does nothing).

### 3. State shape + remembered-category

VM `state` stays `AsyncValue<List<CategoryWithTasks>>` — the category stream,
unchanged. Remembered-category splits into three pieces:

- **Pure rule** in `domain/` — zero-fake unit test:

  ```dart
  /// The category id to preselect for quick-add: the stored id if it still
  /// exists among [categoryIds], else the first, else null when empty.
  /// (Takes ids, not Category rows — fake-free to test; refined during grilling.)
  int? defaultCategoryId(int? stored, List<int> categoryIds) { ... }
  ```

- **`RememberedCategory`** — a thin persistence module
  (`@Riverpod(keepAlive: true)` over `settingsRepositoryProvider`) owning
  read / write / forget of the stored id.

- **VM** coordinates them. It exposes `int? quickAddDefault()` — reads its own
  `state.value`, reads the stored id, returns `defaultCategoryId(stored, cats)`.

The widget drops its `SettingsRepository` import and its `_lastCategoryId`
field; `initState`'s seed disappears. Remember/forget happen *inside* the
intents (below). 100% behind the VM seam.

### 4. Coordinating intents (VM reads its own live state)

The drag callbacks shrink to forwarding raw indices; the VM re-reads
`state.value` at call time (strictly better than today's widget-side re-read):

- `dropTask(oldItem, oldList, newItem, newList)` → reads `state.value`, runs the
  pure `planReorder`, switches the `ReorderPlan`, issues `reorderTasks` /
  `moveTaskToCategoryAt` + the auto-expand (H3); returns `CommandOutcome`. The
  `ReorderPlan` switch (within/across/noop) leaves the widget entirely.
- `reorderCategories(oldIndex, newIndex)` → reads `state.value`, builds the id
  list, calls the pure `reorderedIds`, dispatches.
- `addTask(categoryId, name)` → on success, remembers the category internally.
- `deleteCategory(id)` → forgets the remembered category if it was the deleted
  one.
- `editTask(id, name, categoryId)` → `renameTask`, then `moveTask` if the
  category changed; one outcome (failure if either throws).
- `completeTask(id)` / `restoreTask(id)` → plain inverse intents returning
  outcomes. **No undo concept in the VM.**

`planReorder` and `reorderedIds` stay the pure `domain/` functions they already
are; the VM just calls them.

### 5. Undo (widget-side)

Undo is pure widget UX over the plain inverse intents:

```dart
final outcome = await vm.completeTask(task.id);
if (outcome == CommandOutcome.failure) { showActionFailed(); return; }
if (!mounted) return;
showUndoToast(undoCompleteMessage, () async {
  if (await vm.restoreTask(task.id) == CommandOutcome.failure) showActionFailed();
});
```

The toast UI, backstop `Timer`, and l10n message stay in the widget. Routing
complete through the outcome path **fixes the unguarded-complete
inconsistency** — a failed complete now surfaces `actionFailed` and skips
offering undo.

### 6. Menu/dialog flows

Each handler shrinks to: show UI → get result → call one intent → map outcome.
The widget keeps the bottom-sheet/dialog choreography; the coordinating intents
in §4 absorb the cross-step logic. The quick-add `_busy`/clear/refocus (H5/L5)
stay in `_QuickAddDialog` — unaffected.

## Out of scope

- Atomic (transactional) `editTask` in the DAO — deferred.
- `Clock` seam (Candidate 4) and `TodoRepository` reshape (Candidate 3).

## Testing

TDD order: VM tests red → move coordination into the VM (green) → thin the
widget tests last.

- **New `test/ui/home_view_model_test.dart`** (primary surface) — `ProviderContainer`
  with an in-memory DAO (`NativeDatabase.memory`) + mock prefs. Covers:
  `addTask` remembers on success / **failed `addTask` does not remember (M4)**;
  `deleteCategory` forgets (**M2**); `dropTask` within / across / noop-on-stale /
  collapsed-auto-expand (**H3/H4**); complete→archive; restore re-append;
  `editTask` rename + move; failure outcomes via relocated `_Throwing*Repo`
  doubles.
- **New `test/domain/default_category_test.dart`** — the pure rule, no fakes.
- **Thin `test/ui/home_screen_test.dart`** to genuinely widget-level cases:
  failure outcome → `actionFailed` SnackBar (outcome→UI mapping), undo toast
  floating + auto-dismiss, quick-add stays open, Russian plural rendering,
  header/menu alignment, collapse/expand rendering, stream-error message. The
  *logic* assertions migrate down to the VM test — not duplicated.
- `just lint-ci` clean on an already-committed tree; `just test` green.

## Risk

- **Regression while migrating tests** (med likelihood × med impact). Mitigation:
  TDD — write the VM test asserting the moved behaviour *before* moving it; keep
  the widget test green at each step; rely on the existing hardening regression
  guards until their assertions land at the VM level.
- **Riverpod notifier lifetime assumptions** (low × med). The VM reads
  `state.value` inside intents; if called before the first stream emission,
  `state.value` is null. Mitigation: intents that need the snapshot no-op to
  `success` on null (matching today's `if (cats == null) return`).
- **Architecture-doc drift** (low × low). Mitigation: promotion rides in the
  same PR (new `home-coordination.md`, rewritten `error-handling.md`, README
  index) per the project's hard rule.
