# Archive & retention

Completing a task sets `archivedAt = now`; restoring clears it and re-appends the
task to its category's active order. Archived tasks are retained
`archiveRetentionDays` (30) days from `archivedAt`, then purged.

Purge triggers: app startup (`main`) and opening the Archive view. No background
timer. `daysRemaining` drives the "auto-removes in N days" label; each archived
item also shows its locale-formatted completion date. A manual "Clear archive"
action (`clearArchive`) deletes all archived items regardless of age.
