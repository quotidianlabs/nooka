import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_repository.g.dart';

/// The loaded SharedPreferences instance; overridden in `main()`.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) => throw UnimplementedError(
  'sharedPreferencesProvider must be overridden in main',
);

/// Persists app preferences (theme + locale tokens).
class SettingsRepository {
  SettingsRepository(this._prefs);
  final SharedPreferences _prefs;

  static const _localeKey = 'locale';
  static const _themeKey = 'theme';
  static const _lastCategoryKey = 'last_category';

  String? readLocaleToken() => _prefs.getString(_localeKey);
  Future<void> writeLocaleToken(String token) =>
      _prefs.setString(_localeKey, token);

  String? readThemeToken() => _prefs.getString(_themeKey);
  Future<void> writeThemeToken(String token) =>
      _prefs.setString(_themeKey, token);

  /// The category id last used when adding a to-do, or null if none stored.
  int? readLastCategoryId() => _prefs.getInt(_lastCategoryKey);
  Future<void> writeLastCategoryId(int id) =>
      _prefs.setInt(_lastCategoryKey, id);

  /// Forgets the last-used category (e.g. after it is deleted).
  Future<void> clearLastCategoryId() => _prefs.remove(_lastCategoryKey);
}

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    SettingsRepository(ref.watch(sharedPreferencesProvider));
