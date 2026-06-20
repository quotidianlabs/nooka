---
status: shipped
date: 2026-06-20
slug: hardening-drag-dialogs
spec: hardening-drag-dialogs
summary: Bundle B of the whole-app hardening sweep — harden the drag board and the add/edit dialogs (auto-expand collapsed drop targets, stale-snapshot bounds-checking, double-tap guard, name validation/length cap/overflow, type-derived archived state, post-await mounted check), plus widget-test coverage for the drag-board widgets and the task/confirm-delete dialogs.
supersedes: null
superseded_by: null
pr: null
outcome: "Extracted a pure planReorder() (lib/domain/board_reorder.dart) so _onItemReorder re-reads live state, bounds-checks (H4), and auto-expands a collapsed drop target (H3); guarded quick-add against double-tap + post-dispose focus (H5/L5); disabled confirm on empty name + capped length at 100 + clipped long titles (M3); derived archived from task.archivedAt and dropped the param (L3). Added widget coverage for the drag-board widgets and the task/confirm-delete dialogs. 70/70 tests green. Interactive flutter-run smoke (collapsed-drop, double-tap) left to the user."
---

# Design: hardening — drag board & dialogs (Bundle B)

## Summary

Second fix bundle of the whole-app hardening initiative (audit:
[`2026-06-20-whole-app-hardening.md`](../../audits/2026-06-20-whole-app-hardening.md);
parent spec:
[`hardening-audit-and-tests`](../2026-06-20.01-hardening-audit-and-tests/design.md)).
This bundle fixes the drag-board and dialog findings — **H3, H4, H5, M3, L3,
L5** — and lands the coverage-gap widget tests the parent spec's test pass
targets for the drag-board widgets and the two simpler dialogs.

It is purely a hardening change: no new product surface, no schema change, no
new behavior the user asked for. Every change either closes an audit finding or
adds a regression/coverage test.

## Motivation

