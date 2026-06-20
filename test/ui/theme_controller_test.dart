import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nooka/data/repositories/settings_repository.dart';
import 'package:nooka/ui/core/theme_controller.dart';

Future<ProviderContainer> _container(SharedPreferences prefs) async =>
    ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

void main() {
  test('defaults to system before any save', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = await _container(prefs);
    addTearDown(container.dispose);

    expect(container.read(themeControllerProvider), AppThemeMode.system);
  });

  test('set persists the token and updates state', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = await _container(prefs);
    addTearDown(container.dispose);

    await container
        .read(themeControllerProvider.notifier)
        .set(AppThemeMode.dark);

    expect(container.read(themeControllerProvider), AppThemeMode.dark);
    expect(prefs.getString('theme'), 'dark');

    final reopened = await _container(prefs);
    addTearDown(reopened.dispose);
    expect(reopened.read(themeControllerProvider), AppThemeMode.dark);
  });

  test('an unknown stored token falls back to system', () async {
    SharedPreferences.setMockInitialValues({'theme': 'sepia'});
    final prefs = await SharedPreferences.getInstance();
    final container = await _container(prefs);
    addTearDown(container.dispose);

    expect(container.read(themeControllerProvider), AppThemeMode.system);
  });
}
