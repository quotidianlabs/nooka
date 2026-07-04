# Archive & retention

Completing a task sets `archivedAt = now`; restoring clears it and re-appends the
task to its category's active order. The `now` for `archivedAt` and for the purge
cutoff is sourced from the injectable **Clock seam** (`domain/clock.dart`):
`TodoRepository` holds a `Clock` (production `SystemClock`, overridable with a
`FixedClock` in tests), so archive-lifecycle time is deterministic through the
repository's interface. (A task's `createdAt` is non-injected write-only metadata
the DAO stamps directly — see the decision record.) Archived tasks are retained
`archiveRetentionDays` (30) days from `archivedAt`, then purged. Retention is
measured in elapsed 24-hour periods, not local calendar days, so a DST
transition can shift the boundary by ~an hour (acceptable at a 30-day window).

Purge triggers: app startup (`main`, guarded so a purge failure can't block
boot) and opening the Archive view. No background timer. `daysRemaining` drives
the "auto-removes in N days" label; it rounds the partial day **up**, so a
surviving item never reads 0 and only an already-expired one does. The label's
`now` is recomputed when the app returns to the foreground (lifecycle resume),
so the countdown can't go stale across midnight. Each archived item also shows
its locale-formatted completion date. A manual "Clear archive" action
(`clearArchive`) deletes all archived items regardless of age.

Deleting an active task (`deleteTask`) is distinct from completing it: the row
is hard-deleted immediately and never enters the Archive view (unlike
completing, which sets `archivedAt` and parks the task there for 30 days).

## Dormant recurring tasks share the Archive view

Completing a **recurring** task (non-null `recurrenceCount`/`recurrenceUnit`)
does not archive it: it goes dormant instead, with `archivedAt` left null and
`nextDueAt` set to the next occurrence. The Archive view renders a category
whenever it has archived tasks **or** dormant ones, listing dormant rows ahead
of archived rows (`[...dormantTasks, ...archivedTasks]`). A dormant row shows a
`schedule` icon and a "Returns in N days" subtitle instead of the archived
row's checkmark and completion date.

Tapping a dormant row opens an action sheet (`Return now` / `Delete`) rather
than restoring it directly, since restoring an active-vs-dormant row means
different things: `Return now` calls `returnTaskNow`, waking the task back to
Active immediately; `Delete` hard-deletes it, same as an active task's delete.
Tapping an archived row still restores it directly, unchanged.

"Clear archive" (`clearArchive`) and its confirmation count remain scoped to
**archived** tasks only — dormant tasks are excluded from both the count and
the sweep, at the DAO layer. Dormant tasks leave the Archive view only via
`returnTaskNow` (manual or automatic wake, see [home coordination](home-coordination.md))
or explicit delete, never via the retention purge or "Clear archive".
