# drag-reorder-board — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose drag-and-drop on the Active view — reorder categories,
reorder tasks, drag tasks across categories — and make expanding a category set
it as the add-task default.

**Architecture:** Active view is rebuilt as a `DragAndDropLists` board (one
`DragAndDropList` per category, one `DragAndDropItem` per task). Drag callbacks
map to existing `reorderCategories`/`reorderTasks` plus a new
`moveTaskToCategoryAt` DAO op for cross-category drops. Header/row rendering is
extracted into shared widgets so the Archive view (unchanged) and the board
look identical. Collapse stays our own (tap header → `toggleCollapsed`).

**Tech Stack:** Flutter, Riverpod, Drift, `drag_and_drop_lists` ^0.4.2.

**Spec:** [`design.md`](./design.md)

**Branch:** `feat/drag-reorder-board` (already created).

**Commit strategy:** Per-task commits.

## Global Constraints

- Dart SDK `^3.12.2`; `drag_and_drop_lists` env is `sdk: >=2.17.0 <4.0.0`,
  `flutter: >=3.0.0` — compatible.
- Generated `*.g.dart` is committed; run
  `dart run build_runner build --delete-conflicting-outputs` after touching
  `@riverpod`/Drift code.
- `just lint` (`dart format` + `flutter analyze`) clean and `just test`
  (`flutter test`) green before any task is considered done.
- Preserve existing widget keys: `category-header-{id}`, `category-menu-{id}`,
  `task-{id}`, `task-menu-{id}`, `dismiss-{id}`.
- Drag is **long-press** initiated; Archive view gets **no** drag.

---

### Task 1: Add the `drag_and_drop_lists` dependency

**Files:**
- Modify: `pubspec.yaml`

Add the package and confirm it resolves on this toolchain before any UI work
depends on it.

- [ ] **Step 1: Add the dependency**

  In `pubspec.yaml`, under `dependencies:` (alphabetical, after
  `cupertino_icons`), add:

  ```yaml
  drag_and_drop_lists: ^0.4.2
  ```

- [ ] **Step 2: Resolve and verify**

  Run: `flutter pub get`
  Expected: resolves with no version-solve error; `pubspec.lock` now lists
  `drag_and_drop_lists 0.4.2`.

- [ ] **Step 3: Confirm the API surface**

  Skim the installed package to confirm the symbols this plan uses exist:
  `DragAndDropLists`, `DragAndDropList`, `DragAndDropItem`, and the
  `onItemReorder(int oldItemIndex, int oldListIndex, int newItemIndex, int
  newListIndex)` / `onListReorder(int oldListIndex, int newListIndex)`
  callback signatures, plus `itemDragOnLongPress` / `listDragOnLongPress` and
  `contentsWhenEmpty`.

  Run: `grep -rn "onItemReorder\|onListReorder\|contentsWhenEmpty\|DragOnLongPress" ~/.pub-cache/hosted/pub.dev/drag_and_drop_lists-0.4.2/lib/`
  Expected: matches in the package source. If a name differs, note the actual
  signature and adapt Task 6 accordingly.

