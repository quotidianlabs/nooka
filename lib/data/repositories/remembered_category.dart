import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'settings_repository.dart';

part 'remembered_category.g.dart';

/// Persists the category last used when adding a to-do, so the quick-add
/// default survives restarts. A thin module over [SettingsRepository]; the
/// pure pick rule lives in `domain/default_category.dart`.
class RememberedCategory {
  RememberedCategory(this._settings);
  final SettingsRepository _settings;

  /// The stored category id, or null if none has been remembered.
  int? read() => _settings.readLastCategoryId();

  /// Remembers [id] as the last-used category. Skips the write (an
  /// `SharedPreferences` disk I/O) when [id] is already the stored value —
  /// reads are in-memory, so the common "add several to the same category" path
  /// does no redundant I/O.
  Future<void> write(int id) async {
    if (_settings.readLastCategoryId() == id) return;
    await _settings.writeLastCategoryId(id);
  }

  /// Forgets the remembered category (e.g. after it is deleted).
  Future<void> forget() => _settings.clearLastCategoryId();
}

@Riverpod(keepAlive: true)
RememberedCategory rememberedCategory(Ref ref) =>
    RememberedCategory(ref.watch(settingsRepositoryProvider));
