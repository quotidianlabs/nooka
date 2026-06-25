# JSON Export/Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user export the whole to-do database to a JSON file via the OS share sheet and import such a file to replace all data, with archive state round-tripping losslessly.

**Architecture:** A pure `backup_codec` (encode/decode/build) in `domain/`, a `TodoDao`/`TodoRepository` pair extended with a one-shot full read + a transactional replace-all, a `BackupRepository` that orchestrates file I/O behind an injectable `BackupIo` interface (its only platform-bound implementation isolated and coverage-excluded), and a `@riverpod` `SettingsViewModel` the `SettingsScreen` drives.

**Tech Stack:** Flutter, Drift (SQLite), Riverpod (codegen), `share_plus`, `file_picker`, `path_provider`. Tests: `flutter_test` + in-memory Drift.

## Global Constraints

- **Coverage gate is 100%** (`coverde check ... 100`). Every new line must be unit/widget-tested **except** the single platform-I/O leaf, which goes on the `coverde.yaml` exclude list. Verify with `just lint-ci` then `just test`.
- **Bilingual:** every user-facing string is an l10n key added to **both** `lib/l10n/app_en.arb` and `lib/l10n/app_ru.arb`. No hardcoded UI text.
- **Imports at module level**, never inside function bodies.
- **Annotate test function arguments** (e.g. `WidgetTester tester`).
- **Codegen:** after touching any `@riverpod`/Drift code, run `dart run build_runner build --delete-conflicting-outputs`. Generated `*.g.dart` is committed.
- **Backup format:** `app == "nooka"`, `version == 1`. Row ids are never exported; tasks nest under their category; timestamps are ISO-8601; tasks emitted in `sortOrder`.
- **Pre-commit gate is `just lint-ci`** (check-only), not `just lint` (which rewrites files in place). Format with `just lint` while iterating; verify a clean committed tree with `just lint-ci` last.
- **Final architecture promotion rides in this PR:** new `architecture/backup-io.md`, and the `planning/deferred.md` entry removed.

---

### Task 1: Backup domain models + pure codec

**Files:**
- Create: `lib/domain/models/backup_data.dart`
- Create: `lib/domain/backup_codec.dart`
- Test: `test/domain/backup_codec_test.dart`

**Interfaces:**
- Produces: `BackupTask`, `BackupCategory`, `BackupData`, `BackupFormatException` (in `backup_data.dart`); `String encodeBackup(BackupData)`, `BackupData decodeBackup(String)`, `BackupData buildBackup(List<CategoryWithTasks>, DateTime)` (in `backup_codec.dart`).
- Consumes: `CategoryWithTasks` from `lib/domain/models/category_with_tasks.dart` (already carries active + archived tasks).

- [ ] **Step 1: Write the models**

Create `lib/domain/models/backup_data.dart`:

```dart
/// A single task inside a backup. Row ids are never serialized; the parent
/// link is implicit in [BackupCategory.tasks].
class BackupTask {
  const BackupTask({
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.archivedAt,
  });
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime? archivedAt; // null = active
}

/// A category and its tasks inside a backup.
class BackupCategory {
  const BackupCategory({
    required this.name,
    required this.color,
    required this.emoji,
    required this.collapsed,
    required this.sortOrder,
    required this.createdAt,
    required this.tasks,
  });
  final String name;
  final int color;
  final String? emoji;
  final bool collapsed;
  final int sortOrder;
  final DateTime createdAt;
  final List<BackupTask> tasks;
}

/// A whole-database backup: format [version], when it was [exportedAt], and the
/// ordered [categories].
class BackupData {
  const BackupData({
    required this.version,
    required this.exportedAt,
    required this.categories,
  });
  final int version;
  final DateTime exportedAt;
  final List<BackupCategory> categories;
}

/// Thrown by `decodeBackup` when a file is not a valid v1 Nooka backup. The
/// [message] is English, for logs and tests; the UI shows a localized message.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}
```

- [ ] **Step 2: Write the failing codec test**

