---
status: draft
date: 2026-06-18
slug: drag-reorder-board
supersedes: null
superseded_by: null
pr: null
outcome: null
---

# Design: Drag-reorder board + expand-sets-default

## Summary

Wire up drag-and-drop on the Active view so users can reorder categories,
reorder tasks within a category, and drag a task into a different category —
a Trello-style board over the existing collapsible category sections. The
reorder/move plumbing already exists in the DAO, repository, and view model
but was never exposed in the UI; this change adds the UI plus one new
cross-category move operation. It also adds a small companion behavior:
expanding a collapsed category makes that category the default selection in
the add-task dialog, persisted across restarts via the same mechanism shipped
in [remember-last-category](../../archive/2026-06-18.06-remember-last-category/change.md).

## Motivation

User feedback after #7: "changing categories order and maybe items order, and
when opening category — saving it to selected in item creation window."

Two concrete gaps:

- **Reorder is plumbed but invisible.** `reorderCategories` / `reorderTasks`
  exist in `todo_dao.dart`, `todo_repository.dart`, and `home_view_model.dart`,
  with a `domain/reorder.dart` helper — but `home_screen.dart` renders a plain
  `ListView` of `CategorySection` `Column`s, so nothing is draggable. The user
  also wants drag to move a task **between** categories (today that only happens
  through task → Edit → change category).
