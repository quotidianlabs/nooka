---
status: shipped
date: 2026-06-20
slug: hardening-drag-dialogs
spec: hardening-drag-dialogs
pr: null
---

# hardening-drag-dialogs — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the drag board and the add/edit dialogs — auto-expand a
collapsed drop target, bounds-check the reorder against a fresh snapshot, guard
double-tap quick-add, validate/cap/clip names, derive archived state from the
type — and fill the drag-board + dialog widget-test coverage gaps.

**Spec:** [`design.md`](./design.md)

**Branch:** `fix/hardening-drag-dialogs`

**Commit strategy:** Per-task commits.

## Global Constraints

- Flutter, Dart SDK `^3.12.2`, Riverpod, Drift. Layered MVVM.
- `just lint` (`dart format` + `flutter analyze`) clean; `just test`
  (`flutter test`) green before any task is considered done. `just lint-ci` is
  the check-only CI variant.
- Generated `*.g.dart` is committed; run
  `dart run build_runner build --delete-conflicting-outputs` after touching
  `@riverpod`/Drift code, and commit the regenerated files.
- i18n lives in `lib/l10n/app_en.arb` + `lib/l10n/app_ru.arb`; any new key adds
  both locales (Russian: four CLDR plural forms — one/few/many/other — where
  plurals apply). This bundle adds **no** new ARB keys (validation is
  enable/disable + a formatter, not a message).
- **TDD:** write the failing `flutter test` first, then minimal implementation,
  then green, then commit. Per-task commits.
- Conventional commit subjects; commit body trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Depends on Bundle A:** `_HomeScreenState` has a
  `_guard(Future<void> Function() action)` helper (try/catch → localized
  `actionFailed` SnackBar). Task 1 routes its mutations through it. If Bundle A
  is not yet on the branch base, rebase Task 1 onto it before starting.
- Preserve existing widget keys: `category-header-{id}`, `category-menu-{id}`,
  `task-{id}`, `task-menu-{id}`, `dismiss-{id}`, `quick-add-field`,
  `quick-add-confirm`, `quick-add-done`, `task-name-field`, `task-confirm`,
  `task-category-dropdown`, `category-name-field`, `category-confirm`,
  `confirm-delete`, `confirm-clear-archive`, `add-task-fab`.

---

### Task 1: H4 + H3 — extract a pure `planReorder` decision and make `_onItemReorder` interpret it

**Files:**
- Create: `lib/domain/board_reorder.dart`
- Modify: `lib/ui/home/home_screen.dart`
- Test: `test/domain/board_reorder_test.dart`

The H3/H4 logic lives in the private `_onItemReorder`, reacting to a brittle
drag gesture — untestable in place. Extract the *decision* (no-op when the
snapshot is stale/out-of-range; reorder-within; move-across with optional
auto-expand of a collapsed destination) into a pure function `planReorder` that
takes the current snapshot + the four drag indices and returns a `ReorderPlan`.
`_onItemReorder` then re-reads live state, calls `planReorder`, and interprets
the plan through Bundle A's `_guard`. The pure function is unit-tested directly;
no widget/gesture simulation needed.

