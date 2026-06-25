---
status: shipped
date: 2026-06-25
slug: export-import
summary: Full-DB JSON export/import (share-sheet out, file-picker in) with a pure backup codec, a coverage-isolated platform-I/O seam, and a destructive replace-all import behind a confirm dialog.
supersedes: null
superseded_by: null
pr: null
outcome: |
  Shipped habbits-style: pure `backup_codec` + `BackupData` models, `TodoDao`
  `exportSnapshot`/`importReplace` (one-shot read + atomic replace-all),
  `TodoRepository` pass-throughs, `BackupRepository` over an injectable
  `BackupIo` seam (platform leaf isolated in `platform_backup_io.dart`,
  coverde-excluded), a `@riverpod SettingsViewModel`, Settings Export/Import
  tiles + confirm dialog, and bilingual strings. Archive state round-trips via
  `archivedAt`; import resets the remembered category. New capability doc
  `architecture/backup-io.md`. An emulator integration test
  (`backup_round_trip_test.dart`) drives the real file I/O in CI next to
  `critical_flow_test.dart`. 205 unit/widget tests; coverage 100% (1033/1033).
---

# Design: JSON export/import — full-DB backup and restore

## Summary

Add data portability: the user can **export** the whole to-do database to a
pretty-printed JSON file via the OS share sheet, and **import** such a file to
**replace** all current data in one transaction. The work is decomposed the
habbits way — a pure `backup_codec` in `domain/` (no Drift/Flutter imports), a
`BackupRepository` that orchestrates file I/O behind an injectable `BackupIo`
seam, and a thin `SettingsViewModel` command seam the `SettingsScreen` calls.
`TodoRepository` (the existing data port) gains `exportSnapshot()` and
`importReplace()`; `TodoDao` gains the matching one-shot read and the
replace-all transaction. The export is a true full backup — it carries archived
tasks with their `archivedAt`, so archive state round-trips losslessly. Import
is destructive (replace-all) and gated by a confirm dialog. The only
platform-bound, untestable surface (share_plus / file_picker / path_provider /
`dart:io`) is isolated in one leaf class added to `coverde.yaml`, exactly like
`connection.dart`, so the 100% coverage gate stays green.

## Motivation

`planning/deferred.md` lists JSON export/import with the revisit trigger "when
the local-first / your-data story needs reinforcing." nooka is a local-first
to-do app with no cloud sync; today there is **no way to back up, move, or
recover the database** — a lost or reset device loses everything. habbits
already ships this exact feature
(`planning/changes/2026-06-14.01-export-import/`), so the design is proven; this
change ports it to nooka's category→task shape and stricter coverage gate.

## Non-goals

- **Merge import.** Import always replaces all data; no identity matching,
  id remapping, or conflict resolution. (Decided with the maintainer.)
- **Selective export.** No per-category or active-only export — it is the whole
  DB, every time.
- **CSV, encryption, scheduled/automatic backups, cloud sync.** Out of scope.
- **Per-field import error messages in the UI.** Validation is strict and
  specific internally (for tests/logs), but the UI shows a single localized
  "invalid backup" message to keep the bilingual i18n surface small.
- **Schema migration of old backups.** Only `version: 1` is accepted; a
  mismatch is rejected, not migrated. Revisit when `version` reaches 2.

## Design

### 1. File format (`version: 1`)

nooka's data is nested (categories → tasks, FK `onDelete: cascade`), so the
backup nests tasks under their category. **Row ids are not exported** — they are
autoincrement surrogate keys reassigned on import; the parent/child link is
implicit in the nesting. Tasks are emitted in `sortOrder` for stable diffs.

```json
{
  "app": "nooka",
  "version": 1,
  "exportedAt": "2026-06-25T09:30:00.000",
  "categories": [
    {
      "name": "Work",
      "color": 4278228616,
      "emoji": "💼",
      "collapsed": false,
      "sortOrder": 0,
      "createdAt": "2026-06-01T08:00:00.000",
      "tasks": [
        { "name": "Ship it", "sortOrder": 0,
          "createdAt": "2026-06-02T08:00:00.000", "archivedAt": null },
        { "name": "Old thing", "sortOrder": 1,
          "createdAt": "2026-06-01T08:00:00.000",
          "archivedAt": "2026-06-10T12:00:00.000" }
      ]
    }
  ]
}
```

Field types: `app` literal `"nooka"`; `version` int `1`; `exportedAt` /
`createdAt` / `archivedAt` ISO-8601 (`DateTime.toIso8601String()`); `emoji`
string or `null`; `archivedAt` string or `null` (null = active). Pretty-printed
with 2-space indent.

