---
status: shipped
date: 2026-06-20
slug: hardening-archive-and-coverage
spec: hardening-archive-and-coverage
pr: null
---

# hardening-archive-and-coverage — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the archive-and-ordering polish fixes (M1, L1, L4, M2, M4) and
close the remaining DAO / controller / flow coverage gaps the parent test pass
deferred to the fix bundles.

**Spec:** [`design.md`](./design.md)

**Branch:** `fix/hardening-archive-and-coverage`

**Commit strategy:** Per-task commits.

## Global Constraints

- Flutter, Dart SDK `^3.12.2`, Riverpod, Drift. Layered MVVM.
- `just lint` (`dart format` + `flutter analyze`) clean; `just test`
  (`flutter test`) green before any task is considered done.
- Generated `*.g.dart` is committed; run
  `dart run build_runner build --delete-conflicting-outputs` after touching
  `@riverpod`/Drift code (this bundle adds DAO + repo + view-model
  `updateCategory` methods → **regen required**) and commit the regenerated
  files.
- i18n in `app_en.arb` + `app_ru.arb` (Russian: four CLDR plural forms where
  plurals apply). This bundle adds **no** ARB keys — M1's ceil keeps the
  existing `autoRemovesIn` `=0` form valid.
- TDD: failing `flutter test` first, then minimal impl, green, commit.
  Per-task commits.
- Conventional commit subjects; commit body trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- **Depends on Bundle A** (executed first): the
  `Future<void> _guard(Future<void> Function() action)` helper on
  `_HomeScreenState`. M4's `addTask` and L4's `updateCategory` UI calls route
  through `_guard(() => _vm.xxx(...))`. If `_guard` is not yet present, call
  `_vm.xxx(...)` directly and leave a `// TODO(bundle-a): wrap in _guard` note.

---

### Task 1: M1 — ceil `daysRemaining`

**Files:**
- Modify: `lib/domain/archive.dart`
- Test: `test/domain/archive_test.dart`

Round the archive countdown's partial day up so a not-yet-expired item reports
`>= 1` and only an already-expired item reports `0`.

- [ ] **Step 1: Write the failing tests**

  In `test/domain/archive_test.dart`, inside `group('daysRemaining', ...)`
  (after the `never returns negative` test, before its closing `});`), add:

  ```dart
  test('a sliver of life left rounds up to 1, not down to 0', () {
    expect(
      daysRemaining(
        now.subtract(const Duration(days: 29, hours: 23)),
        now,
      ),
      1,
    );
  });
  test('exactly at expiry reports 0', () {
    expect(daysRemaining(now.subtract(const Duration(days: 30)), now), 0);
  });
  ```

- [ ] **Step 2: Run the tests to verify they fail**

  Run: `flutter test test/domain/archive_test.dart`
  Expected: FAIL — the 29d23h case returns `0` (truncation) instead of `1`.

- [ ] **Step 3: Implement the ceil**

  In `lib/domain/archive.dart`, replace the body of `daysRemaining` (lines
  14–18). Change the doc comment and the `remaining` computation:

  ```dart
  /// Whole days until an item archived at [archivedAt] is auto-removed, as of
  /// [now]. Rounds a partial day up, so a not-yet-expired item always reports
  /// at least 1; only an expired item reports 0. Clamped to 0; never negative.
  int daysRemaining(DateTime archivedAt, DateTime now) {
    final expiry = archivedAt.add(const Duration(days: archiveRetentionDays));
    final remaining =
        (expiry.difference(now).inMilliseconds / Duration.millisecondsPerDay)
            .ceil();
    return remaining < 0 ? 0 : remaining;
  }
  ```

- [ ] **Step 4: Run the tests to verify they pass**

  Run: `flutter test test/domain/archive_test.dart`
  Expected: PASS — including the existing `== 30`, `== 20`, `== 0` cases
  (exact-day boundaries ceil to themselves).

