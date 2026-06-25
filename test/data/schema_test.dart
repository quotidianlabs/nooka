import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';

void main() {
  test('schema creates the categories and tasks tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Forcing a query opens the connection and runs migration.onCreate,
    // which builds every table from its column definitions.
    final categories = await db.select(db.categories).get();
    final tasks = await db.select(db.tasks).get();

    expect(categories, isEmpty);
    expect(tasks, isEmpty);
    // The generated table metadata reflects the hand-written column getters.
    expect(db.categories.actualTableName, 'categories');
    expect(db.tasks.actualTableName, 'tasks');
  });
}
