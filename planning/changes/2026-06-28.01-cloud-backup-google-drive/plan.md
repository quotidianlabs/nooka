# Cloud backup/restore via Google Drive — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user connect a Google account and manually back up the whole
database to their own Drive `appDataFolder` (keeping the newest 5 copies) and
restore by replacing all local data from a chosen copy.

**Spec:** [`design.md`](./design.md)

**Branch:** `cloud-backup-google-drive` (already created).

**Commit strategy:** Per-task commits.

## Global constraints

- **Flutter/Dart SDK:** `sdk: ^3.12.2` (see `pubspec.yaml`); do not raise.
- **Backup payload is unchanged:** reuse `encodeBackup` / `decodeBackup` /
  `buildBackup` from `lib/domain/backup_codec.dart` verbatim. No new JSON
  format, no schema/data-model change (`version: 1` stays).
- **Restore is replace-all:** apply through the existing
  `SettingsViewModel.applyImport(BackupData)` — never re-implement the replace
  or the remembered-category reset.
- **Coverage gate stays green:** every new file except the platform Drive leaf
  (`google_drive_backup_io.dart`) must be unit/widget-tested. That leaf is added
  to `coverde.yaml`'s exclude globs, exactly like `platform_backup_io.dart`.
- **Bilingual:** every user-facing string gets an `app_en.arb` **and**
  `app_ru.arb` entry.
- **Codegen is committed:** after touching any `@riverpod`/`@Riverpod` code run
  `dart run build_runner build --delete-conflicting-outputs` and commit the
  regenerated `*.g.dart`.
- **Final gate is `just lint-ci`** (not `just lint`), plus `just coverage` and
  `just check-planning`.

---

### Task 1: Cloud seam + orchestration repository (unit-tested core)

**Files:**
- Create: `lib/data/services/backup/cloud_backup_io.dart`
- Create: `lib/data/repositories/cloud_backup_repository.dart`
- Test: `test/data/cloud_backup_repository_test.dart`

Defines the `CloudBackupIo` seam plus its value types, and a
`CloudBackupRepository` that encodes+uploads+prunes and downloads+decodes — all
through the injectable seam, so it is fully unit-testable with a fake. No
external packages and no provider yet (the provider arrives in Task 2 with the
concrete impl, to keep this task free of the untestable Drive dependency).

- [ ] **Step 1: Create the seam interface + value types**

  `lib/data/services/backup/cloud_backup_io.dart`:

  ```dart
  /// A backup entry in Drive's appDataFolder.
  class CloudBackupRef {
    const CloudBackupRef({
      required this.id,
      required this.name,
      required this.createdAt,
    });
    final String id; // Drive file id
    final String name; // nooka-backup-<stamp>.json
    final DateTime createdAt; // Drive createdTime; for sort/prune/display
  }

  /// Minimal projection of the connected account for the UI.
  class CloudAccount {
    const CloudAccount(this.email);
    final String email;
  }

  /// The platform cloud-storage seam for backups. The default
  /// [GoogleDriveBackupIo] talks to Google Drive's appDataFolder; tests
  /// substitute a fake so [CloudBackupRepository] is exercised without a device.
  abstract interface class CloudBackupIo {
    /// The currently connected account, or null if not connected.
    Future<CloudAccount?> currentAccount();

    /// Interactive sign-in + appdata authorization; null if the user cancels.
    Future<CloudAccount?> connect();

    /// Forgets the connected account / revokes local tokens.
    Future<void> disconnect();

    /// Lists backup files in appDataFolder (any order).
    Future<List<CloudBackupRef>> list();

    /// Uploads [contents] as a new file named [name] in appDataFolder.
    Future<void> upload(String name, String contents);

    /// Downloads the contents of the file with [id].
    Future<String> download(String id);

    /// Deletes the file with [id].
    Future<void> delete(String id);
  }
  ```

