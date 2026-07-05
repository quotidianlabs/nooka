# Recurrence at creation — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recurrence can be set when creating a task: the quick-add dialog
gains the Repeat control (extracted into a shared, touch-friendly widget also
used by the edit dialog), and the create path carries the optional recurrence
pair end to end.

**Spec:** [`design.md`](./design.md)

**Branch:** `recurrence-at-creation` (already created; the design commit is on
it)

**Commit strategy:** Per-task commits. TDD — a failing test precedes each code
change.

## Global Constraints

- Stack: Flutter, Riverpod (`@riverpod` codegen), Drift (SQLite), gen-l10n.
- All imports at module level, never inside function bodies. Annotate every
  function argument (user rule).
- **No schema change, no migration, no new l10n strings** in this change. If
  you think you need one, stop — re-read the spec.
- No `build_runner` run is expected: no `@riverpod` provider signatures, table
  definitions, or `.arb` files change. (Adding optional named parameters to
  `HomeViewModel` methods does not alter the generated provider.)
- The recurrence pair invariant: `recurrenceCount` and `recurrenceUnit` are
  both null or both non-null. Callers guarantee it via
  `_repeat ? _count : null` for both; no new validation layer.
- Test keys are load-bearing: `task-repeat-toggle`, `task-repeat-stepper`,
  `task-repeat-unit` must keep exactly these names.
- Final gate before every commit: `just lint-ci` clean (NOT `just lint`, which
  reformats in place and can leave a dirty tree), then `just test`.
- Architecture promotion rides in this same PR (Task 5), never as a follow-up.

---

### Task 1: DAO — `createTask` accepts recurrence

**Files:**
- Modify: `lib/data/services/database/todo_dao.dart:92-104`
- Test: `test/data/todo_dao_test.dart`

**Interfaces:**
- Consumes: existing nullable columns `recurrenceCount` (`IntColumn`) and
  `recurrenceUnit` (`intEnum<RecurrenceUnit>`) on the `Tasks` table; `Value`
  from drift (already imported in the DAO).
- Produces: `Future<int> TodoDao.createTask({required int categoryId,
  required String name, int? recurrenceCount, RecurrenceUnit? recurrenceUnit})`
  — Task 2 calls this from the repository.