### 2. Domain models + codec (pure, 100% unit-testable)

`lib/domain/models/backup_data.dart`:

```dart
class BackupTask {
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime? archivedAt;
}
class BackupCategory {
  final String name;
  final int color;
  final String? emoji;
  final bool collapsed;
  final int sortOrder;
  final DateTime createdAt;
  final List<BackupTask> tasks;
}
class BackupData {
  final int version;
  final DateTime exportedAt;
  final List<BackupCategory> categories;
}
class BackupFormatException implements Exception {
  final String message; // English; for logs/tests, not shown raw to the user
}
```

`lib/domain/backup_codec.dart` — no Drift/Flutter imports:

```dart
String encodeBackup(BackupData data);          // -> pretty JSON
BackupData decodeBackup(String source);        // strict; throws BackupFormatException
BackupData buildBackup(List<CategoryWithTasks> rows, DateTime now);
```

`decodeBackup` validates **everything before returning** (a bad file can never
reach a DB write): root is a `Map`; `app == 'nooka'`; `version` is int `1`;
`exportedAt` parseable; `categories` is a `List`; each category's `name` is a
non-empty string, `color`/`sortOrder` are ints, `emoji` is null-or-string,
`collapsed` is a bool, `createdAt` parseable, `tasks` is a `List`; each task's
`name` non-empty string, `sortOrder` int, `createdAt` parseable, `archivedAt`
null-or-parseable. First violation throws.

`buildBackup` consumes `CategoryWithTasks` (which already carries active **and**
archived tasks), sorting tasks by `sortOrder`.

### 3. Data layer — DAO + the `TodoRepository` port

`TodoDao` gains two methods:

- `Future<List<CategoryWithTasks>> exportSnapshot()` — one-shot version of the
  existing categories⋈tasks join (all tasks, active + archived), ordered.
- `Future<void> importReplace(List<BackupCategory> categories)` — **one
  transaction**: `delete(tasks)`, `delete(categories)`, then insert each
  category (capturing its new autoincrement id) and its tasks under that id.
  `createdAt`/`archivedAt` are written from the backup; a mid-import failure
  rolls the whole thing back to the prior state.

`TodoRepository` (the single data seam) gets thin pass-throughs
`exportSnapshot()` and `importReplace()`, keeping view models off the DAO. No
`Clock` involvement here — import preserves the backup's own timestamps.

### 4. File I/O — `BackupRepository` + the coverage-isolated `BackupIo` seam

The untestable, platform-bound calls are confined to one leaf:

```dart
// lib/data/services/backup/backup_io.dart  (interface — testable)
abstract interface class BackupIo {
  Future<String> writeTemp(String filename, String contents); // -> path
  Future<void> shareFile(String path, String subject);
  Future<String?> pickFile();   // -> path, or null if cancelled
  Future<String> readFile(String path);
}
```

```dart
// lib/data/services/backup/platform_backup_io.dart  (EXCLUDED from coverage)
class PlatformBackupIo implements BackupIo { /* share_plus, file_picker,
   path_provider, dart:io File */ }
```

`platform_backup_io.dart` is added to `coverde.yaml`'s `exclude-untestable`
glob list, exactly like `connection.dart` — production glue unrunnable under
`flutter test`, covered instead by manual/emulator verification.

```dart
// lib/data/repositories/backup_repository.dart  (orchestration — testable via fake BackupIo)
class BackupRepository {
  BackupRepository(this._todos, this._io, {Clock clock = const SystemClock()});

  Future<void> exportAndShare({required String subject}) async {
    final now = _clock.now();
    final json = encodeBackup(buildBackup(await _todos.exportSnapshot(), now));
    final path = await _io.writeTemp('nooka-backup-${_isoDate(now)}.json', json);
    await _io.shareFile(path, subject);
  }

  Future<BackupData?> pickAndDecode() async {
    final path = await _io.pickFile();
    if (path == null) return null;               // cancelled
    return decodeBackup(await _io.readFile(path)); // may throw BackupFormatException
  }
}
```

The export timestamp comes from the injectable `Clock` (consistent with the
clock-seam decision, `2026-06-24.02`), so the filename and `exportedAt` are
deterministic in tests.

### 5. Command seam — `SettingsViewModel`