- [ ] **Step 2: Write the failing repository test**

  `test/data/cloud_backup_repository_test.dart`:

  ```dart
  import 'package:drift/native.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/repositories/cloud_backup_repository.dart';
  import 'package:nooka/data/repositories/todo_repository.dart';
  import 'package:nooka/data/services/backup/cloud_backup_io.dart';
  import 'package:nooka/data/services/database/database.dart';
  import 'package:nooka/domain/backup_codec.dart';
  import 'package:nooka/domain/clock.dart';
  import 'package:nooka/domain/models/backup_data.dart';

  class FakeCloudBackupIo implements CloudBackupIo {
    FakeCloudBackupIo({this.account});
    CloudAccount? account;
    final Map<String, String> contents = {}; // id -> json
    final List<CloudBackupRef> refs = [];
    final List<String> deleted = [];
    int _seq = 0;
    DateTime uploadCreatedAt = DateTime.utc(2030); // set per upload in tests
    bool throwOnUpload = false;
    bool throwOnList = false;

    @override
    Future<CloudAccount?> currentAccount() async => account;
    @override
    Future<CloudAccount?> connect() async =>
        account ??= const CloudAccount('a@b.com');
    @override
    Future<void> disconnect() async => account = null;
    @override
    Future<List<CloudBackupRef>> list() async {
      if (throwOnList) throw Exception('list boom');
      return List.of(refs);
    }

    @override
    Future<void> upload(String name, String c) async {
      if (throwOnUpload) throw Exception('upload boom');
      final id = 'id${_seq++}';
      contents[id] = c;
      refs.add(CloudBackupRef(id: id, name: name, createdAt: uploadCreatedAt));
    }

    @override
    Future<String> download(String id) async => contents[id]!;
    @override
    Future<void> delete(String id) async {
      deleted.add(id);
      refs.removeWhere((r) => r.id == id);
    }
  }

  void main() {
    late AppDatabase db;
    late TodoRepository todos;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      todos = TodoRepository(db.todoDao);
    });
    tearDown(() => db.close());

    BackupCategory cat(String name) => BackupCategory(
      name: name,
      color: 1,
      emoji: null,
      collapsed: false,
      sortOrder: 0,
      createdAt: DateTime.utc(2026, 6, 1),
      tasks: const [],
    );

    test('backupNow uploads a stamped, decodable file', () async {
      await todos.importReplace([cat('Work')]);
      final io = FakeCloudBackupIo();
      final repo = CloudBackupRepository(
        todos,
        io,
        clock: FixedClock(DateTime.utc(2026, 6, 28, 14, 32, 5)),
      );

      await repo.backupNow();

      expect(io.refs.single.name, 'nooka-backup-2026-06-28T14-32-05.json');
      final decoded = decodeBackup(io.contents[io.refs.single.id]!);
      expect(decoded.categories.single.name, 'Work');
    });

    test('backupNow prunes to the newest 5', () async {
      final io = FakeCloudBackupIo();
      for (var i = 1; i <= 5; i++) {
        io.refs.add(
          CloudBackupRef(
            id: 'old$i',
            name: 'old$i',
            createdAt: DateTime.utc(2026, 1, i),
          ),
        );
        io.contents['old$i'] = '{}';
      }
      io.uploadCreatedAt = DateTime.utc(2026, 2, 1); // newest
      final repo = CloudBackupRepository(todos, io);

      await repo.backupNow();

      expect(io.deleted, ['old1']); // oldest dropped
      expect(io.refs.length, 5);
    });

    test('listBackups returns newest-first', () async {
      final io = FakeCloudBackupIo()
        ..refs.addAll([
          CloudBackupRef(id: 'a', name: 'a', createdAt: DateTime.utc(2026, 1, 1)),
          CloudBackupRef(id: 'b', name: 'b', createdAt: DateTime.utc(2026, 3, 1)),
          CloudBackupRef(id: 'c', name: 'c', createdAt: DateTime.utc(2026, 2, 1)),
        ]);
      final repo = CloudBackupRepository(todos, io);

      final got = await repo.listBackups();

      expect(got.map((r) => r.id).toList(), ['b', 'c', 'a']);
    });

    test('fetch decodes a good file', () async {
      await todos.importReplace([cat('Home')]);
      final io = FakeCloudBackupIo();
      final repo = CloudBackupRepository(
        todos,
        io,
        clock: FixedClock(DateTime.utc(2026, 6, 28, 1, 2, 3)),
      );
      await repo.backupNow();
      final id = io.refs.single.id;

      final data = await repo.fetch(id);

      expect(data.categories.single.name, 'Home');
    });

    test('fetch throws BackupFormatException on a corrupt file', () async {
      final io = FakeCloudBackupIo()
        ..refs.add(
          CloudBackupRef(id: 'x', name: 'x', createdAt: DateTime.utc(2026)),
        )
        ..contents['x'] = 'not json';
      final repo = CloudBackupRepository(todos, io);

      expect(() => repo.fetch('x'), throwsA(isA<BackupFormatException>()));
    });

    test('connect / account / disconnect pass through', () async {
      final io = FakeCloudBackupIo();
      final repo = CloudBackupRepository(todos, io);

      expect(await repo.account(), isNull);
      expect((await repo.connect())!.email, 'a@b.com');
      expect((await repo.account())!.email, 'a@b.com');
      await repo.disconnect();
      expect(await repo.account(), isNull);
    });
  }
  ```

