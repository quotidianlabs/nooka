---
status: draft
date: 2026-06-20
slug: hardening-error-resilience
spec: hardening-error-resilience
pr: null
---

# hardening-error-resilience — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop swallowing DB-write failures, keep app launch alive when the
startup purge throws, log lost async rejections, and localize the
stream-error screen — Bundle A of the whole-app hardening sweep (audit H1, H2,
L6, L9).

**Spec:** [`design.md`](./design.md)

**Branch:** `fix/hardening-error-resilience`

**Commit strategy:** Per-task commits.

## Global Constraints

- Flutter, Dart SDK `^3.12.2`, Riverpod (riverpod_annotation/generator), Drift.
  Layered MVVM (domain pure / data / ui).
- Lint: `just lint` (`dart format` + `flutter analyze`) must pass clean. Tests:
  `just test` (`flutter test`).
- Generated `*.g.dart` is committed. After editing any `@riverpod` class or
  Drift table/DAO, run
  `dart run build_runner build --delete-conflicting-outputs` and commit the
  regenerated files.
- i18n: user-facing strings live in `lib/l10n/app_en.arb` (template) +
  `app_ru.arb`; regenerate `lib/l10n/app_localizations*.dart` via the build
  (`flutter gen-l10n` runs on build). Add BOTH en and ru.
- TDD: each behavioral change = failing `flutter test` first, then minimal
  impl, then green, then commit. Per-task commits.
- Conventional commit subjects; end every commit body with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

**Shared interface this bundle defines** (Bundles B and C reuse these exact
names):

- ARB keys `errorLoading` and `actionFailed` (no placeholders) in both ARBs.
- The `_HomeScreenState._guard(Future<void> Function() action)` helper. Bundles
  B and C route their own edited/new awaited mutations through this same
  `_guard`.

---

### Task 1: Startup resilience — guard + log the purge (H2 / L9)

**Files:**
- Modify: `lib/main.dart`

Wrap the startup `purgeExpired()` in `try/catch` so a DB failure logs and still
reaches `runApp`, and capture + log the returned count. No behavioral test
harness for the boot path (straight-line `try/catch`); verified by analyze +
smoke.

- [ ] **Step 1: Guard and log the purge**

  In `lib/main.dart`, replace the current purge line (the comment + `await
  container.read(todoRepositoryProvider).purgeExpired();` at lines 19–20) with:

  ```dart
  // Startup cleanup: purge archived items past their 30-day retention. Must
  // never block boot — log failures and continue.
  try {
    final purged = await container.read(todoRepositoryProvider).purgeExpired();
    debugPrint('Startup purge removed $purged expired item(s).');
  } catch (e, st) {
    debugPrint('Startup purge failed (continuing): $e\n$st');
  }
  ```

- [ ] **Step 2: Ensure `debugPrint` is in scope**

  `debugPrint` lives in `package:flutter/foundation.dart`. `main.dart` imports
  `package:flutter/material.dart`, which re-exports `foundation`, so no new
  import should be needed.

  Run: `flutter analyze lib/main.dart`
  Expected: no errors. If `debugPrint` is reported undefined, add
  `import 'package:flutter/foundation.dart';` to the import block (alphabetical,
  after the `material.dart` import) and re-run.

- [ ] **Step 3: Commit**

  ```bash
  git add lib/main.dart
  git commit -m "fix: survive a failing startup purge and log its count

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 2: Global async-error handler (H1, cross-cutting half)

**Files:**
- Modify: `lib/main.dart`

Install `FlutterError.onError` and wrap `runApp` in `runZonedGuarded` so any
rejection that escapes a guard is logged, not lost. `WidgetsFlutterBinding`
stays initialized in the root zone.

- [ ] **Step 1: Add the FlutterError handler**

  In `lib/main.dart`, immediately after
  `WidgetsFlutterBinding.ensureInitialized();` (line 14), add:

  ```dart
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  ```

- [ ] **Step 2: Wrap `runApp` in `runZonedGuarded`**

  `runZonedGuarded` is in `dart:async`. Add `import 'dart:async';` at the top of
  the import block (before the `package:` imports). Replace the existing
  `runApp(...)` call (lines 22–24):

  ```dart
  runApp(
    UncontrolledProviderScope(container: container, child: const NookaApp()),
  );
  ```

  with:

  ```dart
  runZonedGuarded(
    () => runApp(
      UncontrolledProviderScope(container: container, child: const NookaApp()),
    ),
    (error, stack) => debugPrint('Uncaught zone error: $error\n$stack'),
  );
  ```

- [ ] **Step 3: Analyze**

  Run: `flutter analyze lib/main.dart`
  Expected: no errors. (`FlutterError`/`debugPrint` come from `material.dart`;
  `runZonedGuarded` from the new `dart:async` import.)

- [ ] **Step 4: Smoke the boot path**

  Run: `flutter test` (the full suite — confirms nothing in `main.dart` broke
  shared providers).
  Expected: green. Optionally `flutter run` once and confirm the app launches
  to the home screen.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/main.dart
  git commit -m "fix: log uncaught async + framework errors via global handlers

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 3: ARB keys `errorLoading` + `actionFailed` (shared interface)

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_ru.arb`
- Regenerate: `lib/l10n/app_localizations*.dart` (committed)