- [ ] **Step 1: Write the failing test**

  In `test/data/todo_dao_test.dart` (imports for `Value`, `RecurrenceUnit`,
  and the db are already at the top of the file), add a new top-level group
  inside `main()`:

  ```dart
  group('createTask recurrence', () {
    test('persists count and unit when given', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final id = await db.todoDao.createTask(
        categoryId: cat,
        name: 'Water plants',
        recurrenceCount: 2,
        recurrenceUnit: RecurrenceUnit.weeks,
      );
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.recurrenceCount, 2);
      expect(row.recurrenceUnit, RecurrenceUnit.weeks);
    });

    test('leaves both null when omitted', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final id = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.recurrenceCount, isNull);
      expect(row.recurrenceUnit, isNull);
    });
  });
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `flutter test test/data/todo_dao_test.dart`
  Expected: FAIL — compile error, `No named parameter with the name
  'recurrenceCount'` on `createTask`.

- [ ] **Step 3: Write the implementation**

  In `lib/data/services/database/todo_dao.dart`, replace the existing
  `createTask` (lines 92–104) with:

  ```dart
  Future<int> createTask({
    required int categoryId,
    required String name,
    int? recurrenceCount,
    RecurrenceUnit? recurrenceUnit,
  }) async {
    return into(tasks).insert(
      TasksCompanion.insert(
        categoryId: categoryId,
        name: name,
        sortOrder: await _nextTaskOrder(categoryId),
        createdAt: DateTime.now(),
        recurrenceCount: Value(recurrenceCount),
        recurrenceUnit: Value(recurrenceUnit),
      ),
    );
  }
  ```

  (`Value(...)` on both, matching `renameAndMove` directly above it — an
  explicit null write equals absent on insert for these nullable columns.)

- [ ] **Step 4: Run test to verify it passes**

  Run: `flutter test test/data/todo_dao_test.dart`
  Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

  ```bash
  just lint-ci && just test
  git add lib/data/services/database/todo_dao.dart test/data/todo_dao_test.dart
  git commit -m "feat(db): createTask accepts optional recurrence"
  ```

---

### Task 2: Repository and view model forward recurrence

**Files:**
- Modify: `lib/data/repositories/todo_repository.dart:48-49`
- Modify: `lib/ui/home/home_view_model.dart:114-124`
- Test: `test/data/todo_repository_passthrough_test.dart`
- Test: `test/ui/home_view_model_test.dart` (also fix the
  `_ThrowingCreateTaskRepo` override at its top)

**Interfaces:**
- Consumes: `TodoDao.createTask({required int categoryId, required String
  name, int? recurrenceCount, RecurrenceUnit? recurrenceUnit})` from Task 1.
- Produces: `Future<int> TodoRepository.createTask({required int categoryId,
  required String name, int? recurrenceCount, RecurrenceUnit? recurrenceUnit})`
  and `Future<CommandOutcome> HomeViewModel.addTask(int categoryId, String
  name, {int? recurrenceCount, RecurrenceUnit? recurrenceUnit})` — Task 4's
  call sites in `home_screen.dart` use the latter.

- [ ] **Step 1: Write the failing tests**

  In `test/data/todo_repository_passthrough_test.dart`, add to the imports:

  ```dart
  import 'package:nooka/domain/recurrence.dart';
  ```

  and add inside `main()`:

  ```dart
  test('createTask passes recurrence through to the DAO', () async {
    final cat = await repo.createCategory(name: 'Home', color: 1);
    final t = await repo.createTask(
      categoryId: cat,
      name: 'Water plants',
      recurrenceCount: 2,
      recurrenceUnit: RecurrenceUnit.weeks,
    );

    final row = await (db.select(
      db.tasks,
    )..where((r) => r.id.equals(t))).getSingle();
    expect(row.recurrenceCount, 2);
    expect(row.recurrenceUnit, RecurrenceUnit.weeks);
  });
  ```

  In `test/ui/home_view_model_test.dart` (`RecurrenceUnit` is already
  imported there), add inside the `addTask remembered-category (M4)` group:

  ```dart
  test('addTask forwards recurrence to the repository', () async {
    final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
    final (_, vm) = await build();

    final outcome = await vm.addTask(
      cat,
      'Water plants',
      recurrenceCount: 2,
      recurrenceUnit: RecurrenceUnit.weeks,
    );

    expect(outcome, CommandOutcome.success);
    final cats = await snapshot();
    final task = cats.single.tasks.single;
    expect(task.recurrenceCount, 2);
    expect(task.recurrenceUnit, RecurrenceUnit.weeks);
  });
  ```

- [ ] **Step 2: Run tests to verify they fail**

  Run: `flutter test test/data/todo_repository_passthrough_test.dart test/ui/home_view_model_test.dart`
  Expected: FAIL — compile errors, `No named parameter with the name
  'recurrenceCount'` on `repo.createTask` and `vm.addTask`.

- [ ] **Step 3: Write the implementation**

  In `lib/data/repositories/todo_repository.dart`, replace `createTask`
  (lines 48–49) with:

  ```dart
  Future<int> createTask({
    required int categoryId,
    required String name,
    int? recurrenceCount,
    RecurrenceUnit? recurrenceUnit,
  }) => _dao.createTask(
    categoryId: categoryId,
    name: name,
    recurrenceCount: recurrenceCount,
    recurrenceUnit: recurrenceUnit,
  );
  ```

  In `lib/ui/home/home_view_model.dart`, replace `addTask` (lines 114–124)
  with (doc comment kept):

  ```dart
  /// Adds a task and, on success, remembers its category as the quick-add
  /// default. A failed add never persists the remembered category.
  Future<CommandOutcome> addTask(
    int categoryId,
    String name, {
    int? recurrenceCount,
    RecurrenceUnit? recurrenceUnit,
  }) async {
    final outcome = await _run(
      () => _repo.createTask(
        categoryId: categoryId,
        name: name,
        recurrenceCount: recurrenceCount,
        recurrenceUnit: recurrenceUnit,
      ),
    );
    if (outcome == CommandOutcome.success) {
      await _bestEffort(() => _remembered.write(categoryId));
    }
    return outcome;
  }
  ```

  In `test/ui/home_view_model_test.dart`, the `_ThrowingCreateTaskRepo`
  override no longer matches the superclass — replace it with:

  ```dart
  /// createTask always throws; everything else (incl. the watch stream) is the
  /// real DAO so the board still loads.
  class _ThrowingCreateTaskRepo extends TodoRepository {
    _ThrowingCreateTaskRepo(super.dao);
    @override
    Future<int> createTask({
      required int categoryId,
      required String name,
      int? recurrenceCount,
      RecurrenceUnit? recurrenceUnit,
    }) => Future.error(Exception('db locked'));
  }
  ```

- [ ] **Step 4: Run tests to verify they pass**

  Run: `flutter test test/data/todo_repository_passthrough_test.dart test/ui/home_view_model_test.dart`
  Expected: PASS (all tests in both files).

- [ ] **Step 5: Commit**

  ```bash
  just lint-ci && just test
  git add lib/data/repositories/todo_repository.dart lib/ui/home/home_view_model.dart \
    test/data/todo_repository_passthrough_test.dart test/ui/home_view_model_test.dart
  git commit -m "feat(home): addTask forwards recurrence to the create path"
  ```

---

### Task 3: Shared `RepeatField` widget; edit dialog swaps to it

**Files:**
- Create: `lib/ui/widgets/repeat_field.dart`
- Modify: `lib/ui/widgets/task_dialog.dart:116-168` (the `SwitchListTile` +
  `if (_repeat)` block inside `_TaskDialogState.build`)
- Test: create `test/ui/repeat_field_test.dart`
- Regression gate: `test/ui/task_dialog_test.dart` and
  `test/ui/dialog_edge_cases_test.dart` must stay green untouched.

**Interfaces:**
- Consumes: `RecurrenceUnit` (`lib/domain/recurrence.dart`); l10n getters
  `repeatLabel`, `recurrenceUnitDays`, `recurrenceUnitWeeks`,
  `recurrenceUnitMonths`, `recurrenceSummary(count, unitName)` (all exist).
- Produces: `RepeatField({required bool repeat, required int count, required
  RecurrenceUnit unit, required void Function(bool repeat, int count,
  RecurrenceUnit unit) onChanged})` — a controlled widget; Task 4 embeds it in
  the quick-add dialog.

- [ ] **Step 1: Write the failing test**

  Create `test/ui/repeat_field_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/domain/recurrence.dart';
  import 'package:nooka/l10n/app_localizations.dart';
  import 'package:nooka/ui/widgets/repeat_field.dart';

  Widget _host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  void main() {
    testWidgets('off: only the toggle shows; switching on reports the change', (
      tester,
    ) async {
      (bool, int, RecurrenceUnit)? reported;
      await tester.pumpWidget(
        _host(
          RepeatField(
            repeat: false,
            count: 1,
            unit: RecurrenceUnit.days,
            onChanged: (bool repeat, int count, RecurrenceUnit unit) =>
                reported = (repeat, count, unit),
          ),
        ),
      );

      expect(find.byKey(const Key('task-repeat-toggle')), findsOneWidget);
      expect(find.byKey(const Key('task-repeat-stepper')), findsNothing);
      expect(find.byKey(const Key('task-repeat-unit')), findsNothing);

      await tester.tap(find.byKey(const Key('task-repeat-toggle')));
      expect(reported, (true, 1, RecurrenceUnit.days));
    });

    testWidgets('on: minus is disabled at count 1; plus reports count+1', (
      tester,
    ) async {
      (bool, int, RecurrenceUnit)? reported;
      await tester.pumpWidget(
        _host(
          RepeatField(
            repeat: true,
            count: 1,
            unit: RecurrenceUnit.days,
            onChanged: (bool repeat, int count, RecurrenceUnit unit) =>
                reported = (repeat, count, unit),
          ),
        ),
      );

      final minus = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.byIcon(Icons.remove),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(minus.onPressed, isNull);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('task-repeat-stepper')),
          matching: find.byIcon(Icons.add),
        ),
      );
      expect(reported, (true, 2, RecurrenceUnit.days));
    });

    testWidgets('on: minus reports count-1 when count > 1', (tester) async {
      (bool, int, RecurrenceUnit)? reported;
      await tester.pumpWidget(
        _host(
          RepeatField(
            repeat: true,
            count: 3,
            unit: RecurrenceUnit.days,
            onChanged: (bool repeat, int count, RecurrenceUnit unit) =>
                reported = (repeat, count, unit),
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('task-repeat-stepper')),
          matching: find.byIcon(Icons.remove),
        ),
      );
      expect(reported, (true, 2, RecurrenceUnit.days));
    });

    testWidgets('unit selection reports the new unit, keeping the count', (
      tester,
    ) async {
      (bool, int, RecurrenceUnit)? reported;
      await tester.pumpWidget(
        _host(
          RepeatField(
            repeat: true,
            count: 2,
            unit: RecurrenceUnit.days,
            onChanged: (bool repeat, int count, RecurrenceUnit unit) =>
                reported = (repeat, count, unit),
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('task-repeat-unit')),
          matching: find.text('Weeks'),
        ),
      );
      expect(reported, (true, 2, RecurrenceUnit.weeks));
    });
  }
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `flutter test test/ui/repeat_field_test.dart`
  Expected: FAIL — compile error, `repeat_field.dart` does not exist.