- [ ] **Step 3: Run the test to verify it fails**

  Run: `just test test/data/cloud_backup_repository_test.dart`
  Expected: FAIL — `cloud_backup_repository.dart` / `CloudBackupRepository` not found.

- [ ] **Step 4: Implement the repository**

  `lib/data/repositories/cloud_backup_repository.dart`:

  ```dart
  import '../../domain/backup_codec.dart';
  import '../../domain/clock.dart';
  import '../../domain/models/backup_data.dart';
  import '../services/backup/cloud_backup_io.dart';
  import 'todo_repository.dart';

  /// Orchestrates cloud backup/restore: builds + encodes a snapshot and uploads
  /// it (pruning to the newest [_keep]); lists and downloads + decodes backups.
  /// All platform calls go through the injectable [CloudBackupIo] seam.
  class CloudBackupRepository {
    CloudBackupRepository(
      this._todos,
      this._io, {
      this._clock = const SystemClock(),
    });
    final TodoRepository _todos;
    final CloudBackupIo _io;
    final Clock _clock;

    static const int _keep = 5;

    Future<CloudAccount?> account() => _io.currentAccount();
    Future<CloudAccount?> connect() => _io.connect();
    Future<void> disconnect() => _io.disconnect();

    Future<void> backupNow() async {
      final now = _clock.now();
      final json = encodeBackup(buildBackup(await _todos.exportSnapshot(), now));
      await _io.upload('nooka-backup-${_fileStamp(now)}.json', json);
      await _pruneToNewest(_keep);
    }

    Future<List<CloudBackupRef>> listBackups() async {
      final all = await _io.list();
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
      return all;
    }

    Future<BackupData> fetch(String id) async =>
        decodeBackup(await _io.download(id));

    Future<void> _pruneToNewest(int keep) async {
      final all = await listBackups(); // already newest-first
      for (final r in all.skip(keep)) {
        await _io.delete(r.id);
      }
    }

    String _fileStamp(DateTime d) {
      String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
      return '${p(d.year, 4)}-${p(d.month)}-${p(d.day)}'
          'T${p(d.hour)}-${p(d.minute)}-${p(d.second)}';
    }
  }
  ```

- [ ] **Step 5: Run the test to verify it passes**

  Run: `just test test/data/cloud_backup_repository_test.dart`
  Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

  ```bash
  git add lib/data/services/backup/cloud_backup_io.dart \
          lib/data/repositories/cloud_backup_repository.dart \
          test/data/cloud_backup_repository_test.dart
  git commit -m "feat(backup): cloud seam + orchestration repository"
  ```

---

### Task 2: Google Drive concrete impl + provider wiring (coverage-excluded)

**Files:**
- Create: `lib/data/services/backup/google_drive_backup_io.dart`
- Modify: `pubspec.yaml` (add deps)
- Modify: `coverde.yaml` (exclude the new leaf)
- Modify: `lib/data/repositories/cloud_backup_repository.dart` (add provider)
- Create: `lib/data/repositories/cloud_backup_repository.g.dart` (generated)

Adds the real Drive implementation behind the seam and the keep-alive provider
the view model will read. This leaf is **not unit-tested by design** (platform
auth + network); it is coverage-excluded and verified on a device/emulator.

> **API caution:** `google_sign_in` v7 split authentication from authorization
> (`authenticate()` returns identity only; Drive access comes from
> `authorizationClient.authorizeScopes([...])`). Before finalizing this file,
> confirm the exact current API and the `googleapis`-authenticated-`http.Client`
> wiring against current docs (use the context7 MCP for `google_sign_in` and
> `googleapis`). Do not assume the v6 `signIn()` API. The skeleton below is the
> intended shape, not a guaranteed-current signature.