- [ ] **Step 5: Commit**

  ```bash
  git add lib/domain/archive.dart test/domain/archive_test.dart
  git commit -m "fix: ceil archive countdown so surviving items never show 0 days

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 2: L1 — deterministic DB ordering tiebreakers

**Files:**
- Modify: `lib/data/services/database/todo_dao.dart`
- Test: `test/data/todo_dao_test.dart`

Append `categories.id` and `tasks.id` as final `OrderingTerm`s so duplicate
`sortOrder` values order deterministically.

- [ ] **Step 1: Write the failing test**

  In `test/data/todo_dao_test.dart`, inside `group('reordering', ...)` (after
  the `moveTaskToCategoryAt` test, before the group's closing `});`), add:

  ```dart
  test('duplicate sortOrder orders deterministically by id', () async {
    final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
    final t1 = await db.todoDao.createTask(categoryId: cat, name: 't1');
    final t2 = await db.todoDao.createTask(categoryId: cat, name: 't2');
    final t3 = await db.todoDao.createTask(categoryId: cat, name: 't3');

    // Force a sortOrder collision (reachable via the stale-set reorder hazard).
    for (final id in [t1, t2, t3]) {
      await (db.update(db.tasks)..where((t) => t.id.equals(id)))
          .write(const TasksCompanion(sortOrder: Value(0)));
    }

    final a = await db.todoDao.watchCategoriesWithTasks().first;
    final b = await db.todoDao.watchCategoriesWithTasks().first;
    final orderA = a.first.activeTasks.map((t) => t.id).toList();
    final orderB = b.first.activeTasks.map((t) => t.id).toList();
    expect(orderA, [t1, t2, t3]); // id-ascending tiebreak
    expect(orderA, orderB); // stable across reads
  });
  ```

  Ensure `TasksCompanion` / `Value` are available — the test file imports
  `package:nooka/data/services/database/database.dart` (which re-exports them
  via the generated `database.dart`) and `OrderingTerm` from
  `package:drift/drift.dart`. Add `Value` to the drift import show-list if
  `flutter analyze` flags it.

- [ ] **Step 2: Run the test to verify it fails**

  Run: `flutter test test/data/todo_dao_test.dart -n "deterministic"`
  Expected: FAIL or FLAKY — with no id tiebreaker, the collided rows order by
  insertion/rowid only incidentally and the assertion is not guaranteed.

- [ ] **Step 3: Add the tiebreakers**

  In `lib/data/services/database/todo_dao.dart`, in
  `watchCategoriesWithTasks` (lines 202–205), extend the `orderBy` list:

  ```dart
  ..orderBy([
    OrderingTerm(expression: categories.sortOrder),
    OrderingTerm(expression: tasks.sortOrder),
    OrderingTerm(expression: categories.id),
    OrderingTerm(expression: tasks.id),
  ]);
  ```

- [ ] **Step 4: Run the test to verify it passes**

  Run: `flutter test test/data/todo_dao_test.dart`
  Expected: PASS — including the existing grouping/order tests.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/data/services/database/todo_dao.dart test/data/todo_dao_test.dart
  git commit -m "fix: add id tiebreakers to category/task ordering

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 3: L4 — batched `updateCategory` (DAO + repo + view model)

**Files:**
- Modify: `lib/data/services/database/todo_dao.dart`
- Modify: `lib/data/repositories/todo_repository.dart`
- Modify: `lib/ui/home/home_view_model.dart`
- Test: `test/data/todo_dao_test.dart`

**Interfaces (this bundle defines):**
- `TodoDao.updateCategory({required int id, required String name, required int color, required String? emoji}) -> Future<void>`
- `TodoRepository.updateCategory({required int id, required String name, required int color, required String? emoji}) -> Future<void>`
- `HomeViewModel.updateCategory({required int id, required String name, required int color, required String? emoji}) -> Future<void>`

One DAO method writes name + color + emoji together, threaded through repo and
view model. Wired into the UI in Task 4.

- [ ] **Step 1: Write the failing DAO test**

  In `test/data/todo_dao_test.dart`, inside `group('categories', ...)` (after
  the `setCollapsed persists` test, before the group's closing `});`), add:

  ```dart
  test('updateCategory writes name, color and emoji in one call', () async {
    final id = await db.todoDao.createCategory(
      name: 'Home',
      color: 1,
      emoji: '🏠',
    );

    await db.todoDao.updateCategory(
      id: id,
      name: 'House',
      color: 2,
      emoji: '🏡',
    );
    var row = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(id))).getSingle();
    expect(row.name, 'House');
    expect(row.color, 2);
    expect(row.emoji, '🏡');

    // Clearing the emoji to null is a real write, not "unchanged".
    await db.todoDao.updateCategory(
      id: id,
      name: 'House',
      color: 2,
      emoji: null,
    );
    row = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(id))).getSingle();
    expect(row.emoji, isNull);
  });
  ```

- [ ] **Step 2: Run it to verify it fails**

  Run: `flutter test test/data/todo_dao_test.dart -n "updateCategory"`
  Expected: FAIL — `updateCategory` is not defined.

- [ ] **Step 3: Implement the DAO method**

  In `lib/data/services/database/todo_dao.dart`, after `setCategoryEmoji`
  (around line 48), add:

  ```dart
  /// Writes a category's name, color and emoji in a single update — the edit
  /// dialog's three fields, batched so the stream rebuilds once.
  Future<void> updateCategory({
    required int id,
    required String name,
    required int color,
    required String? emoji,
  }) =>
      (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          name: Value(name),
          color: Value(color),
          emoji: Value(emoji),
        ),
      );
  ```

- [ ] **Step 4: Add the repository passthrough**

  In `lib/data/repositories/todo_repository.dart`, after `setCategoryEmoji`
  (line 29), add:

  ```dart
  Future<void> updateCategory({
    required int id,
    required String name,
    required int color,
    required String? emoji,
  }) => _dao.updateCategory(id: id, name: name, color: color, emoji: emoji);
  ```

- [ ] **Step 5: Add the view-model passthrough**

  In `lib/ui/home/home_view_model.dart`, after `setCategoryEmoji` (line 29),
  add:

  ```dart
  Future<void> updateCategory({
    required int id,
    required String name,
    required int color,
    required String? emoji,
  }) => _repo.updateCategory(id: id, name: name, color: color, emoji: emoji);
  ```

- [ ] **Step 6: Regenerate and verify it compiles**

  Run: `dart run build_runner build --delete-conflicting-outputs`
  Then: `flutter analyze`
  Expected: no errors. (No `.g.dart` diff is expected from a plain method, but
  run it to be safe and commit any regenerated file.)

- [ ] **Step 7: Run the DAO test to verify it passes**

  Run: `flutter test test/data/todo_dao_test.dart -n "updateCategory"`
  Expected: PASS.

- [ ] **Step 8: Commit**

  ```bash
  git add lib/data/services/database/todo_dao.dart \
    lib/data/repositories/todo_repository.dart \
    lib/ui/home/home_view_model.dart \
    test/data/todo_dao_test.dart \
    lib/data/services/database/todo_dao.g.dart \
    lib/data/repositories/todo_repository.g.dart \
    lib/ui/home/home_view_model.g.dart
  git commit -m "feat: batched updateCategory DAO/repo/view-model op

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 4: L4 — wire the category-edit path to `updateCategory`