- [ ] **Step 3: Write the implementation**

  Create `lib/ui/widgets/repeat_field.dart`:

  ```dart
  import 'package:flutter/material.dart';

  import '../../domain/recurrence.dart';
  import '../../l10n/app_localizations.dart';

  /// The Repeat section shared by the quick-add and edit task dialogs: an
  /// on/off switch and, when on, a count stepper and a unit selector, all
  /// full-width rows with 48px touch targets. Controlled: the parent owns
  /// the state and receives every change through [onChanged].
  class RepeatField extends StatelessWidget {
    const RepeatField({
      super.key,
      required this.repeat,
      required this.count,
      required this.unit,
      required this.onChanged,
    });

    final bool repeat;
    final int count;
    final RecurrenceUnit unit;
    final void Function(bool repeat, int count, RecurrenceUnit unit) onChanged;

    @override
    Widget build(BuildContext context) {
      final l10n = AppLocalizations.of(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            key: const Key('task-repeat-toggle'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.repeatLabel),
            value: repeat,
            onChanged: (v) => onChanged(v, count, unit),
          ),
          if (repeat) ...[
            Row(
              key: const Key('task-repeat-stepper'),
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: count > 1
                        ? () => onChanged(repeat, count - 1, unit)
                        : null,
                    child: const Icon(Icons.remove),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => onChanged(repeat, count + 1, unit),
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<RecurrenceUnit>(
                key: const Key('task-repeat-unit'),
                style: SegmentedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                segments: [
                  ButtonSegment(
                    value: RecurrenceUnit.days,
                    label: Text(l10n.recurrenceUnitDays),
                  ),
                  ButtonSegment(
                    value: RecurrenceUnit.weeks,
                    label: Text(l10n.recurrenceUnitWeeks),
                  ),
                  ButtonSegment(
                    value: RecurrenceUnit.months,
                    label: Text(l10n.recurrenceUnitMonths),
                  ),
                ],
                selected: {unit},
                showSelectedIcon: false,
                onSelectionChanged: (s) => onChanged(repeat, count, s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.recurrenceSummary(count, unit.name),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      );
    }
  }
  ```

