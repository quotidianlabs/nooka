import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/repositories/backup_repository.dart';
import 'package:nooka/data/repositories/cloud_backup_repository.dart';
import 'package:nooka/data/repositories/settings_repository.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/backup/backup_io.dart';
import 'package:nooka/data/services/backup/cloud_backup_io.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/backup_codec.dart';
import 'package:nooka/domain/models/backup_data.dart';
import 'package:nooka/ui/settings/settings_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Throwing TodoRepository subclass for failure tests
// ---------------------------------------------------------------------------

class ThrowingTodoRepository extends TodoRepository {
  ThrowingTodoRepository(super.dao);

  @override
  Future<void> importReplace(List<BackupCategory> categories) =>
      Future.error(Exception('DB exploded'));
}

// ---------------------------------------------------------------------------
// Configurable fake BackupIo
// ---------------------------------------------------------------------------

class FakeBackupIo implements BackupIo {
  FakeBackupIo({
    this.pickResult,
    this.pickContents = '',
    this.throwOnPick = false,
    this.throwOnShare = false,
  });

  /// Path returned by pickFile, or null to simulate cancellation.
  final String? pickResult;

  /// Contents returned by readFile.
  final String pickContents;

  /// If true, pickFile throws a generic Exception.
  final bool throwOnPick;

  /// If true, shareFile throws a generic Exception.
  final bool throwOnShare;

  @override
  Future<String?> pickFile() async {
    if (throwOnPick) throw Exception('picker exploded');
    return pickResult;
  }

  @override
  Future<String> readFile(String path) async => pickContents;

  @override
  Future<void> shareFile(String path, String subject) async {
    if (throwOnShare) throw Exception('share failed');
  }

  @override
  Future<String> writeTemp(String filename, String contents) async =>
      '/tmp/$filename';
}

// ---------------------------------------------------------------------------
// Configurable fake CloudBackupIo
// ---------------------------------------------------------------------------

class FakeCloudBackupIo implements CloudBackupIo {
  FakeCloudBackupIo({this.account});
  CloudAccount? account;
  final Map<String, String> contents = {}; // id -> json
  final List<CloudBackupRef> refs = [];
  final List<String> deleted = [];
  int _seq = 0;
  DateTime uploadCreatedAt = DateTime.utc(2030);
  bool throwOnUpload = false;
  bool throwOnList = false;
  bool throwOnConnect = false;
  bool throwOnDisconnect = false;

  @override
  Future<CloudAccount?> currentAccount() async => account;
  @override
  Future<CloudAccount?> connect() async {
    if (throwOnConnect) throw Exception('connect boom');
    return account ??= const CloudAccount('a@b.com');
  }

  @override
  Future<void> disconnect() async {
    if (throwOnDisconnect) throw Exception('disconnect boom');
    account = null;
  }

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

BackupData _minimalBackup() => BackupData(
  version: 1,
  exportedAt: DateTime.utc(2026),
  categories: [
    BackupCategory(
      name: 'Imported',
      color: 1,
      emoji: null,
      collapsed: false,
      sortOrder: 0,
      createdAt: DateTime.utc(2026, 6, 1),
      tasks: const [],
    ),
  ],
);

void main() {
  late AppDatabase db;
  late TodoRepository todos;
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    todos = TodoRepository(db.todoDao);
    SharedPreferences.setMockInitialValues({'last_category': 5});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => db.close());

