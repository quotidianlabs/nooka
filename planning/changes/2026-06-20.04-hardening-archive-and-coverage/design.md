---
status: shipped
date: 2026-06-20
slug: hardening-archive-and-coverage
spec: hardening-archive-and-coverage
summary: Fix the archive-countdown truncation, stale last-category pref, premature add-default persistence, nondeterministic ordering, and un-batched category edits, then close the remaining DAO/controller/flow coverage gaps.
supersedes: null
superseded_by: null
pr: "#12"
outcome: "Ceiled daysRemaining so surviving items never show 0 (M1); added category/task id ordering tiebreakers (L1); batched category edits into one updateCategory DAO/repo/VM write wired through _guard (L4); clear last_category when its category is deleted (M2); persist last_category only after addTask succeeds (M4). Closed coverage gaps: DAO purge-boundary/restore-reappend/move-sortOrder, locale/theme controller round-trips, and a full add→complete→purge-boundary→restore flow test. 88/88 tests green."
---

# Design: Archive countdown, ordering & remaining coverage

## Summary

Bundle C of the whole-app hardening initiative (audit:
[`2026-06-20-whole-app-hardening.md`](../../audits/2026-06-20-whole-app-hardening.md),
parent spec:
[`hardening-audit-and-tests`](../2026-06-20.01-hardening-audit-and-tests/design.md)).
It lands the archive-and-ordering polish fixes — **M1** (`daysRemaining`
truncation), **M2** (stale `last_category` not cleared on delete), **M4**
(`last_category` persisted before `addTask` resolves), **L1** (no DB ordering
tiebreaker), **L4** (category edit = three un-batched writes) — and then closes
the remaining coverage gaps the parent spec's test pass deferred to the fix
bundles: DAO purge-boundary / restore-reappend / move-sortOrder assertions,
`locale_controller` + `theme_controller` round-trip unit tests, and the full
add → complete → archive → purge → restore flow test.

## Motivation

The audit (§Medium, §Low, §Test gaps) flagged five low-risk-but-real defects
clustered in the archive countdown and the ordering/edit plumbing, plus a set
of untested behaviors that no current test would catch a regression in:

- **M1 — `daysRemaining` truncates** (`archive.dart:14-18`,
  `task_row_content.dart:51`): `expiry.difference(now).inDays` truncates toward
  zero, but `purgeExpired` only deletes at `archivedAt <= now-30d`. For the
  final ~24h of retention the row reads "auto-removes in 0 days" (rendered as
  "under a day" via the `=0` plural) while the task is *not yet* purgeable — the
  countdown contradicts the engine for surviving items.
- **M2 — stale `last_category` not cleared on delete**
  (`home_screen.dart:395-401`, `settings_repository.dart`): deleting a category
  leaves its id in `_lastCategoryId` and the `last_category` pref. Guarded today
  by `_addTask`'s `ids.contains(_lastCategoryId)` fallback, but the stale id
  lingers and would mis-target if an id were ever reused.
- **M4 — `last_category` persisted before `addTask` resolves**
  (`home_screen.dart:319-325`): the `onAdd` callback writes `_lastCategoryId`
  and `writeLastCategoryId(...)` *before* `await _vm.addTask(...)`. If the add
  throws (and its error is swallowed pre-Bundle A), the default is persisted to
  a category that never accepted the task.
- **L1 — no DB ordering tiebreaker** (`todo_dao.dart:202-205`):
  `watchCategoriesWithTasks` orders by `categories.sortOrder` then
  `tasks.sortOrder` with no secondary key, so any duplicate `sortOrder`
  (reachable via the stale-set reorder hazard) orders nondeterministically and
  the list "jumps."
- **L4 — category edit = three un-batched writes**
  (`home_screen.dart:383-387`): the edit path calls `renameCategory` +
  `setCategoryColor` + `setCategoryEmoji` as three separate awaited writes — no
  transaction (partial-failure inconsistency) and three stream rebuilds /
  flickers.

Test-coverage gaps the parent spec's §Test gaps assigned to the fix bundles:

- `purgeExpired` boundary is tested at 40d/5d only — never exactly `now-30d`
  (the M1-adjacent boundary) nor a 29d case, so the boundary is unverified.
- `restoreTask` asserts only that `archivedAt` is cleared, never the restored
  `sortOrder` re-append (`== count(active)`).
- `moveTaskToCategoryAt` asserts relative order only, never concrete
  `sortOrder` values for source and destination — a renumber regression would
  pass silently.
- `locale_controller` / `theme_controller` have zero coverage: persistence
  round-trip, default-before-save, and unknown-token fallback are all untested.
