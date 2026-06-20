import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/data/services/database/database_providers.dart';
import 'package:nooka/ui/home/home_view_model.dart';

void main() {
  test('add -> complete -> purge boundary -> restore', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    // Subscribe so the stream provider stays alive.
    final sub = container.listen(homeViewModelProvider, (_, next) {});
    addTearDown(sub.close);

    final vm = container.read(homeViewModelProvider.notifier);

    // Create a category + a task.
    final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
    await vm.addTask(cat, 'Sweep');
    var snapshot = await db.todoDao.watchCategoriesWithTasks().first;
    final task = snapshot.first.activeTasks.single;
    expect(task.name, 'Sweep');

    // Complete it → archived.
    await vm.completeTask(task.id);
    snapshot = await db.todoDao.watchCategoriesWithTasks().first;
    expect(snapshot.first.activeTasks, isEmpty);
    expect(snapshot.first.archivedTasks.single.id, task.id);

    // Backdate the archive to 29 days: purge at 'now' must NOT delete it.
    final now = DateTime(2026, 6, 17);
    await db.todoDao.completeTask(
      task.id,
      now.subtract(const Duration(days: 29)),
    );
    expect(await db.todoDao.purgeExpired(now), 0);

    // Restore it (still within retention) → back to active.
    await vm.restoreTask(task.id);
    snapshot = await db.todoDao.watchCategoriesWithTasks().first;
    expect(snapshot.first.activeTasks.single.id, task.id);
    expect(snapshot.first.archivedTasks, isEmpty);
  });
}