  ProviderContainer makeContainer({
    required BackupIo io,
    AppDatabase? overrideDb,
  }) {
    final targetDb = overrideDb ?? db;
    final backup = BackupRepository(TodoRepository(targetDb.todoDao), io);
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todoRepositoryProvider.overrideWith(
          (ref) => TodoRepository(targetDb.todoDao),
        ),
        backupRepositoryProvider.overrideWith((ref) => backup),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // export
  // -------------------------------------------------------------------------

  test('export returns true on success', () async {
    final c = makeContainer(io: FakeBackupIo(pickResult: null));
    addTearDown(c.dispose);

    final result = await c
        .read(settingsViewModelProvider.notifier)
        .export('Nooka backup');

    expect(result, isTrue);
  });

  test('export returns false on failure', () async {
    final c = makeContainer(io: FakeBackupIo(throwOnShare: true));
    addTearDown(c.dispose);

    final result = await c
        .read(settingsViewModelProvider.notifier)
        .export('Nooka backup');

    expect(result, isFalse);
  });

  // -------------------------------------------------------------------------
  // pickImport — four outcomes
  // -------------------------------------------------------------------------

  test('pickImport returns ImportPickCancelled when user cancels', () async {
    // pickFile returns null => cancelled
    final c = makeContainer(io: FakeBackupIo(pickResult: null));
    addTearDown(c.dispose);

    final result = await c
        .read(settingsViewModelProvider.notifier)
        .pickImport();

    expect(result, isA<ImportPickCancelled>());
  });

  test('pickImport returns ImportPickReady with valid backup', () async {
    final validJson = encodeBackup(_minimalBackup());
    final c = makeContainer(
      io: FakeBackupIo(pickResult: '/tmp/backup.json', pickContents: validJson),
    );
    addTearDown(c.dispose);

    final result = await c
        .read(settingsViewModelProvider.notifier)
        .pickImport();

    expect(result, isA<ImportPickReady>());
    final ready = result as ImportPickReady;
    expect(ready.data.categories.single.name, 'Imported');
  });

  test('pickImport returns ImportPickInvalid for a bad file', () async {
    // readFile returns garbage => decodeBackup throws BackupFormatException
    final c = makeContainer(
      io: FakeBackupIo(
        pickResult: '/tmp/garbage.json',
        pickContents: 'not-valid-json',
      ),
    );
    addTearDown(c.dispose);

    final result = await c
        .read(settingsViewModelProvider.notifier)
        .pickImport();

    expect(result, isA<ImportPickInvalid>());
  });

  test(
    'pickImport returns ImportPickFailed on unexpected picker error',
    () async {
      // pickFile throws a generic Exception
      final c = makeContainer(io: FakeBackupIo(throwOnPick: true));
      addTearDown(c.dispose);

      final result = await c
          .read(settingsViewModelProvider.notifier)
          .pickImport();

      expect(result, isA<ImportPickFailed>());
    },
  );

  // -------------------------------------------------------------------------
  // applyImport
  // -------------------------------------------------------------------------

  test('applyImport returns true and forgets remembered category', () async {
    final c = makeContainer(io: FakeBackupIo(pickResult: null));
    addTearDown(c.dispose);

    expect(prefs.getInt('last_category'), 5); // pre-condition

    final ok = await c
        .read(settingsViewModelProvider.notifier)
        .applyImport(_minimalBackup());

    expect(ok, isTrue);
    expect(prefs.getInt('last_category'), isNull); // forgotten

    final snapshot = await TodoRepository(db.todoDao).exportSnapshot();
    expect(snapshot.single.category.name, 'Imported');
  });

  test('applyImport returns false on failure', () async {
    final throwingTodos = ThrowingTodoRepository(db.todoDao);
    final backup = BackupRepository(
      throwingTodos,
      FakeBackupIo(pickResult: null),
    );
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todoRepositoryProvider.overrideWith((ref) => throwingTodos),
        backupRepositoryProvider.overrideWith((ref) => backup),
      ],
    );
    addTearDown(c.dispose);

    final ok = await c
        .read(settingsViewModelProvider.notifier)
        .applyImport(_minimalBackup());

    expect(ok, isFalse);
  });

  // -------------------------------------------------------------------------
  // cloud commands
  // -------------------------------------------------------------------------

  test('cloudBackupNow returns true and uploads', () async {
    final io = FakeCloudBackupIo();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect(await vm.cloudBackupNow(), isTrue);
    expect(io.refs, isNotEmpty);
  });

  test('cloudBackups returns refs; null on failure', () async {
    final io = FakeCloudBackupIo()
      ..refs.add(
        CloudBackupRef(
          id: 'a',
          name: 'nooka-backup-a',
          createdAt: DateTime.utc(2026),
        ),
      );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect((await vm.cloudBackups())!.single.id, 'a');

    io.throwOnList = true;
    expect(await vm.cloudBackups(), isNull);
  });

  test('fetchCloudBackup maps good/corrupt to Ready/Invalid', () async {
    final io = FakeCloudBackupIo()
      ..refs.addAll([
        CloudBackupRef(id: 'good', name: 'g', createdAt: DateTime.utc(2026)),
        CloudBackupRef(id: 'bad', name: 'b', createdAt: DateTime.utc(2026)),
      ])
      ..contents['good'] =
          '{"app":"nooka","version":1,"exportedAt":"2026-06-28T00:00:00.000","categories":[]}'
      ..contents['bad'] = 'not json';
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect(await vm.fetchCloudBackup('good'), isA<ImportPickReady>());
    expect(await vm.fetchCloudBackup('bad'), isA<ImportPickInvalid>());
  });

  test('cloudBackupNow returns false on failure', () async {
    final io = FakeCloudBackupIo()..throwOnUpload = true;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect(await vm.cloudBackupNow(), isFalse);
  });

  test('fetchCloudBackup maps a non-format error to Failed', () async {
    // No content for the id => the fake's download(id) panics on contents[id]!,
    // a generic error (not BackupFormatException) => ImportPickFailed.
    final io = FakeCloudBackupIo();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect(await vm.fetchCloudBackup('missing-id'), isA<ImportPickFailed>());
  });

  test('connect / account / disconnect round-trip', () async {
    final io = FakeCloudBackupIo();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect(await vm.cloudAccount(), isNull);
    expect(await vm.connectCloud(), isA<CloudAccount>());
    expect(await vm.cloudAccount(), isNotNull);
    await vm.disconnectCloud();
    expect(await vm.cloudAccount(), isNull);
  });

  test('connectCloud returns null when connect throws', () async {
    final io = FakeCloudBackupIo()..throwOnConnect = true;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect(await vm.connectCloud(), isNull);
  });

  test('disconnectCloud handles error gracefully', () async {
    final io = FakeCloudBackupIo()..throwOnDisconnect = true;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    // Should not throw
    await vm.disconnectCloud();
  });
}
