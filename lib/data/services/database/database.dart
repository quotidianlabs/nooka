import 'package:drift/drift.dart';

import '../../../domain/recurrence.dart';
import 'connection.dart';
import 'tables.dart';
import 'todo_dao.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Categories, Tasks], daos: [TodoDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(resolveExecutor(executor));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(tasks, tasks.recurrenceCount);
        await m.addColumn(tasks, tasks.recurrenceUnit);
        await m.addColumn(tasks, tasks.nextDueAt);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
