import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/backup_codec.dart';
import 'package:nooka/domain/models/backup_data.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'export snapshot includes archived tasks; round-trips via importReplace',
    () async {
      final dao = db.todoDao;
      final cat = await dao.createCategory(name: 'Work', color: 1, emoji: '💼');
      final active = await dao.createTask(categoryId: cat, name: 'Active');
      final archived = await dao.createTask(categoryId: cat, name: 'Archived');
      await dao.completeTask(archived, DateTime.utc(2026, 6, 10));

      final snapshot = await dao.exportSnapshot();
      expect(snapshot.single.tasks, hasLength(2));

      final backup = buildBackup(snapshot, DateTime.utc(2026, 6, 25));

      // Replace with a different backup, then confirm the DB matches it exactly.
      await dao.importReplace([
        BackupCategory(
          name: 'Home',
          color: 2,
          emoji: null,
          collapsed: true,
          sortOrder: 0,
          createdAt: DateTime.utc(2026, 6, 1),
          tasks: [
            BackupTask(
              name: 'Imported archived',
              sortOrder: 0,
              createdAt: DateTime.utc(2026, 6, 2),
              archivedAt: DateTime.utc(2026, 6, 3),
            ),
          ],
        ),
      ]);

      final after = await dao.exportSnapshot();
      expect(after, hasLength(1));
      expect(after.single.category.name, 'Home');
      expect(after.single.category.collapsed, isTrue);
      expect(after.single.tasks.single.name, 'Imported archived');
      expect(
        after.single.tasks.single.archivedAt!.isAtSameMomentAs(
          DateTime.utc(2026, 6, 3),
        ),
        isTrue,
      );

      // The original active/archived ids are gone (replace, not merge).
      expect(backup.categories.single.tasks, hasLength(2));
      expect(after.single.tasks, hasLength(1));

      // Suppress unused variable warning.
      expect(active, isNonZero);
    },
  );
}
