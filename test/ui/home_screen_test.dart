import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/data/services/database/database_providers.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/home/home_screen.dart';

Widget _app(AppDatabase db, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
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

  testWidgets('Russian locale renders the 4-form plural correctly', (
    tester,
  ) async {
    final cat = await db.todoDao.createCategory(name: 'Дом', color: 0xFF009688);
    for (var i = 0; i < 5; i++) {
      await db.todoDao.createTask(categoryId: cat, name: 'Дело $i');
    }
    await tester.pumpWidget(_app(db, locale: const Locale('ru')));
    await tester.pumpAndSettle();

    // 5 active items -> Russian "many" form: "5 дел".
    expect(find.textContaining('5 дел'), findsOneWidget);

    // An archived item shows the Russian countdown with "дней".
    final archivedCat = await db.todoDao.createCategory(
      name: 'Работа',
      color: 0xFF3F51B5,
    );
    final id = await db.todoDao.createTask(
      categoryId: archivedCat,
      name: 'Отчёт',
    );
    await db.todoDao.completeTask(id, DateTime.now());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Архив'));
    await tester.pumpAndSettle();
    expect(find.textContaining('дней'), findsOneWidget);
  });

  testWidgets('tapping a category header collapses and expands its rows', (
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

    await tester.tap(find.byKey(Key('category-header-$cat')));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsNothing); // collapsed

    await tester.tap(find.byKey(Key('category-header-$cat')));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget); // expanded again
  });

  testWidgets('category header is a flat label with no leading circle', (
    tester,
  ) async {
    await db.todoDao.createCategory(name: 'Home', color: 0xFF009688);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    // The old header used a CircleAvatar swatch; the flat label has none, and
    // item rows use icons, so there should be no CircleAvatar on the screen.
    expect(find.byType(CircleAvatar), findsNothing);
    // Name + localized count render in the header rich text.
    expect(find.textContaining('Home'), findsOneWidget);
    expect(find.textContaining('no items'), findsOneWidget);
  });

  testWidgets('category header shows the icon before the name when set', (
    tester,
  ) async {
    await db.todoDao.createCategory(
      name: 'Shopping',
      color: 0xFF1E88E5,
      emoji: '🛒',
    );
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();
    expect(find.textContaining('🛒 Shopping'), findsOneWidget);
  });

  testWidgets('header and row ⋮ menus align on one vertical line', (
    tester,
  ) async {
    final cat = await db.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    final task = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    final headerMenu = tester.getCenter(find.byKey(Key('category-menu-$cat')));
    final rowMenu = tester.getCenter(find.byKey(Key('task-menu-$task')));
    expect(headerMenu.dx, moreOrLessEquals(rowMenu.dx, epsilon: 0.5));

    final chevron = tester.getCenter(find.byIcon(Icons.expand_less));
    final radio = tester.getCenter(find.byIcon(Icons.radio_button_unchecked));
    expect(chevron.dx, moreOrLessEquals(radio.dx, epsilon: 0.5));
  });

  testWidgets('undo toast is floating and auto-dismisses', (tester) async {
    final cat = await db.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump(); // flush the completeTask await
    await tester.pump(const Duration(milliseconds: 300)); // snackbar entrance
    expect(find.text('Item completed'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
      SnackBarBehavior.floating,
    );

    // Advance past duration + backstop; the toast must be gone.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Item completed'), findsNothing);
  });
}