**Files:**
- Modify: `lib/ui/home/home_screen.dart`

Replace the three awaited calls in `_categoryMenu`'s `'edit'` case with one
`updateCategory`, routed through Bundle A's `_guard`.

- [ ] **Step 1: Replace the three writes**

  In `lib/ui/home/home_screen.dart`, in `_categoryMenu`, the `'edit'` case
  currently reads (lines 383–387):

  ```dart
  if (r != null) {
    await _vm.renameCategory(cwt.category.id, r.name);
    await _vm.setCategoryColor(cwt.category.id, r.color);
    await _vm.setCategoryEmoji(cwt.category.id, r.emoji);
  }
  ```

  Replace with a single batched call through `_guard`:

  ```dart
  if (r != null) {
    await _guard(
      () => _vm.updateCategory(
        id: cwt.category.id,
        name: r.name,
        color: r.color,
        emoji: r.emoji,
      ),
    );
  }
  ```

  If Bundle A's `_guard` is not yet present, call `_vm.updateCategory(...)`
  directly and add `// TODO(bundle-a): wrap in _guard`.

- [ ] **Step 2: Verify the existing UI suite stays green**

  Run: `flutter test test/ui/home_screen_test.dart`
  Expected: PASS — the edit flow's observable result (renamed/recolored
  category) is unchanged; only the write count drops from three to one.