Add the two placeholder-free keys to both ARBs and regenerate the localizations.
These keys are consumed by Tasks 4 and 5 and reused by Bundles B and C.

- [ ] **Step 1: Add the keys to the English template**

  In `lib/l10n/app_en.arb`, after the `"undoAction": "Undo",` line (before
  `"settingsTitle"`), add:

  ```json
  "errorLoading": "Something went wrong",
  "actionFailed": "Couldn’t complete that. Try again.",
  ```

- [ ] **Step 2: Add the keys to the Russian ARB**

  In `lib/l10n/app_ru.arb`, after the `"undoAction": "Отменить",` line (before
  `"settingsTitle"`), add:

  ```json
  "errorLoading": "Что-то пошло не так",
  "actionFailed": "Не удалось выполнить действие. Попробуйте ещё раз.",
  ```

- [ ] **Step 3: Regenerate the localizations**

  Run: `flutter gen-l10n`
  (or `flutter pub get` / a build, which runs `gen-l10n` automatically).
  Expected: `lib/l10n/app_localizations.dart`,
  `app_localizations_en.dart`, and `app_localizations_ru.dart` now declare
  `String get errorLoading;` / `String get actionFailed;`.

- [ ] **Step 4: Verify parity + analyze**

  Run: `flutter analyze lib/l10n/`
  Expected: no errors, no untranslated-message warnings (both keys present in
  en and ru).

