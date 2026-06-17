import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('complete persists across relaunch, then restores', (
    tester,
  ) async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/it_nooka.sqlite');
    if (file.existsSync()) file.deleteSync();

    // Launch 1: seed + complete.
    final db1 = AppDatabase(NativeDatabase(file));
    final cat = await db1.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    final id = await db1.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await db1.todoDao.completeTask(id, DateTime.now());
    await db1.close();

    // Launch 2: reopen same file, confirm archived, restore via UI.
    final db2 = AppDatabase(NativeDatabase(file));
    addTearDown(db2.close);
    await tester.pumpWidget(_app(db2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);
  });
}
