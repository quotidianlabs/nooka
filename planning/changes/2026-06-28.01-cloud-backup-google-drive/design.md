---
summary: Manual whole-DB backup and restore to the user's own Google Drive (hidden appDataFolder), reusing the existing JSON codec and replace-all import behind a coverage-isolated Drive seam; automatic backup and multi-device sync deferred.
---

# Design: Cloud backup and restore via Google Drive

## Summary

Add zero-backend **cloud backup and restore** of the whole to-do database to
the user's own Google Drive. A new "Cloud backup (Google Drive)" section in
Settings lets the user **connect** a Google account, **back up now** (encode the
DB to the existing backup JSON and upload it to Drive's hidden
`appDataFolder`, keeping the newest 5 timestamped copies), and **restore** by
picking one of those copies and replacing all local data. The work reuses the
proven Backup I/O seam pattern: the platform-bound Drive calls
(`google_sign_in` v7 + `googleapis` Drive v3) are confined to one
coverage-excluded leaf (`GoogleDriveBackupIo`), while a fully unit-tested
`CloudBackupRepository` orchestrates encode/upload/prune and download/decode.
Restore reuses the existing `decodeBackup` + `importReplace` +
`RememberedCategory.forget()` path verbatim, so the destructive replace-all,
its confirm-dialog invariant, and the remembered-category reset all carry over
unchanged. The data model and backup format (`version: 1`) are **not** touched.

## Motivation

nooka is local-first with no cloud presence: today the only backup is a manual
share-sheet file export (`2026-06-25.02-export-import`). That protects a user
who remembers to export and stash the file somewhere safe, but a lost, reset, or
upgraded device with no recent manual export loses everything. "Move to a new
phone and get my lists back" is the most common real-world recovery need and the
file export does not serve it smoothly (the user must locate and re-pick a file
they may never have saved).