- [ ] **Step 1: Write the failing unit tests for `planReorder`**

  Create `test/domain/board_reorder_test.dart`. Build `CategoryWithTasks`
  fixtures from the generated `Category`/`Task` data classes (pure rows, no DB).
  Verify: out-of-range list/item indices → `ReorderNoop` (H4); a within-category
  drop → `ReorderWithin` with the reordered ids; a cross-category drop into an
  **expanded** destination → `ReorderAcross` with `expandCategoryId == null`; a
  cross-category drop into a **collapsed** destination → `ReorderAcross` with
  `expandCategoryId == <destination id>` (H3); an append (`newItemIndex ==
  length`) is allowed (not a no-op).

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/services/database/database.dart';
  import 'package:nooka/domain/board_reorder.dart';
  import 'package:nooka/domain/models/category_with_tasks.dart';

  Category _cat(int id, {bool collapsed = false}) => Category(
    id: id,
    name: 'C$id',
    color: 0xFF009688,
    emoji: null,
    collapsed: collapsed,
    sortOrder: id,
    createdAt: DateTime(2026, 1, 1),
  );

  Task _task(int id, int categoryId) => Task(
    id: id,
    categoryId: categoryId,
    name: 'T$id',
    sortOrder: id,
    createdAt: DateTime(2026, 1, 1),
    archivedAt: null,
  );

  CategoryWithTasks _cwt(Category c, List<Task> tasks) =>
      CategoryWithTasks(category: c, tasks: tasks);

  void main() {
    // Two categories: list 0 = {t1,t2}, list 1 = {t3}.
    List<CategoryWithTasks> snapshot({bool dstCollapsed = false}) => [
      _cwt(_cat(1), [_task(1, 1), _task(2, 1)]),
      _cwt(_cat(2, collapsed: dstCollapsed), [_task(3, 2)]),
    ];

    test('out-of-range list index returns ReorderNoop', () {
      expect(planReorder(snapshot(), 0, 0, 0, 5), isA<ReorderNoop>());
      expect(planReorder(snapshot(), 0, 9, 0, 0), isA<ReorderNoop>());
    });

    test('out-of-range item index returns ReorderNoop', () {
      // list 0 has 2 items; item index 2 is out of range for a same-list move.
      expect(planReorder(snapshot(), 2, 0, 0, 0), isA<ReorderNoop>());
    });

    test('within-category drop returns ReorderWithin with reordered ids', () {
      final plan = planReorder(snapshot(), 0, 0, 1, 0);
      expect(plan, isA<ReorderWithin>());
      expect((plan as ReorderWithin).orderedIds, [2, 1]);
    });

    test('cross-category drop into an expanded destination does not expand', () {
      final plan = planReorder(snapshot(), 0, 0, 0, 1);
      expect(plan, isA<ReorderAcross>());
      final across = plan as ReorderAcross;
      expect(across.movedId, 1);
      expect(across.toCategoryId, 2);
      expect(across.orderedTargetIds, [1, 3]);
      expect(across.expandCategoryId, isNull);
    });

    test('cross-category drop into a collapsed destination expands it (H3)', () {
      final plan =
          planReorder(snapshot(dstCollapsed: true), 0, 0, 1, 1) as ReorderAcross;
      expect(plan.expandCategoryId, 2);
      expect(plan.orderedTargetIds, [3, 1]); // appended at index 1
    });

    test('append index (== length) is allowed, not a no-op', () {
      // destination list 1 has length 1; newItemIndex 1 appends.
      expect(planReorder(snapshot(), 0, 0, 1, 1), isA<ReorderAcross>());
    });
  }
  ```

  (Confirm the `Category`/`Task` constructor field names + the
  `CategoryWithTasks` constructor against `database.g.dart` /
  `category_with_tasks.dart`; adjust if the generated signatures differ.)

- [ ] **Step 2: Run it to verify it fails**

  Run: `flutter test test/domain/board_reorder_test.dart`
  Expected: FAIL to compile — `board_reorder.dart` / `planReorder` /
  `ReorderPlan` do not exist yet.

- [ ] **Step 3: Create the pure `planReorder` helper**

  Create `lib/domain/board_reorder.dart`. It depends only on the domain model
  and the existing `reorder.dart` primitives (`reorderedIds`, `insertedAt`) —
  no Flutter, no Drift, no Riverpod:

  ```dart
  import 'models/category_with_tasks.dart';
  import 'reorder.dart';

  /// The decision a drag-board drop resolves to. Pure data; the UI layer
  /// interprets it (issuing the guarded mutations).
  sealed class ReorderPlan {
    const ReorderPlan();
  }

  /// Stale/out-of-range drop — the snapshot no longer matches; do nothing.
  class ReorderNoop extends ReorderPlan {
    const ReorderNoop();
  }

  /// Reorder tasks within a single category.
  class ReorderWithin extends ReorderPlan {
    const ReorderWithin(this.orderedIds);
    final List<int> orderedIds;
  }

  /// Move [movedId] into [toCategoryId] at the resolved position.
  /// [expandCategoryId] is set when the destination was collapsed and must be
  /// auto-expanded so the moved task is not hidden (H3); null otherwise.
  class ReorderAcross extends ReorderPlan {
    const ReorderAcross({
      required this.movedId,
      required this.toCategoryId,
      required this.orderedTargetIds,
      required this.expandCategoryId,
    });
    final int movedId;
    final int toCategoryId;
    final List<int> orderedTargetIds;
    final int? expandCategoryId;
  }

  /// Resolve a `drag_and_drop_lists` drop against the CURRENT [cats] snapshot.
  /// All four indices are validated against the live snapshot so a drop that
  /// raced a stream emission becomes a [ReorderNoop] instead of a RangeError
  /// or a wrong-task move (H4).
  ReorderPlan planReorder(
    List<CategoryWithTasks> cats,
    int oldItemIndex,
    int oldListIndex,
    int newItemIndex,
    int newListIndex,
  ) {
    if (oldListIndex < 0 ||
        oldListIndex >= cats.length ||
        newListIndex < 0 ||
        newListIndex >= cats.length) {
      return const ReorderNoop();
    }
    final from = cats[oldListIndex];
    final to = cats[newListIndex];
    if (oldItemIndex < 0 || oldItemIndex >= from.activeTasks.length) {
      return const ReorderNoop();
    }
    // An insert index may equal the list length (append); reject only beyond.
    if (newItemIndex < 0 || newItemIndex > to.activeTasks.length) {
      return const ReorderNoop();
    }

    final movedId = from.activeTasks[oldItemIndex].id;
    if (oldListIndex == newListIndex) {
      final ids = [for (final t in from.activeTasks) t.id];
      return ReorderWithin(reorderedIds(ids, oldItemIndex, newItemIndex));
    }
    final targetIds = [for (final t in to.activeTasks) t.id];
    return ReorderAcross(
      movedId: movedId,
      toCategoryId: to.category.id,
      orderedTargetIds: insertedAt(targetIds, movedId, newItemIndex),
      expandCategoryId: to.category.collapsed ? to.category.id : null,
    );
  }
  ```

- [ ] **Step 4: Run the unit tests to verify they pass**

  Run: `flutter test test/domain/board_reorder_test.dart`
  Expected: PASS — all six cases green.

- [ ] **Step 5: Rewrite `_onItemReorder` to re-read state and interpret the plan**

  In `lib/ui/home/home_screen.dart`, add the import for `board_reorder.dart`,
  then replace the current method (lines 237-258) so it re-reads live state and
  switches on the plan, routing each mutation through `_guard`. Drop the `cats`
  parameter:

  ```dart
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
          () => _vm.moveTaskToCategoryAt(movedId, toCategoryId, orderedTargetIds),
        );
        // H3: a collapsed destination renders no items, so the dropped task
        // would be hidden. Auto-expand it.
        if (expandCategoryId != null) {
          _guard(() => _vm.toggleCollapsed(expandCategoryId, false));
        }
    }
  }
  ```

  Then update the call site in `_board` (the `onItemReorder` closure, ~line
  166-174) to drop the `cats` argument:

  ```dart
  onItemReorder: (oldItemIndex, oldListIndex, newItemIndex, newListIndex) {
    _onItemReorder(oldItemIndex, oldListIndex, newItemIndex, newListIndex);
  },
  ```

  (`_board` and `_dragList` still take `cats` for building the lists; only the
  reorder closure stops forwarding it.)

- [ ] **Step 6: Run the full UI suite + lint**

  Run: `flutter test test/ui/home_screen_test.dart` then `just lint`
  Expected: PASS — all existing collapse/menu/swipe/locale tests still green;
  lint clean. Confirm `_guard` resolves (Bundle A); if `flutter analyze` reports
  `_guard` undefined, Bundle A has not landed — rebase before continuing.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/domain/board_reorder.dart lib/ui/home/home_screen.dart \
    test/domain/board_reorder_test.dart
  git commit -m "fix: bounds-check reorder via pure planReorder and auto-expand collapsed drop target

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 2: H5 + L5 — guard quick-add against double-tap and post-await disposal

**Files:**
- Modify: `lib/ui/widgets/task_dialog.dart`
- Test: `test/ui/task_dialog_test.dart`

Add a `_busy` re-entrancy guard, clear the field synchronously *before* the
await, and add a `mounted` check before `requestFocus`.

- [ ] **Step 1: Create the failing test — two rapid taps add exactly one item**

  Create `test/ui/task_dialog_test.dart`. Use a `Completer`-gated `onAdd` so the
  await is still pending when the second tap lands:

  ```dart
  import 'dart:async';

  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/services/database/database.dart';
  import 'package:nooka/l10n/app_localizations.dart';
  import 'package:nooka/ui/widgets/task_dialog.dart';

  Widget _host(Widget Function(BuildContext) onOpen) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => onOpen(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  // A throwaway Category row for the dropdown. Field names + the required
  // createdAt match the generated `Category` data class in database.g.dart.
  Category _cat(int id, String name) => Category(
    id: id,
    name: name,
    color: 0xFF009688,
    emoji: null,
    collapsed: false,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  void main() {
    testWidgets('rapid double-tap on quick-add only adds once', (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      await tester.pumpWidget(
        _host(
          (context) => showQuickAddDialog(
            context,
            categories: [_cat(1, 'Home')],
            initialCategoryId: 1,
            onAdd: (name, categoryId) async {
              calls++;
              await gate.future; // hold the await open
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('quick-add-field')), 'Milk');
      await tester.tap(find.byKey(const Key('quick-add-confirm')));
      await tester.pump(); // start the first _submit; field clears synchronously
      // Field is already empty, so the second tap reads empty and no-ops; the
      // _busy guard would also reject it.
      await tester.tap(find.byKey(const Key('quick-add-confirm')));
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
    });
  }
  ```

  (Confirm the `Category` constructor argument names against
  `lib/data/services/database/database.g.dart` — Drift generates positional/
  named fields `id, name, color, emoji, sortOrder, collapsed`; adjust if the
  generated signature differs.)

- [ ] **Step 2: Run it to verify it fails**

  Run: `flutter test test/ui/task_dialog_test.dart`
  Expected: FAIL — `calls == 2`, because the current `_submit` clears the field
  only after the await, so the second tap re-reads "Milk" and calls `onAdd`
  again.

- [ ] **Step 3: Implement the `_busy` guard + synchronous clear + mounted check**

  In `lib/ui/widgets/task_dialog.dart`, add a `_busy` field to
  `_QuickAddDialogState` and rewrite `_submit` (lines 150-156):

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
    _focus.requestFocus(); // keep the keyboard up for the next item
  }
  ```

- [ ] **Step 4: Run it to verify it passes**

  Run: `flutter test test/ui/task_dialog_test.dart`
  Expected: PASS — `calls == 1`.

- [ ] **Step 5: Add the L5 mid-await-dismiss test**

  Append to `test/ui/task_dialog_test.dart`:

  ```dart
  testWidgets('dismissing quick-add mid-await does not requestFocus on a '
      'disposed node', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(
      _host(
        (context) => showQuickAddDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
          onAdd: (name, categoryId) async => gate.future,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quick-add-field')), 'Milk');
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pump(); // _submit awaits onAdd

    // Close the dialog while the await is still pending.
    await tester.tap(find.byKey(const Key('quick-add-done')));
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();
    // No "requestFocus after dispose" / setState-after-dispose error -> pass.
    expect(tester.takeException(), isNull);
  });
  ```

  Run: `flutter test test/ui/task_dialog_test.dart`
  Expected: PASS (the `if (!mounted) return;` from Step 3 prevents the disposed
  `requestFocus`).

- [ ] **Step 6: Lint + commit**

  ```bash
  just lint
  git add lib/ui/widgets/task_dialog.dart test/ui/task_dialog_test.dart
  git commit -m "fix: guard quick-add against double-tap and post-dispose focus

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 3: M3a — enable/disable confirm buttons on name emptiness + length cap

**Files:**
- Modify: `lib/ui/widgets/task_dialog.dart`
- Modify: `lib/ui/widgets/category_dialog.dart`
- Test: `test/ui/task_dialog_test.dart`
- Test: `test/ui/category_dialog_test.dart`

Drive each confirm button's `onPressed` from a name-controller listener (enabled
only when `text.trim().isNotEmpty`) and cap name length with a shared formatter.

- [ ] **Step 1: Write the failing tests — button disabled until non-empty, length clamped**

  Append to `test/ui/task_dialog_test.dart` (quick-add):

  ```dart
  testWidgets('quick-add confirm is disabled until the name is non-empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        (context) => showQuickAddDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
          onAdd: (name, categoryId) async {},
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    TextButton confirm() =>
        tester.widget<TextButton>(find.byKey(const Key('quick-add-confirm')));
    expect(confirm().onPressed, isNull); // empty -> disabled

    await tester.enterText(find.byKey(const Key('quick-add-field')), '   ');
    await tester.pump();
    expect(confirm().onPressed, isNull); // whitespace-only -> still disabled

    await tester.enterText(find.byKey(const Key('quick-add-field')), 'Milk');
    await tester.pump();
    expect(confirm().onPressed, isNotNull); // non-empty -> enabled

    await tester.enterText(
      find.byKey(const Key('quick-add-field')),
      'x' * 200,
    );
    await tester.pump();
    final field =
        tester.widget<TextField>(find.byKey(const Key('quick-add-field')));
    expect(field.controller!.text.length, 100); // capped at kMaxNameLength
  });
  ```

  Append to `test/ui/category_dialog_test.dart`:

  ```dart
  testWidgets('category confirm is disabled until the name is non-empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCategoryDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    TextButton confirm() =>
        tester.widget<TextButton>(find.byKey(const Key('category-confirm')));
    expect(confirm().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('category-name-field')), 'Home');
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
  });
  ```

- [ ] **Step 2: Run them to verify they fail**

  Run: `flutter test test/ui/task_dialog_test.dart test/ui/category_dialog_test.dart`
  Expected: FAIL — confirm `onPressed` is non-null even when empty (buttons are
  always enabled today), and the 200-char entry is not clamped.

- [ ] **Step 3: Add the shared cap constant + formatter, and listener-driven enable**

  In `lib/ui/widgets/task_dialog.dart`, add a module-top constant and import the
  services formatter:

  ```dart
  import 'package:flutter/services.dart';
  ```
  ```dart
  /// Max length for a task/category name. Caps storage and prevents row overflow.
  const int kMaxNameLength = 100;
  ```

  In `_QuickAddDialogState`: add a listener so the button reflects emptiness, and
  the formatter on the field. In `initState` (add one) attach
  `_name.addListener(() => setState(() {}));` and remove it in `dispose` (the
  controller is disposed there already; the listener goes with it). On the
  `quick-add-field` `TextField` add:

  ```dart
  inputFormatters: [LengthLimitingTextInputFormatter(kMaxNameLength)],
  ```

  Change the `quick-add-confirm` button to gate on emptiness **and** `_busy`:

  ```dart
  TextButton(
    key: const Key('quick-add-confirm'),
    onPressed: (_busy || _name.text.trim().isEmpty) ? null : _submit,
    child: Text(l10n.add),
  ),
  ```

  Apply the same listener + formatter pattern to `_TaskDialogState` and its
  `task-confirm` button:

  ```dart
  onPressed: _name.text.trim().isEmpty
      ? null
      : () {
          final name = _name.text.trim();
          if (name.isEmpty) return;
          Navigator.pop(context, TaskDialogResult(name, _categoryId));
        },
  ```

  In `lib/ui/widgets/category_dialog.dart`, import `task_dialog.dart` for
  `kMaxNameLength` (or define a shared `const` in a small shared file if a
  cross-import reads oddly — a co-located re-use is fine here), add
  `_name.addListener(() => setState(() {}));` in an `initState`, add
  `inputFormatters: [LengthLimitingTextInputFormatter(kMaxNameLength)]` to the
  `category-name-field`, and gate `category-confirm`:

  ```dart
  onPressed: _name.text.trim().isEmpty
      ? null
      : () {
          final name = _name.text.trim();
          if (name.isEmpty) return;
          final icon = _icon.text.trim();
          Navigator.pop(
            context,
            CategoryDialogResult(name, _color, icon.isEmpty ? null : icon),
          );
        },
  ```

  (`category_dialog.dart` already imports `package:flutter/services.dart`.)

- [ ] **Step 4: Run them to verify they pass**

  Run: `flutter test test/ui/task_dialog_test.dart test/ui/category_dialog_test.dart`
  Expected: PASS.

- [ ] **Step 5: Full suite + lint**

  Run: `just test` then `just lint`
  Expected: all green; lint clean. (Existing `category_dialog_test.dart` and
  `home_screen_test.dart` flows still pass — they always enter a non-empty name
  before tapping confirm.)

- [ ] **Step 6: Commit**

  ```bash
  git add lib/ui/widgets/task_dialog.dart lib/ui/widgets/category_dialog.dart \
    test/ui/task_dialog_test.dart test/ui/category_dialog_test.dart
  git commit -m "fix: disable confirm on empty name and cap name length

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 4: M3b — clip a long task title to two lines

**Files:**
- Modify: `lib/ui/home/widgets/task_row_content.dart`
- Test: `test/ui/task_row_content_test.dart`

Give the row title `maxLines: 2, overflow: TextOverflow.ellipsis` so a long name
can't overflow the row.

- [ ] **Step 1: Write the failing test**

  Create `test/ui/task_row_content_test.dart` (shared host reused by Task 6's L3
  test). Assert the title `Text` widget has the overflow guard:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/services/database/database.dart';
  import 'package:nooka/l10n/app_localizations.dart';
  import 'package:nooka/ui/home/widgets/task_row_content.dart';

  // Field names + required createdAt match the generated `Task` data class.
  Task _task({DateTime? archivedAt}) => Task(
    id: 1,
    categoryId: 1,
    name: 'A very very very long task name that would overflow the row badly',
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
    archivedAt: archivedAt,
  );

  Widget _host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  void main() {
    testWidgets('long title is clipped to two lines with ellipsis', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          TaskRowContent(
            task: _task(),
            color: const Color(0xFF009688),
            now: DateTime(2026, 6, 20),
            onTaskTap: (_) {},
            onTaskMenu: null,
          ),
        ),
      );
      final title = tester.widget<Text>(find.text(_task().name));
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
    });
  }
  ```

  Note: this test already constructs `TaskRowContent` **without** the `archived`
  param (removed in Task 6). Land Task 6 first, or temporarily pass
  `archived: false` here and drop it in Task 6. The plan sequences Task 6 (L3,
  param removal) so consider swapping their order if simpler; either is fine as
  long as the suite is green per task. Adjust the `Task(...)` constructor field
  names to match `database.g.dart`.

- [ ] **Step 2: Run it to verify it fails**

  Run: `flutter test test/ui/task_row_content_test.dart`
  Expected: FAIL — the title `Text` currently has `maxLines == null`.

- [ ] **Step 3: Add the overflow guard**

  In `lib/ui/home/widgets/task_row_content.dart`, change the title (line 47):

  ```dart
  title: Text(task.name, maxLines: 2, overflow: TextOverflow.ellipsis),
  ```

- [ ] **Step 4: Run it to verify it passes**

  Run: `flutter test test/ui/task_row_content_test.dart`
  Expected: PASS.

- [ ] **Step 5: Lint + commit**

  ```bash
  just lint
  git add lib/ui/home/widgets/task_row_content.dart test/ui/task_row_content_test.dart
  git commit -m "fix: clip long task titles to two lines

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 5: L3 — derive `archived` from the type in `TaskRowContent`; remove the param

