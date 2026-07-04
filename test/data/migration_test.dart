import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v1 database upgrades to v2 with null recurrence columns', () async {
    // Build a v1-shaped database on a raw connection (snake_case column
    // names, DateTime stored as int seconds, user_version = 1).
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE categories (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, color INTEGER NOT NULL, emoji TEXT NULL,
        collapsed INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL,
        created_at INTEGER NOT NULL);
    ''');
    raw.execute('''
      CREATE TABLE tasks (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL REFERENCES categories (id) ON DELETE CASCADE,
        name TEXT NOT NULL, sort_order INTEGER NOT NULL,
        created_at INTEGER NOT NULL, archived_at INTEGER NULL);
    ''');
    raw.execute('PRAGMA user_version = 1;');
    raw.execute(
      "INSERT INTO categories (name, color, sort_order, created_at) "
      "VALUES ('Home', 1, 0, 1000000000);",
    );
    raw.execute(
      "INSERT INTO tasks (category_id, name, sort_order, created_at) "
      "VALUES (1, 'Water plants', 0, 1000000000);",
    );

    // Opening AppDatabase on the same connection runs onUpgrade(1 -> 2).
    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(1));
    expect(tasks.single.name, 'Water plants');
    expect(tasks.single.recurrenceCount, isNull);
    expect(tasks.single.recurrenceUnit, isNull);
    expect(tasks.single.nextDueAt, isNull);
    expect(db.schemaVersion, 2);
  });
}