Create `test/domain/backup_codec_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/domain/backup_codec.dart';
import 'package:nooka/domain/models/backup_data.dart';

void main() {
  BackupData sample() => BackupData(
    version: 1,
    exportedAt: DateTime.utc(2026, 6, 25, 9, 30),
    categories: [
      BackupCategory(
        name: 'Work',
        color: 4278228616,
        emoji: '💼',
        collapsed: false,
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 6, 1, 8),
        tasks: [
          BackupTask(
            name: 'Ship it',
            sortOrder: 0,
            createdAt: DateTime.utc(2026, 6, 2, 8),
            archivedAt: null,
          ),
          BackupTask(
            name: 'Old thing',
            sortOrder: 1,
            createdAt: DateTime.utc(2026, 6, 1, 8),
            archivedAt: DateTime.utc(2026, 6, 10, 12),
          ),
        ],
      ),
    ],
  );

  test('round-trips through encode/decode', () {
    final decoded = decodeBackup(encodeBackup(sample()));
    expect(decoded.version, 1);
    expect(decoded.categories.single.name, 'Work');
    expect(decoded.categories.single.emoji, '💼');
    final tasks = decoded.categories.single.tasks;
    expect(tasks[0].archivedAt, isNull);
    expect(tasks[1].archivedAt, DateTime.utc(2026, 6, 10, 12));
  });

  test('encodes an empty database', () {
    final json = encodeBackup(
      BackupData(version: 1, exportedAt: DateTime.utc(2026), categories: []),
    );
    expect(decodeBackup(json).categories, isEmpty);
  });

  group('decode rejects', () {
    void rejects(String source) =>
        expect(() => decodeBackup(source), throwsA(isA<BackupFormatException>()));

    test('non-JSON', () => rejects('not json'));
    test('non-object root', () => rejects('[1,2,3]'));
    test('wrong app', () => rejects('{"app":"habbits","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[]}'));
    test('wrong version', () => rejects('{"app":"nooka","version":2,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[]}'));
    test('missing categories', () => rejects('{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000"}'));
    test('category missing name', () => rejects('{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"color":1,'
        '"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[]}]}'));
    test('task with bad archivedAt', () => rejects('{"app":"nooka","version":1,'
        '"exportedAt":"2026-06-25T00:00:00.000","categories":[{"name":"C",'
        '"color":1,"emoji":null,"collapsed":false,"sortOrder":0,'
        '"createdAt":"2026-06-25T00:00:00.000","tasks":[{"name":"T",'
        '"sortOrder":0,"createdAt":"2026-06-25T00:00:00.000",'
        '"archivedAt":"not-a-date"}]}]}'));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/domain/backup_codec_test.dart`
Expected: FAIL — `backup_codec.dart` does not exist / functions undefined.

- [ ] **Step 4: Implement the codec**

Create `lib/domain/backup_codec.dart`:

```dart
import 'dart:convert';

import 'models/backup_data.dart';
import 'models/category_with_tasks.dart';

const String _appMarker = 'nooka';
const int _currentVersion = 1;

/// Serializes [data] to pretty-printed JSON.
String encodeBackup(BackupData data) {
  final map = <String, Object?>{
    'app': _appMarker,
    'version': data.version,
    'exportedAt': data.exportedAt.toIso8601String(),
    'categories': [
      for (final c in data.categories)
        {
          'name': c.name,
          'color': c.color,
          'emoji': c.emoji,
          'collapsed': c.collapsed,
          'sortOrder': c.sortOrder,
          'createdAt': c.createdAt.toIso8601String(),
          'tasks': [
            for (final t in c.tasks)
              {
                'name': t.name,
                'sortOrder': t.sortOrder,
                'createdAt': t.createdAt.toIso8601String(),
                'archivedAt': t.archivedAt?.toIso8601String(),
              },
          ],
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

/// Parses and strictly validates a Nooka v1 backup. Throws
/// [BackupFormatException] on the first violation, before returning anything.
BackupData decodeBackup(String source) {
  final Object? root;
  try {
    root = jsonDecode(source);
  } catch (_) {
    throw const BackupFormatException('Not valid JSON.');
  }
  if (root is! Map<String, dynamic>) {
    throw const BackupFormatException('Root is not an object.');
  }
  if (root['app'] != _appMarker) {
    throw const BackupFormatException('Not a Nooka backup.');
  }
  final version = root['version'];
  if (version is! int || version != _currentVersion) {
    throw BackupFormatException('Unsupported version: ${root['version']}.');
  }
  final exportedAt = _date(root['exportedAt'], 'exportedAt');
  final categoriesRaw = root['categories'];
  if (categoriesRaw is! List) {
    throw const BackupFormatException('Missing categories list.');
  }
  return BackupData(
    version: version,
    exportedAt: exportedAt,
    categories: [for (final c in categoriesRaw) _category(c)],
  );
}

BackupCategory _category(Object? item) {
  if (item is! Map<String, dynamic>) {
    throw const BackupFormatException('Invalid category entry.');
  }
  final name = item['name'];
  if (name is! String || name.isEmpty) {
    throw const BackupFormatException('A category is missing its name.');
  }
  final color = item['color'];
  if (color is! int) {
    throw BackupFormatException('Category "$name" has an invalid color.');
  }
  final emoji = item['emoji'];
  if (emoji != null && emoji is! String) {
    throw BackupFormatException('Category "$name" has an invalid emoji.');
  }
  final collapsed = item['collapsed'];
  if (collapsed is! bool) {
    throw BackupFormatException('Category "$name" has an invalid collapsed.');
  }
  final sortOrder = item['sortOrder'];
  if (sortOrder is! int) {
    throw BackupFormatException('Category "$name" has an invalid sortOrder.');
  }
  final tasksRaw = item['tasks'];
  if (tasksRaw is! List) {
    throw BackupFormatException('Category "$name" has an invalid tasks list.');
  }
  return BackupCategory(
    name: name,
    color: color,
    emoji: emoji as String?,
    collapsed: collapsed,
    sortOrder: sortOrder,
    createdAt: _date(item['createdAt'], 'category "$name" createdAt'),
    tasks: [for (final t in tasksRaw) _task(t, name)],
  );
}

BackupTask _task(Object? item, String categoryName) {
  if (item is! Map<String, dynamic>) {
    throw BackupFormatException('Category "$categoryName" has an invalid task.');
  }
  final name = item['name'];
  if (name is! String || name.isEmpty) {
    throw BackupFormatException('A task in "$categoryName" is missing its name.');
  }
  final sortOrder = item['sortOrder'];
  if (sortOrder is! int) {
    throw BackupFormatException('Task "$name" has an invalid sortOrder.');
  }
  final archivedRaw = item['archivedAt'];
  final archivedAt = archivedRaw == null
      ? null
      : _date(archivedRaw, 'task "$name" archivedAt');
  return BackupTask(
    name: name,
    sortOrder: sortOrder,
    createdAt: _date(item['createdAt'], 'task "$name" createdAt'),
    archivedAt: archivedAt,
  );
}

DateTime _date(Object? value, String field) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) {
    throw BackupFormatException('Invalid $field.');
  }
  return parsed;
}

/// Builds a [BackupData] snapshot from DB rows; [now] stamps `exportedAt`.
/// Tasks are emitted in `sortOrder` for stable diffs.
BackupData buildBackup(List<CategoryWithTasks> rows, DateTime now) {
  return BackupData(
    version: _currentVersion,
    exportedAt: now,
    categories: [
      for (final r in rows)
        BackupCategory(
          name: r.category.name,
          color: r.category.color,
          emoji: r.category.emoji,
          collapsed: r.category.collapsed,
          sortOrder: r.category.sortOrder,
          createdAt: r.category.createdAt,
          tasks: [
            for (final t in [...r.tasks]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
              BackupTask(
                name: t.name,
                sortOrder: t.sortOrder,
                createdAt: t.createdAt,
                archivedAt: t.archivedAt,
              ),
          ],
        ),
    ],
  );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/domain/backup_codec_test.dart`
