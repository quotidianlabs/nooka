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
      final row = await (db.select(db.categories)
            ..where((c) => c.id.equals(cat)))
          .getSingle();
      expect(row.collapsed, isTrue);
    });
  });
}
