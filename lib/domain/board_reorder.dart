import 'models/category_with_tasks.dart';
import 'reorder.dart';

/// The decision a drag-board drop resolves to. Pure data; the UI layer
/// interprets it (issuing the guarded mutations).
sealed class ReorderPlan {
  const ReorderPlan();
}

/// Stale/out-of-range drop — the snapshot no longer matches; do nothing.
class ReorderNoop extends ReorderPlan {
  const ReorderNoop();
}

/// Reorder tasks within a single category.
class ReorderWithin extends ReorderPlan {
  const ReorderWithin(this.orderedIds);
  final List<int> orderedIds;
}

/// Move [movedId] into [toCategoryId] at the resolved position.
/// [expandCategoryId] is set when the destination was collapsed and must be
/// auto-expanded so the moved task is not hidden (H3); null otherwise.
class ReorderAcross extends ReorderPlan {
  const ReorderAcross({
    required this.movedId,
    required this.toCategoryId,
    required this.orderedTargetIds,
    required this.expandCategoryId,
  });
  final int movedId;
  final int toCategoryId;
  final List<int> orderedTargetIds;
  final int? expandCategoryId;
}

/// Resolve a `drag_and_drop_lists` drop against the CURRENT [cats] snapshot.
/// All four indices are validated against the live snapshot so a drop that
/// raced a stream emission becomes a [ReorderNoop] instead of a RangeError
/// or a wrong-task move (H4).
ReorderPlan planReorder(
  List<CategoryWithTasks> cats,
  int oldItemIndex,
  int oldListIndex,
  int newItemIndex,
  int newListIndex,
) {
  if (oldListIndex < 0 ||
      oldListIndex >= cats.length ||
      newListIndex < 0 ||
      newListIndex >= cats.length) {
    return const ReorderNoop();
  }
  final from = cats[oldListIndex];
  final to = cats[newListIndex];
  if (oldItemIndex < 0 || oldItemIndex >= from.activeTasks.length) {
    return const ReorderNoop();
  }
  // An insert index may equal the list length (append); reject only beyond.
  if (newItemIndex < 0 || newItemIndex > to.activeTasks.length) {
    return const ReorderNoop();
  }

  final movedId = from.activeTasks[oldItemIndex].id;
  if (oldListIndex == newListIndex) {
    final ids = [for (final t in from.activeTasks) t.id];
    return ReorderWithin(reorderedIds(ids, oldItemIndex, newItemIndex));
  }
  final targetIds = [for (final t in to.activeTasks) t.id];
  return ReorderAcross(
    movedId: movedId,
    toCategoryId: to.category.id,
    orderedTargetIds: insertedAt(targetIds, movedId, newItemIndex),
    expandCategoryId: to.category.collapsed ? to.category.id : null,
  );
}