- **Expanding a category does nothing to the add default.** The last-used
  category (persisted in #7) updates only when a task is *added* via the FAB.
  The user expects that opening (expanding) a category also makes it the
  default for the next quick-add.

## Non-goals

- No reordering in the Archive view — archived tasks keep their read-only list.
- No drag for archived tasks; no multi-select drag.
- No new "reorder mode" toggle — drag is always available via long-press.
- Cross-category move via the Edit dialog stays; drag is additive, not a
  replacement.

## Design

### 1. Dependency: `drag_and_drop_lists`

Add `drag_and_drop_lists: ^0.4.2` (env `sdk: >=2.17.0 <4.0.0`,
`flutter: >=3.0.0` — compatible with our `sdk: ^3.12.2`). It provides exactly
the target interaction: reorder outer lists, reorder items, drag items between
lists, and expandable lists (`DragAndDropListExpansion`).

### 2. Active view → board

The Active branch of `HomeScreen._body` is replaced by a `DragAndDropLists`:

- One `DragAndDropList` per category. Its `header` renders the current colored
  header (chevron + emoji + bold category-color name + open-items count + `⋮`
  menu) plus the colored underline. We keep our **existing** collapse mechanism
  rather than the package's `DragAndDropListExpansion`: tapping the header calls
  `toggleCollapsed` as today, and the list's `children` are the task items only
  when `!category.collapsed`. This preserves the current collapse/expand
  behavior and its widget test verbatim.
- A collapsed or empty category still needs to be a valid drop target, so each
  `DragAndDropList` sets `contentsWhenEmpty` to a small drop zone (so you can
  drag a task onto a collapsed/empty category).
- One `DragAndDropItem` per active task, rendering the current row (radio
  leading icon, name, `⋮` menu) wrapped in the existing swipe-right-to-complete
  `Dismissible`.
- **Drag initiation: long-press** (`DragAndDropLists` default), so no layout
  change. Tap-to-complete, swipe-right-to-complete, and tap-header-to-toggle
  all remain.
- **Expansion state** is driven by `category.collapsed`; expanding/collapsing
  calls `toggleCollapsed` as today. Expanding (collapsed → expanded) also sets
  the add-task default — see §5.

Existing widget keys are preserved so current widget tests keep resolving:
`category-header-{id}`, `category-menu-{id}`, `task-{id}`, `task-menu-{id}`.

### 3. Shared header/row builders

To avoid duplicating rendering between the board (Active) and the unchanged
`CategorySection` (Archive), extract the header content and the task-row
content from `CategorySection` into reusable widgets/builders
(e.g. `category_row.dart` / `task_row.dart` under `lib/ui/home/widgets/`):

- `CategoryHeaderContent` — emoji + name + count + `⋮`, given the same inputs.
- `TaskRowContent` — leading icon, title, optional subtitle (archive), `⋮`.

`CategorySection` (Archive) and the board (Active) both compose these, so the
two views stay visually identical and there is a single place to change a row.

### 4. Cross-category move (data layer)

Drag callbacks from `DragAndDropLists` give source list/item and target
list/item indices. The view model maps them:

- **Reorder categories** → existing `reorderCategories(orderedIds)`.
- **Reorder tasks within one category** → existing `reorderTasks(orderedIds)`
  with that category's new active-task ordering.
- **Move a task to another category at a position** → new
  `moveTaskToCategoryAt(taskId, newCategoryId, orderedTargetIds)`:

  ```dart
  // TodoDao
  Future<void> moveTaskToCategoryAt(
    int taskId,
    int newCategoryId,
    List<int> orderedTargetIds, // target category's active task ids in the new
                                // order, including taskId at its drop position
  ) async {
    await transaction(() async {
      await (update(tasks)..where((t) => t.id.equals(taskId)))
          .write(TasksCompanion(categoryId: Value(newCategoryId)));
      for (var i = 0; i < orderedTargetIds.length; i++) {
        await (update(tasks)..where((t) => t.id.equals(orderedTargetIds[i])))
            .write(TasksCompanion(sortOrder: Value(i)));
      }
    });
  }
  ```

  The source category needs no renumber: removing a task leaves a `sortOrder`
  gap, but relative order (and therefore the `ORDER BY sortOrder` stream) is
  unchanged. Mirrored through `TodoRepository` and `HomeViewModel`.

### 5. Expand-sets-default

In `HomeScreen`, when a category is expanded (the toggle transitions
`collapsed: true → false`), set `_lastCategoryId = id` and persist via
`ref.read(settingsRepositoryProvider).writeLastCategoryId(id)` — reusing the
exact key/accessor from #7. Collapsing does not change the default. The FAB
quick-add already seeds from `readLastCategoryId()` and guards with
`ids.contains(_lastCategoryId)`, so a since-deleted category still falls back
to `cats.first`. No change to `SettingsRepository`.

### 6. Domain helper

Add a pure helper next to `reorderedIds` for the cross-list case — insert an id
at an index into a target list — so the index math is unit-tested independently
of Flutter:

```dart
/// Returns [ids] with [item] inserted at [index] (clamped to the list bounds).
List<int> insertedAt(List<int> ids, int item, int index);
```

## Out of scope

- Archive reordering, multi-select drag, and a dedicated reorder mode (see
  Non-goals).

## Testing

- **Domain** (`test/domain/reorder_test.dart`): extend with `insertedAt` cases
  (head, middle, tail, clamp). TDD — failing test first.
- **DAO** (`test/data/todo_dao_test.dart` or equivalent):
  `moveTaskToCategoryAt` round-trip — a task moved from A to B at index k ends
  up in B at position k; B's tasks are `0..n-1`; A's remaining tasks keep their
  relative order; the `watchCategoriesWithTasks` grouping reflects it.
- **Expand-sets-default** (`test/ui/home_screen_test.dart`): expanding a
  collapsed category writes its id via `writeLastCategoryId`, and the next
  quick-add dialog preselects it. Collapsing does not write.
- **Drag gestures are not simulated** in widget tests (gesture simulation for
  `DragAndDropLists` is flaky); the callback-to-DAO mapping is covered at the
  domain/DAO/VM level, and the actual drag is verified manually on device
  (see Risk).
- `just lint` clean; `just test` green.

## Risk

- **Long-press-drag vs. horizontal swipe-to-complete on the same row**
  (likely × medium). Both gestures live on the active task row. Mitigation:
  long-press and horizontal pan are distinguishable, but if they fight on
  device, fall back to an explicit drag handle on rows (layout change, accept
  as last resort). Manual device check is a required verification step.
- **Dropping into a collapsed category** (medium × low). Decide and verify the
  behavior: dropping on a collapsed header appends to that category (and may
  auto-expand). Covered by the manual check; encode the chosen behavior once
  observed.
- **Package staleness** (low × low). `drag_and_drop_lists` last published
  2024-11; SDK constraint still admits our toolchain. If a future Flutter bump
  breaks it, the fallback is the built-in nested approach (was design option C).
- **Widget-test key drift** (low × medium). The board must keep the existing
  keys; the shared-builder refactor is the place that could drop them — the
  existing `home_screen_test.dart` suite guards against this.
- **Menu-alignment test under the board** (medium × low). `DragAndDropLists`
  can indent items relative to list headers, which would break the 0.5px
  `category-menu`/`task-menu` and chevron/radio alignment assertions. Mitigation:
  set the package's list/item padding to zero so header and item share the same
  horizontal structure; if the package forces a fixed indent, update that test's
  expectation to the new (still-consistent) offset.