Google Drive's per-app `appDataFolder` gives us a backup destination that costs
the maintainer nothing, runs no server, and keeps the privacy story intact: the
data lives in the **user's own** Drive, in a hidden folder invisible to the user
and to other apps, reached with the **non-sensitive** `drive.appdata` scope
(which should avoid Google's full OAuth verification review). It reuses the
existing JSON codec almost as-is. This is the highest effort-to-value step
toward "never lose your data" while staying true to "your data, on your device."

## Non-goals

- **Automatic backup.** Manual-triggered only in this change. Automatic
  (lifecycle/scheduled, throttled, opt-in) is the explicit **phase-2** below.
- **Multi-device sync.** No two-way merge, change tracking, or conflict
  resolution. Restore stays replace-all. (Decision A, deferred.)
- **Sync-ready data model.** No UUIDs, per-row `updatedAt`, or tombstones; the
  data model and `version: 1` backup format are unchanged. The format's
  `version` field remains the clean upgrade path if sync ever lands.
- **iCloud / other clouds.** Google Drive is the sole cloud target. (The
  existing manual file export remains the no-account, any-destination fallback.)
- **Encryption of the backup blob.** Out of scope; the file is the same
  plaintext JSON as the manual export, protected by the user's Google account.
- **Selective backup, merge restore, CSV.** Whole DB, replace-all, JSON — same
  as the existing export/import.

## Design

### 1. What goes to Drive

The uploaded object is **byte-for-byte the existing backup JSON** produced by
`encodeBackup(buildBackup(...))` — `app:"nooka"`, `version:1`, `exportedAt`,
nested `categories`/`tasks`, row ids not serialized. No new format, no schema
change. Each backup is a separate Drive file named
`nooka-backup-<ISO8601>.json` (e.g. `nooka-backup-2026-06-28T14-32-05.json`,
colons replaced for filename safety), stored in the `appDataFolder` space.

**Retention:** after each successful upload, prune so only the newest **5**
files remain (delete the oldest by `createdTime`). This rolling set is the
safety net that makes phase-2 automatic backup safe to enable later: an
accidental wipe followed by a backup cannot destroy every good copy.

### 2. The `CloudBackupIo` seam (interface — testable)

A new platform seam mirrors the existing `BackupIo`, exposing only Drive
primitives — no encode/decode, no DB:

```dart
// lib/data/services/backup/cloud_backup_io.dart  (interface — testable)
class CloudBackupRef {            // an entry in appDataFolder
  final String id;               // Drive file id
  final String name;             // nooka-backup-<ISO>.json
  final DateTime createdAt;      // Drive createdTime, for sort/prune/display
}

abstract interface class CloudBackupIo {
  Future<CloudAccount?> currentAccount();        // null = not connected
  Future<CloudAccount?> connect();               // interactive sign-in + authorize scope; null if cancelled
  Future<void> disconnect();
  Future<List<CloudBackupRef>> list();           // appDataFolder, any order
  Future<void> upload(String name, String contents);
  Future<String> download(String id);            // -> file contents
  Future<void> delete(String id);
}

class CloudAccount {             // minimal projection for the UI
  final String email;
}
```

### 3. `GoogleDriveBackupIo` (concrete impl — coverage-excluded)

```dart
// lib/data/services/backup/google_drive_backup_io.dart  (EXCLUDED from coverage)
class GoogleDriveBackupIo implements CloudBackupIo { /* google_sign_in v7 +
   googleapis Drive v3, space: 'appDataFolder' */ }
```

Auth uses **`google_sign_in` v7**, which split authentication from
authorization: `connect()` calls `authenticate()` for identity, then
`authorizationClient.authorizeScopes([drive.DriveApi.driveAppdataScope])` to
obtain the Drive token, and builds an authenticated `http.Client` for the
`googleapis` Drive client. All Drive calls set `spaces: 'appDataFolder'` and
`parents: ['appDataFolder']` so files never touch the user's visible Drive.

This leaf is added to `coverde.yaml`'s exclude glob exactly like
`platform_backup_io.dart` and `connection.dart` — it is platform glue that
cannot run under `flutter test`. All logic above it stays covered via a fake.

### 4. `CloudBackupRepository` (orchestration — fully tested via fake)

```dart
// lib/data/repositories/cloud_backup_repository.dart
class CloudBackupRepository {
  CloudBackupRepository(this._todos, this._io, {Clock clock = const SystemClock()});

  Future<CloudAccount?> account();      // -> _io.currentAccount()
  Future<CloudAccount?> connect();      // -> _io.connect()
  Future<void> disconnect();            // -> _io.disconnect()

  Future<void> backupNow() async {      // encode -> upload -> prune to 5
    final now = _clock.now();
    final json = encodeBackup(buildBackup(await _todos.exportSnapshot(), now));
    await _io.upload('nooka-backup-${_fileStamp(now)}.json', json);
    await _pruneToNewest(5);
  }

  Future<List<CloudBackupRef>> listBackups();        // sorted newest-first
  Future<BackupData> fetch(String id) async =>        // download + decode (may throw)
      decodeBackup(await _io.download(id));
}
```

`backupNow` reuses `buildBackup`/`encodeBackup` and the injectable `Clock`
(clock-seam, `2026-06-24.02`) so filenames and `exportedAt` are deterministic in
tests. `fetch` reuses `decodeBackup`, so an alien/corrupt cloud file throws the
same `BackupFormatException` the file-import path already handles. **Applying** a
restore is *not* re-implemented here: the screen calls the existing
`SettingsViewModel.applyImport(data)`, which already does
`TodoRepository.importReplace` + `RememberedCategory.forget()` atomically.

### 5. `SettingsViewModel` additions

Extend the existing `SettingsViewModel` (added by `2026-06-25.02`) with the
cloud command seam; restore deliberately routes its apply step through the
existing `applyImport`:

```dart
Future<CloudAccount?> cloudAccount();
Future<CloudAccount?> connectCloud();
Future<void> disconnectCloud();
Future<void> cloudBackupNow();
Future<List<CloudBackupRef>> cloudBackups();
Future<BackupData> fetchCloudBackup(String id);   // then -> applyImport(data)
```

A keep-alive `cloudBackupRepositoryProvider` wires `TodoRepository` +
`GoogleDriveBackupIo` + `clock`.

### 6. `SettingsScreen` — the "Cloud backup (Google Drive)" section

- **Not connected:** one tile "Connect Google Drive" → `connectCloud()`.
- **Connected (shows account email):**
  - "Back up now" → `cloudBackupNow()` → success/failure SnackBar.
  - "Restore from Drive" → `cloudBackups()`; empty → "no backups" SnackBar;
    otherwise a list of entries labelled by local date/time (newest first,
    "Latest" marker on the top one) → on tap, `fetchCloudBackup(id)` → the
    **existing replace-all confirm `AlertDialog`** (`importReplaceTitle` /
    `importReplaceBody(count)`, reused verbatim) → `applyImport(data)` →
    `importDone(count)` SnackBar.
  - "Disconnect" → `disconnectCloud()`.

The existing "Export data" / "Import data" tiles are untouched.

### 7. Error & result surfacing (bilingual EN + RU)

Per `architecture/error-handling.md`, raw errors never reach the UI as text; the
screen maps outcomes to localized SnackBars in one place. Reused keys:
`actionFailed` (network/Drive/auth failure), `importInvalidFile`
(`BackupFormatException` from a corrupt cloud file), `importDone(count)`
(restore success). New EN+RU keys: `cloudBackupSection`, `cloudConnect`,
`cloudDisconnect`, `cloudConnectedAs(email)`, `cloudBackupNow`,
`cloudBackupDone`, `cloudRestore`, `cloudNoBackups`, `cloudLatest`. A cancelled
sign-in (`connect()` → null) is silent, mirroring the cancelled file-pick.

## Operations

One-time, out-of-repo, by the maintainer (prerequisite to shipping):

- Create an **OAuth client** in Google Cloud Console for Android (package name +
  release & debug SHA-1) and iOS (bundle id); configure the consent screen.
- Add the `.../auth/drive.appdata` scope. It is **non-sensitive**, so this
  should not trigger Google's full OAuth verification/security-assessment, but
  the consent screen and test users must be configured.
- iOS: add the reversed-client-id URL scheme to `Info.plist` per
  `google_sign_in` iOS setup.

These are documented as a setup checklist in the plan; no repo infra/DNS.

## Out of scope

See Non-goals. Notably deferred: automatic backup (phase-2), multi-device sync,
sync-ready schema (UUIDs/updatedAt/tombstones), iCloud, encryption.

### Phase-2 (documented, not built here)

Automatic backup as an **opt-in** Settings toggle, triggered on a cheap signal
(app moving to background) and **throttled to at most once per N hours**, with
silent-failure handling and connectivity checks. It builds directly on this
change: it calls the same `cloudBackupNow()` and relies on the 5-file rolling
retention as its safety net. Sequenced after the manual path is proven.

## Testing

Everything except the excluded Drive leaf is unit/widget-tested, preserving the
coverage gate:

- `test/data/cloud_backup_repository_test.dart` — orchestration via a
  `FakeCloudBackupIo`: `backupNow` hands the correct filename + encoded
  contents to `upload` and prunes to the newest 5 (oldest deleted);
  `listBackups` returns newest-first; `fetch` decodes a good file and propagates
  `BackupFormatException` on a corrupt one; connect/disconnect/account
  pass-through; failures from the seam surface as thrown errors.
- `test/ui/settings_view_model_test.dart` — extended: cloud command methods;
  restore routes through `applyImport` (replace + remembered-category reset).
- `test/ui/settings_screen_test.dart` — extended: not-connected vs connected
  rendering; "Back up now" success/failure SnackBars; "Restore" list, empty-state
  SnackBar, confirm dialog → replace → `importDone` SnackBar; invalid-file
  SnackBar; cancelled connect is silent.

`google_drive_backup_io.dart` is coverage-excluded (added to `coverde.yaml`).
Its real auth + Drive round trip cannot run headlessly; it is **manual /
emulator verify** with a real Google account, noted alongside the existing
`PlatformBackupIo` integration note — not added to the headless unit/widget
suite. Final gate: `just lint-ci` clean, `just coverage` green.

Architecture promotion (same PR): extend `architecture/backup-io.md` with the
cloud-backup section (seam, repository, retention, restore-reuse, coverage
exclusion); minor touches to `architecture/error-handling.md` (new cloud
SnackBar mappings) and `architecture/i18n-theming.md` (new keys).

## Risk

- **Coverage gate breakage (likely x medium).** Drive plugins are not
  unit-testable. Mitigation: the `CloudBackupIo` seam confines every untestable
  call to one leaf on the `coverde.yaml` exclude list (the established
  `connection.dart` / `platform_backup_io.dart` pattern); all orchestration is
  covered via a fake.
- **OAuth setup / `google_sign_in` v7 friction (medium x medium).** v7's
  auth/authorization split and the Cloud Console client setup are easy to
  misconfigure (SHA-1, bundle id, URL scheme). Mitigation: a setup checklist in
  the plan; verify the v7 authorize-scope API and the
  `googleapis`-authenticated-client wiring against current package docs during
  implementation (do not assume the v6 API).
- **Destructive restore data loss (low x high).** Restore is replace-all.
  Mitigation: the existing confirm dialog and atomic `importReplace` carry over
  unchanged; the 5-file rolling retention means a bad restore source can be
  swapped for an older good one.
- **Drive scope verification surprise (low x medium).** If Google later treats
  `drive.appdata` as needing verification for this app, distribution could be
  gated. Mitigation: scope is currently non-sensitive; the manual file export
  remains a fully functional fallback regardless.
- **Android plugin/Gradle compatibility (medium x low).** New Google plugins may
  perturb the Android build (cf. the existing `flutter_plugin_android_lifecycle`
  override). Mitigation: verify the build during implementation; add overrides
  only if required.