**Files:**
- Modify: `lib/ui/home/widgets/task_row_content.dart`
- Modify: `lib/ui/home/home_screen.dart`
- Modify: `lib/ui/home/widgets/category_section.dart`
- Test: `test/ui/task_row_content_test.dart`

Remove the `archived` constructor parameter and derive it from
`task.archivedAt != null`, making the `archivedAt!` unwraps type-safe. Update
both call sites.

- [ ] **Step 1: Write the failing test — archived state follows the model**

  Append to `test/ui/task_row_content_test.dart`:

  ```dart
  testWidgets('active task (archivedAt null) shows radio and no subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TaskRowContent(
          task: _task(),
          color: const Color(0xFF009688),
          now: DateTime(2026, 6, 20),
          onTaskTap: (_) {},
          onTaskMenu: null,
        ),
      ),
    );
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.textContaining('Auto-removes in'), findsNothing);
  });

  testWidgets('archived task (archivedAt set) shows check_circle + subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TaskRowContent(
          task: _task(archivedAt: DateTime(2026, 6, 1)),
          color: const Color(0xFF009688),
          now: DateTime(2026, 6, 20),
          onTaskTap: (_) {},
          onTaskMenu: null,
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    expect(find.textContaining('Auto-removes in'), findsOneWidget);
  });

  testWidgets('tapping the row fires onTaskTap with the task', (tester) async {
    Task? tapped;
    await tester.pumpWidget(
      _host(
        TaskRowContent(
          task: _task(),
          color: const Color(0xFF009688),
          now: DateTime(2026, 6, 20),
          onTaskTap: (t) => tapped = t,
          onTaskMenu: null,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('task-1')));
    expect(tapped?.id, 1);
  });
  ```

  These calls construct `TaskRowContent` with **no** `archived` argument.

