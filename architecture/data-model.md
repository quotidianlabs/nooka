# Data model

Two Drift tables (`schemaVersion = 1`, foreign keys ON).

**Categories**: id, name, color (ARGB int), emoji (nullable), collapsed (bool),
sortOrder, createdAt.

**Tasks**: id, categoryId → Categories (onDelete cascade), name, sortOrder,
createdAt, archivedAt (nullable; null = active, non-null = archived instant).

Active vs archived is derived from `archivedAt`. Deleting a category cascades to
its tasks. Ordering invariants are rewritten transactionally on reorder.

Tasks can be reordered within a category and moved to another category at a
chosen position; both renumber `sortOrder` transactionally (`reorderTasks` /
`moveTaskToCategoryAt`). Reorder/move is surfaced as a drag board on the Active
view only.
