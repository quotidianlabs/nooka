---
summary: Add completion-relative recurring tasks — a task can repeat every N days/weeks/months after each completion, going dormant (hidden, shown in Archive as "Returns in N days") until it wakes back into its slot.
---

# Design: Recurring tasks (completion-relative)

## Summary

Let a task **repeat**. When a recurring task is completed it does not archive —
it goes **dormant**: hidden from the Active list until an interval measured
**from the completion instant** elapses, then it wakes back into its original
slot. The interval is a count + unit (`every 3 days` / `2 weeks` / `1 month`).
Dormant tasks are visible in the existing **Archive** view labelled "Returns in
N days" (distinct from archived tasks' "Auto-removes in N days"), where they can
be woken early ("Return now") or deleted (ending the recurrence). This is the
first real schema migration (`schemaVersion` 1 → 2, additive nullable columns)
and the first bump of the backup format (v1 → v2, backward compatible).

## Motivation

nooka today has no notion of a repeating task. Recurring chores — water the
plants, pay rent, weekly review — must be re-added by hand every time, or
completed-and-then-recreated. This is the most common gap in a to-do app that is
otherwise complete. The app is deliberately **dateless** (tasks are ordered list
items; completion just stamps `archivedAt`), so we choose the recurrence model
that fits that grain: **relative to completion**, not a fixed calendar schedule.
"Water the plants every 3 days" means 3 days after I last did it — no due dates,
no calendar view, no pile-up of missed occurrences.

## Non-goals

