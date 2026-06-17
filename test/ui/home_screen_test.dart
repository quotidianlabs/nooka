import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/data/services/database/database_providers.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/home/home_screen.dart';

Widget _app(AppDatabase db) => ProviderScope(
  overrides: [appDatabaseProvider.overrideWithValue(db)],
  child: const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: HomeScreen(),
  ),
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('empty state shown with no categories', (tester) async {
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();
    expect(find.text('No categories yet — add one'), findsOneWidget);
  });

  testWidgets('completing a task moves it from Active to Archive', (
    tester,
  ) async {
    final cat = await db.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    expect(find.text('Sweep'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pumpAndSettle();
    // Removed from Active view.
    expect(find.text('Sweep'), findsNothing);

    // Switch to Archive and see it with a countdown.
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);
    expect(find.textContaining('Auto-removes in'), findsOneWidget);
  });

  testWidgets('restoring from Archive returns it to Active', (tester) async {
    final cat = await db.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    final id = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await db.todoDao.completeTask(id, DateTime.now());
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsNothing); // gone from archive

    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);
  });

  testWidgets('quick add keeps the dialog open for several items', (
    tester,
  ) async {
    await db.todoDao.createCategory(name: 'Home', color: 0xFF009688);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-task-fab')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('quick-add-field')), 'First');
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pumpAndSettle();
    // Dialog is still open (field present) and cleared.
    expect(find.byKey(const Key('quick-add-field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('quick-add-field')), 'Second');
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-add-done')));
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('swipe-right completes an active item', (tester) async {
    final cat = await db.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    // Task id is 1 (first row in a fresh in-memory DB).
    await tester.drag(find.byKey(const Key('dismiss-1')), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsNothing);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);
  });

  testWidgets('clear archive removes all archived items', (tester) async {
    final cat = await db.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    final id = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await db.todoDao.completeTask(id, DateTime.now());
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-archive-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-clear-archive')));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsNothing);
  });
}
