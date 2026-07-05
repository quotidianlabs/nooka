# Data model

Two Drift tables. `schemaVersion` is `2`; the migration from 1 is additive
(three nullable columns, see below), so every pre-existing row opens
unaffected. Foreign keys ON.

**Categories**: id, name, color (ARGB int), emoji (nullable), collapsed (bool),
sortOrder, createdAt.

**Tasks**: id, categoryId → Categories (onDelete cascade), name, sortOrder,
createdAt, archivedAt (nullable; null = active, non-null = archived instant),
recurrenceCount (nullable int), recurrenceUnit (nullable `RecurrenceUnit`,
stored as its `intEnum` index), nextDueAt (nullable; non-null = dormant).

## Active / dormant / archived

A task derives one of three states — there is no status column:

| State | Condition | Where it shows |
|---|---|---|
| Active | `archivedAt == null` AND `nextDueAt == null` | Active list, in its `sortOrder` slot |
| Dormant | `archivedAt == null` AND `nextDueAt != null` | Archive view, "Returns in N days" |
| Archived | `archivedAt != null` | Archive view, "Auto-removes in N days" |

`recurrenceCount` + `recurrenceUnit` are set together (both null ⇒ a
non-recurring task) and mark a task as recurring independent of its current
state; they can be written at creation (`createTask` takes the optional
pair) or by a later edit (`renameAndMove`). `nextDueAt` alone drives the
active/dormant split. Completing a
recurring task (`completeTask`) writes `nextDueAt` to the next occurrence and
leaves `sortOrder` and `archivedAt` untouched — the row keeps its slot with a
gap left open, exactly like `deleteTask` — instead of archiving. Waking it
(`wakeTask`, or the batch `wakeDueTasks(now)` for every dormant row already
due) clears `nextDueAt` back to null, returning it to Active in the same slot.
`_nextTaskOrder` (used by `createTask` and `moveTask`) excludes both archived
and dormant rows, so appending or renumbering active tasks never counts a
dormant one.

`CategoryWithTasks` (`domain/models/category_with_tasks.dart`) exposes this
split as three getters over the same joined row list: `activeTasks`,
`dormantTasks` (soonest-`nextDueAt`-first), and `archivedTasks`
(newest-`archivedAt`-first).

## Ordering, editing, delete/undo

Active vs archived is derived from `archivedAt`. Deleting a category cascades to
its tasks. Ordering invariants are rewritten transactionally on reorder.
`watchCategoriesWithTasks` orders by `sortOrder` then `id` — categories
(`sortOrder`, `id`) before tasks (`sortOrder`, `id`) — so a duplicate
`sortOrder` is broken deterministically by id rather than by row order.

Tasks can be reordered within a category and moved to another category at a
chosen position; both renumber `sortOrder` transactionally (`reorderTasks` /
`moveTaskToCategoryAt`). Reorder/move is surfaced as a drag board on the Active
view only. A drop is resolved by a pure `planReorder` (`domain/board_reorder.dart`)
against a freshly re-read snapshot: indices left stale by a mid-drag stream
update collapse to a no-op, and dropping a task into a collapsed category
auto-expands it so the moved task is never hidden. Editing a category's name,
color, and emoji is a single batched `updateCategory` write (one stream
rebuild). Renaming/moving a task also writes its recurrence fields in the same
transaction (`renameAndMove`). An individual active task can be hard-deleted
(`deleteTask`); the delete leaves a `sortOrder` gap (no renumber), keeping the
slot open for undo. Undo re-inserts the captured row (`insertTask`), restoring
the exact id and position.

## Recurrence math (`lib/domain/recurrence.dart`)

Pure module, no Flutter/Drift imports: `nextDueDate(completedAt, count, unit)`
computes the return instant from the completion instant (not the previous due
date, so a late completion never causes drift or pile-up); days/weeks add an
exact `Duration`, months add calendar months with end-of-month clamping
(completing Jan 31 + 1 month lands on Feb 28/29). `daysUntilDue(nextDueAt, now)`
rounds a partial day up and clamps to 0, for the "Returns in N days" label,
mirroring `domain/archive.dart`'s `daysRemaining`.

## Migration testing

Migrations use Drift's `stepByStep` `onUpgrade` (`database.steps.dart`), whose
steps run against the *pinned* schema snapshot for their version, and are
verified by `SchemaVerifier` (`test/data/migration_test.dart`) against the
per-version snapshots in `drift_schemas/` — checking both that each version
migrates to the declared current schema and that data survives. Per-migration
ritual after bumping `schemaVersion` and writing a `fromNToN+1` step:
`just schema-dump` then `just schema-gen`, and commit the regenerated files. CI
enforces this via `just schema-check` (a `schema` job in `ci.yml`): it re-dumps
and regenerates, then fails if any snapshot or generated file is stale — so a
bump that skips the ritual (or an un-dumped new snapshot) cannot merge.