`SettingsScreen` is today a plain `ConsumerWidget`. Introduce a `@riverpod`
`SettingsViewModel` (mirrors habbits and nooka's own `HomeViewModel`):

```dart
@riverpod
class SettingsViewModel extends _$SettingsViewModel {
  @override
  void build() {}
  Future<void> export(String subject);          // -> BackupRepository.exportAndShare
  Future<BackupData?> pickImport();             // -> BackupRepository.pickAndDecode
  Future<void> applyImport(BackupData data);    // -> TodoRepository.importReplace + reset remembered category
}
```

Providers: `backupRepositoryProvider` (keep-alive) wiring
`TodoRepository` + `PlatformBackupIo` + `clock`.

`SettingsScreen` gains two `ListTile`s — **Export data** and **Import data**.
Import: `pickImport()` → if `null` return → **confirm dialog** ("Replace all
data? This deletes N categories and all their tasks", reusing the
`confirm_delete_dialog` / `dialog_constants` style) → `applyImport`.

### 6. Error & result surfacing (bilingual EN + RU)

Following `architecture/error-handling.md`: the raw error never crosses to the
UI as text. The widget maps outcomes to localized SnackBars in one place:

- success → `importDone(categoryCount)`
- `BackupFormatException` → generic `importInvalidFile`
- any other throw → existing `actionFailed`

Because the reactive `watchCategoriesWithTasks` stream re-renders the stored
truth, a failed import visibly self-reverts — no manual rollback. New l10n keys
(`exportData`, `importData`, `importDone`, `importInvalidFile`,
`importReplaceTitle`, `importReplaceBody`, plus the share subject) are added to
both `app_en.arb` and `app_ru.arb`.

### 7. Remembered-category reset

The last-used category id lives in `shared_preferences`
(`remembered_category.dart`). After replace-all, ids are reassigned, so the
stored id is stale. `applyImport` **clears the remembered category** after a
successful import; the `default_category` fallback then selects a valid one.

## Operations

None — no DNS/infra/external accounts. New pub packages only (below).

## Out of scope

See Non-goals. Notably: merge import, selective/active-only export, CSV,
encryption, scheduled backups, cloud sync, and migrating pre-v1 backups.

## Testing

Everything except the excluded leaf is unit/widget-tested, preserving the 100%
gate:

- `test/domain/backup_codec_test.dart` — encode/decode round-trip; every reject
  branch (non-JSON, non-object root, wrong `app`, bad `version`, missing/typed
  fields, bad dates, null vs non-null `archivedAt`); empty-DB backup.
- `test/data/backup_db_test.dart` — in-memory Drift: `buildBackup` snapshot
  ordering; full export→encode→decode→`importReplace` round-trip including
  archived tasks; replace-all clears prior data (cascade) atomically.
- `test/data/backup_repository_test.dart` — orchestration via a fake `BackupIo`:
  correct filename + contents handed to `shareFile`; `pickAndDecode` decodes;
  cancelled pick returns `null`; a decode failure propagates `BackupFormatException`.
- `test/ui/settings_view_model_test.dart` — export/pickImport/applyImport;
  remembered-category reset on import.
- `test/ui/settings_screen_test.dart` — Export/Import tiles render; confirm
  dialog replaces data + success SnackBar with count; invalid-file SnackBar.

`platform_backup_io.dart` is coverage-excluded. Its real file I/O
(`writeTemp`/`readFile`, path_provider + `dart:io`) is exercised by an
**emulator integration test** (`integration_test/backup_round_trip_test.dart`,
run in CI next to `critical_flow_test.dart`) that does a real
export→file→import round-trip — matching the precedent by which
`connection.dart` is excluded-but-emulator-covered. Only `shareFile` (OS share
sheet) and `pickFile` (native picker) remain manual-verify, as neither can be
driven headlessly. Final gate: `just lint-ci` clean, `just coverage` green at
100%, integration test green in CI.

## Risk

- **Coverage gate breakage (likely × medium).** The platform plugins are not
  unit-testable. Mitigation: the `BackupIo` seam confines every untestable call
  to one leaf class on the `coverde.yaml` exclude list — the established
  `connection.dart` pattern; all orchestration stays covered via a fake.
- **Destructive import data loss (low × high).** A mis-tap could wipe data.
  Mitigation: explicit confirm dialog quoting the category count; the
  transaction is atomic, so a failed import leaves data intact.
- **Android plugin compatibility (medium × low).** `file_picker` pulls
  `flutter_plugin_android_lifecycle`; habbits pinned it via
  `dependency_overrides`. Mitigation: verify against nooka's Flutter version
  during implementation and add the override only if the build requires it.
- **iPad share crash (low × low).** habbits noted `SharePlus.share` needs
  `sharePositionOrigin` on iPad. nooka targets iPhone + Android; revisit if iPad
  becomes a target.
