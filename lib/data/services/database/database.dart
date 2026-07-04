import 'package:drift/drift.dart';

import '../../../domain/recurrence.dart';
import 'connection.dart';
import 'database.steps.dart';
import 'tables.dart';
import 'todo_dao.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Categories, Tasks], daos: [TodoDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(resolveExecutor(executor));

  @override
  int get schemaVersion => 2;

  // Extracted to a static field with an inferred type so the step closes over
  // the *pinned* v2 schema snapshot (via its `schema` parameter), never the
  // live database schema — drift's recommended structure.
  static final _upgrade = stepByStep(
    from1To2: (m, schema) async {
      await m.addColumn(schema.tasks, schema.tasks.recurrenceCount);
      await m.addColumn(schema.tasks, schema.tasks.recurrenceUnit);
      await m.addColumn(schema.tasks, schema.tasks.nextDueAt);
    },
  );

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: _upgrade,
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