- [ ] **Step 3: Lint**

  Run: `just lint`
  Expected: clean.

- [ ] **Step 4: Commit**

  ```bash
  git add lib/ui/home/home_screen.dart
  git commit -m "refactor: batch category edit into one updateCategory write

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 5: M2 — clear `last_category` on category delete

**Files:**
- Modify: `lib/data/repositories/settings_repository.dart`
- Modify: `lib/ui/home/home_screen.dart`
- Test: `test/data/settings_repository_test.dart`

**Interfaces (this bundle defines):**
- `SettingsRepository.clearLastCategoryId() -> Future<void>`

Add a repository accessor that removes the `last_category` key, and clear the
remembered default when its category is deleted.

- [ ] **Step 1: Write the failing repository test**

  In `test/data/settings_repository_test.dart`, add a second test inside
  `main()`:

  ```dart
  test('clearLastCategoryId removes a stored id', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(prefs);

    await repo.writeLastCategoryId(7);
    expect(repo.readLastCategoryId(), 7);

    await repo.clearLastCategoryId();
    expect(repo.readLastCategoryId(), isNull);
  });
  ```

- [ ] **Step 2: Run it to verify it fails**

  Run: `flutter test test/data/settings_repository_test.dart`
  Expected: FAIL — `clearLastCategoryId` is not defined.

- [ ] **Step 3: Implement the accessor**

  In `lib/data/repositories/settings_repository.dart`, after
  `writeLastCategoryId` (line 32), add:

  ```dart
  /// Forgets the last-used category (e.g. after it is deleted).
  Future<void> clearLastCategoryId() => _prefs.remove(_lastCategoryKey);
  ```

- [ ] **Step 4: Run the repo test to verify it passes**

  Run: `flutter test test/data/settings_repository_test.dart`
  Expected: PASS.

- [ ] **Step 5: Clear the default in the delete path**

  In `lib/ui/home/home_screen.dart`, in `_categoryMenu`'s `'delete'` case
  (lines 395–401), currently:

  ```dart
  case 'delete':
    final ok = await confirmDeleteCategory(
      context,
      name: cwt.category.name,
      itemCount: cwt.tasks.length,
    );
    if (ok) await _vm.deleteCategory(cwt.category.id);
  ```

  Replace the `if (ok) ...` with a clear of the stale default when the deleted
  category was the remembered one:

  ```dart
  case 'delete':
    final ok = await confirmDeleteCategory(
      context,
      name: cwt.category.name,
      itemCount: cwt.tasks.length,
    );
    if (ok) {
      await _vm.deleteCategory(cwt.category.id);
      if (cwt.category.id == _lastCategoryId) {
        _lastCategoryId = null;
        await ref.read(settingsRepositoryProvider).clearLastCategoryId();
      }
    }
  ```

- [ ] **Step 6: Write the UI regression test**

  In `test/ui/home_screen_test.dart`, add a test that seeds a remembered
  category, deletes it, and asserts the pref is cleared. Mirror the file's
  existing `_app(db, prefs)` harness and confirm-delete flow:

  ```dart
  testWidgets('deleting the remembered category clears last_category', (
    tester,
  ) async {
    final home =
        await db.todoDao.createCategory(name: 'Home', color: 0xFF009688);
    await prefs.setInt('last_category', home);
    await tester.pumpWidget(_app(db, prefs));
    await tester.pumpAndSettle();

    // Open the category menu, choose Delete, confirm.
    await tester.tap(find.byKey(Key('category-menu-$home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last); // confirm dialog
    await tester.pumpAndSettle();

    expect(SettingsRepository(prefs).readLastCategoryId(), isNull);
  });
  ```

  Adapt the delete-confirm finder to the actual `confirmDeleteCategory` button
  label (check `lib/ui/widgets/confirm_delete_dialog.dart` / the ARB `delete`
  key) and add
  `import 'package:nooka/data/repositories/settings_repository.dart';` if the
  file does not already import it.

- [ ] **Step 7: Run the UI test + full suite**

  Run: `flutter test test/ui/home_screen_test.dart` then `just test`
  Expected: all PASS.

- [ ] **Step 8: Commit**

  ```bash
  git add lib/data/repositories/settings_repository.dart \
    lib/ui/home/home_screen.dart \
    test/data/settings_repository_test.dart \
    test/ui/home_screen_test.dart
  git commit -m "fix: clear remembered category when it is deleted

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 6: M4 — persist `last_category` only after `addTask` succeeds

**Files:**
- Modify: `lib/ui/home/home_screen.dart`

Reorder `_addTask`'s `onAdd` callback so the add is awaited (through `_guard`)
before the last-category default is persisted.

- [ ] **Step 1: Reorder the callback**

  In `lib/ui/home/home_screen.dart`, `_addTask`'s `onAdd` currently
  (lines 319–325):

  ```dart
  onAdd: (name, categoryId) async {
    _lastCategoryId = categoryId;
    await ref
        .read(settingsRepositoryProvider)
        .writeLastCategoryId(categoryId);
    await _vm.addTask(categoryId, name);
  },
  ```

  Replace with add-first, persist-on-success, routed through Bundle A's
  `_guard`:

  ```dart
  onAdd: (name, categoryId) async {
    await _guard(() => _vm.addTask(categoryId, name));
    _lastCategoryId = categoryId;
    await ref
        .read(settingsRepositoryProvider)
        .writeLastCategoryId(categoryId);
  },
  ```

  If Bundle A's `_guard` is not yet present, use
  `await _vm.addTask(categoryId, name);` and add
  `// TODO(bundle-a): wrap in _guard`. (The ordering fix — persist after add —
  is the load-bearing change and applies either way.)

- [ ] **Step 2: Verify the existing add + remember-default tests stay green**

  Run: `flutter test test/ui/home_screen_test.dart`
  Expected: PASS — the FAB add flow still adds the task and still persists the
  category as the default (now on success); the #7 / drag-board
  "remember default" tests still hold.

- [ ] **Step 3: Lint**

  Run: `just lint`
  Expected: clean.

- [ ] **Step 4: Commit**

  ```bash
  git add lib/ui/home/home_screen.dart
  git commit -m "fix: persist last category only after addTask succeeds

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 7: Coverage — DAO purge boundary, restore re-append, move sortOrder

**Files:**
- Test: `test/data/todo_dao_test.dart`

Close the §Test-gap DAO assertions: exact 30d/29d purge boundary, `restoreTask`
re-append `sortOrder`, and concrete `moveTaskToCategoryAt` sortOrder values.
Pure test additions — no production code changes.

- [ ] **Step 1: Add the purge-boundary test**

  In `test/data/todo_dao_test.dart`, inside `group('task lifecycle', ...)`
  (after the existing `purgeExpired deletes only items past retention` test),
  add:

  ```dart
  test('purgeExpired boundary: exactly 30d purged, 29d kept', () async {
    final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
    final at30 = await db.todoDao.createTask(categoryId: cat, name: 'at30');
    final at29 = await db.todoDao.createTask(categoryId: cat, name: 'at29');
    final now = DateTime(2026, 6, 17);
    await db.todoDao.completeTask(at30, now.subtract(const Duration(days: 30)));
    await db.todoDao.completeTask(at29, now.subtract(const Duration(days: 29)));

    final deleted = await db.todoDao.purgeExpired(now);

    expect(deleted, 1);
    final remaining = await db.select(db.tasks).get();
    expect(remaining.map((t) => t.name), ['at29']);
    expect(at30, isNotNull);
  });
  ```

- [ ] **Step 2: Add the restore re-append test**

  In the same group, replace/extend the existing
  `completeTask sets archivedAt; restoreTask clears it` coverage with a test
  that asserts the restored `sortOrder` is the tail of the active list:

  ```dart
  test('restoreTask re-appends to the tail of active sortOrder', () async {
    final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
    final a = await db.todoDao.createTask(categoryId: cat, name: 'a'); // 0
    final b = await db.todoDao.createTask(categoryId: cat, name: 'b'); // 1
    final c = await db.todoDao.createTask(categoryId: cat, name: 'c'); // 2
    expect([a, b, c], isNotEmpty);

    // Archive 'a', then restore it: it should re-append after b and c.
    await db.todoDao.completeTask(a, DateTime(2026, 6, 1));
    await db.todoDao.restoreTask(a);

    final row = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(a))).getSingle();
    expect(row.archivedAt, isNull);
    // b=1, c=2 remained active while a was archived → a re-appends at 3.
    expect(row.sortOrder, 3);
  });
  ```

- [ ] **Step 3: Strengthen the `moveTaskToCategoryAt` assertions**

  In `group('reordering', ...)`, add a test asserting concrete `sortOrder`
  values for destination and source (the existing test checks relative order
  only):

  ```dart
  test('moveTaskToCategoryAt renumbers dest, leaves source gap', () async {
    final src = await db.todoDao.createCategory(name: 'Src', color: 1);
    final dst = await db.todoDao.createCategory(name: 'Dst', color: 2);
    final s1 = await db.todoDao.createTask(categoryId: src, name: 's1'); // 0
    final s2 = await db.todoDao.createTask(categoryId: src, name: 's2'); // 1
    final d1 = await db.todoDao.createTask(categoryId: dst, name: 'd1'); // 0
    final d2 = await db.todoDao.createTask(categoryId: dst, name: 'd2'); // 1

    // Move s1 into dst between d1 and d2.
    await db.todoDao.moveTaskToCategoryAt(s1, dst, [d1, s1, d2]);

    Future<int> orderOf(int id) async => (await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle()).sortOrder;

    // Destination renumbered 0,1,2 in the new order.
    expect(await orderOf(d1), 0);
    expect(await orderOf(s1), 1);
    expect(await orderOf(d2), 2);
    // Source is NOT renumbered: s2 keeps its original sortOrder (1), gap left.
    expect(await orderOf(s2), 1);
  });
  ```

- [ ] **Step 4: Run the DAO suite**

  Run: `flutter test test/data/todo_dao_test.dart`
  Expected: PASS — all new and existing cases green.

- [ ] **Step 5: Commit**

  ```bash
  git add test/data/todo_dao_test.dart
  git commit -m "test: cover purge boundary, restore re-append, move sortOrder

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 8: Coverage — `locale_controller` + `theme_controller` round-trip

**Files:**
- Create: `test/ui/locale_controller_test.dart`
- Create: `test/ui/theme_controller_test.dart`

Unit-test both controllers: default-before-save, persistence round-trip, and
unknown-token fallback. Pure test additions.

- [ ] **Step 1: Write the locale controller test**

  Create `test/ui/locale_controller_test.dart`:

  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:nooka/data/repositories/settings_repository.dart';
  import 'package:nooka/ui/core/locale_controller.dart';

  Future<ProviderContainer> _container(SharedPreferences prefs) async =>
      ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );

  void main() {
    test('defaults to system before any save', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(localeControllerProvider), AppLocale.system);
    });

    test('set persists the token and updates state', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await _container(prefs);
      addTearDown(container.dispose);

      await container.read(localeControllerProvider.notifier).set(AppLocale.ru);

      expect(container.read(localeControllerProvider), AppLocale.ru);
      expect(prefs.getString('locale'), 'ru');

      // Round-trip: a fresh container reading the same prefs reads back ru.
      final reopened = await _container(prefs);
      addTearDown(reopened.dispose);
      expect(reopened.read(localeControllerProvider), AppLocale.ru);
    });

    test('an unknown stored token falls back to system', () async {
      SharedPreferences.setMockInitialValues({'locale': 'klingon'});
      final prefs = await SharedPreferences.getInstance();
      final container = await _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(localeControllerProvider), AppLocale.system);
    });
  }
  ```

- [ ] **Step 2: Write the theme controller test**

  Create `test/ui/theme_controller_test.dart` mirroring the above against
  `ThemeController` / `AppThemeMode` / the `'theme'` key:

  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:nooka/data/repositories/settings_repository.dart';
  import 'package:nooka/ui/core/theme_controller.dart';

  Future<ProviderContainer> _container(SharedPreferences prefs) async =>
      ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );

  void main() {
    test('defaults to system before any save', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(themeControllerProvider), AppThemeMode.system);
    });

    test('set persists the token and updates state', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = await _container(prefs);
      addTearDown(container.dispose);

      await container
          .read(themeControllerProvider.notifier)
          .set(AppThemeMode.dark);

      expect(container.read(themeControllerProvider), AppThemeMode.dark);
      expect(prefs.getString('theme'), 'dark');

      final reopened = await _container(prefs);
      addTearDown(reopened.dispose);
      expect(reopened.read(themeControllerProvider), AppThemeMode.dark);
    });

    test('an unknown stored token falls back to system', () async {
      SharedPreferences.setMockInitialValues({'theme': 'sepia'});
      final prefs = await SharedPreferences.getInstance();
      final container = await _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(themeControllerProvider), AppThemeMode.system);
    });
  }
  ```