- [ ] **Step 4: Run test to verify it passes**

  Run: `flutter test test/ui/repeat_field_test.dart`
  Expected: PASS.

- [ ] **Step 5: Swap the edit dialog onto the shared widget**

  In `lib/ui/widgets/task_dialog.dart`, add to the imports:

  ```dart
  import 'repeat_field.dart';
  ```

  Then replace the whole repeat section inside `_TaskDialogState.build` —
  from the `SwitchListTile(` with key `task-repeat-toggle` (line 116) through
  the closing `],` of the `if (_repeat) ...[` block (line 168) — with:

  ```dart
  RepeatField(
    repeat: _repeat,
    count: _count,
    unit: _unit,
    onChanged: (bool repeat, int count, RecurrenceUnit unit) => setState(() {
      _repeat = repeat;
      _count = count;
      _unit = unit;
    }),
  ),
  ```

  The `_repeat`/`_count`/`_unit` state fields and the result-building logic
  in the confirm button stay exactly as they are.

- [ ] **Step 6: Run the dialog regression tests**

  Run: `flutter test test/ui/task_dialog_test.dart test/ui/dialog_edge_cases_test.dart`
  Expected: PASS — every existing test, unmodified (the three keys and the
  segment labels are unchanged).

- [ ] **Step 7: Commit**

  ```bash
  just lint-ci && just test
  git add lib/ui/widgets/repeat_field.dart lib/ui/widgets/task_dialog.dart \
    test/ui/repeat_field_test.dart
  git commit -m "feat(ui): shared RepeatField with 48px touch targets"
  ```

