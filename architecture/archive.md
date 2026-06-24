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
