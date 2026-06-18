import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nooka/data/repositories/settings_repository.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/data/services/database/database_providers.dart';
import 'package:nooka/main.dart';

Future<AppDatabase> seededDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  final dao = db.todoDao;
  final now = DateTime.now();

  Future<void> category(
    String name,
    int color,
    String emoji,
    List<String> active,
    List<String> completed,
  ) async {
    final id = await dao.createCategory(name: name, color: color, emoji: emoji);
    for (final n in active) {
      await dao.createTask(categoryId: id, name: n);
    }
    for (final n in completed) {
      final taskId = await dao.createTask(categoryId: id, name: n);
      await dao.completeTask(taskId, now);
    }
  }

  // Colors are drawn from kCategoryPalette so the shots match the picker.
  await category(
    'Home',
    0xFF009688,
    '🏠',
    ['Water the plants', 'Take out recycling', 'Vacuum living room'],
    ['Replace air filter'],
  );
  await category(
    'Work',
    0xFF1E88E5,
    '💼',
    ['Email Priya', 'Draft Q3 deck'],
    ['Book travel'],
  );
  await category(
    'Groceries',
    0xFF43A047,
    '🛒',
    ['Oat milk', 'Spinach', 'Coffee beans'],
    ['Bananas'],
  );
  return db;
}

Future<void> pumpApp(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final db = await seededDb();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(sp),
      ],
      child: const NookaApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('README screenshots', (tester) async {
    var surfaceReady = false;
    Future<void> shoot(String name) async {
      if (Platform.isAndroid && !surfaceReady) {
        await binding.convertFlutterSurfaceToImage();
        surfaceReady = true;
      }
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    // --- Light, English ---
    await pumpApp(tester, {'theme': 'light'});
    await shoot('home-en');

    // Archive view — seeded completed items show the 30-day countdown.
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await shoot('archive-en');

    // Back to Active for the remaining English shots.
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();

    // Settings screen.
    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    await shoot('settings-en');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // New-category dialog with its color swatches.
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus(); // hide the keyboard
    await tester.pumpAndSettle();
    await shoot('create-en');

    // --- Russian (fresh app) ---
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpApp(tester, {'locale': 'ru', 'theme': 'light'});
    await shoot('home-ru');

    // --- Dark theme (fresh app) ---
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpApp(tester, {'theme': 'dark'});
    await shoot('home-dark');
  });
}