---

### Task 4: Quick-add gains the Repeat control, resetting after each add

**Files:**
- Modify: `lib/ui/widgets/task_dialog.dart` (`showQuickAddDialog`,
  `_QuickAddDialog`, `_QuickAddDialogState` — lines 200-313 pre-Task-3)
- Modify: `lib/ui/home/home_screen.dart:334-341` and `:406-411` (both
  `showQuickAddDialog` call sites)
- Test: `test/ui/task_dialog_test.dart` (one new test; three existing `onAdd`
  lambdas gain two parameters)
- Test: `test/ui/dialog_edge_cases_test.dart` (one existing `onAdd` lambda
  gains two parameters)

**Interfaces:**
- Consumes: `RepeatField` (Task 3); `HomeViewModel.addTask(categoryId, name,
  {recurrenceCount, recurrenceUnit})` (Task 2).
- Produces: `showQuickAddDialog(..., onAdd: Future<void> Function(String name,
  int categoryId, int? recurrenceCount, RecurrenceUnit? recurrenceUnit))` —
  the final public shape; nothing later depends on it.

- [ ] **Step 1: Write the failing test**

  In `test/ui/task_dialog_test.dart`, add inside `main()`:

  ```dart
  testWidgets('quick-add passes recurrence and resets Repeat after each add', (
    tester,
  ) async {
    final added = <(String, int?, RecurrenceUnit?)>[];
    await tester.pumpWidget(
      _host(
        (context) => showQuickAddDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
          onAdd:
              (
                String name,
                int categoryId,
                int? recurrenceCount,
                RecurrenceUnit? recurrenceUnit,
              ) async {
                added.add((name, recurrenceCount, recurrenceUnit));
              },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Repeat every 2 weeks.
    await tester.tap(find.byKey(const Key('task-repeat-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('task-repeat-stepper')),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('task-repeat-unit')),
        matching: find.text('Weeks'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('quick-add-field')),
      'Water plants',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pumpAndSettle();

    expect(added.single, ('Water plants', 2, RecurrenceUnit.weeks));
    // Repeat reset to off for the next entry: the stepper is gone again.
    expect(find.byKey(const Key('task-repeat-stepper')), findsNothing);

    // A second add without touching Repeat passes nulls.
    await tester.enterText(find.byKey(const Key('quick-add-field')), 'Milk');
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pumpAndSettle();
    expect(added.last, ('Milk', null, null));
  });
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `flutter test test/ui/task_dialog_test.dart`
  Expected: FAIL — compile error: the `onAdd` lambda has four parameters but
  `showQuickAddDialog` expects two.

- [ ] **Step 3: Write the implementation**

  In `lib/ui/widgets/task_dialog.dart`, replace everything from the
  `showQuickAddDialog` doc comment to the end of `_QuickAddDialogState`
  with:

  ```dart
  /// Keep-keyboard-open quick add. Calls [onAdd] for each item; the field clears
  /// and refocuses after every Add so several items can be entered in a row. The
  /// dialog stays open until the user taps Done. [onAdd] receives the chosen
  /// category so the caller can remember it as the new default, plus the chosen
  /// recurrence (null/null when Repeat is off). Repeat resets to off after each
  /// add — recurrence is per-item, never sticky — while the category persists.
  Future<void> showQuickAddDialog(
    BuildContext context, {
    required List<Category> categories,
    required int initialCategoryId,
    required Future<void> Function(
      String name,
      int categoryId,
      int? recurrenceCount,
      RecurrenceUnit? recurrenceUnit,
    )
    onAdd,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _QuickAddDialog(
        categories: categories,
        initialCategoryId: initialCategoryId,
        onAdd: onAdd,
      ),
    );
  }

  class _QuickAddDialog extends StatefulWidget {
    const _QuickAddDialog({
      required this.categories,
      required this.initialCategoryId,
      required this.onAdd,
    });
    final List<Category> categories;
    final int initialCategoryId;
    final Future<void> Function(
      String name,
      int categoryId,
      int? recurrenceCount,
      RecurrenceUnit? recurrenceUnit,
    )
    onAdd;

    @override
    State<_QuickAddDialog> createState() => _QuickAddDialogState();
  }

  class _QuickAddDialogState extends State<_QuickAddDialog> {
    final TextEditingController _name = TextEditingController();
    final FocusNode _focus = FocusNode();
    late int _categoryId = widget.initialCategoryId;
    bool _repeat = false;
    int _count = 1;
    RecurrenceUnit _unit = RecurrenceUnit.days;
    bool _busy = false;

    @override
    void initState() {
      super.initState();
      _name.addListener(() => setState(() {}));
    }

    @override
    void dispose() {
      _name.dispose();
      _focus.dispose();
      super.dispose();
    }

    Future<void> _submit() async {
      if (_busy) return;
      final name = _name.text.trim();
      if (name.isEmpty) return;
      _busy = true;
      final recurrenceCount = _repeat ? _count : null;
      final recurrenceUnit = _repeat ? _unit : null;
      // Clear + reset synchronously, before the await: the name so the next
      // item can be typed immediately, Repeat so it never sticks to the next
      // item (recurring is the exception, not the default).
      _name.clear();
      setState(() {
        _repeat = false;
        _count = 1;
        _unit = RecurrenceUnit.days;
      });
      try {
        await widget.onAdd(name, _categoryId, recurrenceCount, recurrenceUnit);
      } finally {
        _busy = false;
      }
      if (!mounted) return; // L5: dialog may have been dismissed mid-await
      _focus.requestFocus(); // keep the keyboard up for the next item
    }

    @override
    Widget build(BuildContext context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.addTask),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('quick-add-field'),
              controller: _name,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(labelText: l10n.taskNameLabel),
              inputFormatters: [
                LengthLimitingTextInputFormatter(kMaxNameLength),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const Key('quick-add-category'),
              initialValue: _categoryId,
              decoration: InputDecoration(labelText: l10n.categoryLabel),
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
            ),
            const SizedBox(height: 8),
            RepeatField(
              repeat: _repeat,
              count: _count,
              unit: _unit,
              onChanged: (bool repeat, int count, RecurrenceUnit unit) =>
                  setState(() {
                    _repeat = repeat;
                    _count = count;
                    _unit = unit;
                  }),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('quick-add-done'),
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.done),
          ),
          TextButton(
            key: const Key('quick-add-confirm'),
            onPressed: (_busy || _name.text.trim().isEmpty) ? null : _submit,
            child: Text(l10n.add),
          ),
        ],
      );
    }
  }
  ```

  In `lib/ui/home/home_screen.dart`, update both call sites. In `_addTask`
  (lines 334–341):

  ```dart
  await showQuickAddDialog(
    context,
    categories: [for (final c in cats) c.category],
    initialCategoryId: initial,
    // addTask remembers the category on success; nothing to persist here.
    onAdd: (name, categoryId, recurrenceCount, recurrenceUnit) => _dispatch(
      _vm.addTask(
        categoryId,
        name,
        recurrenceCount: recurrenceCount,
        recurrenceUnit: recurrenceUnit,
      ),
    ),
  );
  ```

  and in `_categoryMenu`'s `case 'add':` (lines 406–411):

  ```dart
  await showQuickAddDialog(
    context,
    categories: [cwt.category],
    initialCategoryId: cwt.category.id,
    onAdd: (name, categoryId, recurrenceCount, recurrenceUnit) => _dispatch(
      _vm.addTask(
        categoryId,
        name,
        recurrenceCount: recurrenceCount,
        recurrenceUnit: recurrenceUnit,
      ),
    ),
  );
  ```

  Update the existing two-parameter `onAdd` lambdas in tests to the new
  four-parameter shape (behavior unchanged):

  - `test/ui/task_dialog_test.dart` — three sites:
    - `onAdd: (name, categoryId, recurrenceCount, recurrenceUnit) async { calls++; await gate.future; }`
    - `onAdd: (name, categoryId, recurrenceCount, recurrenceUnit) async {},`
    - `onAdd: (name, categoryId, recurrenceCount, recurrenceUnit) async => gate.future,`
  - `test/ui/dialog_edge_cases_test.dart` — one site:
    - ```dart
      onAdd: (name, categoryId, recurrenceCount, recurrenceUnit) async {
        addedName = name;
        addedCategory = categoryId;
      },
      ```

- [ ] **Step 4: Run tests to verify they pass**

  Run: `flutter test test/ui/task_dialog_test.dart test/ui/dialog_edge_cases_test.dart test/ui/home_screen_test.dart`
  Expected: PASS — the new test, all updated tests, and the home-screen
  suite (its quick-add flows go through the updated call sites).

- [ ] **Step 5: Commit**

  ```bash
  just lint-ci && just test
  git add lib/ui/widgets/task_dialog.dart lib/ui/home/home_screen.dart \
    test/ui/task_dialog_test.dart test/ui/dialog_edge_cases_test.dart
  git commit -m "feat(ui): recurrence in the quick-add dialog, reset per add"
  ```

---

### Task 5: Architecture promotion, bundle finalize, full gates

**Files:**
- Modify: `architecture/data-model.md`
- Modify: `architecture/home-coordination.md`
- Modify: `planning/changes/2026-07-05.01-recurrence-at-creation/design.md`
  (frontmatter `summary:` only)

**Interfaces:**
- Consumes: the shipped behavior from Tasks 1–4.
- Produces: nothing downstream; this is the ship gate.

- [ ] **Step 1: Promote into `architecture/data-model.md`**

  In the "Active / dormant / archived" section, the paragraph beginning
  "`recurrenceCount` + `recurrenceUnit` are set together" — after the first
  sentence (ending "independent of its current state;"), the pair's origin is
  now twofold. Replace the first sentence:

  ```
  `recurrenceCount` + `recurrenceUnit` are set together (both null ⇒ a
  non-recurring task) and mark a task as recurring independent of its current
  state; `nextDueAt` alone drives the active/dormant split.
  ```

  with:

  ```
  `recurrenceCount` + `recurrenceUnit` are set together (both null ⇒ a
  non-recurring task) and mark a task as recurring independent of its current
  state; they can be written at creation (`createTask` takes the optional
  pair) or by a later edit (`renameAndMove`). `nextDueAt` alone drives the
  active/dormant split.
  ```

- [ ] **Step 2: Promote into `architecture/home-coordination.md`**

  Replace the `addTask` bullet in "The intents:":

  ```
  - `addTask` — remembers its category as the quick-add default **on success**.
  ```

  with:

  ```
  - `addTask(categoryId, name, {recurrenceCount, recurrenceUnit})` — creates
    the task, recurring when the pair is given, and remembers its category as
    the quick-add default **on success**. The quick-add dialog's Repeat control
    (the shared `RepeatField`, also used by the edit dialog) resets to off
    after each successful add — recurrence is per-item, never sticky — while
    the chosen category persists for the next item.
  ```

- [ ] **Step 3: Finalize the bundle summary**

  In `planning/changes/2026-07-05.01-recurrence-at-creation/design.md`,
  set the frontmatter `summary:` to the realized result:

  ```yaml
  summary: Recurrence is now settable at creation — the quick-add dialog embeds the shared RepeatField (full-width rows, 48px targets, reset per add; same control replaces the edit dialog's cramped repeat row) and createTask carries the pair through VM → repository → DAO. No schema change.
  ```

- [ ] **Step 4: Run every gate**

  ```bash
  just lint-ci
  just test
  just coverage
  just check-planning
  ```

  Expected: all pass. If `just coverage` fails the gated percentage, add the
  missing test for whatever line the report names — do not lower the gate.

- [ ] **Step 5: Commit**

  ```bash
  git add architecture/data-model.md architecture/home-coordination.md \
    planning/changes/2026-07-05.01-recurrence-at-creation/design.md
  git commit -m "docs(architecture): promote recurrence-at-creation"
  ```

- [ ] **Step 6: Manual device check (before merge)**

  On a phone-sized profile (`flutter run`, narrowest supported device), open
  quick-add, toggle Repeat on: the dialog must not overflow and the stepper /
  unit rows must lay out full-width. This is the spec's named mitigation for
  the small-screen layout risk; note the result in the PR description.

---

## After the plan

Finish via `superpowers:finishing-a-development-branch`: push
`recurrence-at-creation`, open a PR to `main` (never local-merge), watch CI.
After merge: `git pull --ff-only` on `main`, delete the local branch,
`git remote prune origin`.