- [ ] **Step 2: Run it to verify it fails to compile**

  Run: `flutter test test/ui/task_row_content_test.dart`
  Expected: FAIL — `archived` is still a required parameter, so the test does
  not compile (missing required argument).

- [ ] **Step 3: Remove the param and derive it internally**

  In `lib/ui/home/widgets/task_row_content.dart`: delete the `required this.archived,`
  line from the constructor and the `final bool archived;` field, then derive it
  at the top of `build`:

  ```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final archived = task.archivedAt != null;
    return ListTile(
      // ...unchanged; `archived` now comes from the line above...
  ```

  Update the doc comment's mention of the param if needed.

- [ ] **Step 4: Update both call sites**

  In `lib/ui/home/home_screen.dart` `_dragList` (~line 226), drop the
  `archived: false,` line from the `TaskRowContent(...)` call.

  In `lib/ui/home/widgets/category_section.dart` (~line 76), drop the
  `archived: archived,` line from the `TaskRowContent(...)` call. Keep the
  `CategorySection.archived` field and its other uses (empty-state text line 64,
  the `if (archived) return tile;` Dismissible branch line 80) — only the row
  no longer receives it.

- [ ] **Step 5: Run the new test + full suite**

  Run: `flutter test test/ui/task_row_content_test.dart` then `just test`
  Expected: PASS. The archive-view tests in `home_screen_test.dart` (check_circle,
  countdown) still pass because archived tasks have non-null `archivedAt`.

