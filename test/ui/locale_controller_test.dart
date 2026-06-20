import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nooka/data/repositories/settings_repository.dart';
import 'package:nooka/ui/core/locale_controller.dart';

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

    expect(container.read(localeControllerProvider), AppLocale.system);
  });

  test('set persists the token and updates state', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = await _container(prefs);
    addTearDown(container.dispose);

    await container.read(localeControllerProvider.notifier).set(AppLocale.ru);

    expect(container.read(localeControllerProvider), AppLocale.ru);
    expect(prefs.getString('locale'), 'ru');

    // Round-trip: a fresh container reading the same prefs reads back ru.
    final reopened = await _container(prefs);
    addTearDown(reopened.dispose);
    expect(reopened.read(localeControllerProvider), AppLocale.ru);
  });

  test('an unknown stored token falls back to system', () async {
    SharedPreferences.setMockInitialValues({'locale': 'klingon'});
    final prefs = await SharedPreferences.getInstance();
    final container = await _container(prefs);
    addTearDown(container.dispose);

    expect(container.read(localeControllerProvider), AppLocale.system);
  });
}
