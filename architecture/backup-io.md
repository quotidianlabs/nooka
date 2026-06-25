# Backup I/O capability

Nooka supports whole-database export and import as a single JSON file, giving
users a portable backup they can share or restore on any device.

## JSON format

A backup is a UTF-8 JSON object with the following top-level fields:

| Field        | Type   | Description                                      |
|--------------|--------|--------------------------------------------------|
| `app`        | String | Fixed marker `"nooka"`; used to reject alien files |
| `version`    | Int    | Format version; currently `1`                    |
| `exportedAt` | String | ISO-8601 UTC timestamp of the export             |
| `categories` | Array  | Ordered list of category objects (see below)     |

Each **category** object:

| Field       | Type    | Description                       |
|-------------|---------|-----------------------------------|
| `name`      | String  | Non-empty display name            |
| `color`     | Int     | ARGB integer                      |
| `emoji`     | String? | Optional leading emoji/character  |
| `collapsed` | Bool    | Whether the section is collapsed  |
| `sortOrder` | Int     | Display position                  |
| `createdAt` | String  | ISO-8601 UTC                      |
| `tasks`     | Array   | Tasks nested inside this category |

Each **task** object:

| Field        | Type    | Description                           |
|--------------|---------|---------------------------------------|
| `name`       | String  | Non-empty display name                |
| `sortOrder`  | Int     | Display position within the category  |
| `createdAt`  | String  | ISO-8601 UTC                          |
| `archivedAt` | String? | ISO-8601 UTC if archived; null if active |

Row ids are never serialized; the parent–child link is implicit in nesting.

## Data flow

```
PlatformBackupIo (platform seam)
        ↕  BackupIo interface
BackupRepository          — orchestrates file I/O + codec
        ↕
backup_codec.dart         — encodeBackup / decodeBackup (pure Dart)
        ↕
TodoDao / AppDatabase     — Drift DAO (read exportSnapshot / write importReplace)
        ↕
SettingsViewModel         — export() / pickImport() / applyImport()
        ↕
SettingsScreen            — two ListTiles, confirm AlertDialog, SnackBars
```

### Export path

1. `SettingsViewModel.export(subject)` calls `BackupRepository.exportAndShare`.
2. `BackupRepository` reads a snapshot via `TodoRepository.exportSnapshot()`,
   encodes it with `encodeBackup`, writes a temp file via `BackupIo.writeTemp`,
   then hands the file to the OS share sheet via `BackupIo.shareFile`.
3. On failure the VM returns `false`; the screen shows the `actionFailed`
   snackbar.

### Import path

1. `SettingsViewModel.pickImport()` calls `BackupRepository.pickAndDecode()`.
2. `BackupRepository` opens the OS file picker via `BackupIo.pickFile`.
   - `null` → user cancelled → `ImportPickCancelled`.
   - file path returned → read with `BackupIo.readFile` → decode with
     `decodeBackup` → `ImportPickReady(BackupData)`.
   - `BackupFormatException` from decoder → `ImportPickInvalid`.
   - any other exception → `ImportPickFailed`.
3. The screen switches over the `ImportPick` sealed class:
   - **Cancelled** — silent return.
   - **Invalid** — `importInvalidFile` snackbar.
   - **Failed** — `actionFailed` snackbar.
   - **Ready** — confirm `AlertDialog` titled `importReplaceTitle` / body
     `importReplaceBody(count)` with a Cancel button and a
     `confirm-import`-keyed Replace button.
4. On confirm, `SettingsViewModel.applyImport(data)` is called:
   - `TodoRepository.importReplace(data.categories)` replaces all data
     atomically in a single Drift transaction.
   - `RememberedCategory.forget()` clears the stale last-used-category id from
     SharedPreferences (the old id is meaningless after replace-all).
   - Returns `false` on any failure; the VM logs the error.
5. The screen shows `importDone(count)` on success or `actionFailed` on
   failure.

## Replace-all + confirm-dialog invariant

The import flow always shows a confirmation dialog before mutating any data.
The `applyImport` call is only reached when `confirmed == true` and
`context.mounted`. This prevents accidental data loss from a mis-tap and
makes the destructive step explicit to the user.

## Remembered-category reset

After `importReplace`, the previously remembered category id (stored in
SharedPreferences) no longer corresponds to any real category. `applyImport`
calls `RememberedCategory.forget()` unconditionally so the home screen's
quick-add default falls back to the first available category from the new data.

## BackupIo coverage-exclusion seam

`PlatformBackupIo` (`lib/data/services/backup/platform_backup_io.dart`) uses
`share_plus` and `file_picker` — both require a real device or emulator and are
excluded from the line-coverage gate via `// coverage:ignore-file`. All
orchestration logic lives in `BackupRepository`, which is fully tested through
the injected `BackupIo` interface using a `FakeBackupIo` test double.

## Integration test note

End-to-end validation of the share sheet and file picker (the excluded
`PlatformBackupIo` code) requires a running emulator and belongs in the
`integration_test/` suite, not in unit/widget tests.
