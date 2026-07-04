import 'package:drift/drift.dart';

import '../../../domain/recurrence.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get color => integer()();
  TextColumn get emoji => text().nullable()();
  BoolColumn get collapsed => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
}

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()(); // null = active
  IntColumn get recurrenceCount => integer().nullable()();
  IntColumn get recurrenceUnit => intEnum<RecurrenceUnit>().nullable()();
  DateTimeColumn get nextDueAt => dateTime().nullable()(); // non-null = dormant
}