- [ ] **Step 3: Run both controller tests**

  Run: `flutter test test/ui/locale_controller_test.dart test/ui/theme_controller_test.dart`
  Expected: PASS — these guard existing behavior (no production change), so they
  should pass on first run; if either fails, the controller's `fromStorage`
  fallback or `set` write is broken and gets fixed before commit.

- [ ] **Step 4: Commit**

  ```bash
  git add test/ui/locale_controller_test.dart test/ui/theme_controller_test.dart
  git commit -m "test: cover locale/theme controller round-trip and fallback

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 9: Coverage — full archive flow test (widget test over in-memory Drift)

**Files:**
- Create: `test/integration/archive_flow_test.dart`

Drive `HomeViewModel` against an in-memory Drift DB through the full create →
add → complete (archive) → purge-boundary → restore flow. **Decision: a
`flutter test` widget/container test, not a new `integration_test/` harness** —
the existing `integration_test/critical_flow_test.dart` already covers on-device
relaunch persistence; the gap is the deterministic purge-boundary leg, which a
host-VM test with `NativeDatabase.memory()` and injected `archivedAt` exercises
faster and asserts exactly, while still running under `just test`. (Rationale in
`design.md` §Testing.)

- [ ] **Step 1: Write the flow test**

  Create `test/integration/archive_flow_test.dart`:

  ```dart
  import 'package:drift/native.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/repositories/todo_repository.dart';
  import 'package:nooka/data/services/database/database.dart';
  import 'package:nooka/data/services/database/database_providers.dart';
  import 'package:nooka/ui/home/home_view_model.dart';

  void main() {
    test('add -> complete -> purge boundary -> restore', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      // Subscribe so the stream provider stays alive.
      final sub = container.listen(homeViewModelProvider, (_, __) {});
      addTearDown(sub.close);

      final vm = container.read(homeViewModelProvider.notifier);

      // Create a category + a task.
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      await vm.addTask(cat, 'Sweep');
      var snapshot = await db.todoDao.watchCategoriesWithTasks().first;
      final task = snapshot.first.activeTasks.single;
      expect(task.name, 'Sweep');

      // Complete it → archived.
      await vm.completeTask(task.id);
      snapshot = await db.todoDao.watchCategoriesWithTasks().first;
      expect(snapshot.first.activeTasks, isEmpty);
      expect(snapshot.first.archivedTasks.single.id, task.id);

      // Backdate the archive to 29 days: purge at 'now' must NOT delete it.
      final now = DateTime(2026, 6, 17);
      await db.todoDao.completeTask(
        task.id,
        now.subtract(const Duration(days: 29)),
      );
      expect(await db.todoDao.purgeExpired(now), 0);

      // At exactly 30 days it IS eligible — but we restore instead of purging.
      await vm.restoreTask(task.id);
      snapshot = await db.todoDao.watchCategoriesWithTasks().first;
      expect(snapshot.first.activeTasks.single.id, task.id);
      expect(snapshot.first.archivedTasks, isEmpty);
    });
  }
  ```

  Confirm `CategoryWithTasks` exposes `activeTasks` / `archivedTasks` (it does —
  used throughout `home_screen.dart` and the DAO tests). If `TodoRepository` is
  unused after wiring, drop its import.

- [ ] **Step 2: Run the flow test**

  Run: `flutter test test/integration/archive_flow_test.dart`
  Expected: PASS.

- [ ] **Step 3: Full suite + lint**

  Run: `just test` then `just lint`
  Expected: all green; lint clean.

- [ ] **Step 4: Commit**

  ```bash
  git add test/integration/archive_flow_test.dart
  git commit -m "test: full add/complete/purge-boundary/restore flow

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 10: Finalize — full verification, index, PR

