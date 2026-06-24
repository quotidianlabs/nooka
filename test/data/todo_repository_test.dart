import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/clock.dart';

void main() {
  late AppDatabase db;
  final fixed = DateTime(2026, 6, 24, 12);
  late TodoRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TodoRepository(db.todoDao, clock: FixedClock(fixed));
  });
  tearDown(() => db.close());

  test('completeTask stamps archivedAt from the clock', () async {
    final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
    final t = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');

    await repo.completeTask(t);

    final row = await (db.select(
      db.tasks,
    )..where((x) => x.id.equals(t))).getSingle();
    expect(row.archivedAt, fixed);
  });

  test('purgeExpired uses the clock for the retention cutoff', () async {
    final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
    final old = await db.todoDao.createTask(categoryId: cat, name: 'old');
    final fresh = await db.todoDao.createTask(categoryId: cat, name: 'fresh');
    // Backdate relative to the fixed clock: one past retention, one within.
    await db.todoDao.completeTask(old, fixed.subtract(const Duration(days: 31)));
    await db.todoDao.completeTask(fresh, fixed.subtract(const Duration(days: 1)));

    final purged = await repo.purgeExpired();

    expect(purged, 1);
    final remaining = await db.select(db.tasks).get();
    expect(remaining.map((t) => t.name), ['fresh']);
  });
}