- [ ] **Step 4: Commit**

  ```bash
  git add pubspec.yaml pubspec.lock
  git commit -m "chore: add drag_and_drop_lists dependency

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 2: Domain helper `insertedAt`

**Files:**
- Modify: `lib/domain/reorder.dart`
- Test: `test/domain/reorder_test.dart`

**Interfaces:**
- Produces: `List<int> insertedAt(List<int> ids, int item, int index)` —
  returns `ids` with `item` inserted at `index` (clamped to `0..ids.length`),
  without mutating `ids`. Used by Task 6 to build a target category's new
  ordering on a cross-category drop.

- [ ] **Step 1: Write the failing tests**

  Append to `test/domain/reorder_test.dart`:

  ```dart
  group('insertedAt', () {
    test('inserts at the head', () {
      expect(insertedAt([2, 3], 1, 0), [1, 2, 3]);
    });
    test('inserts in the middle', () {
      expect(insertedAt([1, 3], 2, 1), [1, 2, 3]);
    });
    test('inserts at the tail', () {
      expect(insertedAt([1, 2], 3, 2), [1, 2, 3]);
    });
    test('clamps an out-of-range index to the tail', () {
      expect(insertedAt([1, 2], 3, 99), [1, 2, 3]);
    });
    test('clamps a negative index to the head', () {
      expect(insertedAt([2, 3], 1, -5), [1, 2, 3]);
    });
    test('does not mutate the input', () {
      final input = [1, 2];
      insertedAt(input, 3, 1);
      expect(input, [1, 2]);
    });
  });
  ```

- [ ] **Step 2: Run the tests to verify they fail**

  Run: `flutter test test/domain/reorder_test.dart`
  Expected: FAIL — `insertedAt` is not defined.

- [ ] **Step 3: Implement `insertedAt`**

  Append to `lib/domain/reorder.dart`:

  ```dart
  /// Returns [ids] with [item] inserted at [index], clamped to `0..ids.length`.
  /// Does not mutate [ids].
  List<int> insertedAt(List<int> ids, int item, int index) {
    final list = [...ids];
    list.insert(index.clamp(0, list.length), item);
    return list;
  }
  ```

- [ ] **Step 4: Run the tests to verify they pass**

  Run: `flutter test test/domain/reorder_test.dart`
  Expected: PASS (all `reorder_test.dart` tests green).

- [ ] **Step 5: Commit**

  ```bash
  git add lib/domain/reorder.dart test/domain/reorder_test.dart
  git commit -m "feat: add insertedAt reorder helper

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 3: DAO `moveTaskToCategoryAt`

**Files:**
- Modify: `lib/data/services/database/todo_dao.dart`
- Test: `test/data/todo_dao_test.dart`

**Interfaces:**
- Produces: `Future<void> moveTaskToCategoryAt(int taskId, int newCategoryId,
  List<int> orderedTargetIds)` — in one transaction, sets `taskId`'s
  `categoryId` to `newCategoryId`, then writes `sortOrder = i` for each id in
  `orderedTargetIds` (the moved task included at its drop position). The source
  category is intentionally not renumbered.

- [ ] **Step 1: Write the failing test**

  In `test/data/todo_dao_test.dart`, inside the existing `group('reordering',
  ...)` (after the `reorderTasks` test, before its closing `});`):

  ```dart
  test('moveTaskToCategoryAt reassigns category and positions the task',
      () async {
    final src = await db.todoDao.createCategory(name: 'Src', color: 1);
    final dst = await db.todoDao.createCategory(name: 'Dst', color: 2);
    final s1 = await db.todoDao.createTask(categoryId: src, name: 's1');
    final s2 = await db.todoDao.createTask(categoryId: src, name: 's2');
    final d1 = await db.todoDao.createTask(categoryId: dst, name: 'd1');
    final d2 = await db.todoDao.createTask(categoryId: dst, name: 'd2');

    // Move s1 into dst between d1 and d2.
    await db.todoDao.moveTaskToCategoryAt(s1, dst, [d1, s1, d2]);

    final snapshot = await db.todoDao.watchCategoriesWithTasks().first;
    final byName = {for (final c in snapshot) c.category.name: c};
    expect(
      byName['Dst']!.activeTasks.map((t) => t.name),
      ['d1', 's1', 'd2'],
    );
    // Source keeps its remaining task in order; s1 is gone from it.
    expect(byName['Src']!.activeTasks.map((t) => t.name), ['s2']);
    expect(s2, isNotNull);
  });
  ```

- [ ] **Step 2: Run the test to verify it fails**

  Run: `flutter test test/data/todo_dao_test.dart`
  Expected: FAIL — `moveTaskToCategoryAt` is not defined.

- [ ] **Step 3: Implement the DAO method**

  In `lib/data/services/database/todo_dao.dart`, after `reorderTasks` (around
  line 146), add:

  ```dart
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
  ```

- [ ] **Step 4: Run the test to verify it passes**

  Run: `flutter test test/data/todo_dao_test.dart`
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/data/services/database/todo_dao.dart test/data/todo_dao_test.dart
  git commit -m "feat: add moveTaskToCategoryAt DAO op

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 4: Thread `moveTaskToCategoryAt` through repo + view model

