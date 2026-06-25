import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nooka/data/repositories/settings_repository.dart';

void main() {
  test('last category id round-trips and is null before any write', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(prefs);

    expect(repo.readLastCategoryId(), isNull);

    await repo.writeLastCategoryId(42);

    expect(repo.readLastCategoryId(), 42);
  });

  test('clearLastCategoryId removes a stored id', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(prefs);

    await repo.writeLastCategoryId(7);
    expect(repo.readLastCategoryId(), 7);

    await repo.clearLastCategoryId();
    expect(repo.readLastCategoryId(), isNull);
  });

  test('sharedPreferencesProvider throws until overridden in main', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container.read(sharedPreferencesProvider),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.exception,
          'exception',
          isA<UnimplementedError>(),
        ),
      ),
    );
  });
}
