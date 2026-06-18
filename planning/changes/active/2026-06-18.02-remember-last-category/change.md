---
status: draft
date: 2026-06-18
slug: remember-last-category
supersedes: null
superseded_by: null
pr: null
outcome: null
---

# Change: Persist the last-used category for quick add

**Lane:** lightweight — ≲30 LOC net, 2 source files + a test, no new file, no
public-API change.

## Goal

When creating a to-do via the add-task FAB, default the category dropdown to the
one used last time — **across app restarts**. Today the "last category" lives
only in `_HomeScreenState._lastCategoryId`, an in-memory field, so it resets to
the first category every launch. User-reported: "previously chosen category is
not saved."

## Approach

Persist the last-used category id through the existing `SettingsRepository`
(SharedPreferences), mirroring how locale/theme tokens are stored. `HomeScreen`
seeds `_lastCategoryId` from it on init and writes through on each add. The
existing `ids.contains(_lastCategoryId)` guard in `_addTask` already falls back
to `cats.first` if the stored category was since deleted, so no extra handling
is needed.

Scope note: only the FAB quick-add (`_addTask`) persists the default — the
category-scoped add from a category's overflow menu (`_categoryMenu` → `'add'`)
keeps its current behavior and does not move the global default. This matches
the current code, where only `_addTask` touches `_lastCategoryId`.

## Files

- `lib/data/repositories/settings_repository.dart` — add `_lastCategoryKey`,
  `int? readLastCategoryId()` (`_prefs.getInt`), and
  `Future<void> writeLastCategoryId(int id)` (`_prefs.setInt`). No `.g.dart`
  regeneration needed: the generator only emits the providers, not these plain
  methods.
- `lib/ui/home/home_screen.dart` — in `initState`, seed
  `_lastCategoryId = ref.read(settingsRepositoryProvider).readLastCategoryId();`
  In `_addTask`'s `onAdd`, after `_lastCategoryId = categoryId`, also
  `ref.read(settingsRepositoryProvider).writeLastCategoryId(categoryId)`.
- `test/data/settings_repository_test.dart` — round-trip test for the new
  accessor (null before any write; reads back what was written).
- `test/ui/home_screen_test.dart` — the shared `_app` harness now also overrides
  `sharedPreferencesProvider` (HomeScreen reads it in `initState`); `setUp`
  builds a mock `SharedPreferences`.

## Verification

- [x] Failing test first: assert `readLastCategoryId()` returns the value
      written by `writeLastCategoryId(id)` (and `null` before any write).
- [x] `flutter test test/data/settings_repository_test.dart` — passes.
- [x] `just test` — full suite green (37 tests).
- [x] `just lint` — clean.
- [ ] Manual: add a task to a non-first category, fully restart the app, open
      the add-task FAB → that category is preselected.
