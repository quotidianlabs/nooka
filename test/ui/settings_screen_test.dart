import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/repositories/backup_repository.dart';
import 'package:nooka/data/repositories/settings_repository.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/backup/backup_io.dart';
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
}) {
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      backupRepositoryProvider.overrideWith((ref) => backupRepo),
      todoRepositoryProvider.overrideWith((ref) => todoRepo),
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
}
