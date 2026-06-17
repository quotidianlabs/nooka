// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_dao.dart';

// ignore_for_file: type=lint
mixin _$TodoDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $TasksTable get tasks => attachedDatabase.tasks;
  TodoDaoManager get managers => TodoDaoManager(this);
}

class TodoDaoManager {
  final _$TodoDaoMixin _db;
  TodoDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db.attachedDatabase, _db.tasks);
}