- [ ] **Step 5: Commit**

  ```bash
  git add lib/l10n/app_en.arb lib/l10n/app_ru.arb lib/l10n/app_localizations*.dart
  git commit -m "feat(i18n): add errorLoading + actionFailed strings (en/ru)

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 4: Localize the stream-error widget (L6)

**Files:**
- Modify: `lib/ui/home/home_screen.dart`
- Test: `test/ui/home_screen_test.dart`

Replace the raw `Text('$e')` in the `state.when(error:)` branch with the
localized `errorLoading` key, guarded by a widget test that forces the watch
stream into an error.

- [ ] **Step 1: Add a throwing-stream fake + failing test**

  In `test/ui/home_screen_test.dart`, add a `TodoRepository` subclass near the
  top of the file (after the imports, before `_app`) whose stream errors:

  ```dart
  class _ErrorStreamRepo extends TodoRepository {
    _ErrorStreamRepo(super.dao);
    @override
    Stream<List<CategoryWithTasks>> watchCategoriesWithTasks() =>
        Stream.error(Exception('boom'));
  }
  ```

  Add the imports this needs at the top of the test file:

  ```dart
  import 'package:nooka/data/repositories/todo_repository.dart';
  import 'package:nooka/domain/models/category_with_tasks.dart';
  ```

  Add an `_app`-style helper that overrides the repository provider (place it
  beside `_app`):

  ```dart
  Widget _appWithRepo(
    TodoRepository repo,
    SharedPreferences prefs, {
    Locale locale = const Locale('en'),
  }) => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      todoRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    ),
  );
  ```

  Then add the test inside `main()`:

  ```dart
  testWidgets('stream error shows a localized message, not the raw exception', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithRepo(_ErrorStreamRepo(db.todoDao), prefs));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });
  ```

- [ ] **Step 2: Run it to verify it fails**

  Run: `flutter test test/ui/home_screen_test.dart -n "localized message"`
  Expected: FAIL — the error branch currently renders `Text('$e')`, so
  `find.textContaining('Exception')` matches and `'Something went wrong'` is
  absent.

- [ ] **Step 3: Localize the error branch**

  In `lib/ui/home/home_screen.dart`, in `build`'s `state.when(...)` (line 114),
  change:

  ```dart
  error: (e, _) => Center(child: Text('$e')),
  ```

  to:

  ```dart
  error: (e, _) =>
      Center(child: Text(AppLocalizations.of(context).errorLoading)),
  ```

  (`AppLocalizations` is already imported and `l10n` is in scope; using the
  direct call keeps the change to one line.)

- [ ] **Step 4: Run it to verify it passes**

  Run: `flutter test test/ui/home_screen_test.dart -n "localized message"`
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/ui/home/home_screen.dart test/ui/home_screen_test.dart
  git commit -m "fix: localize the stream-error screen

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 5: `_guard` helper + convert fire-and-forget call sites (H1, UI half)

**Files:**
- Modify: `lib/ui/home/home_screen.dart`
- Test: `test/ui/home_screen_test.dart`

Add the shared `_guard` helper and route the existing non-drag fire-and-forget
mutations through it, so a throwing write shows the `actionFailed` SnackBar
instead of crashing silently. `_onItemReorder` is left for Bundle B.

- [ ] **Step 1: Add a throwing-mutation fake + failing test**

  In `test/ui/home_screen_test.dart`, add a second `TodoRepository` subclass
  (beside `_ErrorStreamRepo`) whose stream works but whose mutations throw. We
  make `purgeExpired` throw because switching to the Archive tab calls it via a
  guarded path:

  ```dart
  class _ThrowingMutationRepo extends TodoRepository {
    _ThrowingMutationRepo(super.dao);
    @override
    Future<int> purgeExpired() => Future.error(Exception('locked'));
  }
  ```

  Add the test inside `main()` (it reuses `_appWithRepo` from Task 4):

  ```dart
  testWidgets('a throwing mutation surfaces the actionFailed SnackBar', (
    tester,
  ) async {
    // Seed a category so the board renders and the Archive tab is reachable.
    final cat = await db.todoDao.createCategory(name: 'Home', color: 0xFF009688);
    await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await tester.pumpWidget(
      _appWithRepo(_ThrowingMutationRepo(db.todoDao), prefs),
    );
    await tester.pumpAndSettle();

    // Switching to Archive triggers the guarded purgeExpired, which throws.
    await tester.tap(find.text('Archive'));
    await tester.pump(); // let the guard catch + show the SnackBar
    await tester.pump();

    expect(find.text('Couldn’t complete that. Try again.'), findsOneWidget);
  });
  ```

  > Note: `_ThrowingMutationRepo` shares `db.todoDao`, so its
  > `watchCategoriesWithTasks` streams the real seeded data; only `purgeExpired`
  > throws.

- [ ] **Step 2: Run it to verify it fails**

  Run: `flutter test test/ui/home_screen_test.dart -n "actionFailed SnackBar"`
  Expected: FAIL — today the `:99` call is `if (s.first == _View.archive)
  _vm.purgeExpired();` (fire-and-forget, no guard), so the rejection is
  unhandled and no SnackBar appears.

- [ ] **Step 3: Add the `_guard` helper**

  In `lib/ui/home/home_screen.dart`, in `_HomeScreenState`, add the helper
  (place it just above the `// ---- commands + toasts ----` comment, line 269):

  ```dart
  /// Runs an imperative mutation, surfacing any failure as a localized
  /// SnackBar instead of an unhandled async error. Bundles B and C route their
  /// edited/new mutations through this same guard.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).actionFailed)),
      );
    }
  }
  ```

- [ ] **Step 4: Route the Archive-tab purge through `_guard`**

  In `build`, the `onSelectionChanged` callback (line 99). Change:

  ```dart
  if (s.first == _View.archive) _vm.purgeExpired();
  ```

  to:

  ```dart
  if (s.first == _View.archive) _guard(() => _vm.purgeExpired());
  ```

- [ ] **Step 5: Route the archive collapse toggle through `_guard`**

  In `_body`'s archived `CategorySection` (line 144–145). Change:

  ```dart
  onToggleCollapsed: () =>
      _vm.toggleCollapsed(cwt.category.id, !cwt.category.collapsed),
  ```

  to:

  ```dart
  onToggleCollapsed: () => _guard(
    () => _vm.toggleCollapsed(cwt.category.id, !cwt.category.collapsed),
  ),
  ```

