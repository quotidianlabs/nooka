import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nooka/data/repositories/remembered_category.dart';
import 'package:nooka/data/repositories/settings_repository.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/data/services/database/database_providers.dart';
import 'package:nooka/domain/models/category_with_tasks.dart';
import 'package:nooka/ui/home/home_view_model.dart';

/// createTask always throws; everything else (incl. the watch stream) is the
/// real DAO so the board still loads.
class _ThrowingCreateTaskRepo extends TodoRepository {
  _ThrowingCreateTaskRepo(super.dao);
  @override
  Future<int> createTask({required int categoryId, required String name}) =>
      Future.error(Exception('db locked'));
}

/// purgeExpired always throws.
class _ThrowingMutationRepo extends TodoRepository {
  _ThrowingMutationRepo(super.dao);
  @override
  Future<int> purgeExpired() => Future.error(Exception('locked'));
}

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => db.close());

  /// Builds the VM with the in-memory DB + mock prefs, keeps it alive, and
  /// awaits the first stream emission so `state.value` is populated.
  Future<(ProviderContainer, HomeViewModel)> build({
    TodoRepository? repo,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (repo != null) todoRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    container.listen(homeViewModelProvider, (_, _) {}); // keep alive
    await container.read(homeViewModelProvider.future);
    return (container, container.read(homeViewModelProvider.notifier));
  }

  Future<List<CategoryWithTasks>> snapshot() =>
      db.todoDao.watchCategoriesWithTasks().first;

  group('addTask remembered-category (M4)', () {
    test('addTask remembers the category on success', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final (container, vm) = await build();

      final outcome = await vm.addTask(cat, 'Sweep');

      expect(outcome, CommandOutcome.success);
      expect(container.read(rememberedCategoryProvider).read(), cat);
    });

    test('failed addTask does NOT remember the category', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final (container, vm) = await build(repo: _ThrowingCreateTaskRepo(db.todoDao));

      final outcome = await vm.addTask(cat, 'Sweep');

      expect(outcome, CommandOutcome.failure);
      expect(container.read(rememberedCategoryProvider).read(), isNull);
    });
  });

  group('deleteCategory forgets remembered (M2)', () {
    test('deleting the remembered category clears it', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final (container, vm) = await build();
      await container.read(rememberedCategoryProvider).write(cat);

      final outcome = await vm.deleteCategory(cat);

      expect(outcome, CommandOutcome.success);
      expect(container.read(rememberedCategoryProvider).read(), isNull);
    });

    test('deleting a different category leaves remembered intact', () async {
      final keep = await db.todoDao.createCategory(name: 'Keep', color: 1);
      final other = await db.todoDao.createCategory(name: 'Other', color: 2);
      final (container, vm) = await build();
      await container.read(rememberedCategoryProvider).write(keep);

      await vm.deleteCategory(other);

      expect(container.read(rememberedCategoryProvider).read(), keep);
    });
  });

  group('quickAddDefault', () {
    test('falls back to the first category when nothing remembered', () async {
      final first = await db.todoDao.createCategory(name: 'A', color: 1);
      await db.todoDao.createCategory(name: 'B', color: 2);
      final (_, vm) = await build();

      expect(vm.quickAddDefault(), first);
    });

    test('returns the remembered category when it still exists', () async {
      await db.todoDao.createCategory(name: 'A', color: 1);
      final b = await db.todoDao.createCategory(name: 'B', color: 2);
      final (container, vm) = await build();
      await container.read(rememberedCategoryProvider).write(b);

      expect(vm.quickAddDefault(), b);
    });
  });

  group('dropTask (H3/H4)', () {
    test('reorders tasks within a category', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t1 = await db.todoDao.createTask(categoryId: cat, name: 't1');
      final t2 = await db.todoDao.createTask(categoryId: cat, name: 't2');
      final t3 = await db.todoDao.createTask(categoryId: cat, name: 't3');
      final (_, vm) = await build();

      final outcome = await vm.dropTask(0, 0, 2, 0); // t1 -> end

      expect(outcome, CommandOutcome.success);
      final order = (await snapshot()).first.activeTasks.map((t) => t.id);
      expect(order, [t2, t3, t1]);
    });

    test('moves a task across categories', () async {
      final a = await db.todoDao.createCategory(name: 'A', color: 1);
      final b = await db.todoDao.createCategory(name: 'B', color: 2);
      final a1 = await db.todoDao.createTask(categoryId: a, name: 'a1');
      final b1 = await db.todoDao.createTask(categoryId: b, name: 'b1');
      final (_, vm) = await build();

      final outcome = await vm.dropTask(0, 0, 1, 1); // a1 -> after b1

      expect(outcome, CommandOutcome.success);
      final byName = {for (final c in await snapshot()) c.category.name: c};
      expect(byName['B']!.activeTasks.map((t) => t.id), [b1, a1]);
      expect(byName['A']!.activeTasks, isEmpty);
    });

    test('auto-expands a collapsed destination (H3)', () async {
      final a = await db.todoDao.createCategory(name: 'A', color: 1);
      final b = await db.todoDao.createCategory(name: 'B', color: 2);
      await db.todoDao.createTask(categoryId: a, name: 'a1');
      await db.todoDao.createTask(categoryId: b, name: 'b1');
      await db.todoDao.setCollapsed(b, true);
      final (_, vm) = await build();

      await vm.dropTask(0, 0, 0, 1); // a1 -> into collapsed B

      final byName = {for (final c in await snapshot()) c.category.name: c};
      expect(byName['B']!.category.collapsed, isFalse); // auto-expanded
      expect(byName['B']!.activeTasks.any((t) => t.name == 'a1'), isTrue);
    });

    test('a stale/out-of-range drop is a no-op (H4)', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t1 = await db.todoDao.createTask(categoryId: cat, name: 't1');
      final t2 = await db.todoDao.createTask(categoryId: cat, name: 't2');
      final (_, vm) = await build();

      final outcome = await vm.dropTask(9, 0, 0, 0); // oldItem out of range

      expect(outcome, CommandOutcome.success); // nothing failed
      final order = (await snapshot()).first.activeTasks.map((t) => t.id);
      expect(order, [t1, t2]); // unchanged
    });
  });

  group('toggleActiveCategory remembers on expand', () {
    test('expanding a collapsed category remembers it', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      await db.todoDao.setCollapsed(cat, true);
      final (container, vm) = await build();

      final outcome = await vm.toggleActiveCategory(cat, true); // -> expand

      expect(outcome, CommandOutcome.success);
      expect(container.read(rememberedCategoryProvider).read(), cat);
      expect((await snapshot()).first.category.collapsed, isFalse);
    });

    test('collapsing an expanded category does NOT remember it', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final (container, vm) = await build();

      await vm.toggleActiveCategory(cat, false); // -> collapse

      expect(container.read(rememberedCategoryProvider).read(), isNull);
      expect((await snapshot()).first.category.collapsed, isTrue);
    });
  });

  group('reorderCategories', () {
    test('reorders categories by index', () async {
      final a = await db.todoDao.createCategory(name: 'A', color: 1);
      final b = await db.todoDao.createCategory(name: 'B', color: 2);
      final c = await db.todoDao.createCategory(name: 'C', color: 3);
      final (_, vm) = await build();

      await vm.reorderCategories(0, 2); // A -> end

      final order = (await snapshot()).map((c) => c.category.id);
      expect(order, [b, c, a]);
    });
  });

  group('complete / restore', () {
    test('completeTask archives the task', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
      final (_, vm) = await build();

      final outcome = await vm.completeTask(t);

      expect(outcome, CommandOutcome.success);
      final cwt = (await snapshot()).first;
      expect(cwt.activeTasks, isEmpty);
      expect(cwt.archivedTasks.map((t) => t.id), [t]);
    });

    test('restoreTask returns an archived task to active', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
      await db.todoDao.completeTask(t, DateTime(2026, 6, 1));
      final (_, vm) = await build();

      final outcome = await vm.restoreTask(t);

      expect(outcome, CommandOutcome.success);
      final cwt = (await snapshot()).first;
      expect(cwt.activeTasks.map((t) => t.id), [t]);
      expect(cwt.archivedTasks, isEmpty);
    });
  });

  group('editTask', () {
    test('renames and moves when the category changes', () async {
      final a = await db.todoDao.createCategory(name: 'A', color: 1);
      final b = await db.todoDao.createCategory(name: 'B', color: 2);
      final t = await db.todoDao.createTask(categoryId: a, name: 'old');
      final (_, vm) = await build();

      final outcome = await vm.editTask(t, 'new', b);

      expect(outcome, CommandOutcome.success);
      final byName = {for (final c in await snapshot()) c.category.name: c};
      expect(byName['A']!.activeTasks, isEmpty);
      final moved = byName['B']!.activeTasks.single;
      expect(moved.id, t);
      expect(moved.name, 'new');
    });

    test('renames without moving when the category is unchanged', () async {
      final a = await db.todoDao.createCategory(name: 'A', color: 1);
      final t = await db.todoDao.createTask(categoryId: a, name: 'old');
      final (_, vm) = await build();

      await vm.editTask(t, 'renamed', a);

      final task = (await snapshot()).first.activeTasks.single;
      expect(task.name, 'renamed');
      expect(task.categoryId, a);
    });
  });

  group('failure outcomes', () {
    test('a throwing mutation returns CommandOutcome.failure', () async {
      await db.todoDao.createCategory(name: 'Home', color: 1);
      final (_, vm) = await build(repo: _ThrowingMutationRepo(db.todoDao));

      expect(await vm.purgeExpired(), CommandOutcome.failure);
    });
  });
}