- [ ] **Step 1: Add dependencies**

  Add to `pubspec.yaml` under `dependencies:` (use the latest versions resolved
  by pub, then pin the caret floor to what resolves):

  ```yaml
  google_sign_in: ^7.2.0
  googleapis: ^14.0.0
  http: ^1.2.0
  ```

  Run: `flutter pub get`
  Expected: resolves without conflict. If the Android build later fails on
  `flutter_plugin_android_lifecycle` AAR metadata (as `file_picker` did — see
  the existing `dependency_overrides` note in `pubspec.yaml`), extend that
  override rather than removing it.

- [ ] **Step 2: Implement the Drive leaf**

  `lib/data/services/backup/google_drive_backup_io.dart` (confirm the
  `google_sign_in` v7 calls against current docs per the caution above):

  ```dart
  import 'dart:convert';

  import 'package:googleapis/drive/v3.dart' as drive;
  import 'package:google_sign_in/google_sign_in.dart';
  import 'package:http/http.dart' as http;

  import 'cloud_backup_io.dart';

  /// Google Drive appDataFolder implementation of [CloudBackupIo].
  /// EXCLUDED from coverage (platform auth + network) — see coverde.yaml.
  class GoogleDriveBackupIo implements CloudBackupIo {
    static const _scope = drive.DriveApi.driveAppdataScope;
    static const _space = 'appDataFolder';

    Future<drive.DriveApi> _api() async {
      // Build an authenticated http.Client via google_sign_in v7's
      // authorizationClient (authorizeScopes([_scope])) and return
      // drive.DriveApi(client). Confirm exact API against current docs.
      throw UnimplementedError('wire google_sign_in v7 auth client');
    }

    @override
    Future<CloudAccount?> currentAccount() async {
      // Return CloudAccount(email) if a lightweight/silent auth succeeds, else null.
      throw UnimplementedError();
    }

    @override
    Future<CloudAccount?> connect() async {
      // Interactive authenticate() + authorizeScopes([_scope]); null on cancel.
      throw UnimplementedError();
    }

    @override
    Future<void> disconnect() async {
      // Sign out / disconnect via GoogleSignIn.
      throw UnimplementedError();
    }

    @override
    Future<List<CloudBackupRef>> list() async {
      final api = await _api();
      final res = await api.files.list(
        spaces: _space,
        $fields: 'files(id,name,createdTime)',
        pageSize: 100,
      );
      return [
        for (final f in res.files ?? const <drive.File>[])
          CloudBackupRef(
            id: f.id!,
            name: f.name ?? '',
            createdAt: f.createdTime ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
      ];
    }

    @override
    Future<void> upload(String name, String contents) async {
      final api = await _api();
      final bytes = utf8.encode(contents);
      await api.files.create(
        drive.File(name: name, parents: [_space]),
        uploadMedia: drive.Media(
          Stream.value(bytes),
          bytes.length,
          contentType: 'application/json',
        ),
      );
    }

    @override
    Future<String> download(String id) async {
      final api = await _api();
      final media =
          await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia)
              as drive.Media;
      final chunks = <int>[];
      await for (final c in media.stream) {
        chunks.addAll(c);
      }
      return utf8.decode(chunks);
    }

    @override
    Future<void> delete(String id) async {
      final api = await _api();
      await api.files.delete(id);
    }
  }
  ```

- [ ] **Step 3: Exclude the leaf from coverage**

  Append to `coverde.yaml` under `exclude-untestable:` (mirror the existing
  `platform_backup_io.dart` entry):

  ```yaml
    - type: skip-by-glob
      glob: "**/data/services/backup/google_drive_backup_io.dart"
  ```

- [ ] **Step 4: Add the provider to the repository file**

  Edit `lib/data/repositories/cloud_backup_repository.dart`: add the riverpod
  import and `part` directive at the top, and the provider at the bottom.

  Add imports + part near the existing imports:

  ```dart
  import 'package:riverpod_annotation/riverpod_annotation.dart';

  import '../services/backup/google_drive_backup_io.dart';
  // ... existing imports ...

  part 'cloud_backup_repository.g.dart';
  ```

  Add at the end of the file:

  ```dart
  @Riverpod(keepAlive: true)
  CloudBackupRepository cloudBackupRepository(Ref ref) => CloudBackupRepository(
    ref.watch(todoRepositoryProvider),
    GoogleDriveBackupIo(),
    clock: ref.watch(clockProvider),
  );
  ```

