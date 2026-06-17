import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nooka/data/repositories/settings_repository.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/core/theme_controller.dart';
import 'package:nooka/ui/settings/settings_screen.dart';

void main() {
  testWidgets('changing theme to Dark persists the token', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
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

    // Tap the DropdownButton in the theme-tile's trailing slot.
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
}
