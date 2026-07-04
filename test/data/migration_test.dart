import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v1.dart' as v1;
import '../generated_migrations/schema_v2.dart' as v2;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('migrates v1 -> v2 to the declared schema', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    // Fails if the migrated database does not match the declared v2 schema.
    await verifier.migrateAndValidate(db, 2);
    await db.close();
  });

  test('v1 -> v2 preserves rows and defaults recurrence to null', () async {
    final schema = await verifier.schemaAt(1);
    // Generated v1/v2 schema classes model raw column storage (no type
    // converters), so DateTime columns surface as unix-seconds ints here.
    final createdAt = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;

    // Seed a category + task using the v1 schema.
    final oldDb = v1.DatabaseAtV1(schema.newConnection());
    final catId = await oldDb
        .into(oldDb.categories)
        .insert(
          v1.CategoriesCompanion.insert(
            name: 'Home',
            color: 1,
            sortOrder: 0,
            createdAt: createdAt,
          ),
        );
    await oldDb
        .into(oldDb.tasks)
        .insert(
          v1.TasksCompanion.insert(
            categoryId: catId,
            name: 'Water plants',
            sortOrder: 0,
            createdAt: createdAt,
          ),
        );
    await oldDb.close();

    // Run the migration through the real AppDatabase.
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    await db.close();

    // Read back with the v2 schema: row survived, recurrence columns null.
    final migrated = v2.DatabaseAtV2(schema.newConnection());
    final t = await migrated.select(migrated.tasks).getSingle();
    expect(t.name, 'Water plants');
    expect(t.categoryId, catId);
    expect(t.createdAt, createdAt);
    expect(t.recurrenceCount, isNull);
    expect(t.recurrenceUnit, isNull);
    expect(t.nextDueAt, isNull);
    await migrated.close();
  });
}
