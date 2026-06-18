---
status: shipped
date: 2026-06-17
slug: todo-list
supersedes: null
superseded_by: null
pr: null
outcome: 38ee702 — initial local-first to-do list; colored categories holding tasks, complete→archive with 30-day retention, drag-reorder, undo toasts, light/dark, en/ru.
---

# Nooka — To-Do List Design Spec

**Date:** 2026-06-17
**Name:** Nooka (Dart package `nooka`, org `com.nooka`). Brand name shown as the app title in both locales.
**Status:** Approved for planning
**Reference:** The `habbits` Flutter app (`../habbits`) is the architectural and stylistic template for everything below.

## Overview

A simple, local-first **to-do list** app. Users organize to-do items into colored categories. Completing an item archives it; archived items can be restored, and are automatically removed from the archive 30 days after completion. The app supports light/dark themes and English/Russian localization.

This is deliberately a *simple to-do list*, not a task manager. Features that turn a to-do app into a project-management platform (tags, sync, nested subtasks, recurrence, statistics/streaks) are explicitly out of scope for v1.

## Goals

- Capture to-do items under named, colored categories.
- Complete an item → it moves to an archive.
- Restore an archived item back to its category.
- Auto-remove archived items 30 days after completion.
- Light/dark theme (system-aware) and English/Russian localization.
- A handful of low-cost polish features: undo toast, optional category emoji, drag-to-reorder, collapsible categories.
- **Fast capture**: keep-keyboard-open rapid add (add several items in a row without re-opening the dialog) into the current/last-used category.
- **Swipe-to-complete**: swipe an active item right to complete it (with haptic feedback), keeping the tap checkbox as an accessible fallback.
- **Legible archive**: each archived item shows its completion date alongside "auto-removes in N days", plus a manual "Clear archive now" action.

## Non-Goals (v1)

Tags/labels, cloud sync, account/login, nested subtasks, recurring items, due dates/reminders, priorities, search, statistics/streaks, multi-level grouping, sharing/collaboration. These can be revisited later; none are built now.

## Technical Approach

Mirror the `habbits` stack exactly — same shape, conventions, and tooling, so the two apps share one mental model.

- **Flutter + Riverpod** (codegen notifiers, `@riverpod`), **layered MVVM**.
- **Layers:** `domain/` (pure logic, no Flutter/Drift imports) → `data/` (repositories + Drift DAO + services) → `ui/` (feature-first screens + view models). Unidirectional flow: `view → view model → repository → DAO → Drift SQLite`; reactive `watch…()` streams propagate changes back.
- **Persistence:** Drift (SQLite). UI is driven by reactive watch streams.
- **Localization:** ARB files (`app_en.arb` / `app_ru.arb`) + generated `AppLocalizations`; `LocaleController` (system/en/ru), persisted in `shared_preferences`.
- **Theming:** Material 3 light/dark `ThemeData` factories; `ThemeController` (system/light/dark), persisted in `shared_preferences`.
- **Models:** plain-Dart domain classes; Drift-generated row classes for tables.
- **Conventions:** committed `.g.dart`, feature-first folders, no hard-coded UI strings, `Key(...)` on interactive widgets, `Justfile` (`just lint` / `just test`), `architecture/*.md` living docs + `planning/changes/` history.

**Alternative considered:** a lighter stack (Provider + sqflite/Hive, no codegen). Rejected — matching habbits maximizes reuse and maintainability; there is no reason to diverge for a simpler app.

## Data Model (Drift)

Two tables. Foreign keys enforced (`PRAGMA foreign_keys = ON`), mirroring habbits.

```
Categories
  id          int  autoIncrement  PK
  name        text
  color       int                  // ARGB int, chosen from a fixed palette (cf. kHabitPalette)
  emoji       text  nullable       // optional glyph shown beside the name
  collapsed   bool  default false  // section expand/collapse state, persisted
  sortOrder   int                  // manual order of category sections
  createdAt   dateTime

Tasks                              // a "to-do item"
  id          int  autoIncrement  PK
  categoryId  int   -> Categories.id  (onDelete: cascade)
  name        text
  sortOrder   int                  // manual order within its category's active list
  createdAt   dateTime
  archivedAt  dateTime  nullable   // null = active; non-null = completed/archived at this instant
```

### Invariants & rules

- **Active vs archived** is derived from `Tasks.archivedAt`: `null` = active, non-null = archived. No separate archive table.
- **Complete** sets `archivedAt = now`. **Restore** sets `archivedAt = null`; the item reappears in its category's active list (uncheck-to-restore pattern).
- **30-day clock** starts at `archivedAt` (the completion instant).
- **Cleanup**: delete tasks where `archivedAt` is older than `now − 30 days`. Triggered (a) on app startup and (b) when the Archive view is opened. No background timer — pragmatic, reliable, matches habbits' avoidance of background work.
- **Manual clear**: a "Clear archive now" action deletes *all* archived tasks (`archivedAt != null`), regardless of age, after confirmation.
- **Cascade delete**: deleting a category removes all its tasks (active and archived) via FK `onDelete: cascade`. Confirmed via a dialog stating the counts. No orphaned tasks can exist, so restore never targets a missing category.
- **Ordering**: each category has a unique `sortOrder`; each task has a unique `sortOrder` within its category's active list. Reorders run in a single transaction that rewrites the affected `sortOrder` values to `0..n-1`, exactly like habbits' `reorderHabits`.
- `schemaVersion = 1`; `beforeOpen` enables foreign keys.

