import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/database/database.dart';

void main() {
  late AppDatabase db;
  late TodoRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TodoRepository(db.todoDao);
  });
  tearDown(() => db.close());

  Future<List<dynamic>> tasks() => db.select(db.tasks).get();

  test(
    'createCategory then updateCategory writes through to the DAO',
    () async {
      final id = await repo.createCategory(name: 'Home', color: 1, emoji: '🏠');

      await repo.updateCategory(id: id, name: 'House', color: 2, emoji: null);

      final row = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(id))).getSingle();
      expect(row.name, 'House');
      expect(row.color, 2);
      expect(row.emoji, isNull);
    },
  );

  test('renameTask writes through to the DAO', () async {
    final cat = await repo.createCategory(name: 'Home', color: 1);
    final t = await repo.createTask(categoryId: cat, name: 'old');

    await repo.renameTask(t, 'new');

    final row = (await tasks()).single;
    expect(row.name, 'new');
  });

  test('moveTask writes through to the DAO', () async {
    final a = await repo.createCategory(name: 'A', color: 1);
    final b = await repo.createCategory(name: 'B', color: 2);
    final t = await repo.createTask(categoryId: a, name: 't');

    await repo.moveTask(t, b);

    final row = (await tasks()).single;
    expect(row.categoryId, b);
  });
}
