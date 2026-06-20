# Data model

Two Drift tables (`schemaVersion = 1`, foreign keys ON).

**Categories**: id, name, color (ARGB int), emoji (nullable), collapsed (bool),
sortOrder, createdAt.

**Tasks**: id, categoryId → Categories (onDelete cascade), name, sortOrder,
createdAt, archivedAt (nullable; null = active, non-null = archived instant).

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
rebuild).