**Files:**
- Modify: `lib/data/repositories/todo_repository.dart`
- Modify: `lib/ui/home/home_view_model.dart`

**Interfaces:**
- Consumes: `TodoDao.moveTaskToCategoryAt(int, int, List<int>)` (Task 3).
- Produces: `TodoRepository.moveTaskToCategoryAt(int taskId, int newCategoryId,
  List<int> orderedTargetIds)` and the identical `HomeViewModel` passthrough —
  consumed by Task 6.

- [ ] **Step 1: Add the repository passthrough**

  In `lib/data/repositories/todo_repository.dart`, after the `reorderTasks`
  line (line 44), add:

  ```dart
  Future<void> moveTaskToCategoryAt(
    int taskId,
    int newCategoryId,
    List<int> orderedTargetIds,
  ) => _dao.moveTaskToCategoryAt(taskId, newCategoryId, orderedTargetIds);
  ```

- [ ] **Step 2: Add the view-model passthrough**

  In `lib/ui/home/home_view_model.dart`, after the `reorderTasks` getter
  (line 44), add:

  ```dart
  Future<void> moveTaskToCategoryAt(
    int taskId,
    int newCategoryId,
    List<int> orderedTargetIds,
  ) => _repo.moveTaskToCategoryAt(taskId, newCategoryId, orderedTargetIds);
  ```

- [ ] **Step 3: Regenerate and verify it compiles**

  Run: `dart run build_runner build --delete-conflicting-outputs`
  Then: `flutter analyze`
  Expected: no errors. (No `.g.dart` change is expected from a plain method, but
  run it to be safe.)

