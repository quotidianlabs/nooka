import 'package:drift/drift.dart' show OrderingTerm, Value;
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

    test('updateCategory writes name, color and emoji in one call', () async {
      final id = await db.todoDao.createCategory(
        name: 'Home',
        color: 1,
        emoji: '🏠',
      );

      await db.todoDao.updateCategory(
        id: id,
        name: 'House',
        color: 2,
        emoji: '🏡',
      );
      var row = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(id))).getSingle();
      expect(row.name, 'House');
      expect(row.color, 2);
      expect(row.emoji, '🏡');

      // Clearing the emoji to null is a real write, not "unchanged".
      await db.todoDao.updateCategory(
        id: id,
        name: 'House',
        color: 2,
        emoji: null,
      );
      row = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(id))).getSingle();
      expect(row.emoji, isNull);
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

    test(
      'moveTaskToCategoryAt reassigns category and positions the task',
      () async {
        final src = await db.todoDao.createCategory(name: 'Src', color: 1);
        final dst = await db.todoDao.createCategory(name: 'Dst', color: 2);
        final s1 = await db.todoDao.createTask(categoryId: src, name: 's1');
        final s2 = await db.todoDao.createTask(categoryId: src, name: 's2');
        final d1 = await db.todoDao.createTask(categoryId: dst, name: 'd1');
        final d2 = await db.todoDao.createTask(categoryId: dst, name: 'd2');

        // Move s1 into dst between d1 and d2.
        await db.todoDao.moveTaskToCategoryAt(s1, dst, [d1, s1, d2]);

        final snapshot = await db.todoDao.watchCategoriesWithTasks().first;
        final byName = {for (final c in snapshot) c.category.name: c};
        expect(byName['Dst']!.activeTasks.map((t) => t.name), [
          'd1',
          's1',
          'd2',
        ]);
        // Source keeps its remaining task in order; s1 is gone from it.
        expect(byName['Src']!.activeTasks.map((t) => t.name), ['s2']);
        expect(s2, isNotNull);
      },
    );

    test('moveTaskToCategoryAt renumbers dest, leaves source gap', () async {
      final src = await db.todoDao.createCategory(name: 'Src', color: 1);
      final dst = await db.todoDao.createCategory(name: 'Dst', color: 2);
      final s1 = await db.todoDao.createTask(categoryId: src, name: 's1'); // 0
      final s2 = await db.todoDao.createTask(categoryId: src, name: 's2'); // 1
      final d1 = await db.todoDao.createTask(categoryId: dst, name: 'd1'); // 0
      final d2 = await db.todoDao.createTask(categoryId: dst, name: 'd2'); // 1

      // Move s1 into dst between d1 and d2.
      await db.todoDao.moveTaskToCategoryAt(s1, dst, [d1, s1, d2]);

      Future<int> orderOf(int id) async => (await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle()).sortOrder;

      // Destination renumbered 0,1,2 in the new order.
      expect(await orderOf(d1), 0);
      expect(await orderOf(s1), 1);
      expect(await orderOf(d2), 2);
      // Source is NOT renumbered: s2 keeps its original sortOrder (1), gap left.
      expect(await orderOf(s2), 1);
    });

    test('duplicate sortOrder orders deterministically by id', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final t1 = await db.todoDao.createTask(categoryId: cat, name: 't1');
      final t2 = await db.todoDao.createTask(categoryId: cat, name: 't2');
      final t3 = await db.todoDao.createTask(categoryId: cat, name: 't3');

      // Force a sortOrder collision (reachable via the stale-set reorder hazard).
      for (final id in [t1, t2, t3]) {
        await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
          const TasksCompanion(sortOrder: Value(0)),
        );
      }

      final a = await db.todoDao.watchCategoriesWithTasks().first;
      final b = await db.todoDao.watchCategoriesWithTasks().first;
      final orderA = a.first.activeTasks.map((t) => t.id).toList();
      final orderB = b.first.activeTasks.map((t) => t.id).toList();
      expect(orderA, [t1, t2, t3]); // id-ascending tiebreak
      expect(orderA, orderB); // stable across reads
    });

    test(
      'duplicate category sortOrder orders categories by id, not tasks',
      () async {
        final catA = await db.todoDao.createCategory(name: 'A', color: 1);
        final catB = await db.todoDao.createCategory(name: 'B', color: 2);
        // Force a category sortOrder collision.
        for (final id in [catA, catB]) {
          await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
            const CategoriesCompanion(sortOrder: Value(0)),
          );
        }
        // Give A a high task sortOrder and B a low one: with the category id
        // tiebreak placed after tasks.sortOrder, the rows interleave and B sorts
        // first. Grouping the order keys by table keeps category order by id.
        final ta = await db.todoDao.createTask(categoryId: catA, name: 'ta');
        final tb = await db.todoDao.createTask(categoryId: catB, name: 'tb');
        await (db.update(db.tasks)..where((t) => t.id.equals(ta))).write(
          const TasksCompanion(sortOrder: Value(5)),
        );
        await (db.update(db.tasks)..where((t) => t.id.equals(tb))).write(
          const TasksCompanion(sortOrder: Value(1)),
        );

        final snap = await db.todoDao.watchCategoriesWithTasks().first;
        expect(snap.map((c) => c.category.id), [catA, catB]); // id-ascending
      },
    );
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

    test('purgeExpired boundary: exactly 30d purged, 29d kept', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final at30 = await db.todoDao.createTask(categoryId: cat, name: 'at30');
      final at29 = await db.todoDao.createTask(categoryId: cat, name: 'at29');
      final now = DateTime(2026, 6, 17);
      await db.todoDao.completeTask(
        at30,
        now.subtract(const Duration(days: 30)),
      );
      await db.todoDao.completeTask(
        at29,
        now.subtract(const Duration(days: 29)),
      );

      final deleted = await db.todoDao.purgeExpired(now);

      expect(deleted, 1);
      final remaining = await db.select(db.tasks).get();
      expect(remaining.map((t) => t.name), ['at29']);
    });

    test('restoreTask re-appends to the tail of active sortOrder', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final a = await db.todoDao.createTask(categoryId: cat, name: 'a'); // 0
      final b = await db.todoDao.createTask(categoryId: cat, name: 'b'); // 1
      final c = await db.todoDao.createTask(categoryId: cat, name: 'c'); // 2

      // Archive 'a', then restore it: it should re-append after b and c.
      await db.todoDao.completeTask(a, DateTime(2026, 6, 1));
      await db.todoDao.restoreTask(a);

      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(a))).getSingle();
      expect(row.archivedAt, isNull);
      // b=1, c=2 remained active while a was archived → a re-appends at 3.
      expect(row.sortOrder, 3);
      // The active order reflects the re-append: b, c, then a.
      final active = (await db.todoDao.watchCategoriesWithTasks().first)
          .first
          .activeTasks
          .map((t) => t.id)
          .toList();
      expect(active, [b, c, a]);
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

    test('renameAndMove applies rename and move together', () async {
      final a = await db.todoDao.createCategory(name: 'A', color: 1);
      final b = await db.todoDao.createCategory(name: 'B', color: 2);
      final t = await db.todoDao.createTask(categoryId: a, name: 'old');

      await db.todoDao.renameAndMove(t, 'new', b);

      final row = await (db.select(
        db.tasks,
      )..where((x) => x.id.equals(t))).getSingle();
      expect(row.name, 'new');
      expect(row.categoryId, b);
    });

    test('renameAndMove with a null category renames only', () async {
      final a = await db.todoDao.createCategory(name: 'A', color: 1);
      final t = await db.todoDao.createTask(categoryId: a, name: 'old');

      await db.todoDao.renameAndMove(t, 'new', null);

      final row = await (db.select(
        db.tasks,
      )..where((x) => x.id.equals(t))).getSingle();
      expect(row.name, 'new');
      expect(row.categoryId, a);
    });

    test('renameAndMove rolls back the rename when the move fails', () async {
      final a = await db.todoDao.createCategory(name: 'A', color: 1);
      final t = await db.todoDao.createTask(categoryId: a, name: 'old');

      // Moving to a non-existent category violates the FK → whole tx rolls back.
      await expectLater(
        db.todoDao.renameAndMove(t, 'new', 9999),
        throwsA(anything),
      );

      final row = await (db.select(
        db.tasks,
      )..where((x) => x.id.equals(t))).getSingle();
      expect(row.name, 'old'); // rename rolled back with the failed move
      expect(row.categoryId, a);
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
