import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('categories', () {
    test('createCategory assigns incrementing sortOrder', () async {
      final a = await db.todoDao.createCategory(name: 'Home', color: 1);
      final b = await db.todoDao.createCategory(name: 'Work', color: 2);
      final rows = await db.select(db.categories).get();
      final byId = {for (final c in rows) c.id: c};
      expect(byId[a]!.sortOrder, 0);
      expect(byId[b]!.sortOrder, 1);
    });

    test('deleteCategory cascades to its tasks', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
      await db.todoDao.deleteCategory(cat);
      expect(await db.select(db.tasks).get(), isEmpty);
    });

    test('setCollapsed persists', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      await db.todoDao.setCollapsed(cat, true);
      final row = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(cat))).getSingle();
      expect(row.collapsed, isTrue);
    });
  });

  group('reordering', () {
    test('reorderCategories persists the new order', () async {
      final aId = await db.todoDao.createCategory(name: 'A', color: 1);
      final bId = await db.todoDao.createCategory(name: 'B', color: 2);
      final cId = await db.todoDao.createCategory(name: 'C', color: 3);

      await db.todoDao.reorderCategories([cId, aId, bId]);

      final rows = await (db.select(
        db.categories,
      )..orderBy([(c) => OrderingTerm(expression: c.sortOrder)])).get();
      expect(rows.map((c) => c.name), ['C', 'A', 'B']);
      expect(rows.map((c) => c.sortOrder), [0, 1, 2]);
    });

    test('reorderTasks persists the new order within a category', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t1 = await db.todoDao.createTask(categoryId: cat, name: 't1');
      final t2 = await db.todoDao.createTask(categoryId: cat, name: 't2');
      final t3 = await db.todoDao.createTask(categoryId: cat, name: 't3');

      await db.todoDao.reorderTasks([t3, t1, t2]);

      final rows = await (db.select(
        db.tasks,
      )..orderBy([(t) => OrderingTerm(expression: t.sortOrder)])).get();
      expect(rows.map((t) => t.name), ['t3', 't1', 't2']);
      expect(rows.map((t) => t.sortOrder), [0, 1, 2]);
    });
  });

  group('task lifecycle', () {
    test('completeTask sets archivedAt; restoreTask clears it', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final id = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
      final now = DateTime(2026, 6, 17);

      await db.todoDao.completeTask(id, now);
      var row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.archivedAt, now);

      await db.todoDao.restoreTask(id);
      row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.archivedAt, isNull);
    });

    test('purgeExpired deletes only items past retention', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final old = await db.todoDao.createTask(categoryId: cat, name: 'old');
      final fresh = await db.todoDao.createTask(categoryId: cat, name: 'fresh');
      final now = DateTime(2026, 6, 17);
      await db.todoDao.completeTask(
        old,
        now.subtract(const Duration(days: 40)),
      );
      await db.todoDao.completeTask(
        fresh,
        now.subtract(const Duration(days: 5)),
      );

      final deleted = await db.todoDao.purgeExpired(now);

      expect(deleted, 1);
      final remaining = await db.select(db.tasks).get();
      expect(remaining.map((t) => t.name), ['fresh']);
    });

    test('clearArchive deletes all archived but keeps active', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final done = await db.todoDao.createTask(categoryId: cat, name: 'done');
      await db.todoDao.createTask(categoryId: cat, name: 'active');
      await db.todoDao.completeTask(done, DateTime(2026, 6, 1));

      final deleted = await db.todoDao.clearArchive();

      expect(deleted, 1);
      final remaining = await db.select(db.tasks).get();
      expect(remaining.map((t) => t.name), ['active']);
    });

    test('moveTask changes category', () async {
      final home = await db.todoDao.createCategory(name: 'Home', color: 1);
      final work = await db.todoDao.createCategory(name: 'Work', color: 2);
      final id = await db.todoDao.createTask(categoryId: home, name: 'Call');
      await db.todoDao.moveTask(id, work);
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.categoryId, work);
    });

    test(
      'watchCategoriesWithTasks groups tasks under categories in order',
      () async {
        final home = await db.todoDao.createCategory(name: 'Home', color: 1);
        await db.todoDao.createCategory(name: 'Work', color: 2);
        await db.todoDao.createTask(categoryId: home, name: 'Sweep');

        final snapshot = await db.todoDao.watchCategoriesWithTasks().first;
        expect(snapshot.map((c) => c.category.name), ['Home', 'Work']);
        expect(snapshot.first.activeTasks.map((t) => t.name), ['Sweep']);
        expect(snapshot.last.activeTasks, isEmpty);
      },
    );
  });
}