- [ ] **Step 5: Regenerate code**

  Run: `dart run build_runner build --delete-conflicting-outputs`
  Expected: writes `lib/data/repositories/cloud_backup_repository.g.dart`.

- [ ] **Step 6: Verify analyze + existing tests still pass**

  Run: `just lint-ci`
  Expected: `dart format` clean + `flutter analyze` no issues + `check-planning` OK.
  Run: `just test`
  Expected: all existing + Task 1 tests PASS.

- [ ] **Step 7: Commit**

  ```bash
  git add pubspec.yaml pubspec.lock coverde.yaml \
          lib/data/services/backup/google_drive_backup_io.dart \
          lib/data/repositories/cloud_backup_repository.dart \
          lib/data/repositories/cloud_backup_repository.g.dart
  git commit -m "feat(backup): Google Drive appDataFolder impl + provider"
  ```

---

### Task 3: SettingsViewModel cloud commands (unit-tested)

**Files:**
- Modify: `lib/ui/settings/settings_view_model.dart`
- Modify: `lib/ui/settings/settings_view_model.g.dart` (generated)
- Modify: `test/ui/settings_view_model_test.dart`

Adds the command seam the screen drives. Restore decoding reuses the existing
`ImportPick` sealed type (Ready/Invalid/Failed) so the screen can route a cloud
restore through the same confirm + `applyImport` flow as file import. Failures
are logged and mapped to coarse results — raw errors never cross the seam.

- [ ] **Step 1: Write the failing VM tests**

  Add to `test/ui/settings_view_model_test.dart`. Reuse the file's existing
  `setUp`/container pattern; add a `FakeCloudBackupIo` (copy the one from
  `test/data/cloud_backup_repository_test.dart`) and override
  `cloudBackupRepositoryProvider` with a real `CloudBackupRepository` wired to
  it. Add these tests:

  ```dart
  test('cloudBackupNow returns true and uploads', () async {
    final io = FakeCloudBackupIo();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect(await vm.cloudBackupNow(), isTrue);
    expect(io.refs, isNotEmpty);
  });

  test('cloudBackups returns refs; null on failure', () async {
    final io = FakeCloudBackupIo()
      ..refs.add(
        CloudBackupRef(id: 'a', name: 'a', createdAt: DateTime.utc(2026)),
      );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect((await vm.cloudBackups())!.single.id, 'a');

    io.throwOnList = true;
    expect(await vm.cloudBackups(), isNull);
  });

  test('fetchCloudBackup maps good/corrupt to Ready/Invalid', () async {
    final io = FakeCloudBackupIo()
      ..refs.addAll([
        CloudBackupRef(id: 'good', name: 'g', createdAt: DateTime.utc(2026)),
        CloudBackupRef(id: 'bad', name: 'b', createdAt: DateTime.utc(2026)),
      ])
      ..contents['good'] =
          '{"app":"nooka","version":1,"exportedAt":"2026-06-28T00:00:00.000","categories":[]}'
      ..contents['bad'] = 'not json';
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudBackupRepositoryProvider.overrideWith(
          (ref) => CloudBackupRepository(todos, io),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(settingsViewModelProvider.notifier);

    expect(await vm.fetchCloudBackup('good'), isA<ImportPickReady>());
    expect(await vm.fetchCloudBackup('bad'), isA<ImportPickInvalid>());
  });
  ```

  Add the imports the new tests need at the top of the file:

  ```dart
  import 'package:nooka/data/repositories/cloud_backup_repository.dart';
  import 'package:nooka/data/services/backup/cloud_backup_io.dart';
  ```

- [ ] **Step 2: Run the tests to verify they fail**

  Run: `just test test/ui/settings_view_model_test.dart`
  Expected: FAIL — `cloudBackupNow` / `cloudBackups` / `fetchCloudBackup` not defined.