- No end-to-end test drives the full add → complete → archive → purge → restore
  flow against a real DB.

## Non-goals

- No error-resilience work (H1/H2/L6/L9) — that is Bundle A.
- No drag-board / dialog work (H3/H4/H5/M3/L3/L5) — that is Bundle B.
- No new ARB keys: M1's ceil keeps `daysRemaining` `>= 1` for surviving items
  and `0` only for already-expired ones, and `autoRemovesIn` already renders
  `=0` as "under a day"; the existing key stays valid in both locales.
- No schema migration: L1 changes only the `orderBy` of a read query; no table
  or column changes.
- Deferred audit items (L2, L7, L8) are untouched.

## Design

### 1. M1 — ceil `daysRemaining` (`lib/domain/archive.dart`)

Replace the truncating `inDays` with a ceil over the partial day so a
not-yet-expired item always reports `>= 1`, and only an already-expired item
reports `0`:

```dart
/// Whole days until an item archived at [archivedAt] is auto-removed, as of
/// [now]. Rounds a partial day up, so a not-yet-expired item always reports at
/// least 1; only an expired item reports 0. Clamped to 0; never negative.
int daysRemaining(DateTime archivedAt, DateTime now) {
  final expiry = archivedAt.add(const Duration(days: archiveRetentionDays));
  final remaining =
      (expiry.difference(now).inMilliseconds / Duration.millisecondsPerDay)
          .ceil();
  return remaining < 0 ? 0 : remaining;
}
```

The existing tests (`daysRemaining(now, now) == 30`,
`now - 10d == 20`, `now - 99d == 0`) all still hold (exact-day boundaries ceil
to themselves). The consumer at `task_row_content.dart:51` is unchanged.

### 2. L1 — ordering tiebreakers (`lib/data/services/database/todo_dao.dart`)

Append the primary keys as final `OrderingTerm`s so the read query is a total
order:

```dart
..orderBy([
  OrderingTerm(expression: categories.sortOrder),
  OrderingTerm(expression: tasks.sortOrder),
  OrderingTerm(expression: categories.id),
  OrderingTerm(expression: tasks.id),
]);
```

Duplicate `sortOrder` values now break ties deterministically by id.

### 3. L4 — batched `updateCategory` (DAO + repo + view-model)

A single DAO method writes name + color + emoji in one `update().write(...)`,
threaded through the repository and view model, called once from the edit path:

```dart
// TodoDao
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

```dart
// TodoRepository
Future<void> updateCategory({
  required int id,
  required String name,
  required int color,
  required String? emoji,
}) => _dao.updateCategory(id: id, name: name, color: color, emoji: emoji);

