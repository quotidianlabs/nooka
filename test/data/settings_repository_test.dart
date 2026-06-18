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
}