- [ ] **Step 6: Route `reorderCategories` through `_guard`**

  In `_board`'s `onListReorder` (line 162–165). Change the body:

  ```dart
  onListReorder: (oldIndex, newIndex) {
    final ids = [for (final c in cats) c.category.id];
    _vm.reorderCategories(reorderedIds(ids, oldIndex, newIndex));
  },
  ```

  to:

  ```dart
  onListReorder: (oldIndex, newIndex) {
    final ids = [for (final c in cats) c.category.id];
    _guard(() => _vm.reorderCategories(reorderedIds(ids, oldIndex, newIndex)));
  },
  ```

  (Do **not** touch `onItemReorder` / `_onItemReorder` — Bundle B owns it.)

- [ ] **Step 7: Route the active-board collapse toggle through `_guard`**

  In `_onExpandToggle` (line 260–267). Change:

  ```dart
  _vm.toggleCollapsed(category.id, !category.collapsed);
  ```

  to:

  ```dart
  _guard(() => _vm.toggleCollapsed(category.id, !category.collapsed));
  ```

  (The `writeLastCategoryId` persistence below it is unchanged.)

- [ ] **Step 8: Route the undo-toast actions through `_guard`**

  The toast actions re-drive a mutation when the user taps Undo. In `_complete`
  (line 295–300) change:

  ```dart
  _showUndoToast(message, () => _vm.restoreTask(task.id));
  ```

  to:

  ```dart
  _showUndoToast(message, () => _guard(() => _vm.restoreTask(task.id)));
  ```

  In `_restore` (line 302–307) change:

  ```dart
  _showUndoToast(message, () => _vm.completeTask(task.id));
  ```

  to:

  ```dart
  _showUndoToast(message, () => _guard(() => _vm.completeTask(task.id)));
  ```

  (`_showUndoToast` takes a `VoidCallback`; `() => _guard(...)` returns the
  ignored `Future`, matching the existing `() => _vm.restoreTask(...)` shape.)

- [ ] **Step 9: Run the target test to verify it passes**

  Run: `flutter test test/ui/home_screen_test.dart -n "actionFailed SnackBar"`
  Expected: PASS — the guarded `purgeExpired` throw is caught and the
  `actionFailed` SnackBar shows.

- [ ] **Step 10: Run the full suite + lint**

  Run: `just test` then `just lint`
  Expected: all green (the existing complete/restore/collapse/reorder tests
  still pass — `_guard` is transparent on the success path); lint clean.

- [ ] **Step 11: Commit**

  ```bash
  git add lib/ui/home/home_screen.dart test/ui/home_screen_test.dart
  git commit -m "fix: guard fire-and-forget mutations with an actionFailed snackbar

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 6: Ship — frontmatter, index, PR

**Files:**
- Modify: `planning/changes/2026-06-20.02-hardening-error-resilience/design.md`
- Modify: `planning/changes/2026-06-20.02-hardening-error-resilience/plan.md`
- Regenerate: the planning index

Flip status to shipped and open the PR.

- [ ] **Step 1: Full green gate**

  Run: `just test` then `just lint`
  Expected: all green; lint clean.

- [ ] **Step 2: Set frontmatter to shipped**

  In both `design.md` and `plan.md`, set `status: shipped`. Fill the design's
  `pr:` and `outcome:` once the PR number exists.

- [ ] **Step 3: Regenerate the change index**

  Run: `just index`
  Expected: the generated listing now shows this bundle as shipped.

- [ ] **Step 4: Commit + open the PR**

  ```bash
  git add planning/
  git commit -m "chore(planning): ship hardening-error-resilience bundle

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

  Push `fix/hardening-error-resilience` and open a PR titled
  `fix: error resilience — guarded mutations + survivable startup`.

---

## Self-review

- **Spec coverage:** startup guard + count log H2/L9 (T1), global async handler
  H1-cross-cutting (T2), shared ARB keys (T3), localized stream error L6 (T4),
  `_guard` helper + guarded call sites H1-UI (T5), ship (T6). Every design
  §1–§5 maps to a task.
- **Shared-interface fidelity:** ARB keys `errorLoading` / `actionFailed`
  (no placeholders) and `_guard(Future<void> Function())` are named exactly as
  Bundles B and C will consume them; `_onItemReorder` left untouched for
  Bundle B.
- **Placeholder scan:** none — every code step carries concrete Dart copied or
  adapted from the real source (line numbers from the current
  `home_screen.dart` / `main.dart`).
- **TDD:** T4 and T5 each write a failing widget test (throwing-stream and
  throwing-mutation `TodoRepository` subclasses injected via
  `todoRepositoryProvider.overrideWithValue`) before the fix; T1/T2 are
  boot-path `try/catch` verified by analyze + suite + smoke.