- [ ] **Step 3: Implement the VM methods**

  In `lib/ui/settings/settings_view_model.dart`: add the import

  ```dart
  import '../../data/repositories/cloud_backup_repository.dart';
  import '../../data/services/backup/cloud_backup_io.dart';
  ```

  add the getter next to the existing ones:

  ```dart
  CloudBackupRepository get _cloud => ref.read(cloudBackupRepositoryProvider);
  ```

  and add the methods to the `SettingsViewModel` class:

  ```dart
  /// The connected account, or null if not connected / on error.
  Future<CloudAccount?> cloudAccount() async {
    try {
      return await _cloud.account();
    } catch (e, st) {
      debugPrint('cloud account failed: $e\n$st');
      return null;
    }
  }

  /// Interactive connect; returns the account, or null if cancelled/failed.
  Future<CloudAccount?> connectCloud() async {
    try {
      return await _cloud.connect();
    } catch (e, st) {
      debugPrint('cloud connect failed: $e\n$st');
      return null;
    }
  }

  Future<void> disconnectCloud() async {
    try {
      await _cloud.disconnect();
    } catch (e, st) {
      debugPrint('cloud disconnect failed: $e\n$st');
    }
  }

  /// Backs up to Drive. Returns false on any failure (logged).
  Future<bool> cloudBackupNow() async {
    try {
      await _cloud.backupNow();
      return true;
    } catch (e, st) {
      debugPrint('cloud backup failed: $e\n$st');
      return false;
    }
  }

  /// Lists backups newest-first; null signals failure (vs empty = none).
  Future<List<CloudBackupRef>?> cloudBackups() async {
    try {
      return await _cloud.listBackups();
    } catch (e, st) {
      debugPrint('cloud list failed: $e\n$st');
      return null;
    }
  }

  /// Downloads + decodes a backup into an [ImportPick] (Ready/Invalid/Failed).
  Future<ImportPick> fetchCloudBackup(String id) async {
    try {
      return ImportPickReady(await _cloud.fetch(id));
    } on BackupFormatException catch (e) {
      debugPrint('cloud restore invalid: ${e.message}');
      return const ImportPickInvalid();
    } catch (e, st) {
      debugPrint('cloud restore failed: $e\n$st');
      return const ImportPickFailed();
    }
  }
  ```

- [ ] **Step 4: Regenerate code**

  Run: `dart run build_runner build --delete-conflicting-outputs`
  Expected: updates `settings_view_model.g.dart` (no error).

- [ ] **Step 5: Run the tests to verify they pass**

  Run: `just test test/ui/settings_view_model_test.dart`
  Expected: PASS (existing + 3 new).

- [ ] **Step 6: Commit**

  ```bash
  git add lib/ui/settings/settings_view_model.dart \
          lib/ui/settings/settings_view_model.g.dart \
          test/ui/settings_view_model_test.dart
  git commit -m "feat(backup): settings view-model cloud commands"
  ```

---

