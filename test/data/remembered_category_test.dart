import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nooka/data/repositories/remembered_category.dart';
import 'package:nooka/data/repositories/settings_repository.dart';

Future<RememberedCategory> _module() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return RememberedCategory(SettingsRepository(prefs));
}

void main() {
  test('read is null before any write', () async {
    final remembered = await _module();
    expect(remembered.read(), isNull);
  });

  test('write then read round-trips the id', () async {
    final remembered = await _module();
    await remembered.write(42);
    expect(remembered.read(), 42);
  });

  test('forget clears a stored id', () async {
    final remembered = await _module();
    await remembered.write(7);
    expect(remembered.read(), 7);

    await remembered.forget();
    expect(remembered.read(), isNull);
  });
}