- [ ] **Step 4: Commit**

  ```bash
  git add lib/data/repositories/todo_repository.dart lib/ui/home/home_view_model.dart
  git commit -m "feat: expose moveTaskToCategoryAt via repo and view model

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 5: Extract shared header + row builders

**Files:**
- Create: `lib/ui/home/widgets/category_header_content.dart`
- Create: `lib/ui/home/widgets/task_row_content.dart`
- Modify: `lib/ui/home/widgets/category_section.dart`

Pull the header rendering and the task-row rendering out of `CategorySection`
into two reusable widgets so the board (Task 6) and the unchanged Archive
`CategorySection` render identically. Pure refactor — the full suite must stay
green with no test edits.

- [ ] **Step 1: Create `CategoryHeaderContent`**

  Create `lib/ui/home/widgets/category_header_content.dart` with a
  `StatelessWidget` that renders the current header `ListTile` exactly as it is
  today in `category_section.dart` (lines ~51–89): leading chevron
  (`category.collapsed ? Icons.expand_more : Icons.expand_less`), the
  `Text.rich` title (emoji + bold name in `nameColor` + `· openItemsCount`),
  and the trailing `category-menu-{id}` `IconButton`. It takes:

  ```dart
  const CategoryHeaderContent({
    super.key,
    required this.category,
    required this.taskCount,
    required this.onToggleCollapsed,
    required this.onHeaderMenu,
  });
  ```

  Keep the `Key('category-header-${category.id}')` on the `ListTile` and
  `Key('category-menu-${category.id}')` on the `IconButton`. Move the
  `readableOn` color computation here.

- [ ] **Step 2: Create `TaskRowContent`**

  Create `lib/ui/home/widgets/task_row_content.dart` with a `StatelessWidget`
  rendering the current task `ListTile` (lines ~109–133): leading icon
  (archived → `Icons.check_circle` in category color; active → the
  `markDoneLabel` `Semantics` + `Icons.radio_button_unchecked`), title, the
  archive subtitle (completed-on + auto-removes-in), and the trailing
  `task-menu-{id}` `IconButton` when `onTaskMenu != null`. It takes:

  ```dart
  const TaskRowContent({
    super.key,
    required this.task,
    required this.color,
    required this.archived,
    required this.now,
    required this.onTaskTap,
    required this.onTaskMenu,
  });
  ```

  Keep `Key('task-${task.id}')` on the `ListTile` and `Key('task-menu-${task.id}')`
  on the menu button. Do **not** move the `Dismissible` here — that stays at the
  call site so the board and section can each decide whether to wrap.

- [ ] **Step 3: Rewrite `CategorySection` to compose the two widgets**

  In `lib/ui/home/widgets/category_section.dart`, replace the inline header
  `ListTile` with `CategoryHeaderContent(...)` and replace the inline row
  `ListTile` (inside the `for (final task in tasks)` loop) with
  `TaskRowContent(...)`, keeping the surrounding colored underline `Container`,
  the collapse `if (!category.collapsed)`, the empty-state text, and the active
  `Dismissible` wrapper (`dismiss-{id}`) exactly as they are now.

- [ ] **Step 4: Run the full suite to verify the refactor is behavior-neutral**

  Run: `just test`
  Expected: all tests PASS with **no** test-file edits — the header/row keys,
  text, and alignment assertions in `home_screen_test.dart` still hold.

- [ ] **Step 5: Lint**

  Run: `just lint`
  Expected: clean.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/ui/home/widgets/
  git commit -m "refactor: extract shared category-header and task-row widgets

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 6: Build the drag board in the Active view

**Files:**
- Modify: `lib/ui/home/home_screen.dart`
- Test: `test/ui/home_screen_test.dart`

**Interfaces:**
- Consumes: `CategoryHeaderContent`, `TaskRowContent` (Task 5);
  `HomeViewModel.reorderCategories`, `.reorderTasks`,
  `.moveTaskToCategoryAt` (Tasks 3–4); `reorderedIds`, `insertedAt`
  (`lib/domain/reorder.dart`, Task 2).

Replace the Active branch of `_body` with a `DragAndDropLists`. Archive keeps
the existing `CategorySection` list. The widget tests here guard keys and
existing behavior; drag gestures themselves are not simulated.

- [ ] **Step 1: Add a regression test that the board still renders + collapses**

  The existing `home_screen_test.dart` already covers collapse/expand, menu
  alignment, swipe, and counts; those now run against the board. Add one test
  asserting the board renders multiple categories with their tasks in order, so
  a broken `DragAndDropLists` build fails loudly. Inside `main()`:

  ```dart
  testWidgets('active view renders categories and tasks as a board', (
    tester,
  ) async {
    final home = await db.todoDao.createCategory(name: 'Home', color: 0xFF009688);
    final work = await db.todoDao.createCategory(name: 'Work', color: 0xFF3F51B5);
    await db.todoDao.createTask(categoryId: home, name: 'Sweep');
    await db.todoDao.createTask(categoryId: work, name: 'Email');
    await tester.pumpWidget(_app(db, prefs));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('category-header-$home')), findsOneWidget);
    expect(find.byKey(Key('category-header-$work')), findsOneWidget);
    expect(find.text('Sweep'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });
  ```

- [ ] **Step 2: Run it to confirm it passes against the current (pre-board) UI**

  Run: `flutter test test/ui/home_screen_test.dart -n "board"`
  Expected: PASS (the keys/text already exist via `CategorySection`). This test
  is the guardrail for the rewrite in Step 3 — it must stay green afterward.

- [ ] **Step 3: Rewrite the Active branch as a board**

  In `lib/ui/home/home_screen.dart`:

  1. Import the package and the new widgets:

     ```dart
     import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';

     import 'widgets/category_header_content.dart';
     import 'widgets/task_row_content.dart';
     ```

  2. In `_body`, keep the empty/archive handling. For the **archived** case,
     keep the existing `ListView` of `CategorySection`. For the **active** case,
     return a new `_board(visible, now)`.

  3. Add `_board`, building one `DragAndDropList` per category. Header is
     `CategoryHeaderContent` (toggling collapse + opening the header menu);
     children are `DragAndDropItem`s only when `!collapsed`, each wrapping the
     active `TaskRowContent` in the existing `Dismissible` (`dismiss-{id}`).
     Provide `contentsWhenEmpty` so collapsed/empty categories stay drop
     targets:

     ```dart
     Widget _board(List<CategoryWithTasks> cats, DateTime now) {
       return DragAndDropLists(
         listPadding: EdgeInsets.zero,
         itemDragOnLongPress: true,
         listDragOnLongPress: true,
         onListReorder: (oldIndex, newIndex) {
           final ids = [for (final c in cats) c.category.id];
           _vm.reorderCategories(reorderedIds(ids, oldIndex, newIndex));
         },
         onItemReorder:
             (oldItemIndex, oldListIndex, newItemIndex, newListIndex) {
           _onItemReorder(
             cats,
             oldItemIndex,
             oldListIndex,
             newItemIndex,
             newListIndex,
           );
         },
         children: [
           for (final cwt in cats) _dragList(cwt, now),
         ],
       );
     }

     DragAndDropList _dragList(CategoryWithTasks cwt, DateTime now) {
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
                         onTaskTap: () => _complete(task),
                         onTaskMenu: () => _taskMenu(cats, task),
                       ),
                     ),
                   ),
               ],
       );
     }
     ```

     Add `import 'package:flutter/services.dart';` for `HapticFeedback` if not
     already imported.

  4. Add the item-reorder mapping. Same list → `reorderTasks`; different list →
     `moveTaskToCategoryAt` with the target ordering built via `insertedAt`:

     ```dart
     void _onItemReorder(
       List<CategoryWithTasks> cats,
       int oldItemIndex,
       int oldListIndex,
       int newItemIndex,
       int newListIndex,
     ) {
       final from = cats[oldListIndex];
       final to = cats[newListIndex];
       final movedId = from.activeTasks[oldItemIndex].id;
       if (oldListIndex == newListIndex) {
         final ids = [for (final t in from.activeTasks) t.id];
         _vm.reorderTasks(reorderedIds(ids, oldItemIndex, newItemIndex));
       } else {
         final targetIds = [for (final t in to.activeTasks) t.id];
         _vm.moveTaskToCategoryAt(
           movedId,
           to.category.id,
           insertedAt(targetIds, movedId, newItemIndex),
         );
       }
     }
     ```

- [ ] **Step 4: Run the board guardrail + the full UI suite**

  Run: `flutter test test/ui/home_screen_test.dart`
  Expected: PASS — including the existing collapse/expand, menu-alignment,
  swipe, count, and locale tests now running against the board. If the
  menu-alignment test fails on a package-imposed item indent, set the package
  padding to zero (already `listPadding: EdgeInsets.zero`); if an unavoidable
  fixed offset remains, update that test's expected offset per the design's
  Risk note and record the change in the task.

- [ ] **Step 5: Lint**

  Run: `just lint`
  Expected: clean.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/ui/home/home_screen.dart test/ui/home_screen_test.dart
  git commit -m "feat: drag-reorder board for the active view

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 7: Expanding a category sets the add-task default

**Files:**
- Modify: `lib/ui/home/home_screen.dart`
- Test: `test/ui/home_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsRepository.writeLastCategoryId(int)` /
  `readLastCategoryId()`; `HomeViewModel.toggleCollapsed(int, bool)`.

Implement `_onExpandToggle` (referenced in Task 6): toggling collapse, and when
the transition is collapse→expand, recording that category as the quick-add
default (persisted, like #7). Collapsing does not change the default.

- [ ] **Step 1: Write the failing test**

  Add to `home_screen_test.dart` inside `main()`:

  ```dart
  testWidgets('expanding a category makes it the quick-add default', (
    tester,
  ) async {
    final home = await db.todoDao.createCategory(name: 'Home', color: 0xFF009688);
    final work = await db.todoDao.createCategory(name: 'Work', color: 0xFF3F51B5);
    // Start both collapsed so expanding is a real collapse->expand transition.
    await db.todoDao.setCollapsed(home, true);
    await db.todoDao.setCollapsed(work, true);
    await tester.pumpWidget(_app(db, prefs));
    await tester.pumpAndSettle();

    // Expand Work (the non-first category).
    await tester.tap(find.byKey(Key('category-header-$work')));
    await tester.pumpAndSettle();

    expect(
      SettingsRepository(prefs).readLastCategoryId(),
      work,
    );

    // The quick-add dialog should preselect Work.
    await tester.tap(find.byKey(const Key('add-task-fab')));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsWidgets);
  });
  ```

  Add `import 'package:nooka/data/repositories/settings_repository.dart';` if
  not already present (it is, per the existing imports).

- [ ] **Step 2: Run it to verify it fails**

  Run: `flutter test test/ui/home_screen_test.dart -n "quick-add default"`
  Expected: FAIL — expanding does not yet write the last category (and/or
  `_onExpandToggle` is undefined if Task 6 left it as a stub).

- [ ] **Step 3: Implement `_onExpandToggle`**

  In `lib/ui/home/home_screen.dart`, add:

  ```dart
  void _onExpandToggle(Category category) {
    final expanding = category.collapsed; // currently collapsed -> expanding
    _vm.toggleCollapsed(category.id, !category.collapsed);
    if (expanding) {
      _lastCategoryId = category.id;
      ref
          .read(settingsRepositoryProvider)
          .writeLastCategoryId(category.id);
    }
  }
  ```

  Ensure `Category` is imported (it is, via
  `data/services/database/database.dart`).

- [ ] **Step 4: Run the test to verify it passes**

  Run: `flutter test test/ui/home_screen_test.dart -n "quick-add default"`
  Expected: PASS.

- [ ] **Step 5: Full suite + lint**

  Run: `just test` then `just lint`
  Expected: all green; lint clean.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/ui/home/home_screen.dart test/ui/home_screen_test.dart
  git commit -m "feat: expanding a category sets the add-task default

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 8: Manual device verification + architecture promotion

**Files:**
- Modify: `architecture/data-model.md`
- Modify: `planning/README.md` (move bundle to Archived on merge — done at PR
  time, noted here)

Drag behavior can't be trusted from widget tests alone; verify on a device,
then promote the data-model note.

- [ ] **Step 1: Manual smoke on a simulator/device**

  Run: `flutter run`
  Verify, in the Active view:
  - Long-press a category header → drag → categories reorder and persist after
    a restart.
  - Long-press a task → drag within its category → tasks reorder and persist.
  - Long-press a task → drag onto another category (including a collapsed one)
    → it reassigns to that category at the drop position.
  - Tap-to-complete and swipe-right-to-complete still work (long-press-drag vs.
    horizontal-swipe do not fight). If they conflict, apply the design's
    fallback (explicit drag handle) and note it.
  - Expanding a collapsed category, then opening the FAB → that category is
    preselected; restart confirms persistence.
  - Archive view shows no drag affordance.

- [ ] **Step 2: Promote the data-model note**

  In `architecture/data-model.md`, update the ordering sentence to reflect the
  new cross-category move, e.g. append:

  > Tasks can be reordered within a category and moved to another category at a
  > chosen position; both renumber `sortOrder` transactionally
  > (`reorderTasks` / `moveTaskToCategoryAt`). Reorder/move is surfaced as a
  > drag board on the Active view only.

- [ ] **Step 3: Commit**

  ```bash
  git add architecture/data-model.md
  git commit -m "docs: note cross-category task move in data-model

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

- [ ] **Step 4: Open the PR**

  Push the branch and open a PR titled `feat: drag-reorder board +
  expand-sets-default`. On merge, set this bundle's `design.md`/`plan.md`
  frontmatter to `status: shipped` with the `pr:`/`outcome:`, move the folder
  to `planning/changes/`, and move its `planning/README.md` line from
  **Active** to **Archived**.

---

## Self-review

- **Spec coverage:** dependency (T1), domain helper (T2), cross-category DAO op
  (T3), repo+VM seam (T4), shared builders (T5), board UI + reorder/move
  callbacks (T6), expand-sets-default (T7), manual drag verification + arch
  promotion (T8). All design §1–§6, Testing, and Risk items map to a task.
- **Placeholder scan:** none — every code/edit step carries concrete code or an
  exact command.
- **Type consistency:** `moveTaskToCategoryAt(int, int, List<int>)` and
  `insertedAt(List<int>, int, int)` are used identically across T2–T7;
  `reorderedIds` matches the existing signature; widget keys match the existing
  suite.