// HomeViewModel
Future<void> updateCategory({
  required int id,
  required String name,
  required int color,
  required String? emoji,
}) => _repo.updateCategory(id: id, name: name, color: color, emoji: emoji);
```

The home-screen edit path (`home_screen.dart:383-387`) replaces its three
awaited calls with a single `updateCategory` call, routed through Bundle A's
`_guard` (see §6). `renameCategory` / `setCategoryColor` / `setCategoryEmoji`
stay on the DAO/repo/VM (still used elsewhere — e.g. `_taskMenu` rename); only
the category-edit path is switched to the batched method.

### 4. M2 — clear `last_category` on category delete

Add a `SettingsRepository` accessor that removes the key:

```dart
Future<void> clearLastCategoryId() => _prefs.remove(_lastCategoryKey);
```

In `home_screen.dart`'s delete path (`_categoryMenu` `'delete'` case), after a
confirmed delete, if the deleted category was the remembered default, clear both
the in-memory field and the pref:

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

(`Categories.id` is AUTOINCREMENT, so the cleared id is never reused — the
audit's M2 note confirms this bounds the risk.)

### 5. M4 — persist `last_category` only after `addTask` succeeds

In `_addTask`'s `onAdd` callback, await the add first (through Bundle A's
`_guard`), then persist the last category — so a failed add never leaves a
default pointing at a category that rejected the task:

```dart
onAdd: (name, categoryId) async {
  await _guard(() => _vm.addTask(categoryId, name));
  _lastCategoryId = categoryId;
  await ref
      .read(settingsRepositoryProvider)
      .writeLastCategoryId(categoryId);
},
```

### 6. Dependency on Bundle A (`_guard`)

Bundle A adds a `Future<void> _guard(Future<void> Function() action)` helper on
`_HomeScreenState` that awaits a mutation inside `try/catch` and surfaces
failures. This bundle routes its two new/changed UI mutation call sites —
M4's `addTask` and L4's `updateCategory` — through `_guard(() => _vm.xxx(...))`.
Bundle A executes first; if this bundle is implemented before `_guard` lands,
the wiring tasks call `_vm.xxx(...)` directly and a follow-up wraps them once
`_guard` exists. The plan states the `_guard` form as the target.

### New method signatures (this bundle defines)

- `SettingsRepository.clearLastCategoryId() -> Future<void>`
- `TodoDao.updateCategory({required int id, required String name, required int color, required String? emoji}) -> Future<void>`
- `TodoRepository.updateCategory({required int id, required String name, required int color, required String? emoji}) -> Future<void>`
- `HomeViewModel.updateCategory({required int id, required String name, required int color, required String? emoji}) -> Future<void>`

## Testing

TDD throughout — a failing `flutter test` precedes each fix/method.

- **M1** (`test/domain/archive_test.dart`): an item archived at
  `now - Duration(days: 29, hours: 23)` reports `daysRemaining == 1` (not 0);
  an item archived exactly `now - Duration(days: 30)` reports `0`. Existing
  cases stay green.
- **L1** (`test/data/todo_dao_test.dart`): two categories given the same
  `sortOrder` (and two tasks the same `sortOrder`) stream back in a stable
  id-ascending order across repeated reads.
- **L4** (`test/data/todo_dao_test.dart`): `updateCategory` writes name, color,
  and emoji together (and can clear emoji to null) in a single call.
- **M2** (`test/data/settings_repository_test.dart`): `clearLastCategoryId`
  removes a previously-written id so `readLastCategoryId()` is null again.
- **DAO purge boundary** (`test/data/todo_dao_test.dart`): a task archived
  exactly `now - 30d` is purged AND one archived `now - 29d` is not (the
  existing test checks 40d/5d only).
- **`restoreTask` re-append** (`test/data/todo_dao_test.dart`): after restoring,
  the task's `sortOrder == count(active tasks in its category) - 1` — i.e. it is
  appended to the tail, not just `archivedAt`-cleared.
- **`moveTaskToCategoryAt` sortOrder** (`test/data/todo_dao_test.dart`): assert
  concrete `sortOrder` values for destination (`0,1,2`) and that the source's
  remaining task keeps its original `sortOrder` (gap left, not renumbered).
- **Controllers** (`test/ui/locale_controller_test.dart`,
  `test/ui/theme_controller_test.dart`): default-before-save is `system`;
  `set(...)` writes the token and updates state (round-trip via a fresh
  container reading the same prefs); an unknown stored token falls back to
  `system`.
- **Flow test**: full create category → add task → complete (archives) → purge
  boundary → restore. **Decision: high-level widget test driving
  `HomeViewModel` against an in-memory Drift DB**, placed at
  `test/integration/archive_flow_test.dart`, *not* a new `integration_test/`
  harness. Rationale: the existing `integration_test/critical_flow_test.dart`
  already covers the relaunch-persistence path on-device; the gap the parent
  spec names is the purge-boundary leg, which is deterministic and DB-driven and
  does not need the device binding. A `flutter test` (host VM) widget test over
  a `ProviderContainer` with `appDatabaseProvider.overrideWithValue(...)` and
  `NativeDatabase.memory()` runs in CI with `just test`, exercises the real DAO
  through the view model, and lets us assert the exact purge boundary by
  injecting `archivedAt` — which the on-device harness cannot do cleanly. This
  keeps the suite single-command and fast.

`just lint` clean and `just test` green gate every task. Generated `*.g.dart`
is regenerated and committed after the DAO/repo/VM `updateCategory` additions.

## Risk

- **M1 ceil interacts with L7 (deferred DST drift)** (low × low): ceil over
  elapsed milliseconds still counts elapsed time, not calendar days, so a DST
  transition can nudge the boundary by an hour — but ceil *reduces* the
  user-visible mismatch the audit cited, and L7 stays explicitly deferred.
- **L1 tiebreaker masks a duplicate-sortOrder bug** (low × low): making order
  deterministic could hide that duplicates arose at all. Acceptable — the
  determinism is the user-facing fix; the stale-set hazard that produces
  duplicates is Bundle B's concern.
- **`updateCategory` writing `emoji: Value(null)`** (low × medium): the
  `CategoriesCompanion(emoji: Value(emoji))` form *sets* emoji to whatever the
  dialog returns, including clearing it to null — matching the current
  three-call behavior (`setCategoryEmoji(id, r.emoji)`); the L4 test asserts the
  null-clear case so a regression to "absent = unchanged" is caught.
- **Bundle A ordering** (low × low): if A has not landed, `_guard` is absent;
  the plan notes the direct-call fallback so this bundle is not blocked.