- [ ] **Step 6: Lint + commit**

  ```bash
  just lint
  git add lib/ui/home/widgets/task_row_content.dart lib/ui/home/home_screen.dart \
    lib/ui/home/widgets/category_section.dart test/ui/task_row_content_test.dart
  git commit -m "fix: derive archived state from task.archivedAt, drop archived param

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 6: Coverage — `category_header_content` widget tests

**Files:**
- Test: `test/ui/category_header_content_test.dart`

Pure coverage for the extracted header widget: renders name + count + emoji,
fires its two callbacks.

- [ ] **Step 1: Write the tests**

  Create `test/ui/category_header_content_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/services/database/database.dart';
  import 'package:nooka/l10n/app_localizations.dart';
  import 'package:nooka/ui/home/widgets/category_header_content.dart';

  Category _cat({String? emoji}) => Category(
    id: 7,
    name: 'Home',
    color: 0xFF009688,
    emoji: emoji,
    collapsed: false,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  Widget _host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  void main() {
    testWidgets('renders name, count, and emoji; fires callbacks', (
      tester,
    ) async {
      var toggled = 0;
      var menu = 0;
      await tester.pumpWidget(
        _host(
          CategoryHeaderContent(
            category: _cat(emoji: '🏠'),
            taskCount: 3,
            onToggleCollapsed: () => toggled++,
            onHeaderMenu: () => menu++,
          ),
        ),
      );
      expect(find.textContaining('🏠 Home'), findsOneWidget);
      expect(find.textContaining('3 items'), findsOneWidget);

      await tester.tap(find.byKey(const Key('category-header-7')));
      expect(toggled, 1);

      await tester.tap(find.byKey(const Key('category-menu-7')));
      expect(menu, 1);
    });
  }
  ```

  (Match the `Category` constructor field names to `database.g.dart`.)

- [ ] **Step 2: Run it**

  Run: `flutter test test/ui/category_header_content_test.dart`
  Expected: PASS (the widget already exists; this is coverage only).

- [ ] **Step 3: Lint + commit**

  ```bash
  just lint
  git add test/ui/category_header_content_test.dart
  git commit -m "test: cover category_header_content rendering and callbacks

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 7: Coverage — `category_section` widget tests

**Files:**
- Test: `test/ui/category_section_test.dart`

Pure coverage for the section widget in both active and archived modes.

- [ ] **Step 1: Write the tests**

  Create `test/ui/category_section_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/services/database/database.dart';
  import 'package:nooka/l10n/app_localizations.dart';
  import 'package:nooka/ui/home/widgets/category_section.dart';

  Category _cat() => Category(
    id: 1,
    name: 'Home',
    color: 0xFF009688,
    emoji: null,
    collapsed: false,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  Task _task(int id, String name, {DateTime? archivedAt}) => Task(
    id: id,
    categoryId: 1,
    name: name,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
    archivedAt: archivedAt,
  );

  Widget _host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: ListView(children: [child])),
  );

  void main() {
    testWidgets('active section renders rows and fires tap + toggle', (
      tester,
    ) async {
      var tapped = 0;
      var toggled = 0;
      await tester.pumpWidget(
        _host(
          CategorySection(
            category: _cat(),
            tasks: [_task(1, 'Sweep')],
            archived: false,
            now: DateTime(2026, 6, 20),
            onToggleCollapsed: () => toggled++,
            onHeaderMenu: () {},
            onTaskTap: (_) => tapped++,
            onTaskMenu: (_) {},
          ),
        ),
      );
      expect(find.text('Sweep'), findsOneWidget);

      await tester.tap(find.byKey(const Key('category-header-1')));
      expect(toggled, 1);

      await tester.tap(find.byKey(const Key('task-1')));
      expect(tapped, 1);
    });

    testWidgets('archived section shows the countdown subtitle, no menu', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          CategorySection(
            category: _cat(),
            tasks: [_task(1, 'Sweep', archivedAt: DateTime(2026, 6, 1))],
            archived: true,
            now: DateTime(2026, 6, 20),
            onToggleCollapsed: () {},
            onHeaderMenu: () {},
            onTaskTap: (_) {},
            onTaskMenu: null,
          ),
        ),
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.textContaining('Auto-removes in'), findsOneWidget);
      expect(find.byKey(const Key('task-menu-1')), findsNothing);
    });
  }
  ```

- [ ] **Step 2: Run it**

  Run: `flutter test test/ui/category_section_test.dart`
  Expected: PASS.

- [ ] **Step 3: Lint + commit**

  ```bash
  just lint
  git add test/ui/category_section_test.dart
  git commit -m "test: cover category_section active and archived rendering

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 8: Coverage — `task_dialog` confirm/cancel + `confirm_delete_dialog`

**Files:**
- Test: `test/ui/task_dialog_test.dart`
- Test: `test/ui/confirm_delete_dialog_test.dart`

Round out dialog coverage: `_TaskDialog` returns a result on confirm and null on
cancel; the two confirm-delete dialogs return true/false.

- [ ] **Step 1: Add the `showTaskDialog` confirm/cancel tests**

  Append to `test/ui/task_dialog_test.dart` (reuse `_host` and `_cat`):

  ```dart
  testWidgets('showTaskDialog returns the result on confirm', (tester) async {
    TaskDialogResult? result;
    await tester.pumpWidget(
      _host(
        (context) async {
          result = await showTaskDialog(
            context,
            categories: [_cat(1, 'Home')],
            initialCategoryId: 1,
          );
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('task-name-field')), 'Sweep');
    await tester.tap(find.byKey(const Key('task-confirm')));
    await tester.pumpAndSettle();
    expect(result?.name, 'Sweep');
    expect(result?.categoryId, 1);
  });

  testWidgets('showTaskDialog returns null on cancel', (tester) async {
    Object? sentinel = 'unset';
    await tester.pumpWidget(
      _host(
        (context) async {
          sentinel = await showTaskDialog(
            context,
            categories: [_cat(1, 'Home')],
            initialCategoryId: 1,
          );
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sentinel, isNull);
  });
  ```

  (`_host`'s `onOpen` is `Widget Function(BuildContext)` returning the dialog
  future in Task 2; widen it to accept an async `void` callback, or add a second
  host helper that ignores the return — adjust `_host` to
  `void Function(BuildContext)` so both `showQuickAddDialog` and these awaited
  calls fit.)

- [ ] **Step 2: Create `confirm_delete_dialog_test.dart`**

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/l10n/app_localizations.dart';
  import 'package:nooka/ui/widgets/confirm_delete_dialog.dart';

  Widget _host(Future<void> Function(BuildContext) onOpen) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => onOpen(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  void main() {
    testWidgets('confirmDeleteCategory returns true on confirm', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        _host((context) async {
          answer = await confirmDeleteCategory(context, name: 'Home', itemCount: 2);
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    testWidgets('confirmDeleteCategory returns false on cancel', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        _host((context) async {
          answer = await confirmDeleteCategory(context, name: 'Home', itemCount: 2);
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('confirmClearArchive returns true on confirm', (tester) async {
      bool? answer;
      await tester.pumpWidget(
        _host((context) async {
          answer = await confirmClearArchive(context, count: 3);
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-clear-archive')));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });
  }
  ```

- [ ] **Step 2b: Run them**

  Run: `flutter test test/ui/task_dialog_test.dart test/ui/confirm_delete_dialog_test.dart`
  Expected: PASS.

- [ ] **Step 3: Lint + commit**

  ```bash
  just lint
  git add test/ui/task_dialog_test.dart test/ui/confirm_delete_dialog_test.dart
  git commit -m "test: cover task dialog confirm/cancel and confirm-delete dialogs

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 9: Full suite, lint, manual smoke, and PR

**Files:**
- (no source changes; verification + PR)

- [ ] **Step 1: Whole suite + lint**

  Run: `just test` then `just lint`
  Expected: all green; lint clean.

- [ ] **Step 2: Manual smoke**

  Run: `flutter run`. In the Active view, verify:
  - Drag a task onto a **collapsed** category → that category expands and the
    task is visible at the drop position.
  - Type a name, double-tap **Add** fast → exactly one task is created.
  - The Add/Save button is greyed out for an empty or whitespace-only name.
  - A name pasted longer than 100 chars is truncated; a long name shows two
    lines with an ellipsis in the row.
  - Archive view rows still show the check_circle + countdown unchanged.

- [ ] **Step 3: Open the PR**

  Push `fix/hardening-drag-dialogs` and open a PR titled
  `fix: harden drag board and dialogs (H3/H4/H5/M3/L3/L5)`. On merge, set this
  bundle's `design.md`/`plan.md` frontmatter to `status: shipped` with `pr:` /
  `outcome:`, and run `just index`.

---

## Self-review

- **Finding coverage:** H4+H3 via a pure `planReorder` in
  `lib/domain/board_reorder.dart`, unit-tested in `test/domain/board_reorder_test.dart`
  (T1), H5+L5 (T2), M3 button-enable + length-cap
  (T3), M3 title overflow (T4), L3 param removal (T5); coverage gaps —
  category_header_content (T6), category_section (T7), task_dialog confirm/cancel
  + confirm_delete_dialog (T8); task_row_content coverage folded into T4/T5.
  Verify + PR (T9).
- **Signature changes:** `TaskRowContent` loses its `archived` bool param
  (T5) — both call sites (`home_screen.dart` `_dragList`,
  `category_section.dart`) updated in the same task. `_onItemReorder` drops its
  `cats` parameter (T1) and re-reads state internally; the `_board` closure is
  updated.
- **New constant:** `kMaxNameLength = 100` (top of `task_dialog.dart`), reused
  by `category_dialog.dart`.
- **Bundle A dependency:** T1 routes `reorderTasks` / `moveTaskToCategoryAt` /
  `toggleCollapsed` through `_guard`; if `_guard` is undefined at lint, Bundle A
  has not landed — rebase first.
- **No ARB changes** in this bundle.
- **Placeholder scan:** every code/edit step carries concrete code from the
  actual source or an exact command; constructor field names for the generated
  `Category`/`Task` Drift rows are flagged to verify against `database.g.dart`.
