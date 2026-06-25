import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/backup_repository.dart';
import '../../data/repositories/remembered_category.dart';
import '../../data/repositories/todo_repository.dart';
import '../../domain/models/backup_data.dart';

part 'settings_view_model.g.dart';

/// The outcome of picking + decoding a backup file, before the user confirms.
sealed class ImportPick {
  const ImportPick();
}

/// A valid backup is ready; show the confirm dialog for [data].
class ImportPickReady extends ImportPick {
  const ImportPickReady(this.data);
  final BackupData data;
}

/// The user cancelled the file picker — do nothing.
class ImportPickCancelled extends ImportPick {
  const ImportPickCancelled();
}

/// The chosen file is not a valid Nooka backup.
class ImportPickInvalid extends ImportPick {
  const ImportPickInvalid();
}

/// An unexpected error occurred while picking/reading the file.
class ImportPickFailed extends ImportPick {
  const ImportPickFailed();
}

/// Owns the settings screen's backup commands: export, pick-and-decode, and
/// apply (replace-all). Raw errors never cross the seam — they are logged and
/// mapped to a coarse result the widget turns into a localized SnackBar.
@riverpod
class SettingsViewModel extends _$SettingsViewModel {
  @override
  void build() {}

  BackupRepository get _backup => ref.read(backupRepositoryProvider);
  TodoRepository get _todos => ref.read(todoRepositoryProvider);
  RememberedCategory get _remembered => ref.read(rememberedCategoryProvider);

  /// Exports + shares the database. Returns false on any failure (logged).
  Future<bool> export(String subject) async {
    try {
      await _backup.exportAndShare(subject: subject);
      return true;
    } catch (e, st) {
      debugPrint('export failed: $e\n$st');
      return false;
    }
  }

  /// Opens the picker and decodes the chosen file into an [ImportPick].
  Future<ImportPick> pickImport() async {
    try {
      final data = await _backup.pickAndDecode();
      return data == null ? const ImportPickCancelled() : ImportPickReady(data);
    } on BackupFormatException catch (e) {
      debugPrint('import invalid: ${e.message}');
      return const ImportPickInvalid();
    } catch (e, st) {
      debugPrint('import pick failed: $e\n$st');
      return const ImportPickFailed();
    }
  }

  /// Replaces all data with [data] and forgets the stale remembered category.
  /// Returns false on any failure (logged); the reactive stream reverts the UI.
  Future<bool> applyImport(BackupData data) async {
    try {
      await _todos.importReplace(data.categories);
      await _remembered.forget();
      return true;
    } catch (e, st) {
      debugPrint('import apply failed: $e\n$st');
      return false;
    }
  }
}
