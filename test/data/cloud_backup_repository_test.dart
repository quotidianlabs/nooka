import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/repositories/cloud_backup_repository.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/backup/cloud_backup_io.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/backup_codec.dart';
import 'package:nooka/domain/clock.dart';
import 'package:nooka/domain/models/backup_data.dart';

class FakeCloudBackupIo implements CloudBackupIo {
  FakeCloudBackupIo({this.account});
  CloudAccount? account;
  final Map<String, String> contents = {}; // id -> json
  final List<CloudBackupRef> refs = [];
  final List<String> deleted = [];
  int _seq = 0;
  DateTime uploadCreatedAt = DateTime.utc(2030); // set per upload in tests
  bool throwOnUpload = false;
  bool throwOnList = false;

  @override
  Future<CloudAccount?> currentAccount() async => account;
  @override
  Future<CloudAccount?> connect() async =>
      account ??= const CloudAccount('a@b.com');
  @override
  Future<void> disconnect() async => account = null;
  @override
  Future<List<CloudBackupRef>> list() async {
    if (throwOnList) throw Exception('list boom');
    return List.of(refs);
  }

  @override
  Future<void> upload(String name, String c) async {
    if (throwOnUpload) throw Exception('upload boom');
    final id = 'id${_seq++}';
    contents[id] = c;
    refs.add(CloudBackupRef(id: id, name: name, createdAt: uploadCreatedAt));
  }

  @override
  Future<String> download(String id) async => contents[id]!;
  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    refs.removeWhere((r) => r.id == id);
  }
}

void main() {
  late AppDatabase db;
  late TodoRepository todos;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    todos = TodoRepository(db.todoDao);
  });
  tearDown(() => db.close());

  BackupCategory cat(String name) => BackupCategory(
    name: name,
    color: 1,
    emoji: null,
    collapsed: false,
    sortOrder: 0,
    createdAt: DateTime.utc(2026, 6, 1),
    tasks: const [],
  );

  test('backupNow uploads a stamped, decodable file', () async {
    await todos.importReplace([cat('Work')]);
    final io = FakeCloudBackupIo();
    final repo = CloudBackupRepository(
      todos,
      io,
      clock: FixedClock(DateTime.utc(2026, 6, 28, 14, 32, 5)),
    );

    await repo.backupNow();

    expect(io.refs.single.name, 'nooka-backup-2026-06-28T14-32-05.json');
    final decoded = decodeBackup(io.contents[io.refs.single.id]!);
    expect(decoded.categories.single.name, 'Work');
  });

  test('backupNow prunes to the newest 5', () async {
    final io = FakeCloudBackupIo();
    for (var i = 1; i <= 5; i++) {
      io.refs.add(
        CloudBackupRef(
          id: 'old$i',
          name: 'nooka-backup-old-$i',
          createdAt: DateTime.utc(2026, 1, i),
        ),
      );
      io.contents['old$i'] = '{}';
    }
    io.uploadCreatedAt = DateTime.utc(2026, 2, 1); // newest
    final repo = CloudBackupRepository(todos, io);

    await repo.backupNow();

    expect(io.deleted, ['old1']); // oldest dropped
    expect(io.refs.length, 5);
  });

  test('listBackups returns newest-first', () async {
    final io = FakeCloudBackupIo()
      ..refs.addAll([
        CloudBackupRef(
          id: 'a',
          name: 'nooka-backup-a',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        CloudBackupRef(
          id: 'b',
          name: 'nooka-backup-b',
          createdAt: DateTime.utc(2026, 3, 1),
        ),
        CloudBackupRef(
          id: 'c',
          name: 'nooka-backup-c',
          createdAt: DateTime.utc(2026, 2, 1),
        ),
      ]);
    final repo = CloudBackupRepository(todos, io);

    final got = await repo.listBackups();

    expect(got.map((r) => r.id).toList(), ['b', 'c', 'a']);
  });

  test('fetch decodes a good file', () async {
    await todos.importReplace([cat('Home')]);
    final io = FakeCloudBackupIo();
    final repo = CloudBackupRepository(
      todos,
      io,
      clock: FixedClock(DateTime.utc(2026, 6, 28, 1, 2, 3)),
    );
    await repo.backupNow();
    final id = io.refs.single.id;

    final data = await repo.fetch(id);

    expect(data.categories.single.name, 'Home');
  });

  test('fetch throws BackupFormatException on a corrupt file', () async {
    final io = FakeCloudBackupIo()
      ..refs.add(
        CloudBackupRef(id: 'x', name: 'x', createdAt: DateTime.utc(2026)),
      )
      ..contents['x'] = 'not json';
    final repo = CloudBackupRepository(todos, io);

    await expectLater(repo.fetch('x'), throwsA(isA<BackupFormatException>()));
  });

  test(
    'listBackups excludes non-nooka files; backupNow prune never deletes them',
    () async {
      final io = FakeCloudBackupIo();
      // Foreign file that must never be listed or pruned.
      io.refs.add(
        CloudBackupRef(
          id: 'foreign',
          name: 'other.txt',
          createdAt: DateTime.utc(2025),
        ),
      );
      io.contents['foreign'] = '{}';
      // 5 nooka backups already present.
      for (var i = 1; i <= 5; i++) {
        io.refs.add(
          CloudBackupRef(
            id: 'nooka$i',
            name: 'nooka-backup-2026-0$i-01T00-00-00.json',
            createdAt: DateTime.utc(2026, i),
          ),
        );
        io.contents['nooka$i'] = '{}';
      }
      final repo = CloudBackupRepository(todos, io);

      // listBackups excludes the foreign file.
      final listed = await repo.listBackups();
      expect(listed.map((r) => r.id), isNot(contains('foreign')));
      expect(listed.length, 5);

      // backupNow uploads 1 more nooka backup → 6 nooka total → prunes oldest 1.
      // The foreign file must not appear in deleted.
      io.uploadCreatedAt = DateTime.utc(2027);
      await repo.backupNow();

      expect(io.deleted, isNot(contains('foreign')));
      expect(
        io.refs.where((r) => r.name.startsWith('nooka-backup-')).length,
        5,
      );
    },
  );

  test('connect / account / disconnect pass through', () async {
    final io = FakeCloudBackupIo();
    final repo = CloudBackupRepository(todos, io);

    expect(await repo.account(), isNull);
    expect((await repo.connect())!.email, 'a@b.com');
    expect((await repo.account())!.email, 'a@b.com');
    await repo.disconnect();
    expect(await repo.account(), isNull);
  });
}
