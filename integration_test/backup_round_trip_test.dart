import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/backup/platform_backup_io.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/backup_codec.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exports to a real file and re-imports it losslessly', (
    WidgetTester tester,
  ) async {
    const io = PlatformBackupIo();

    // Source DB: seed a category with one active + one archived task.
    final srcFile = File('${Directory.systemTemp.path}/it_backup_src.sqlite');
    if (srcFile.existsSync()) srcFile.deleteSync();
    final src = AppDatabase(NativeDatabase(srcFile));
    final srcRepo = TodoRepository(src.todoDao);
    final cat = await src.todoDao.createCategory(
      name: 'Work',
      color: 0xFF009688,
      emoji: '💼',
    );
    await src.todoDao.createTask(categoryId: cat, name: 'Active');
    final archived = await src.todoDao.createTask(
      categoryId: cat,
      name: 'Archived',
    );
    await src.todoDao.completeTask(archived, DateTime(2026, 6, 10));

    // Export through the REAL platform file I/O.
    final snapshot = await srcRepo.exportSnapshot();
    final json = encodeBackup(buildBackup(snapshot, DateTime(2026, 6, 25)));
    final path = await io.writeTemp('nooka-backup-2026-06-25.json', json);
    expect(File(path).existsSync(), isTrue);
    await src.close();

    // Re-read the real file and import into a fresh DB.
    final decoded = decodeBackup(await io.readFile(path));
    final dstFile = File('${Directory.systemTemp.path}/it_backup_dst.sqlite');
    if (dstFile.existsSync()) dstFile.deleteSync();
    final dst = AppDatabase(NativeDatabase(dstFile));
    addTearDown(dst.close);
    final dstRepo = TodoRepository(dst.todoDao);
    await dstRepo.importReplace(decoded.categories);

    // The fresh DB reproduces the source exactly, archive state included.
    final after = await dstRepo.exportSnapshot();
    expect(after, hasLength(1));
    expect(after.single.category.name, 'Work');
    expect(after.single.category.emoji, '💼');
    expect(after.single.tasks, hasLength(2));
    expect(after.single.tasks.where((t) => t.archivedAt != null), hasLength(1));
  });
}
