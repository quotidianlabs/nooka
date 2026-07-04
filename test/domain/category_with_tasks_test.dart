import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/models/category_with_tasks.dart';
import 'package:nooka/domain/recurrence.dart';

Task _task({
  required int id,
  DateTime? archivedAt,
  int? recurrenceCount,
  RecurrenceUnit? recurrenceUnit,
  DateTime? nextDueAt,
}) => Task(
  id: id,
  categoryId: 1,
  name: 't$id',
  sortOrder: id,
  createdAt: DateTime(2026, 1, 1),
  archivedAt: archivedAt,
  recurrenceCount: recurrenceCount,
  recurrenceUnit: recurrenceUnit,
  nextDueAt: nextDueAt,
);

void main() {
  final category = Category(
    id: 1,
    name: 'Home',
    color: 1,
    emoji: null,
    collapsed: false,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  test('splits active, dormant, and archived by the derived rules', () {
    final active = _task(id: 1);
    final dormantSoon = _task(
      id: 2,
      recurrenceCount: 1,
      recurrenceUnit: RecurrenceUnit.days,
      nextDueAt: DateTime(2026, 7, 5),
    );
    final dormantLater = _task(
      id: 3,
      recurrenceCount: 1,
      recurrenceUnit: RecurrenceUnit.days,
      nextDueAt: DateTime(2026, 7, 20),
    );
    final archived = _task(id: 4, archivedAt: DateTime(2026, 6, 1));

    final cwt = CategoryWithTasks(category, [
      active,
      dormantLater,
      dormantSoon,
      archived,
    ]);

    expect(cwt.activeTasks.map((t) => t.id), [1]);
    expect(cwt.dormantTasks.map((t) => t.id), [2, 3]); // soonest first
    expect(cwt.archivedTasks.map((t) => t.id), [4]);
  });
}