### Task 4: Settings screen cloud section + l10n (widget-tested)

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_ru.arb`
- Modify: `lib/ui/settings/settings_screen.dart`
- Modify: `test/ui/settings_screen_test.dart`

Adds the "Cloud backup (Google Drive)" section: connect/disconnect, "Back up
now", and "Restore from Drive" → list → existing replace-all confirm dialog →
`applyImport`. Connected/loading state lives in a small
`ConsumerStatefulWidget` so the rest of the screen stays a `ConsumerWidget`.

- [ ] **Step 1: Add localized strings**

  Add to `lib/l10n/app_en.arb` (before the closing brace; mind trailing commas):

  ```json
  "cloudBackupSection": "Cloud backup (Google Drive)",
  "cloudConnect": "Connect Google Drive",
  "cloudDisconnect": "Disconnect",
  "cloudConnectedAs": "Connected as {email}",
  "@cloudConnectedAs": { "placeholders": { "email": { "type": "String" } } },
  "cloudBackupNow": "Back up now",
  "cloudBackupDone": "Backed up to Drive.",
  "cloudRestore": "Restore from Drive",
  "cloudNoBackups": "No backups found in Drive.",
  "cloudLatest": "Latest"
  ```

  Add the Russian equivalents to `lib/l10n/app_ru.arb`:

  ```json
  "cloudBackupSection": "Облачная копия (Google Drive)",
  "cloudConnect": "Подключить Google Drive",
  "cloudDisconnect": "Отключить",
  "cloudConnectedAs": "Вход: {email}",
  "@cloudConnectedAs": { "placeholders": { "email": { "type": "String" } } },
  "cloudBackupNow": "Создать копию",
  "cloudBackupDone": "Копия сохранена в Drive.",
  "cloudRestore": "Восстановить из Drive",
  "cloudNoBackups": "Резервные копии в Drive не найдены.",
  "cloudLatest": "Последняя"
  ```

- [ ] **Step 2: Regenerate localizations**

  Run: `flutter gen-l10n`
  Expected: updates `lib/l10n/app_localizations*.dart` with the new getters
  (`cloudBackupSection`, `cloudConnectedAs(String email)`, etc.).

- [ ] **Step 3: Write the failing widget tests**

  Add to `test/ui/settings_screen_test.dart`, reusing the file's existing
  `ProviderScope`/override helpers. Override `cloudBackupRepositoryProvider`
  with a `CloudBackupRepository(todoRepo, FakeCloudBackupIo(...))` (copy the
  fake). Cover:

  ```dart
  testWidgets('shows Connect when not connected', (tester) async {
    // account == null in the fake
    // pump the screen, expect find.text(l10n.cloudConnect) and
    // expect find.text(l10n.cloudBackupNow), findsNothing
  });

  testWidgets('connected: Back up now shows success snackbar', (tester) async {
    // fake account set; tap key('cloud-backup-now-tile');
    // expect SnackBar with l10n.cloudBackupDone; fake.refs not empty
  });

  testWidgets('Restore: empty list shows no-backups snackbar', (tester) async {
    // connected, no refs; tap key('cloud-restore-tile');
    // expect SnackBar with l10n.cloudNoBackups
  });

  testWidgets('Restore: pick + confirm replaces data', (tester) async {
    // connected, one valid backup ref+contents (1 category);
    // tap restore tile -> tap the backup entry -> confirm dialog
    // (key('confirm-import')) -> expect importDone snackbar
  });
  ```

  Fill each test body following the existing widget-test idioms in the file
  (pump, `tester.tap(find.byKey(...))`, `await tester.pumpAndSettle()`,
  `expect(find.text(...), findsOneWidget)`).

- [ ] **Step 4: Run the tests to verify they fail**

  Run: `just test test/ui/settings_screen_test.dart`
  Expected: FAIL — the cloud tiles/keys don't exist yet.

- [ ] **Step 5: Implement the cloud section**

  In `lib/ui/settings/settings_screen.dart`, add a `_CloudBackupSection`
  `ConsumerStatefulWidget` and insert `const _CloudBackupSection()` into the
  `ListView` children after the import tile. The section:
  - loads `vm.cloudAccount()` in `initState`, stores `CloudAccount? _account`
    + a `bool _loading`;
  - **not connected:** `ListTile(key: Key('cloud-connect-tile'),
    title: Text(l10n.cloudConnect))` → `connectCloud()` → on success `setState`
    the account;
  - **connected:** a header `ListTile` showing
    `l10n.cloudConnectedAs(_account!.email)`; a
    `Key('cloud-backup-now-tile')` tile → `cloudBackupNow()` → SnackBar
    `cloudBackupDone` / `actionFailed`; a `Key('cloud-restore-tile')` tile →
    `_restore(...)`; a `Key('cloud-disconnect-tile')` tile → `disconnectCloud()`
    + `setState` clears the account.
  - `_restore`: `final refs = await vm.cloudBackups();` — null → `actionFailed`
    SnackBar; empty → `cloudNoBackups` SnackBar; else show a list (e.g. a
    `showModalBottomSheet` or `SimpleDialog`) of entries labelled by
    `ref.createdAt` local date/time (top one tagged `l10n.cloudLatest`); on
    tap, `final pick = await vm.fetchCloudBackup(ref.id);` then **reuse the
    exact confirm + apply flow from the existing `_import`** (switch on
    `ImportPickReady`/`Invalid`/`Failed`, `importReplaceTitle` /
    `importReplaceBody(count)` dialog with `Key('confirm-import')`, then
    `vm.applyImport(data)` → `importDone(count)` / `actionFailed` SnackBar).

  Guard every post-`await` `BuildContext` use with `if (!context.mounted) return;`
  / `if (!mounted) return;` as the existing handlers do.

- [ ] **Step 6: Run the tests to verify they pass**

  Run: `just test test/ui/settings_screen_test.dart`
  Expected: PASS (existing + 4 new).

- [ ] **Step 7: Commit**

  ```bash
  git add lib/l10n/app_en.arb lib/l10n/app_ru.arb \
          lib/l10n/app_localizations*.dart \
          lib/ui/settings/settings_screen.dart \
          test/ui/settings_screen_test.dart
  git commit -m "feat(backup): settings cloud backup/restore UI"
  ```

---

### Task 5: Architecture promotion + final gate

**Files:**
- Modify: `architecture/backup-io.md`
- Modify: `architecture/error-handling.md`
- Modify: `architecture/i18n-theming.md`
- Modify: `planning/changes/2026-06-28.01-cloud-backup-google-drive/design.md` (finalize `summary`)

Promotes the realized behavior into the living capability docs (same PR) and
runs the full gate.

- [ ] **Step 1: Extend `architecture/backup-io.md`**

  Add a "Cloud backup (Google Drive)" section documenting: the `CloudBackupIo`
  seam and its `GoogleDriveBackupIo` impl (appDataFolder, `drive.appdata`
  scope, `google_sign_in` v7 auth/authorization split); `CloudBackupRepository`
  (encode→upload→prune-to-5, list newest-first, download→decode); that restore
  reuses `applyImport` (replace-all + remembered-category reset) and the
  confirm-dialog invariant; and that `google_drive_backup_io.dart` is
  coverage-excluded like `platform_backup_io.dart`. Note automatic backup as a
  documented future phase.

- [ ] **Step 2: Touch `architecture/error-handling.md`**

  Add the new cloud SnackBar mappings (success → `cloudBackupDone` /
  `importDone`; empty → `cloudNoBackups`; corrupt file → `importInvalidFile`;
  any other failure → `actionFailed`; cancelled connect → silent).

- [ ] **Step 3: Touch `architecture/i18n-theming.md`**

  Note the new EN/RU keys (`cloudBackupSection`, `cloudConnect`,
  `cloudDisconnect`, `cloudConnectedAs`, `cloudBackupNow`, `cloudBackupDone`,
  `cloudRestore`, `cloudNoBackups`, `cloudLatest`).

- [ ] **Step 4: Finalize the bundle summary**

  Confirm `design.md`'s `summary:` states the realized result (it already
  describes the shipped behavior — adjust only if scope changed during build).

- [ ] **Step 5: Run the full gate**

  Run: `just lint-ci`  → expected: format clean, analyze clean, check-planning OK.
  Run: `just test`     → expected: all PASS.
  Run: `just coverage` → expected: gate green (the Drive leaf is excluded).

- [ ] **Step 6: Commit**

  ```bash
  git add architecture/backup-io.md architecture/error-handling.md \
          architecture/i18n-theming.md \
          planning/changes/2026-06-28.01-cloud-backup-google-drive/design.md
  git commit -m "docs(architecture): promote cloud backup capability"
  ```

---

## Operations checklist (out-of-repo, maintainer — prerequisite to a working build)

These are not code tasks but must be done for the Drive path to function on
device (the unit/widget suite passes without them):

- [ ] Create an OAuth client in Google Cloud Console: Android (package name +
  release & debug SHA-1) and iOS (bundle id); configure the consent screen.
- [ ] Add the `.../auth/drive.appdata` scope (non-sensitive — should avoid full
  OAuth verification, but configure test users on the consent screen).
- [ ] iOS: add the reversed-client-id URL scheme to `ios/Runner/Info.plist` per
  `google_sign_in` iOS setup.
- [ ] Manual/emulator verify: connect → back up now → confirm a file appears →
  restore → data replaced (this exercises the coverage-excluded leaf).

## Self-review notes

- **Spec coverage:** seam+repo (Task 1) ✓; Drive impl + retention-to-5 +
  provider (Task 2) ✓; VM commands incl. restore-via-`applyImport` reuse
  (Task 3) ✓; UI section + confirm-dialog reuse + bilingual strings (Task 4) ✓;
  coverage exclusion (Task 2 step 3) ✓; architecture promotion (Task 5) ✓;
  OAuth ops prerequisite ✓; phase-2 documented in spec, not built ✓.
- **Type consistency:** `CloudBackupIo`, `CloudBackupRef{id,name,createdAt}`,
  `CloudAccount{email}`, `CloudBackupRepository.{account,connect,disconnect,
  backupNow,listBackups,fetch}`, VM `{cloudAccount,connectCloud,disconnectCloud,
  cloudBackupNow,cloudBackups,fetchCloudBackup}`, provider
  `cloudBackupRepositoryProvider` — used identically across tasks.
- **Deferred:** multi-device sync, sync-ready schema, automatic backup, iCloud,
  encryption — all out of scope per `design.md` Non-goals.
