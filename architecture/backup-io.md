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
excluded from the line-coverage gate via a `skip-by-glob` entry in
`coverde.yaml` (the same mechanism used for `connection.dart`). All
orchestration logic lives in `BackupRepository`, which is fully tested through
the injected `BackupIo` interface using a `FakeBackupIo` test double.

## Integration test note

End-to-end validation of the share sheet and file picker (the excluded
`PlatformBackupIo` code) requires a running emulator and belongs in the
`integration_test/` suite, not in unit/widget tests.

---

## Cloud backup (Google Drive)

Nooka also supports manual cloud backup and restore to the user's own Google
Drive, shipping a new "Cloud backup (Google Drive)" section in Settings.

### CloudBackupIo seam

`lib/data/services/backup/cloud_backup_io.dart` defines the cloud platform
seam, mirroring the `BackupIo` pattern:

```
abstract interface class CloudBackupIo
  currentAccount() → CloudAccount?     // null = not connected
  connect()        → CloudAccount?     // interactive sign-in + authorize scope; null if cancelled
  disconnect()
  list()           → List<CloudBackupRef>   // appDataFolder files, unordered
  upload(name, contents)
  download(id)     → String
  delete(id)
```

Value types: `CloudBackupRef{id, name, createdAt}` (a Drive file entry) and
`CloudAccount{email}` (minimal projection for the UI).

`list()` returns raw appDataFolder entries in whatever order Drive delivers
them. `listBackups()` in `CloudBackupRepository` is what filters to
`nooka-backup-*` entries and sorts them newest-first before returning them to
callers.

### GoogleDriveBackupIo (concrete impl — coverage-excluded)

`lib/data/services/backup/google_drive_backup_io.dart` implements
`CloudBackupIo` using `google_sign_in` v7 and `googleapis` Drive v3.

`google_sign_in` v7 splits authentication from authorization. `connect()`
calls `GoogleSignIn.instance.authenticate()` for identity, then
`account.authorizationClient.authorizeScopes([DriveApi.driveAppdataScope])`
to obtain a Drive token. Subsequent API calls resolve the current account via
`attemptLightweightAuthentication()` (silent, no UI) and fetch a token via
`authorizationForScopes`, then build an authenticated `http.Client` for the
`googleapis` Drive client. All Drive operations set `spaces: 'appDataFolder'`
and `parents: ['appDataFolder']` so files are stored in the hidden per-app
folder, invisible to the user and other apps, reached with the non-sensitive
`drive.appdata` scope.

`google_drive_backup_io.dart` is excluded from the line-coverage gate via a
`skip-by-glob` entry in `coverde.yaml`, exactly like `platform_backup_io.dart`
and `connection.dart` — it is platform glue that cannot run under
`flutter test`. All orchestration logic above it is fully covered through the
injected `CloudBackupIo` interface using a `FakeCloudBackupIo` test double.

### CloudBackupRepository (orchestration — fully tested via fake)

`lib/data/repositories/cloud_backup_repository.dart` orchestrates cloud I/O
against the seam:

- `backupNow()`: reads `TodoRepository.exportSnapshot()`, encodes with
  `buildBackup` / `encodeBackup` (reusing the existing codec), uploads as
  `nooka-backup-<YYYY-MM-DDTHH-MM-SS>.json`, then prunes so only the newest
  **5** files remain (deletes oldest by `createdAt`).
- `listBackups()`: returns entries sorted newest-first.
- `fetch(id)`: downloads and decodes with `decodeBackup` (may throw
  `BackupFormatException` for a corrupt cloud file — same exception the local
  import path already handles).
- `account()`, `connect()`, `disconnect()` delegate to the seam directly.

A keep-alive `cloudBackupRepositoryProvider` wires `TodoRepository` +
`GoogleDriveBackupIo` + the injectable `Clock`.

### Restore and confirm-dialog invariant

**Applying** a cloud restore is not re-implemented: after `fetch(id)` returns
`BackupData`, the screen calls the existing `SettingsViewModel.applyImport(data)`,
which does `TodoRepository.importReplace` + `RememberedCategory.forget()`
atomically — identical to the local file-import path. The same replace-all
confirm `AlertDialog` (`importReplaceTitle` / `importReplaceBody(count)`,
`Key('confirm-import')`) guards the destructive step, preserving the
replace-all + confirm-dialog invariant and the remembered-category reset
described above.

### Integration test note

End-to-end validation of Drive auth, upload, and restore requires a real device
or emulator with a Google account. It belongs in `integration_test/`, not the
headless unit/widget suite, for the same reasons as `PlatformBackupIo`.

### Phase-2 (documented, not built)

Automatic backup (opt-in toggle, triggered on app-backgrounded, throttled to at
most once per N hours, with silent-failure handling) is the documented next phase.
It will call the same `cloudBackupNow()` path and rely on the 5-file rolling
retention as its safety net. Multi-device sync is also deferred — the current
design treats each install as an independent backup source; conflict resolution
across devices is out of scope until a later phase.
