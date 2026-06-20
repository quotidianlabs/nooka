import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/board_reorder.dart';
import 'package:nooka/domain/models/category_with_tasks.dart';

Category _cat(int id, {bool collapsed = false}) => Category(
  id: id,
  name: 'C$id',
  color: 0xFF009688,
  emoji: null,
  collapsed: collapsed,
  sortOrder: id,
  createdAt: DateTime(2026, 1, 1),
);

Task _task(int id, int categoryId) => Task(
  id: id,
  categoryId: categoryId,
  name: 'T$id',
  sortOrder: id,
  createdAt: DateTime(2026, 1, 1),
  archivedAt: null,
);

// CategoryWithTasks uses positional parameters: (category, tasks)
CategoryWithTasks _cwt(Category c, List<Task> tasks) =>
    CategoryWithTasks(c, tasks);

void main() {
  // Two categories: list 0 = {t1,t2}, list 1 = {t3}.
  List<CategoryWithTasks> snapshot({bool dstCollapsed = false}) => [
    _cwt(_cat(1), [_task(1, 1), _task(2, 1)]),
    _cwt(_cat(2, collapsed: dstCollapsed), [_task(3, 2)]),
  ];

  test('out-of-range list index returns ReorderNoop', () {
    expect(planReorder(snapshot(), 0, 0, 0, 5), isA<ReorderNoop>());
    expect(planReorder(snapshot(), 0, 9, 0, 0), isA<ReorderNoop>());
  });

  test('out-of-range item index returns ReorderNoop', () {
    // list 0 has 2 items; item index 2 is out of range for a same-list move.
    expect(planReorder(snapshot(), 2, 0, 0, 0), isA<ReorderNoop>());
  });

  test('within-category drop returns ReorderWithin with reordered ids', () {
    final plan = planReorder(snapshot(), 0, 0, 1, 0);
    expect(plan, isA<ReorderWithin>());
    expect((plan as ReorderWithin).orderedIds, [2, 1]);
  });

  test('cross-category drop into an expanded destination does not expand', () {
    final plan = planReorder(snapshot(), 0, 0, 0, 1);
    expect(plan, isA<ReorderAcross>());
    final across = plan as ReorderAcross;
    expect(across.movedId, 1);
    expect(across.toCategoryId, 2);
    expect(across.orderedTargetIds, [1, 3]);
    expect(across.expandCategoryId, isNull);
  });

  test('cross-category drop into a collapsed destination expands it (H3)', () {
    final plan =
        planReorder(snapshot(dstCollapsed: true), 0, 0, 1, 1) as ReorderAcross;
    expect(plan.expandCategoryId, 2);
    expect(plan.orderedTargetIds, [3, 1]); // appended at index 1
  });

  test('append index (== length) is allowed, not a no-op', () {
    // destination list 1 has length 1; newItemIndex 1 appends.
    expect(planReorder(snapshot(), 0, 0, 1, 1), isA<ReorderAcross>());
  });
}
