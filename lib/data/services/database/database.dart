import 'package:drift/drift.dart';

import 'connection.dart';
import 'tables.dart';
import 'todo_dao.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Categories, Tasks], daos: [TodoDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor != null
            // Tests pass an explicit executor; close streams synchronously so
            // fake-async sees no pending timer after the last listener detaches.
            ? DatabaseConnection(executor, closeStreamsSynchronously: true)
            : openConnection(),
      );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
