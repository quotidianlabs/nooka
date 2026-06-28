import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/core/locale_controller.dart';
import 'package:nooka/ui/core/theme_controller.dart';
import 'package:nooka/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final String? pickResult;
  final String pickContents;
  final bool throwOnPick;
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
// Configurable fake CloudBackupIo (copied from cloud_backup_repository_test)
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

// ---------------------------------------------------------------------------
// ThrowingTodoRepository — simulates DB failure on importReplace
// ---------------------------------------------------------------------------

class ThrowingTodoRepository extends TodoRepository {
  ThrowingTodoRepository(super.dao);

  @override
  Future<void> importReplace(List<BackupCategory> categories) =>
      Future.error(Exception('DB exploded'));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

BackupData _oneCategory() => BackupData(
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

/// Builds a [ProviderContainer] wired for the Settings screen and registers
/// [addTearDown] to dispose it after the test.
ProviderContainer _makeContainer({
  required SharedPreferences prefs,
  required BackupRepository backupRepo,
  required TodoRepository todoRepo,
  CloudBackupRepository? cloudBackupRepo,
}) {
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      backupRepositoryProvider.overrideWith((ref) => backupRepo),
      todoRepositoryProvider.overrideWith((ref) => todoRepo),
      if (cloudBackupRepo != null)
        cloudBackupRepositoryProvider.overrideWith((ref) => cloudBackupRepo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _buildScreen(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsScreen(),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late SharedPreferences prefs;
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  // A non-const construction so the constructor declaration line is recorded
  // as covered deterministically: every other call site is const (resolved at
  // compile time), and whether that registers the declaration line as hit is
  // toolchain-dependent (it flaked between local and CI on the same Flutter).
  test('SettingsScreen constructs', () {
    // ignore: prefer_const_constructors
    expect(SettingsScreen(), isA<SettingsScreen>());
  });

  // Non-const construction of CloudAccount — same rationale as above.
  test('CloudAccount constructs', () {
    // ignore: prefer_const_constructors
    expect(CloudAccount('test@example.com').email, 'test@example.com');
  });

  // -------------------------------------------------------------------------
  // Existing theme / language tests (keep passing)
  // -------------------------------------------------------------------------

  testWidgets('changing theme to Dark persists the token', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('theme-tile')),
        matching: find.byType(DropdownButton<AppThemeMode>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    expect(container.read(themeControllerProvider), AppThemeMode.dark);
    expect(prefs.getString('theme'), 'dark');
  });

  testWidgets('selecting a language updates the locale controller', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('language-tile')),
        matching: find.byType(DropdownButton<AppLocale>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Russian').last);
    await tester.pumpAndSettle();

    expect(container.read(localeControllerProvider), AppLocale.ru);
  });

  // -------------------------------------------------------------------------
  // Test 1: Export + Import tiles render
  // -------------------------------------------------------------------------

  testWidgets('export and import tiles render with localized text', (
    WidgetTester tester,
  ) async {
    final todoRepo = TodoRepository(db.todoDao);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('export-tile')), findsOneWidget);
    expect(find.byKey(const Key('import-tile')), findsOneWidget);
    expect(find.text('Export data'), findsOneWidget);
    expect(find.text('Import data'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Test 2: Export success → no error snackbar
  // -------------------------------------------------------------------------

  testWidgets('export tap success shows no error snackbar', (
    WidgetTester tester,
  ) async {
    final todoRepo = TodoRepository(db.todoDao);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('export-tile')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't complete that. Try again."), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Test 3: Export failure → actionFailed snackbar
  // -------------------------------------------------------------------------

  testWidgets('export tap failure shows actionFailed snackbar', (
    WidgetTester tester,
  ) async {
    final todoRepo = TodoRepository(db.todoDao);
    final backup = BackupRepository(todoRepo, FakeBackupIo(throwOnShare: true));
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('export-tile')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't complete that. Try again."), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Test 4: Import → Cancelled → no dialog, no snackbar
  // -------------------------------------------------------------------------

  testWidgets('import cancelled shows no dialog and no snackbar', (
    WidgetTester tester,
  ) async {
    // pickFile returns null => ImportPickCancelled
    final todoRepo = TodoRepository(db.todoDao);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('import-tile')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Test 5: Import → Invalid → importInvalidFile snackbar, no dialog
  // -------------------------------------------------------------------------

  testWidgets('import invalid file shows importInvalidFile snackbar', (
    WidgetTester tester,
  ) async {
    // pickFile returns a path but readFile returns garbage
    final todoRepo = TodoRepository(db.todoDao);
    final backup = BackupRepository(
      todoRepo,
      FakeBackupIo(pickResult: '/tmp/bad.json', pickContents: 'garbage'),
    );
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('import-tile')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text("That isn't a valid Nooka backup."), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Test 6: Import → Failed → actionFailed snackbar
  // -------------------------------------------------------------------------

  testWidgets('import pick failure shows actionFailed snackbar', (
    WidgetTester tester,
  ) async {
    // pickFile throws a generic error
    final todoRepo = TodoRepository(db.todoDao);
    final backup = BackupRepository(todoRepo, FakeBackupIo(throwOnPick: true));
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('import-tile')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't complete that. Try again."), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Test 7: Import → Ready → dialog appears → tap Cancel → no change, no snackbar
  // -------------------------------------------------------------------------

  testWidgets(
    'import ready shows confirm dialog; Cancel leaves data unchanged',
    (WidgetTester tester) async {
      final validJson = encodeBackup(_oneCategory());
      final todoRepo = TodoRepository(db.todoDao);
      final backup = BackupRepository(
        todoRepo,
        FakeBackupIo(pickResult: '/tmp/ok.json', pickContents: validJson),
      );
      final container = _makeContainer(
        prefs: prefs,
        backupRepo: backup,
        todoRepo: todoRepo,
      );

      await tester.pumpWidget(_buildScreen(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import-tile')));
      await tester.pumpAndSettle();

      expect(find.text('Replace all data?'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      // Data unchanged (DB is empty)
      final snapshot = await todoRepo.exportSnapshot();
      expect(snapshot, isEmpty);
    },
  );

  // -------------------------------------------------------------------------
  // Test 8: Import → Ready → Replace → success → importDone snackbar + data replaced
  // -------------------------------------------------------------------------

  testWidgets(
    'import ready replace success shows importDone snackbar and replaces data',
    (WidgetTester tester) async {
      final validJson = encodeBackup(_oneCategory());
      final todoRepo = TodoRepository(db.todoDao);
      final backup = BackupRepository(
        todoRepo,
        FakeBackupIo(pickResult: '/tmp/ok.json', pickContents: validJson),
      );
      final container = _makeContainer(
        prefs: prefs,
        backupRepo: backup,
        todoRepo: todoRepo,
      );

      await tester.pumpWidget(_buildScreen(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import-tile')));
      await tester.pumpAndSettle();

      expect(find.text('Replace all data?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-import')));
      await tester.pumpAndSettle();

      // Success snackbar with count text
      expect(find.textContaining('Imported'), findsOneWidget);
      expect(find.text('Imported 1 category'), findsOneWidget);

      // Data replaced
      final snapshot = await todoRepo.exportSnapshot();
      expect(snapshot.single.category.name, 'Imported');
    },
  );

  // -------------------------------------------------------------------------
  // Test 9: Import → Ready → Replace → applyImport FAILURE → actionFailed snackbar
  // -------------------------------------------------------------------------

  testWidgets('import replace with throwing repo shows actionFailed snackbar', (
    WidgetTester tester,
  ) async {
    final validJson = encodeBackup(_oneCategory());
    final throwingTodoRepo = ThrowingTodoRepository(db.todoDao);
    final backup = BackupRepository(
      throwingTodoRepo,
      FakeBackupIo(pickResult: '/tmp/ok.json', pickContents: validJson),
    );
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: throwingTodoRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('import-tile')));
    await tester.pumpAndSettle();

    expect(find.text('Replace all data?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-import')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't complete that. Try again."), findsOneWidget);
  });

  // =========================================================================
  // Cloud backup section tests
  // =========================================================================

  // -------------------------------------------------------------------------
  // Cloud 1: Not connected → shows Connect tile, no backup/restore tiles
  // -------------------------------------------------------------------------

  testWidgets('cloud: shows Connect tile when not connected', (tester) async {
    final todoRepo = TodoRepository(db.todoDao);
    final fakeIo = FakeCloudBackupIo(); // account is null
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cloud-section-header')), findsOneWidget);
    expect(find.text('Cloud backup (Google Drive)'), findsOneWidget);
    expect(find.byKey(const Key('cloud-connect-tile')), findsOneWidget);
    expect(find.byKey(const Key('cloud-backup-now-tile')), findsNothing);
    expect(find.byKey(const Key('cloud-restore-tile')), findsNothing);
    expect(find.byKey(const Key('cloud-disconnect-tile')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Cloud 2: Connect success → account tile appears, connect tile gone
  // -------------------------------------------------------------------------

  testWidgets('cloud: connect success shows account email', (tester) async {
    final todoRepo = TodoRepository(db.todoDao);
    final fakeIo = FakeCloudBackupIo(); // account is null initially
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cloud-connect-tile')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cloud-connect-tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cloud-section-header')), findsOneWidget);
    expect(find.text('Cloud backup (Google Drive)'), findsOneWidget);
    expect(find.byKey(const Key('cloud-connect-tile')), findsNothing);
    expect(find.text('Connected as a@b.com'), findsOneWidget);
    expect(find.byKey(const Key('cloud-backup-now-tile')), findsOneWidget);
    expect(find.byKey(const Key('cloud-disconnect-tile')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Cloud 3: Disconnect → connect tile returns, account tile gone
  // -------------------------------------------------------------------------

  testWidgets('cloud: disconnect clears account', (tester) async {
    final todoRepo = TodoRepository(db.todoDao);
    final fakeIo = FakeCloudBackupIo(
      account: const CloudAccount('user@test.com'),
    );
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cloud-disconnect-tile')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cloud-disconnect-tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cloud-connect-tile')), findsOneWidget);
    expect(find.byKey(const Key('cloud-disconnect-tile')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Cloud 4: Backup success → cloudBackupDone snackbar
  // -------------------------------------------------------------------------

  testWidgets('cloud: backup now success shows cloudBackupDone snackbar', (
    tester,
  ) async {
    final todoRepo = TodoRepository(db.todoDao);
    final fakeIo = FakeCloudBackupIo(
      account: const CloudAccount('user@test.com'),
    );
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud-backup-now-tile')));
    await tester.pumpAndSettle();

    expect(find.text('Backed up to Drive.'), findsOneWidget);
    expect(fakeIo.refs, isNotEmpty);
  });

  // -------------------------------------------------------------------------
  // Cloud 5: Backup failure (upload throws) → actionFailed snackbar
  // -------------------------------------------------------------------------

  testWidgets('cloud: backup failure shows actionFailed snackbar', (
    tester,
  ) async {
    final todoRepo = TodoRepository(db.todoDao);
    final fakeIo = FakeCloudBackupIo(
      account: const CloudAccount('user@test.com'),
    )..throwOnUpload = true;
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud-backup-now-tile')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't complete that. Try again."), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Cloud 6: Restore with empty list → cloudNoBackups snackbar
  // -------------------------------------------------------------------------

  testWidgets('cloud: restore empty list shows cloudNoBackups snackbar', (
    tester,
  ) async {
    final todoRepo = TodoRepository(db.todoDao);
    final fakeIo = FakeCloudBackupIo(
      account: const CloudAccount('user@test.com'),
    );
    // refs is empty
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud-restore-tile')));
    await tester.pumpAndSettle();

    expect(find.text('No backups found in Drive.'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Cloud 7: Restore list failure (throwOnList) → actionFailed snackbar
  // -------------------------------------------------------------------------

  testWidgets('cloud: restore list failure shows actionFailed snackbar', (
    tester,
  ) async {
    final todoRepo = TodoRepository(db.todoDao);
    final fakeIo = FakeCloudBackupIo(
      account: const CloudAccount('user@test.com'),
    )..throwOnList = true;
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud-restore-tile')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't complete that. Try again."), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Cloud 8: Restore pick + confirm → importDone snackbar
  // -------------------------------------------------------------------------

  testWidgets('cloud: restore pick and confirm replaces data', (tester) async {
    final todoRepo = TodoRepository(db.todoDao);
    final validJson = encodeBackup(_oneCategory());
    final fakeIo =
        FakeCloudBackupIo(account: const CloudAccount('user@test.com'))
          ..refs.add(
            CloudBackupRef(
              id: 'ref1',
              name: 'backup.json',
              createdAt: DateTime.utc(2026, 6, 1),
            ),
          )
          ..contents['ref1'] = validJson;
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud-restore-tile')));
    await tester.pumpAndSettle();

    // Backup list dialog is open; tap the first (and only) entry
    await tester.tap(find.byKey(const Key('cloud-backup-entry-0')));
    await tester.pumpAndSettle();

    // Confirm dialog appears (reusing importReplaceTitle)
    expect(find.text('Replace all data?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-import')));
    await tester.pumpAndSettle();

    expect(find.text('Imported 1 category'), findsOneWidget);
    final snapshot = await todoRepo.exportSnapshot();
    expect(snapshot.single.category.name, 'Imported');
  });

  // -------------------------------------------------------------------------
  // Cloud 9: Restore corrupt backup → importInvalidFile snackbar
  // -------------------------------------------------------------------------

  testWidgets(
    'cloud: restore corrupt backup shows importInvalidFile snackbar',
    (tester) async {
      final todoRepo = TodoRepository(db.todoDao);
      final fakeIo =
          FakeCloudBackupIo(account: const CloudAccount('user@test.com'))
            ..refs.add(
              CloudBackupRef(
                id: 'bad1',
                name: 'bad.json',
                createdAt: DateTime.utc(2026, 6, 2),
              ),
            )
            ..contents['bad1'] = 'not valid json';
      final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
      final backup = BackupRepository(todoRepo, FakeBackupIo());
      final container = _makeContainer(
        prefs: prefs,
        backupRepo: backup,
        todoRepo: todoRepo,
        cloudBackupRepo: cloudRepo,
      );

      await tester.pumpWidget(_buildScreen(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloud-restore-tile')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloud-backup-entry-0')));
      await tester.pumpAndSettle();

      expect(find.text("That isn't a valid Nooka backup."), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------------
  // Cloud 10: Restore - download failure → actionFailed (ImportPickFailed)
  // -------------------------------------------------------------------------

  testWidgets('cloud: restore download failure shows actionFailed snackbar', (
    tester,
  ) async {
    final todoRepo = TodoRepository(db.todoDao);
    // ref added with NO contents entry → download throws → ImportPickFailed
    final fakeIo =
        FakeCloudBackupIo(account: const CloudAccount('user@test.com'))
          ..refs.add(
            CloudBackupRef(
              id: 'fail1',
              name: 'fail.json',
              createdAt: DateTime.utc(2026, 6, 3),
            ),
          );
    // contents['fail1'] intentionally absent → download() throws
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud-restore-tile')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud-backup-entry-0')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't complete that. Try again."), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Cloud 11: Restore - cancel confirm dialog; 2 refs to cover _formatDate
  // -------------------------------------------------------------------------

  testWidgets('cloud: restore cancel confirm dialog leaves data unchanged', (
    tester,
  ) async {
    final todoRepo = TodoRepository(db.todoDao);
    final validJson = encodeBackup(_oneCategory());
    final fakeIo =
        FakeCloudBackupIo(account: const CloudAccount('user@test.com'))
          ..refs.addAll([
            CloudBackupRef(
              id: 'ref1',
              name: 'latest.json',
              createdAt: DateTime.utc(2026, 6, 10),
            ),
            CloudBackupRef(
              id: 'ref2',
              name: 'older.json',
              createdAt: DateTime.utc(2026, 6, 1),
            ),
          ])
          ..contents['ref1'] = validJson
          ..contents['ref2'] = validJson;
    final cloudRepo = CloudBackupRepository(todoRepo, fakeIo);
    final backup = BackupRepository(todoRepo, FakeBackupIo());
    final container = _makeContainer(
      prefs: prefs,
      backupRepo: backup,
      todoRepo: todoRepo,
      cloudBackupRepo: cloudRepo,
    );

    await tester.pumpWidget(_buildScreen(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud-restore-tile')));
    await tester.pumpAndSettle();

    // _formatDate is called for entry at index 1 while building the dialog
    expect(find.byKey(const Key('cloud-backup-entry-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cloud-backup-entry-0')));
    await tester.pumpAndSettle();

    // Confirm dialog appears
    expect(find.text('Replace all data?'), findsOneWidget);

    // Cancel — covers the `confirmed != true` branch
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    final snapshot = await todoRepo.exportSnapshot();
    expect(snapshot, isEmpty);
  });
}