Expected: PASS (all round-trip + reject cases).

- [ ] **Step 6: Commit**

```bash
git add lib/domain/models/backup_data.dart lib/domain/backup_codec.dart test/domain/backup_codec_test.dart
git commit -m "feat(backup): pure JSON codec + domain models for export/import"
```

---

### Task 2: DAO — `exportSnapshot` + `importReplace`

**Files:**
- Modify: `lib/data/services/database/todo_dao.dart`
- Test: `test/data/backup_db_test.dart`

**Interfaces:**
- Consumes: `BackupCategory`/`BackupTask` (Task 1); `CategoryWithTasks`, the existing `_group(List<TypedResult>)` helper.
- Produces: `Future<List<CategoryWithTasks>> TodoDao.exportSnapshot()`, `Future<void> TodoDao.importReplace(List<BackupCategory>)`.

- [ ] **Step 1: Write the failing test**

Create `test/data/backup_db_test.dart` (mirror the in-memory-DB setup used in `test/data/todo_dao_test.dart` — open `AppDatabase` over `NativeDatabase.memory()`):

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/backup_codec.dart';
import 'package:nooka/domain/models/backup_data.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('export snapshot includes archived tasks; round-trips via importReplace',
      () async {
    final dao = db.todoDao;
    final cat = await dao.createCategory(name: 'Work', color: 1, emoji: '💼');
    final active = await dao.createTask(categoryId: cat, name: 'Active');
    final archived = await dao.createTask(categoryId: cat, name: 'Archived');
    await dao.completeTask(archived, DateTime.utc(2026, 6, 10));

    final snapshot = await dao.exportSnapshot();
    expect(snapshot.single.tasks, hasLength(2));

    final backup = buildBackup(snapshot, DateTime.utc(2026, 6, 25));

    // Replace with a different backup, then confirm the DB matches it exactly.
    await dao.importReplace([
      BackupCategory(
        name: 'Home',
        color: 2,
        emoji: null,
        collapsed: true,
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 6, 1),
        tasks: [
          BackupTask(
            name: 'Imported archived',
            sortOrder: 0,
            createdAt: DateTime.utc(2026, 6, 2),
            archivedAt: DateTime.utc(2026, 6, 3),
          ),
        ],
      ),
    ]);

    final after = await dao.exportSnapshot();
    expect(after, hasLength(1));
    expect(after.single.category.name, 'Home');
    expect(after.single.category.collapsed, isTrue);
    expect(after.single.tasks.single.name, 'Imported archived');
    expect(after.single.tasks.single.archivedAt, DateTime.utc(2026, 6, 3));

    // The original active/archived ids are gone (replace, not merge).
    expect(backup.categories.single.tasks, hasLength(2));
    expect(after.single.tasks, hasLength(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/backup_db_test.dart`
Expected: FAIL — `exportSnapshot`/`importReplace` undefined.

- [ ] **Step 3: Add the import and methods to the DAO**

In `lib/data/services/database/todo_dao.dart`, add to the imports:

```dart
import '../../../domain/models/backup_data.dart';
```

Add these methods inside `TodoDao` (e.g. just above `watchCategoriesWithTasks`):

```dart
  /// One-shot read of every category with all its tasks (active + archived),
  /// ordered identically to [watchCategoriesWithTasks]. Used to build a backup.
  Future<List<CategoryWithTasks>> exportSnapshot() {
    final q =
        select(categories).join([
          leftOuterJoin(tasks, tasks.categoryId.equalsExp(categories.id)),
        ])..orderBy([
          OrderingTerm(expression: categories.sortOrder),
          OrderingTerm(expression: categories.id),
          OrderingTerm(expression: tasks.sortOrder),
          OrderingTerm(expression: tasks.id),
        ]);
    return q.get().then(_group);
  }

  /// Replaces the entire database with [data] in one transaction: clears tasks
  /// then categories, then re-inserts each category (capturing its new id) and
  /// its tasks. A mid-import failure rolls back to the prior state.
  Future<void> importReplace(List<BackupCategory> data) async {
    await transaction(() async {
      await delete(tasks).go();
      await delete(categories).go();
      for (final c in data) {
        final categoryId = await into(categories).insert(
          CategoriesCompanion.insert(
            name: c.name,
            color: c.color,
            emoji: Value(c.emoji),
            collapsed: Value(c.collapsed),
            sortOrder: c.sortOrder,
            createdAt: c.createdAt,
          ),
        );
        for (final t in c.tasks) {
          await into(tasks).insert(
            TasksCompanion.insert(
              categoryId: categoryId,
              name: t.name,
              sortOrder: t.sortOrder,
              createdAt: t.createdAt,
              archivedAt: Value(t.archivedAt),
            ),
          );
        }
      }
    });
  }
```

- [ ] **Step 4: Regenerate + run test to verify it passes**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test test/data/backup_db_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/services/database/todo_dao.dart lib/data/services/database/todo_dao.g.dart test/data/backup_db_test.dart
git commit -m "feat(backup): DAO exportSnapshot + transactional importReplace"
```

---

### Task 3: `TodoRepository` pass-throughs

**Files:**
- Modify: `lib/data/repositories/todo_repository.dart`
- Test: `test/data/todo_repository_passthrough_test.dart`

**Interfaces:**
- Produces: `Future<List<CategoryWithTasks>> TodoRepository.exportSnapshot()`, `Future<void> TodoRepository.importReplace(List<BackupCategory>)`.

- [ ] **Step 1: Add a failing pass-through test**

Append to `test/data/todo_repository_passthrough_test.dart` (follow the existing file's pattern of constructing a `TodoRepository` over an in-memory DAO):

```dart
  test('exportSnapshot + importReplace pass through to the DAO', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TodoRepository(db.todoDao);

    await repo.importReplace([
      BackupCategory(
        name: 'Imported',
        color: 7,
        emoji: null,
        collapsed: false,
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 6, 1),
        tasks: const [],
      ),
    ]);

    final snapshot = await repo.exportSnapshot();
    expect(snapshot.single.category.name, 'Imported');
  });
```

Ensure the file imports `package:drift/native.dart`, `package:nooka/data/services/database/database.dart`, and `package:nooka/domain/models/backup_data.dart` (add any missing).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/todo_repository_passthrough_test.dart`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Add the pass-throughs + import to the repository**

In `lib/data/repositories/todo_repository.dart`, add the import:

```dart
import '../../domain/models/backup_data.dart';
```

Add inside `TodoRepository` (e.g. just below `watchCategoriesWithTasks`):

```dart
  Future<List<CategoryWithTasks>> exportSnapshot() => _dao.exportSnapshot();
  Future<void> importReplace(List<BackupCategory> categories) =>
      _dao.importReplace(categories);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/todo_repository_passthrough_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/todo_repository.dart test/data/todo_repository_passthrough_test.dart
git commit -m "feat(backup): TodoRepository export/import pass-throughs"
```

---

### Task 4: Packages + `BackupIo` seam + coverage exclusion

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/data/services/backup/backup_io.dart`
- Create: `lib/data/services/backup/platform_backup_io.dart`
- Modify: `coverde.yaml`

**Interfaces:**
- Produces: `abstract interface class BackupIo` with `writeTemp`, `shareFile`, `pickFile`, `readFile`; `class PlatformBackupIo implements BackupIo`.

- [ ] **Step 1: Add dependencies**

In `pubspec.yaml` under `dependencies:` add:

```yaml
  share_plus: ^11.0.0
  file_picker: ^8.1.0
  path_provider: ^2.1.5
```

Run: `flutter pub get`
Expected: resolves. If the Android build later fails on `flutter_plugin_android_lifecycle` (a `file_picker` transitive), add a `dependency_overrides:` pin matching the version habbits used — but do **not** add it preemptively.

- [ ] **Step 2: Create the interface**

Create `lib/data/services/backup/backup_io.dart`:

```dart
/// The platform file-I/O seam for backups. The default [PlatformBackupIo] does
/// real share-sheet / file-picker / temp-file work; tests substitute a fake so
/// [BackupRepository] orchestration is exercised without a device.
abstract interface class BackupIo {
  /// Writes [contents] to a temp file named [filename]; returns its path.
  Future<String> writeTemp(String filename, String contents);

  /// Hands the file at [path] to the OS share sheet under [subject].
  Future<void> shareFile(String path, String subject);

  /// Opens the OS file picker; returns the chosen path, or null if cancelled.
  Future<String?> pickFile();

  /// Reads the file at [path] as a string.
  Future<String> readFile(String path);
}
```

- [ ] **Step 3: Create the platform implementation (coverage-excluded)**

Create `lib/data/services/backup/platform_backup_io.dart`:

```dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_io.dart';

/// Production file-I/O glue — unrunnable under `flutter test`, so excluded from
/// coverage (see coverde.yaml). Exercised manually / by emulator runs.
class PlatformBackupIo implements BackupIo {
  const PlatformBackupIo();

  @override
  Future<String> writeTemp(String filename, String contents) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(contents);
    return file.path;
  }

  @override
  Future<void> shareFile(String path, String subject) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: subject),
    );
  }

  @override
  Future<String?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    return result?.files.single.path;
  }

  @override
  Future<String> readFile(String path) => File(path).readAsString();
}
```

- [ ] **Step 4: Exclude the platform leaf from coverage**

In `coverde.yaml`, add under `exclude-untestable:` (after the `tables.dart` entry):

```yaml
    - type: skip-by-glob
      glob: "**/data/services/backup/platform_backup_io.dart"
```

- [ ] **Step 5: Verify analyze + existing tests still green**

Run: `flutter analyze && flutter test`
Expected: no analyzer issues; existing suite passes (no behavior change yet).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/data/services/backup/ coverde.yaml
git commit -m "feat(backup): add share/file-picker deps + BackupIo seam (platform leaf coverage-excluded)"
```

---

### Task 5: `BackupRepository` orchestration

**Files:**
- Create: `lib/data/repositories/backup_repository.dart`
- Test: `test/data/backup_repository_test.dart`

**Interfaces:**
- Consumes: `TodoRepository.exportSnapshot/importReplace` (Task 3), `BackupIo` (Task 4), `encodeBackup`/`buildBackup`/`decodeBackup` (Task 1), `Clock`/`SystemClock` (`lib/domain/clock.dart`), `clockProvider` + `todoRepositoryProvider` (`lib/data/repositories/todo_repository.dart`).
- Produces: `class BackupRepository` with `Future<void> exportAndShare({required String subject})` and `Future<BackupData?> pickAndDecode()`; `backupRepositoryProvider`.

- [ ] **Step 1: Write the failing test (fake BackupIo)**

Create `test/data/backup_repository_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/repositories/backup_repository.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/backup/backup_io.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/backup_codec.dart';
import 'package:nooka/domain/clock.dart';
import 'package:nooka/domain/models/backup_data.dart';

class FakeBackupIo implements BackupIo {
  String? sharedSubject;
  String? wroteFilename;
  String? wroteContents;
  String? toReturnOnPick; // null => user cancelled
  String pickFileContents = '';

  @override
  Future<String> writeTemp(String filename, String contents) async {
    wroteFilename = filename;
    wroteContents = contents;
    return '/tmp/$filename';
  }

  @override
  Future<void> shareFile(String path, String subject) async {
    sharedSubject = subject;
  }

  @override
  Future<String?> pickFile() async => toReturnOnPick;

  @override
  Future<String> readFile(String path) async => pickFileContents;
}

void main() {
  late AppDatabase db;
  late TodoRepository todos;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    todos = TodoRepository(db.todoDao);
  });
  tearDown(() => db.close());

  test('exportAndShare writes a dated file and shares it', () async {
    await todos.importReplace([
      BackupCategory(
        name: 'Work', color: 1, emoji: null, collapsed: false, sortOrder: 0,
        createdAt: DateTime.utc(2026, 6, 1), tasks: const [],
      ),
    ]);
    final io = FakeBackupIo();
    final repo = BackupRepository(
      todos, io, clock: FixedClock(DateTime.utc(2026, 6, 25, 9, 30)),
    );

    await repo.exportAndShare(subject: 'Nooka backup');

    expect(io.wroteFilename, 'nooka-backup-2026-06-25.json');
    expect(io.sharedSubject, 'Nooka backup');
    final decoded = decodeBackup(io.wroteContents!);
    expect(decoded.categories.single.name, 'Work');
  });

  test('pickAndDecode returns null when cancelled', () async {
    final io = FakeBackupIo()..toReturnOnPick = null;
    final repo = BackupRepository(todos, io);
    expect(await repo.pickAndDecode(), isNull);
  });

  test('pickAndDecode decodes a chosen file', () async {
    final io = FakeBackupIo()
      ..toReturnOnPick = '/tmp/in.json'
      ..pickFileContents = encodeBackup(
        BackupData(version: 1, exportedAt: DateTime.utc(2026), categories: []),
      );
    final repo = BackupRepository(todos, io);
    expect((await repo.pickAndDecode())!.categories, isEmpty);
  });

  test('pickAndDecode throws on an invalid file', () async {
    final io = FakeBackupIo()
      ..toReturnOnPick = '/tmp/bad.json'
      ..pickFileContents = 'garbage';
    final repo = BackupRepository(todos, io);
    expect(repo.pickAndDecode, throwsA(isA<BackupFormatException>()));
  });
}
```

`FixedClock` already exists in `lib/domain/clock.dart` (used by repo tests); confirm its constructor signature there and adjust if needed.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/backup_repository_test.dart`
Expected: FAIL — `BackupRepository` undefined.

- [ ] **Step 3: Implement the repository + provider**

Create `lib/data/repositories/backup_repository.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/backup_codec.dart';
import '../../domain/clock.dart';
import '../../domain/models/backup_data.dart';
import '../services/backup/backup_io.dart';
import '../services/backup/platform_backup_io.dart';
import 'todo_repository.dart';

part 'backup_repository.g.dart';

/// Orchestrates backup file I/O: builds + encodes a snapshot, writes a temp
/// file and shares it; picks a file, reads and decodes it. All platform calls
/// go through the injectable [BackupIo] seam so this logic is unit-testable.
class BackupRepository {
  BackupRepository(this._todos, this._io, {Clock clock = const SystemClock()})
    : _clock = clock;
  final TodoRepository _todos;
  final BackupIo _io;
  final Clock _clock;

  Future<void> exportAndShare({required String subject}) async {
    final now = _clock.now();
    final json = encodeBackup(buildBackup(await _todos.exportSnapshot(), now));
    final path = await _io.writeTemp('nooka-backup-${_isoDate(now)}.json', json);
    await _io.shareFile(path, subject);
  }

  Future<BackupData?> pickAndDecode() async {
    final path = await _io.pickFile();
    if (path == null) return null;
    return decodeBackup(await _io.readFile(path));
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

@Riverpod(keepAlive: true)
BackupRepository backupRepository(Ref ref) => BackupRepository(
  ref.watch(todoRepositoryProvider),
  const PlatformBackupIo(),
  clock: ref.watch(clockProvider),
);
```

- [ ] **Step 4: Regenerate + run test to verify it passes**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test test/data/backup_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/backup_repository.dart lib/data/repositories/backup_repository.g.dart test/data/backup_repository_test.dart
git commit -m "feat(backup): BackupRepository orchestration over BackupIo"
```

---

### Task 6: `SettingsViewModel` command seam

**Files:**
- Create: `lib/ui/settings/settings_view_model.dart`
- Test: `test/ui/settings_view_model_test.dart`

**Interfaces:**
- Consumes: `backupRepositoryProvider` (Task 5), `todoRepositoryProvider`, `rememberedCategoryProvider` (`lib/data/repositories/remembered_category.dart`), `BackupData`/`BackupFormatException` (Task 1).
- Produces: `SettingsViewModel` (`@riverpod` class) with `Future<bool> export(String)`, `Future<ImportPick> pickImport()`, `Future<bool> applyImport(BackupData)`; the `ImportPick` sealed result.

- [ ] **Step 1: Write the failing test**

Create `test/ui/settings_view_model_test.dart`. Build a `ProviderContainer` overriding `backupRepositoryProvider` with a fake and `todoRepositoryProvider`/`rememberedCategoryProvider` over an in-memory DB + real `SharedPreferences` mock. Use `SharedPreferences.setMockInitialValues({})` and override `sharedPreferencesProvider`.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/repositories/backup_repository.dart';
import 'package:nooka/data/repositories/remembered_category.dart';
import 'package:nooka/data/repositories/settings_repository.dart';
import 'package:nooka/data/repositories/todo_repository.dart';
import 'package:nooka/data/services/backup/backup_io.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/models/backup_data.dart';
import 'package:nooka/ui/settings/settings_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StubBackupIo implements BackupIo {
  @override
  Future<String?> pickFile() async => null;
  @override
  Future<String> readFile(String path) async => '';
  @override
  Future<void> shareFile(String path, String subject) async {}
  @override
  Future<String> writeTemp(String filename, String contents) async => filename;
}

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({'last_category': 5});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => db.close());

  ProviderContainer makeContainer(BackupRepository backup) => ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      todoRepositoryProvider.overrideWith((ref) => TodoRepository(db.todoDao)),
      backupRepositoryProvider.overrideWith((ref) => backup),
    ],
  );

  test('applyImport replaces data and forgets the remembered category', () async {
    final backup = BackupRepository(TodoRepository(db.todoDao), StubBackupIo());
    final c = makeContainer(backup);
    addTearDown(c.dispose);

    final ok = await c.read(settingsViewModelProvider.notifier).applyImport(
      BackupData(
        version: 1,
        exportedAt: DateTime.utc(2026),
        categories: [
          BackupCategory(
            name: 'Imported', color: 1, emoji: null, collapsed: false,
            sortOrder: 0, createdAt: DateTime.utc(2026, 6, 1), tasks: const [],
          ),
        ],
      ),
    );

    expect(ok, isTrue);
    expect(prefs.getInt('last_category'), isNull); // forgotten
    final snapshot = await TodoRepository(db.todoDao).exportSnapshot();
    expect(snapshot.single.category.name, 'Imported');
  });

  test('export returns true on success', () async {
    final backup = BackupRepository(TodoRepository(db.todoDao), StubBackupIo());
    final c = makeContainer(backup);
    addTearDown(c.dispose);
    expect(
      await c.read(settingsViewModelProvider.notifier).export('subject'),
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings_view_model_test.dart`
Expected: FAIL — `settings_view_model.dart` / `settingsViewModelProvider` undefined.

- [ ] **Step 3: Implement the view model**

Create `lib/ui/settings/settings_view_model.dart`:

```dart
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
```

- [ ] **Step 4: Regenerate + run test to verify it passes**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test test/ui/settings_view_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/settings_view_model.dart lib/ui/settings/settings_view_model.g.dart test/ui/settings_view_model_test.dart
git commit -m "feat(backup): SettingsViewModel export/import command seam"
```

---

### Task 7: l10n + SettingsScreen wiring + widget test + architecture promotion

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ru.arb`
- Modify: `lib/ui/settings/settings_screen.dart`
- Test: `test/ui/settings_screen_test.dart`
- Create: `architecture/backup-io.md`
- Modify: `architecture/README.md`, `planning/deferred.md`

**Interfaces:**
- Consumes: `SettingsViewModel`, `ImportPick*` (Task 6).

- [ ] **Step 1: Add l10n keys (both locales)**

In `lib/l10n/app_en.arb`, add before the closing brace:

```json
  "exportData": "Export data",
  "importData": "Import data",
  "exportShareSubject": "Nooka backup",
  "importReplaceTitle": "Replace all data?",
  "importReplaceBody": "This deletes {count, plural, =0{no categories} one{{count} category} other{{count} categories}} and all their items, then loads the backup.",
  "@importReplaceBody": {
    "placeholders": { "count": { "type": "int" } }
  },
  "importDone": "Imported {count, plural, =0{no categories} one{{count} category} other{{count} categories}}",
  "@importDone": {
    "placeholders": { "count": { "type": "int" } }
  },
  "importInvalidFile": "That isn't a valid Nooka backup.",
  "replace": "Replace"
```

In `lib/l10n/app_ru.arb`, add the parallel keys (match the existing file's Russian plural style — `one/few/many/other`):

```json
  "exportData": "Экспорт данных",
  "importData": "Импорт данных",
  "exportShareSubject": "Резервная копия Nooka",
  "importReplaceTitle": "Заменить все данные?",
  "importReplaceBody": "Будут удалены {count, plural, =0{нет категорий} one{{count} категория} few{{count} категории} many{{count} категорий} other{{count} категории}} и все их задачи, затем загрузится копия.",
  "@importReplaceBody": {
    "placeholders": { "count": { "type": "int" } }
  },
  "importDone": "Импортировано {count, plural, =0{нет категорий} one{{count} категория} few{{count} категории} many{{count} категорий} other{{count} категории}}",
  "@importDone": {
    "placeholders": { "count": { "type": "int" } }
  },
  "importInvalidFile": "Это не похоже на резервную копию Nooka.",
  "replace": "Заменить"
```

Run: `flutter gen-l10n` (or `flutter pub get`, which triggers it) to regenerate `app_localizations*.dart`.

- [ ] **Step 2: Write the failing widget test**

In `test/ui/settings_screen_test.dart`, follow the existing file's harness (it already pumps `SettingsScreen` with localization + provider overrides). Add a fake `BackupRepository` override and these cases:

```dart
  testWidgets('import replaces data after confirmation and shows count',
      (WidgetTester tester) async {
    // ... pump SettingsScreen with backupRepositoryProvider overridden so
    // pickAndDecode() returns a one-category BackupData, todoRepositoryProvider
    // over an in-memory DB, sharedPreferencesProvider mocked.
    await tester.tap(find.byKey(const Key('import-tile')));
    await tester.pumpAndSettle();
    // confirm dialog visible
    expect(find.text('Replace all data?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-import')));
    await tester.pumpAndSettle();
    // success SnackBar with the imported count
    expect(find.textContaining('Imported'), findsOneWidget);
    // data replaced
    final snapshot = await todos.exportSnapshot();
    expect(snapshot.single.category.name, 'Imported');
  });

  testWidgets('invalid backup shows the invalid-file message',
      (WidgetTester tester) async {
    // ... backupRepositoryProvider whose pickAndDecode() throws
    // BackupFormatException.
    await tester.tap(find.byKey(const Key('import-tile')));
    await tester.pumpAndSettle();
    expect(find.text("That isn't a valid Nooka backup."), findsOneWidget);
  });

  testWidgets('export tile invokes export', (WidgetTester tester) async {
    // ... spy BackupRepository records exportAndShare was called with the
    // localized subject.
    await tester.tap(find.byKey(const Key('export-tile')));
    await tester.pumpAndSettle();
    expect(spy.exportedSubject, 'Nooka backup');
  });
```

(Write the full harness modelled on the existing tests in this file; the snippets above are the assertions each case must reach.)

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/ui/settings_screen_test.dart`
Expected: FAIL — tiles/keys absent.

- [ ] **Step 4: Wire the SettingsScreen**

In `lib/ui/settings/settings_screen.dart`, add the two tiles to the `ListView` children and the handlers. Add imports for `settings_view_model.dart`. The handlers (as methods on the widget or top-level helpers taking `BuildContext`/`WidgetRef`):

```dart
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(settingsViewModelProvider.notifier)
        .export(l10n.exportShareSubject);
    if (!ok && context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.actionFailed)));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final vm = ref.read(settingsViewModelProvider.notifier);
    final pick = await vm.pickImport();
    if (!context.mounted) return;
    switch (pick) {
      case ImportPickCancelled():
        return;
      case ImportPickInvalid():
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.importInvalidFile)));
      case ImportPickFailed():
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.actionFailed)));
      case ImportPickReady(:final data):
        final count = data.categories.length;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.importReplaceTitle),
            content: Text(l10n.importReplaceBody(count)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                key: const Key('confirm-import'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.replace),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final ok = await vm.applyImport(data);
        messenger.showSnackBar(SnackBar(
          content: Text(ok ? l10n.importDone(count) : l10n.actionFailed),
        ));
    }
  }
