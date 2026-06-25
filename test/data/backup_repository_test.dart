import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/repositories/backup_repository.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/backup/backup_io.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/backup_codec.dart';
import 'package:nooka/domain/clock.dart';
import 'package:nooka/domain/models/backup_data.dart';

class FakeBackupIo implements BackupIo {
  String? sharedSubject;
  String? wroteFilename;
  String? wroteContents;
  String? toReturnOnPick; // null => user cancelled
  String pickFileContents = '';

  @override
  Future<String> writeTemp(String filename, String contents) async {
    wroteFilename = filename;
    wroteContents = contents;
    return '/tmp/$filename';
  }

  @override
  Future<void> shareFile(String path, String subject) async {
    sharedSubject = subject;
  }

  @override
  Future<String?> pickFile() async => toReturnOnPick;

  @override
  Future<String> readFile(String path) async => pickFileContents;
}

void main() {
  late AppDatabase db;
  late TodoRepository todos;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    todos = TodoRepository(db.todoDao);
  });
  tearDown(() => db.close());

  test('exportAndShare writes a dated file and shares it', () async {
    await todos.importReplace([
      BackupCategory(
        name: 'Work',
        color: 1,
        emoji: null,
        collapsed: false,
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 6, 1),
        tasks: const [],
      ),
    ]);
    final io = FakeBackupIo();
    final repo = BackupRepository(
      todos,
      io,
      clock: FixedClock(DateTime.utc(2026, 6, 25, 9, 30)),
    );

    await repo.exportAndShare(subject: 'Nooka backup');

    expect(io.wroteFilename, 'nooka-backup-2026-06-25.json');
    expect(io.sharedSubject, 'Nooka backup');
    final decoded = decodeBackup(io.wroteContents!);
    expect(decoded.categories.single.name, 'Work');
  });

  test('pickAndDecode returns null when cancelled', () async {
    final io = FakeBackupIo()..toReturnOnPick = null;
    final repo = BackupRepository(todos, io);
    expect(await repo.pickAndDecode(), isNull);
  });

  test('pickAndDecode decodes a chosen file', () async {
    final io = FakeBackupIo()
      ..toReturnOnPick = '/tmp/in.json'
      ..pickFileContents = encodeBackup(
        BackupData(version: 1, exportedAt: DateTime.utc(2026), categories: []),
      );
    final repo = BackupRepository(todos, io);
    expect((await repo.pickAndDecode())!.categories, isEmpty);
  });

  test('pickAndDecode throws on an invalid file', () async {
    final io = FakeBackupIo()
      ..toReturnOnPick = '/tmp/bad.json'
      ..pickFileContents = 'garbage';
    final repo = BackupRepository(todos, io);
    expect(repo.pickAndDecode, throwsA(isA<BackupFormatException>()));
  });

  test('backupRepositoryProvider builds a BackupRepository', () {
    final container = ProviderContainer(
      overrides: [todoRepositoryProvider.overrideWithValue(todos)],
    );
    addTearDown(container.dispose);

    expect(container.read(backupRepositoryProvider), isA<BackupRepository>());
  });
}