The drag board (shipped in `drag-reorder-board`, #9) is the app's most
invariant-heavy surface, and the add/edit dialogs are the only place the user
mutates names. The audit found six issues clustered here:

- **H3** — Dragging a task into a *collapsed* category hides it with no
  feedback. Collapsed lists render `children: const []`
  (`home_screen.dart:204-205`) but still expose a `contentsWhenEmpty` drop slot;
  `_onItemReorder` then computes `insertedAt(to.activeTasks, movedId,
  newItemIndex)` against the full DB list while the rendered list is empty, so
  the task lands at the front and immediately vanishes behind the collapsed
  header.
- **H4** — `_onItemReorder` (`home_screen.dart:237-258`) trusts the
  build-time `cats` snapshot. If the watch stream emits mid-drag,
  `from.activeTasks[oldItemIndex]` / `to.activeTasks` can be out of range
  (RangeError) or reference the wrong task, corrupting `sortOrder` or moving the
  wrong task.
- **H5** — Rapid double-tap on the quick-add **Add** button creates duplicate
  tasks. `_submit` (`task_dialog.dart:150-156`) is async, awaits `onAdd`, and
  clears the field only *after* the await; the button is never disabled
  in-flight, so two fast taps both read the same text and both call `onAdd`.
- **M3** — Whitespace-only and overlong names. Submit handlers `trim()` and
  `return` on empty, but the Add/Save button stays enabled (a tap does nothing
  with no feedback). There is no length cap, and a very long name overflows
  `TaskRowContent`'s title (no `maxLines`/`overflow`).
- **L3** — `TaskRowContent` force-unwraps `task.archivedAt!`
  (`task_row_content.dart:50-51`) gated by a separate `archived` bool, not the
  type. A future caller passing `archived: true` for an active task NPEs.
- **L5** — Quick-add `_submit` calls `_focus.requestFocus()` after the await
  with no `mounted` check; dismissing the dialog mid-await can touch a disposed
  node.

## Dependency on Bundle A

Bundle A (error resilience: H1/H2/L6/L9) executes **first** and adds a
`_guard(Future<void> Function() action)` helper to `_HomeScreenState` that
try/catches a mutation and shows a localized `actionFailed` SnackBar. This
bundle's edited `_onItemReorder` routes its mutation calls — `reorderTasks`,
`moveTaskToCategoryAt`, and the new auto-expand `toggleCollapsed` — through
`_guard(() => _vm.xxx(...))`. The H3/H4 task assumes `_guard` already exists; if
Bundle A has not landed on the branch base, that task must rebase onto it (or
the steps inline a minimal `_guard` matching Bundle A's signature).

## Non-goals

- No new product features.
- No schema/migration change — nothing here touches Drift tables.
- No fix for the other audit bundles: H1/H2/L6/L9 are Bundle A; M1/M2/M4/L1/L4
  are Bundle C; L2/L7/L8 are deferred.
- No new unit tests for the thin `todo_repository` / `home_view_model`
  pass-throughs — they delegate and are exercised through DAO and widget tests.
- The `category_dialog` already has good coverage
  (`category_dialog_test.dart`); its M3 button-enable + length-cap fix is in
  scope, but no separate full dialog test suite is added for it beyond a
  validation test.

## Design

### H4 + H3 — `_onItemReorder`: stale-snapshot guard, then collapsed auto-expand

These touch the same method, so they sequence: H4 first (make the method
robust), then H3 (fix the collapsed-drop hole).

**H4.** Stop trusting the captured `cats`. Inside `_onItemReorder`, re-read the
current value: `final cats = ref.read(homeViewModelProvider).value;`. If it is
`null` (loading/error) the drag is stale → no-op. Bounds-check every index used:
`oldListIndex`/`newListIndex` against `cats.length`, `oldItemIndex` against
`from.activeTasks.length`, `newItemIndex` against `to.activeTasks.length` (the
insert index is allowed to equal `length`, i.e. append). Any out-of-range index
means the rendered list and the snapshot disagreed → no-op rather than throw or
corrupt order. The `cats` parameter is dropped from the signature (the closure
in `_board` already passes it, so that call updates too — or `_board` stops
passing it).

**H3.** A collapsed destination renders no items, so a cross-category drop
computes `newItemIndex == 0` against the full hidden list and the task lands at
the front but stays hidden. After a successful cross-category move, auto-expand
the destination if it was collapsed: `if (to.category.collapsed)
_guard(() => _vm.toggleCollapsed(to.category.id, false));`. The user then sees
the moved task land where it was dropped.

Both mutations (`reorderTasks`, `moveTaskToCategoryAt`, and the auto-expand
`toggleCollapsed`) route through Bundle A's `_guard` so a failing write surfaces
a SnackBar instead of an unhandled async error (closes the H1 fire-and-forget
gap for these call sites too).

### H5 + L5 — quick-add `_submit`: double-tap guard and post-await mounted check

Rework `_QuickAddDialogState._submit` so a re-entrant call is impossible and the
field is cleared *before* the await (so a second tap reads empty text and
no-ops):

```dart
bool _busy = false;

Future<void> _submit() async {
  if (_busy) return;
  final name = _name.text.trim();
  if (name.isEmpty) return;
  _busy = true;
  _name.clear(); // clear synchronously, before the await
  try {
    await widget.onAdd(name, _categoryId);
  } finally {
    _busy = false;
  }
  if (!mounted) return; // L5: dialog may have been dismissed mid-await
  _focus.requestFocus();
}
```

The Add button is additionally disabled while `_busy` (and while the name is
empty, per M3) so the in-flight window is also visually closed.

### M3 — name validation, length cap, and title overflow

Three sub-fixes across the two dialogs and the task row:

1. **Button enable/disable** — drive each confirm button's `onPressed` from a
   controller listener: `null` (disabled) when `_name.text.trim().isEmpty`, the
   submit callback otherwise. Applies to `_TaskDialog` (`task-confirm`),
   `_QuickAddDialog` (`quick-add-confirm`, also gated by `_busy`), and
   `_CategoryDialog` (`category-confirm`). Requires a `setState`-driven listener
   on the name controller in each dialog's `initState`/field init.
2. **Length cap** — add `LengthLimitingTextInputFormatter(kMaxNameLength)` to
   the name `TextField`s. Pick a sane cap of **100** characters, defined once as
   a shared `const kMaxNameLength = 100;` (co-located with the dialogs, e.g. top
   of `task_dialog.dart`, reused by `category_dialog.dart`).
3. **Title overflow** — give `TaskRowContent`'s title
   `maxLines: 2, overflow: TextOverflow.ellipsis` so a long (but now capped)
   name can't blow out the row. (The header already has
   `maxLines: 1, overflow: ellipsis`.)

### L3 — derive `archived` from the type in `TaskRowContent`

Remove the `archived` constructor parameter from `TaskRowContent` and derive it
internally: `final archived = task.archivedAt != null;`. The `archivedAt!`
unwraps in the subtitle are then provably safe (they only run when
`archivedAt != null`). Update both call sites:

- `home_screen.dart` active board row (`_dragList`, ~line 226) — drop
  `archived: false`.
- `category_section.dart` (~line 76) — drop `archived: archived` (the
  `CategorySection.archived` field stays for its empty-state text and the
  Dismissible-vs-plain branch, but no longer feeds the row).

The archived view path in `home_screen.dart` passes its rows through
`CategorySection(archived: true, ...)`, which after this change no longer
forwards `archived` to the row — the row infers it. No behavior change because
archived tasks have non-null `archivedAt` and active ones have null.

## Testing

TDD throughout: a failing `flutter test` first, minimal implementation, green,
commit. New/changed coverage:

- **H4/H3** (`home_screen_test.dart`): drive the view model to set up two
  categories with the destination collapsed, then assert that after the
  reorder/move path the destination is auto-expanded and the task is present and
  positioned. Because raw `drag_and_drop_lists` gestures are brittle to
  simulate, prefer asserting on resulting state (DB / rendered rows) after
  invoking the reorder logic over simulating the drag itself. A no-op test for
  the stale-snapshot guard exercises out-of-range indices.
- **H5** (`task_dialog_test.dart`, new): a slow `onAdd` (a `Completer` the test
  controls) plus two rapid taps on `quick-add-confirm` asserts `onAdd` fires
  exactly once and the field is empty before the await resolves.
- **L5** (`task_dialog_test.dart`): dismiss the quick-add dialog mid-await; the
  test passes if no "setState/requestFocus after dispose" error is thrown.
- **M3** (`task_dialog_test.dart` + `category_dialog_test.dart`): confirm button
  is disabled for empty/whitespace-only names and enabled once non-empty;
  entering more than `kMaxNameLength` characters is clamped.
- **L3** (`task_row_content_test.dart`, new — coverage gap): an active task
  (`archivedAt == null`) renders the radio icon and no subtitle; an archived
  task (`archivedAt != null`) renders the check_circle and the
  completed-on/auto-removes-in subtitle — driven purely by the model, with no
  `archived` param.

Coverage-gap widget tests (no fix, pure coverage, from the parent spec's test
pass):

- **`category_section`** (`category_section_test.dart`, new) — renders header +
  rows for active and archived; tapping the header fires
  `onToggleCollapsed`; tapping a row fires `onTaskTap`.
- **`task_row_content`** (`task_row_content_test.dart`) — covered by the L3
  test above plus a tap-callback assertion.
- **`category_header_content`** (`category_header_content_test.dart`, new) —
  renders the name + count + optional emoji; tapping fires `onToggleCollapsed`;
  tapping the ⋮ fires `onHeaderMenu`.
- **`task_dialog`** (`task_dialog_test.dart`) — validation enable/disable;
  confirm returns the `TaskDialogResult`, cancel returns `null`.
- **`confirm_delete_dialog`** (`confirm_delete_dialog_test.dart`, new) —
  `confirmDeleteCategory` and `confirmClearArchive` return `true` on confirm,
  `false` on cancel/dismiss.

Done means `just test` green and `just lint` clean.

## Risk

- **Drag-gesture widget tests are brittle** (med × low). `drag_and_drop_lists`
  gesture simulation is unreliable in the test harness. Mitigation: drive the
  view model / reorder logic directly and assert on resulting `sortOrder` /
  rendered state, exactly as the parent spec's Risk note prescribes. Don't
  simulate raw long-press-drag in these tests.
- **Removing the `archived` param touches two call sites** (low × low). Both are
  in this repo and updated in the same task; the compiler flags any miss.
- **Button-enable listeners add `setState` churn** (low × low). Scoped to dialog
  state; the listener only calls `setState` when emptiness flips, so rebuild
  cost is negligible.