## Screens & UX

A single home screen with a top **segmented switcher: Active ▸ Archive**. Both views share the same grouped-by-category, collapsible layout.

### Active view (default)

- Items grouped under colored, collapsible **category headers**. Header = color swatch + optional emoji + name + open-item count + collapse chevron. Tapping the header toggles `collapsed`.
- **Item row**: a tap-target completion circle + the item name. Completing (via tap or **swipe-right**, with haptic feedback) archives the item (`archivedAt = now`) and shows an **undo toast (~5s)** that restores it. The tap checkbox is always present as an accessible fallback to the swipe.
- **Drag-to-reorder**: items within a category; category sections via header drag.
- **Add item**: FAB → **keep-keyboard-open quick add**: the name field stays focused after each Add so several items can be entered in a row, all into the current/last-used category (a category picker is available to change it); a Done button closes. The last-used category is remembered for the next quick add.
- **Add category**: app-bar action → dialog with name + color (from palette) + optional emoji.
- **Edit**: trailing menu / long-press on an item → rename or move to another category; on a category header → rename, recolor, change emoji, or delete (cascade, count-confirm dialog).
- **Empty states**: no categories ("No categories yet — add one"); a category with no active items shows a short hint.

### Archive view

- Same grouped, collapsible layout. Within each category, items are ordered newest-first by `archivedAt`.
- Each archived item shows its **completion date** (locale-formatted) and **"auto-removes in N days"** (computed from `archivedAt + 30d − now`), localized with correct plural forms.
- Tapping an item **restores** it (`archivedAt = null`); it returns to its category in the Active view, with an undo toast.
- **Clear archive now**: an app-bar action (visible in Archive view) deletes all archived items after a confirmation dialog.
- **Empty state**: "Nothing archived".

## Cross-Cutting Concerns

- **Theme**: Material 3 light/dark + system; `ThemeController`; persisted. Identical pattern to habbits (`theme.dart` + `theme_controller.dart`).
- **Localization**: every UI string from `AppLocalizations`. **Russian requires 4 CLDR plural forms** (one/few/many/other) for all counters — open-item counts, "N items", "auto-removes in N days". `LocaleController` offers system/en/ru, persisted. Date/number formatting via `intl` with the active locale.
- **Accessibility**: category color is *always* paired with the category name (and optional emoji) — never color alone (WCAG 1.4.1). Screen-reader labels on the completion circle and category color swatches. Touch targets ≥ 44dp. Layouts tolerate Russian text expansion (no fixed-width truncation).
- **Cleanup trigger**: a small startup hook + an Archive-view entry hook call the repository's purge method.

## Architecture Layout (target)

Mirrors habbits' feature-first tree:

```
lib/
  main.dart
  l10n/                         app_en.arb, app_ru.arb, generated *_localizations.dart
  domain/
    models/                     category + task value/transfer classes
    archive_cleanup.dart        pure: is-expired, days-remaining
    reorder.dart                pure: reorder id-list logic
  data/
    repositories/
      todo_repository.dart      public data seam over the DAO
      settings_repository.dart  locale/theme tokens (shared_preferences)
    services/database/
      database.dart             Drift schema (Categories, Tasks)
      todo_dao.dart             CRUD, complete/restore, reorder, purge, watch streams
      database_providers.dart   Riverpod providers
  ui/
    core/                       theme.dart, theme_controller.dart, locale_controller.dart, category_colors.dart
    home/                       home_screen.dart, home_view_model.dart (Active/Archive switcher), widgets/
    widgets/                    dialogs (add/edit category, add/edit item, delete-confirm)
```

## Testing Strategy

Mirror habbits' three-tier approach.

- **Unit (pure domain):** 30-day expiry cutoff, "days remaining" computation, reorder list logic.
- **Widget (in-memory Drift, `NativeDatabase.memory()`):** add category; add item; complete → archive → undo; restore from archive; collapse/expand persistence; cascade-delete confirm; Active/Archive switch; English and Russian plural rendering of counters.
- **Integration (file-backed Drift):** create → complete → relaunch → item still archived → restore persists across relaunch.
- Interactive widgets carry `Key(...)` for test selection; tests use Riverpod `ProviderScope` overrides for the DB.

## Open Questions

None blocking. Future considerations (explicitly deferred): search, due dates/reminders, sync.