```

Add the tiles to the `ListView`:

```dart
          ListTile(
            key: const Key('export-tile'),
            title: Text(l10n.exportData),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            key: const Key('import-tile'),
            title: Text(l10n.importData),
            onTap: () => _import(context, ref),
          ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/ui/settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Write the architecture doc + remove the deferred item**

Create `architecture/backup-io.md` describing the capability: the JSON format (`app`/`version`/nested categories→tasks with `archivedAt`), the codec → DAO → repository → VM → screen flow, the replace-all + confirm-dialog invariant, the remembered-category reset, and the `BackupIo` coverage-exclusion seam. Add a one-line pointer in `architecture/README.md`.

Remove the **JSON export/import** bullet from `planning/deferred.md`.

- [ ] **Step 7: Set the change status + regenerate the index**

In `planning/changes/2026-06-25.02-export-import/design.md` frontmatter, set `status: shipped` and fill `pr:` / `outcome:` (the PR number once opened; outcome at merge). Run `just index`.

- [ ] **Step 8: Full gate + commit**

Run: `just lint-ci && just test`
Expected: analyzer clean, formatting already applied, **100% coverage** (the new `platform_backup_io.dart` excluded), all tests green.

```bash
git add lib/l10n/ lib/ui/settings/settings_screen.dart test/ui/settings_screen_test.dart architecture/ planning/
git commit -m "feat(backup): wire export/import into Settings + promote architecture"
```

---

## Notes for the executor

- **PR, not local merge.** Push the branch, open a PR, watch CI. After merge: `git pull --ff-only`, delete the local branch, `git remote prune origin`.
- **Each task is a failing-test-first cycle.** Don't implement before the red test runs.
- If the Android build fails on `flutter_plugin_android_lifecycle`, add the `dependency_overrides:` pin (Task 4 Step 1) and note it in the PR.