- **Fixed-calendar / day-of-week recurrence** ("every Monday", "1st of the
  month") — requires introducing due dates and a date-driven surface; a much
  larger change against a dateless app. Explicitly deferred.
- **End dates or occurrence caps** ("repeat 10 times", "until August") — a
  recurring task runs until the user turns Repeat off or deletes it.
- **Notifications / reminders** — the app has none; recurrence is purely "the
  task reappears in the list". Out of scope.
- **A dedicated "Upcoming" surface** — dormant tasks reuse the Archive view; no
  new top-level screen.
- **Per-occurrence completion history** — the single-row model does not archive
  each completion (see Design §3); the app already keeps only a 30-day archive.

## Design

### 1. Recurrence model — completion-relative, single dormant row

A recurring task is **one row** that cycles through three derived states; there
is no new status column. `archivedAt` continues to mean "archived"; a new
nullable `nextDueAt` means "dormant until this instant".

| State | Condition | Where it shows |
|---|---|---|
| **Active** | `archivedAt == null` AND `nextDueAt == null` | Active list, in its `sortOrder` slot |
| **Dormant** | `archivedAt == null` AND `nextDueAt != null` | Archive view, "Returns in N days" |
| **Archived** | `archivedAt != null` | Archive view, "Auto-removes in N days" (unchanged) |

`nextDueAt == null` is the single source of "awake". Completing a recurring task
sets `nextDueAt` (and never `archivedAt`); waking clears it. The two time
drivers stay cleanly separated: **`archivedAt` drives purge** (unchanged;
dormant rows have `archivedAt == null` so purge and "Clear archive" never touch
them), **`nextDueAt` drives wake**.

Completion is measured from the **completion instant**, not the previous due
date: a task completed late (it woke days ago and sat active) schedules its next
return from *now*, so there is no drift or pile-up. This is the definition of
the completion-relative model.

### 2. Pure domain — `lib/domain/recurrence.dart`

New pure module (no Flutter/Drift imports), tested with the existing
`FixedClock`, mirroring `domain/archive.dart`:

```dart
/// Unit of a recurrence interval. Stored as its index (intEnum) in the DB.
enum RecurrenceUnit { days, weeks, months }

/// The instant a recurring task returns, given when it was completed and the
/// interval. Days/weeks are exact Durations; months add calendar months with
/// end-of-month clamping (complete Jan 31 + 1 month -> Feb 28/29).
DateTime nextDueDate(DateTime completedAt, int count, RecurrenceUnit unit);

/// Whole days until [nextDueAt] as of [now], for the "Returns in N days" label.
/// Rounds a partial day up and clamps to 0, matching archive.daysRemaining.
int daysUntilDue(DateTime nextDueAt, DateTime now);
```

Month math: `days`/`weeks` use `Duration(days: count * (unit == weeks ? 7 : 1))`.
`months` uses `DateTime(y, m + count, min(day, lastDayOf(y, m + count)), ...)`,
preserving the time-of-day and clamping the day into the target month.

### 3. Schema + migration — `schemaVersion` 1 → 2

`Tasks` gains three nullable columns (`tables.dart`):

```dart
IntColumn get recurrenceCount => integer().nullable()();
IntColumn get recurrenceUnit => intEnum<RecurrenceUnit>().nullable()();
DateTimeColumn get nextDueAt => dateTime().nullable()(); // non-null = dormant
```

`recurrenceCount` + `recurrenceUnit` are set together; both null ⇒ a normal task.
`database.dart` bumps `schemaVersion` to 2 and adds an `onUpgrade` step:

```dart
onUpgrade: (m, from, to) async {
  if (from < 2) {
    await m.addColumn(tasks, tasks.recurrenceCount);
    await m.addColumn(tasks, tasks.recurrenceUnit);
    await m.addColumn(tasks, tasks.nextDueAt);
  }
},
```

Additive and nullable: every existing row opens as a non-recurring, active task.
The `beforeOpen` `PRAGMA foreign_keys = ON` is preserved.

### 4. DAO — `lib/data/services/database/todo_dao.dart`

- **`createTask`** / **edit path** gain `int? recurrenceCount,
  RecurrenceUnit? recurrenceUnit` and write them. Making a task recurring does
  **not** set `nextDueAt` — a recurring task stays active until it is completed.
  `renameAndMove` extends to also write the recurrence fields (one transaction).
- **`completeTask(id, now)`** branches on the row's recurrence. It reads the row
  first; if `recurrenceCount != null` it writes
  `nextDueAt = nextDueDate(now, count, unit)` and **leaves `sortOrder` and
  `archivedAt` untouched** (the row keeps its slot, gap left open exactly like
  `deleteTask`); otherwise it writes `archivedAt = now` as today.
- **`wakeTask(int id)`** — clears `nextDueAt`, leaving `sortOrder` intact so the
  task returns to its original position. Used by "Return now" and by undo of a
  recurring completion.
- **`wakeDueTasks(DateTime now)`** — clears `nextDueAt` for every dormant row
  where `nextDueAt <= now`, in one statement. The reveal write the watch stream
  re-renders. Returns the count woken.
- **`_nextTaskOrder`** additionally excludes dormant rows
  (`& t.nextDueAt.isNull()`) so a dormant task is never counted when appending
  or renumbering active tasks.
- **`purgeExpired`** / **`clearArchive`** are unchanged: both already filter
  `archivedAt.isNotNull()`, so dormant rows (`archivedAt == null`) are naturally
  excluded — pending recurrences are never purged or cleared.
- **`importReplace`** carries the three new fields into each
  `TasksCompanion.insert`.

`watchCategoriesWithTasks` is unchanged — it still returns every task; the
active/dormant/archived split happens in the model getter (§5).

### 5. Model split — `lib/domain/models/category_with_tasks.dart`

The single `activeTasks` getter becomes a three-way split:

```dart
List<Task> get activeTasks =>            // Active list
    [for (final t in tasks) if (t.archivedAt == null && t.nextDueAt == null) t];

List<Task> get dormantTasks =>           // Archive: "Returns in N days"
    [for (final t in tasks) if (t.archivedAt == null && t.nextDueAt != null) t]
      ..sort((a, b) => a.nextDueAt!.compareTo(b.nextDueAt!)); // soonest first

List<Task> get archivedTasks =>          // Archive: "Auto-removes in N days"
    [for (final t in tasks) if (t.archivedAt != null) t]
      ..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));
```

### 6. Repository + ViewModel

**`TodoRepository`**: `createTask` / `editTask` gain the recurrence params;
`completeTask` keeps its signature (branching lives in the DAO, `now` from the
`Clock` seam as today); new pass-throughs `wakeTask(int id)` and
`wakeDueTasks()` (sourcing `now` from the injected `Clock`).

**`HomeViewModel`** (`ui/home/home_view_model.dart`):
- `addTask` / `editTask` thread the recurrence fields through, unchanged outcome
  pattern.
- **`returnTaskNow(int id)`** — `_run(() => _repo.wakeTask(id))`. Used by both
  the Archive "Return now" action and the undo of a recurring completion.
- `completeTask` is unchanged at the VM seam (the DAO decides dormant vs
  archive). The VM still has no undo concept.
- `wakeDueTasks` is invoked at the same triggers purge already uses — app
  startup (`main`, guarded) and app resume — so a dormant task whose time has
  come is revealed the next time the app is opened or foregrounded. No timer.
  Consistent with the archive countdown's resume-recompute.

### 7. Widget / UI (`ui/home/home_screen.dart` + edit dialog)

- **Edit dialog — the Repeat control (Layout A, approved).** A "Repeat" toggle;
  when on, a count stepper and a `days / weeks / months` segmented control, plus
  a live summary line: **"Returns 3 weeks after you complete it."** Default when
  first toggled on: every 1 day. Turning Repeat off on an active task clears its
  recurrence. Editing is offered on **active** tasks only (current behavior);
  dormant tasks are managed from the Archive.
- **Active list marker (Layout B, approved).** A recurring active task shows a
  sub-line under its name: **"🔁 Every 3 weeks"**.
- **Archive view.** Renders `dormantTasks` (label "Returns in N days", from
  `daysUntilDue`) alongside `archivedTasks` (existing "Auto-removes in N days").
  A dormant row offers two actions (same menu affordance archived items use):
  **Return now** → `returnTaskNow(id)`; **Delete** → existing `deleteTask(id)`,
  ending the recurrence.
- **Completion undo.** Completing shows the existing "Item completed · Undo"
  toast. The widget already holds the full `Task`; the undo callback routes on
  `task.recurrenceCount != null`: recurring → `returnTaskNow(id)` (restores it
  to its slot by clearing `nextDueAt`), non-recurring → existing
  `restoreTask(id)`.

### 8. Backup format — v1 → v2 (backward compatible)

`BackupTask` (`domain/models/backup_data.dart`) gains `recurrenceCount`,
`recurrenceUnit` (stored as its int index), and `nextDueAt`, so a dormant
recurring task survives export/restore. In `backup_codec.dart`:

- `_currentVersion` → `2`; `buildBackup` / `encodeBackup` emit the new fields.
- `decodeBackup` **accepts version 1 and 2** (`version is int && version >= 1 &&
  version <= _currentVersion`). A v1 task (no recurrence keys) decodes with all
  three fields null — an existing backup still imports. A v2 task reads the
  fields, tolerating absent keys as null.
- `importReplace` (§4) writes the fields back.
- After an import, dormant rows that are already due are revealed by the normal
  startup/resume `wakeDueTasks`; `applyImport` additionally calls `wakeDueTasks`
  so a restored-and-already-due task appears immediately.

### 9. i18n (`lib/l10n`, EN + RU)

New bilingual ARB keys (RU uses the four CLDR plural forms already used by the
archive countdown):

- `repeatToggle` ("Repeat"), unit labels for the segmented control.
- `recurrenceSummary` — "Returns {count} {unit} after you complete it."
- `recurrenceEvery` — "Every {count} {unit}" (Active sub-line).
- `returnsInDays({count})` — "Returns in N days" (plural).
- `returnNow` ("Return now"); reuse existing `delete`.

`{count}`+`{unit}` phrasing uses ICU plurals per unit; RU declines the unit and
count together, consistent with existing counters.

## Operations

None. No infra, no external accounts. The DB migration runs automatically on
first launch of the new build; the backup format change is backward compatible.

## Out of scope

See Non-goals. The DAO/domain seams (`nextDueDate`, `wakeTask`) leave room for a
future fixed-calendar mode or an "Upcoming" view without rework.

## Testing

TDD — a failing test precedes each piece.

- **Domain** (`test/domain/recurrence_test.dart`): `nextDueDate` for days,
  weeks, months; month-end clamp (Jan 31 + 1 month → Feb 28 / 29 leap year);
  time-of-day preserved. `daysUntilDue` rounds up and clamps to 0.
- **DAO** (`test/data/todo_dao_test.dart`, `FixedClock`): completing a recurring
  task sets `nextDueAt` and leaves `archivedAt` null and `sortOrder` unchanged;
  completing a non-recurring task is unchanged; `wakeTask` and `wakeDueTasks`
  clear `nextDueAt` (only for due rows) and restore the row to the active list in
  its slot; `_nextTaskOrder` ignores dormant rows; `purgeExpired` /
  `clearArchive` leave dormant rows untouched; `importReplace` round-trips the
  recurrence fields.
- **Model** (`test/domain/category_with_tasks_test.dart`): the three-way split
  classifies active / dormant / archived correctly; dormant sorted soonest-first.
- **Migration** (`test/data/migration_test.dart`): a v1 DB opens under v2 with
  the new columns null and existing tasks intact.
- **Codec** (`test/domain/backup_codec_test.dart`): v2 round-trips the new
  fields; a v1 file (no recurrence keys) still decodes with nulls; v2 encode sets
  `version: 2`.
- **ViewModel** (`test/ui/home_view_model_test.dart`): `addTask` / `editTask`
  persist recurrence; `returnTaskNow` returns `success` / `failure`.
- **Widget** (home + archive screen tests): the edit dialog shows the Repeat
  control and summary; a recurring active task shows the "🔁 Every N …"
  sub-line; completing a recurring task removes it from Active and the undo toast
  restores it to its slot; the Archive shows a dormant row with "Returns in N
  days" and its Return now / Delete actions.
- `just test`, `just coverage` (gated %) pass; `just lint-ci` clean.

## Risk

- **Time passes while the app is foregrounded** (low × low): a dormant task whose
  `nextDueAt` elapses mid-session is not revealed until the next startup/resume
  `wakeDueTasks`. Acceptable and identical to how the archive countdown label is
  only recomputed on resume.
- **`sortOrder` collision after a reorder while dormant** (low × low): renumbering
  active tasks while one is dormant can leave the dormant row's preserved
  `sortOrder` equal to an active row's. On wake the existing `(sortOrder, id)`
  ordering breaks the tie deterministically by id — no crash, lands adjacent to
  its old position. Same invariant the delete/undo gap already relies on.
- **Old (v1) backup import** (medium × high if mishandled): mitigated by the
  decoder accepting both versions; covered by a v1-decode test so a regression
  can't silently reject existing user backups.
- **Migration on existing installs** (low × high): additive nullable columns can
  never fail on existing rows; covered by the migration test.
- **Undo/return after the task's category was deleted mid-toast** (low × low):
  the wake write matches zero rows or the row is already gone; `_run` catches any
  throw and surfaces `actionFailed`; the stream renders the truth.

## Architecture docs to update (same PR)

- `architecture/data-model.md` — the three new columns; the active/dormant/
  archived derivation; recurring completion sets `nextDueAt` (keeps slot, no
  renumber), wake clears it; `_nextTaskOrder` ignores dormant rows.
- `architecture/archive.md` — dormant recurring tasks appear in the Archive as
  "Returns in N days"; wake runs at startup + resume alongside purge; purge /
  "Clear archive" never touch dormant rows; Return now / Delete actions.
- `architecture/home-coordination.md` — `addTask` / `editTask` carry recurrence;
  new `returnTaskNow` intent; completion undo routes recurring →
  `returnTaskNow`, non-recurring → `restoreTask`.
- `architecture/backup-io.md` — format v2: the three new task fields; decoder
  accepts v1 + v2; `applyImport` wakes already-due restored tasks.
- `architecture/i18n-theming.md` — the new recurrence keys (EN + RU plurals).