**Files:**
- Modify: `planning/changes/2026-06-20.04-hardening-archive-and-coverage/design.md`
- Modify: `planning/changes/2026-06-20.04-hardening-archive-and-coverage/plan.md`

Run the whole gate, regenerate the planning index, and open the PR.

- [ ] **Step 1: Full gate**

  Run: `just test` then `just lint`
  Expected: all green; lint clean. If any `.g.dart` is stale, run
  `dart run build_runner build --delete-conflicting-outputs` and commit it.

- [ ] **Step 2: Regenerate the planning index**

  Run: `just index`
  Expected: the generated change listing now includes this bundle.

- [ ] **Step 3: Open the PR**

  Push `fix/hardening-archive-and-coverage` and open a PR titled
  `fix: archive countdown, ordering & remaining coverage`. On merge, set this
  bundle's `design.md` / `plan.md` frontmatter to `status: shipped` and fill
  `pr:` / `outcome:`; rerun `just index`.

  ```bash
  git add planning/
  git commit -m "chore(planning): index hardening-archive-and-coverage bundle

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

## Self-review

- **Spec coverage:** M1 (T1), L1 (T2), L4 DAO/repo/VM (T3) + UI wiring (T4),
  M2 (T5), M4 (T6); coverage gaps — DAO boundary/restore/move (T7), controllers
  (T8), full flow (T9); finalize (T10). Every design §1–§6 and Testing item maps
  to a task.
- **Shared interfaces:** `SettingsRepository.clearLastCategoryId()`,
  `TodoDao/TodoRepository/HomeViewModel.updateCategory({required int id,
  required String name, required int color, required String? emoji})` are used
  with identical signatures across T3–T5 and match the bundle's declared
  interfaces.
- **Bundle A dependency:** M4 (T6) and L4-UI (T4) route through `_guard`, with a
  stated direct-call fallback if `_guard` has not yet landed.
- **Regen:** the only `.g.dart`-affecting change is T3's `updateCategory`
  additions; T3 runs `build_runner` and commits the regenerated files.
- **Placeholder scan:** none — every code step carries real Dart from the read
  source or an exact command.
- **Integration-vs-widget decision:** stated in T9 and design §Testing — a
  host-VM widget/container test at `test/integration/archive_flow_test.dart`,
  not a new `integration_test/` harness.
