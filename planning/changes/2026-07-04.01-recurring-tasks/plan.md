# Recurring tasks — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** A task can repeat every N days/weeks/months relative to completion; on
completion it goes dormant (hidden, shown in Archive as "Returns in N days")
until it wakes back into its slot.

**Spec:** [`design.md`](./design.md)

**Branch:** `feat/recurring-tasks` (already created and checked out)

**Commit strategy:** Per-task commits. TDD — a failing test precedes each code
change.

## Global Constraints

- Stack: Flutter, Riverpod (`@riverpod` codegen), Drift (SQLite), `intl`/gen-l10n.
- All imports at module level, never inside function bodies. Annotate every
  function argument (user rule).
- Generated `*.g.dart` is committed. After touching `@riverpod` or Drift/table
  code OR editing `lib/l10n/*.arb`, run
  `dart run build_runner build --delete-conflicting-outputs` and commit the
  regenerated files.
- Pure `domain/` code has no Flutter/Drift imports.
- Every user-facing string is bilingual: add to `lib/l10n/app_en.arb`
  (template) AND `lib/l10n/app_ru.arb`. Russian uses all four CLDR plural forms
  (`one`/`few`/`many`/`other`) for any `{count, plural, …}`.
- Final gate before every commit: `just lint-ci` clean (NOT `just lint`, which
  reformats in place and can leave a dirty tree), then `just test`.
- Architecture promotion rides in this same PR (Task 12), never as a follow-up.
- `RecurrenceUnit` is stored as its enum index (`intEnum`) in DB and backups.
- The DB stores `DateTime` as an integer (Unix seconds); relevant only to the
  migration test's raw DDL (Task 2).

---

### Task 1: Pure recurrence domain module

**Files:**
- Create: `lib/domain/recurrence.dart`
- Test: `test/domain/recurrence_test.dart`

**Interfaces:**
- Produces: `enum RecurrenceUnit { days, weeks, months }`;
  `DateTime nextDueDate(DateTime completedAt, int count, RecurrenceUnit unit)`;
  `int daysUntilDue(DateTime nextDueAt, DateTime now)`.

- [ ] **Step 1: Write the failing test**

  Create `test/domain/recurrence_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/domain/recurrence.dart';

  void main() {
    group('nextDueDate', () {
      test('days adds exact duration', () {
        expect(
          nextDueDate(DateTime(2026, 7, 4, 9), 3, RecurrenceUnit.days),
          DateTime(2026, 7, 7, 9),
        );
      });
      test('weeks adds 7 days per count', () {
        expect(
          nextDueDate(DateTime(2026, 7, 4, 9), 2, RecurrenceUnit.weeks),
          DateTime(2026, 7, 18, 9),
        );
      });
      test('months adds calendar months, preserving time of day', () {
        expect(
          nextDueDate(DateTime(2026, 1, 15, 8, 30), 1, RecurrenceUnit.months),
          DateTime(2026, 2, 15, 8, 30),
        );
      });
      test('months clamps to end of a shorter target month', () {
        expect(
          nextDueDate(DateTime(2026, 1, 31, 8), 1, RecurrenceUnit.months),
          DateTime(2026, 2, 28, 8),
        );
      });
      test('months clamps to Feb 29 in a leap year', () {
        expect(
          nextDueDate(DateTime(2028, 1, 31, 8), 1, RecurrenceUnit.months),
          DateTime(2028, 2, 29, 8),
        );
      });
    });

    group('daysUntilDue', () {
      final now = DateTime(2026, 7, 4, 12);
      test('rounds a partial day up', () {
        expect(daysUntilDue(now.add(const Duration(days: 2, hours: 1)), now), 3);
      });
      test('exactly now is 0', () {
        expect(daysUntilDue(now, now), 0);
      });
      test('never negative', () {
        expect(daysUntilDue(now.subtract(const Duration(days: 5)), now), 0);
      });
    });
  }
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `flutter test test/domain/recurrence_test.dart`
  Expected: FAIL — `Error: Couldn't resolve the package 'nooka'` is wrong; the
  real failure is `recurrence.dart` not found / `nextDueDate` undefined.

- [ ] **Step 3: Write the implementation**

  Create `lib/domain/recurrence.dart`:

  ```dart
  /// Unit of a completion-relative recurrence interval. Stored as its index
  /// (intEnum) in the database and in backups.
  enum RecurrenceUnit { days, weeks, months }

  /// The instant a recurring task returns, given when it was completed and the
  /// interval. Days/weeks are exact Durations; months add calendar months with
  /// end-of-month clamping (complete Jan 31 + 1 month -> Feb 28 / 29 leap year),
  /// preserving the time of day.
  DateTime nextDueDate(DateTime completedAt, int count, RecurrenceUnit unit) {
    switch (unit) {
      case RecurrenceUnit.days:
        return completedAt.add(Duration(days: count));
      case RecurrenceUnit.weeks:
        return completedAt.add(Duration(days: 7 * count));
      case RecurrenceUnit.months:
        final targetMonthStart = DateTime(
          completedAt.year,
          completedAt.month + count,
        );
        final lastDay = DateTime(
          targetMonthStart.year,
          targetMonthStart.month + 1,
          0,
        ).day;
        final day = completedAt.day < lastDay ? completedAt.day : lastDay;
        return DateTime(
          targetMonthStart.year,
          targetMonthStart.month,
          day,
          completedAt.hour,
          completedAt.minute,
          completedAt.second,
          completedAt.millisecond,
          completedAt.microsecond,
        );
    }
  }

  /// Whole days until [nextDueAt] as of [now], for the "Returns in N days"
  /// label. Rounds a partial day up and clamps to 0, matching
  /// `archive.daysRemaining`.
  int daysUntilDue(DateTime nextDueAt, DateTime now) {
    final remaining =
        (nextDueAt.difference(now).inMilliseconds / Duration.millisecondsPerDay)
            .ceil();
    return remaining < 0 ? 0 : remaining;
  }
  ```

- [ ] **Step 4: Run test to verify it passes**

  Run: `flutter test test/domain/recurrence_test.dart`
  Expected: PASS (all cases).

- [ ] **Step 5: Commit**

  ```bash
  just lint-ci
  git add lib/domain/recurrence.dart test/domain/recurrence_test.dart
  git commit -m "feat(recurrence): add pure completion-relative interval math"
  ```

---

### Task 2: Schema columns + migration (v1 → v2)

**Files:**
- Modify: `lib/data/services/database/tables.dart`
- Modify: `lib/data/services/database/database.dart`
- Modify (regenerated): `lib/data/services/database/*.g.dart`
- Test: `test/data/migration_test.dart`
- Modify (maybe): `pubspec.yaml` (dev_dependencies: `sqlite3`)

**Interfaces:**
- Produces: `Tasks.recurrenceCount` (`int?`), `Tasks.recurrenceUnit`
  (`RecurrenceUnit?`), `Tasks.nextDueAt` (`DateTime?`) on the generated `Task`
  row class; `AppDatabase.schemaVersion == 2` with an additive `onUpgrade`.

- [ ] **Step 1: Add the three nullable columns**

  In `lib/data/services/database/tables.dart`, add the import and columns to
  `Tasks`:

  ```dart
  import 'package:drift/drift.dart';

  import '../../../domain/recurrence.dart';

  // ... Categories unchanged ...

  class Tasks extends Table {
    IntColumn get id => integer().autoIncrement()();
    IntColumn get categoryId =>
        integer().references(Categories, #id, onDelete: KeyAction.cascade)();
    TextColumn get name => text()();
    IntColumn get sortOrder => integer()();
    DateTimeColumn get createdAt => dateTime()();
    DateTimeColumn get archivedAt => dateTime().nullable()(); // null = active
    IntColumn get recurrenceCount => integer().nullable()();
    IntColumn get recurrenceUnit => intEnum<RecurrenceUnit>().nullable()();
    DateTimeColumn get nextDueAt => dateTime().nullable()(); // non-null = dormant
  }
  ```

- [ ] **Step 2: Bump schemaVersion and add onUpgrade**

  In `lib/data/services/database/database.dart`, replace the class body:

  ```dart
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(tasks, tasks.recurrenceCount);
        await m.addColumn(tasks, tasks.recurrenceUnit);
        await m.addColumn(tasks, tasks.nextDueAt);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
  ```

- [ ] **Step 3: Regenerate Drift code**

  Run: `dart run build_runner build --delete-conflicting-outputs`
  Expected: succeeds; `database.g.dart` now has `recurrence_count`,
  `recurrence_unit`, `next_due_at` columns on the tasks table.

- [ ] **Step 4: Ensure sqlite3 is available to tests**

  Run: `grep -n "sqlite3" pubspec.yaml`
  If it is NOT listed under `dev_dependencies`, add it:

  ```bash
  dart pub add dev:sqlite3
  ```
  (drift/native already pulls sqlite3 transitively; this makes the direct import
  in the migration test resolvable.)

- [ ] **Step 5: Write the failing migration test**

  Create `test/data/migration_test.dart`:

  ```dart
  import 'package:drift/native.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/services/database/database.dart';
  import 'package:sqlite3/sqlite3.dart';

  void main() {
    test('v1 database upgrades to v2 with null recurrence columns', () async {
      // Build a v1-shaped database on a raw connection (snake_case column
      // names, DateTime stored as int seconds, user_version = 1).
      final raw = sqlite3.openInMemory();
      raw.execute('''
        CREATE TABLE categories (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, color INTEGER NOT NULL, emoji TEXT NULL,
          collapsed INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL,
          created_at INTEGER NOT NULL);
      ''');
      raw.execute('''
        CREATE TABLE tasks (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL REFERENCES categories (id) ON DELETE CASCADE,
          name TEXT NOT NULL, sort_order INTEGER NOT NULL,
          created_at INTEGER NOT NULL, archived_at INTEGER NULL);
      ''');
      raw.execute('PRAGMA user_version = 1;');
      raw.execute(
        "INSERT INTO categories (name, color, sort_order, created_at) "
        "VALUES ('Home', 1, 0, 1000000000);",
      );
      raw.execute(
        "INSERT INTO tasks (category_id, name, sort_order, created_at) "
        "VALUES (1, 'Water plants', 0, 1000000000);",
      );

      // Opening AppDatabase on the same connection runs onUpgrade(1 -> 2).
      final db = AppDatabase(NativeDatabase.opened(raw));
      addTearDown(db.close);

      final tasks = await db.select(db.tasks).get();
      expect(tasks, hasLength(1));
      expect(tasks.single.name, 'Water plants');
      expect(tasks.single.recurrenceCount, isNull);
      expect(tasks.single.recurrenceUnit, isNull);
      expect(tasks.single.nextDueAt, isNull);
      expect(db.schemaVersion, 2);
    });
  }
  ```

- [ ] **Step 6: Run the migration test**

  Run: `flutter test test/data/migration_test.dart`
  Expected: PASS. (Also confirm the existing `flutter test test/data/schema_test.dart`
  still passes — it only checks table existence.)

- [ ] **Step 7: Commit**

  ```bash
  just lint-ci
  git add lib/data/services/database/tables.dart \
          lib/data/services/database/database.dart \
          lib/data/services/database/*.g.dart \
          test/data/migration_test.dart pubspec.yaml pubspec.lock
  git commit -m "feat(db): add recurrence columns + v1->v2 migration"
  ```

---

### Task 3: Three-way task-state split on CategoryWithTasks

**Files:**
- Modify: `lib/domain/models/category_with_tasks.dart`
- Test: `test/domain/category_with_tasks_test.dart` (create if absent)

**Interfaces:**
- Produces: `CategoryWithTasks.activeTasks` (now excludes dormant),
  `CategoryWithTasks.dormantTasks` (new, soonest-return first),
  `CategoryWithTasks.archivedTasks` (unchanged semantics).

- [ ] **Step 1: Write the failing test**

  Create `test/domain/category_with_tasks_test.dart`. Build `Task` rows via the
  generated constructor (all columns required positionally/named per
  `database.g.dart` — use named args):

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/services/database/database.dart';
  import 'package:nooka/domain/models/category_with_tasks.dart';
  import 'package:nooka/domain/recurrence.dart';

  Task _task({
    required int id,
    DateTime? archivedAt,
    int? recurrenceCount,
    RecurrenceUnit? recurrenceUnit,
    DateTime? nextDueAt,
  }) => Task(
    id: id,
    categoryId: 1,
    name: 't$id',
    sortOrder: id,
    createdAt: DateTime(2026, 1, 1),
    archivedAt: archivedAt,
    recurrenceCount: recurrenceCount,
    recurrenceUnit: recurrenceUnit,
    nextDueAt: nextDueAt,
  );

  void main() {
    final category = Category(
      id: 1,
      name: 'Home',
      color: 1,
      emoji: null,
      collapsed: false,
      sortOrder: 0,
      createdAt: DateTime(2026, 1, 1),
    );

    test('splits active, dormant, and archived by the derived rules', () {
      final active = _task(id: 1);
      final dormantSoon =
          _task(id: 2, recurrenceCount: 1, recurrenceUnit: RecurrenceUnit.days,
              nextDueAt: DateTime(2026, 7, 5));
      final dormantLater =
          _task(id: 3, recurrenceCount: 1, recurrenceUnit: RecurrenceUnit.days,
              nextDueAt: DateTime(2026, 7, 20));
      final archived = _task(id: 4, archivedAt: DateTime(2026, 6, 1));

      final cwt = CategoryWithTasks(
        category,
        [active, dormantLater, dormantSoon, archived],
      );

      expect(cwt.activeTasks.map((t) => t.id), [1]);
      expect(cwt.dormantTasks.map((t) => t.id), [2, 3]); // soonest first
      expect(cwt.archivedTasks.map((t) => t.id), [4]);
    });
  }
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `flutter test test/domain/category_with_tasks_test.dart`
  Expected: FAIL — `dormantTasks` undefined; `activeTasks` still includes id 2/3.

- [ ] **Step 3: Implement the split**

  Replace the getters in `lib/domain/models/category_with_tasks.dart`:

  ```dart
  /// Active tasks: not archived and not dormant, in sortOrder.
  List<Task> get activeTasks => [
    for (final t in tasks)
      if (t.archivedAt == null && t.nextDueAt == null) t,
  ];

  /// Dormant recurring tasks (completed, waiting to return), soonest first.
  List<Task> get dormantTasks => [
    for (final t in tasks)
      if (t.archivedAt == null && t.nextDueAt != null) t,
  ]..sort((a, b) => a.nextDueAt!.compareTo(b.nextDueAt!));

  /// Archived tasks, newest-completed first.
  List<Task> get archivedTasks => [
    for (final t in tasks)
      if (t.archivedAt != null) t,
  ]..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));
  ```

- [ ] **Step 4: Run test to verify it passes**

  Run: `flutter test test/domain/category_with_tasks_test.dart`
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  just lint-ci
  git add lib/domain/models/category_with_tasks.dart \
          test/domain/category_with_tasks_test.dart
  git commit -m "feat(model): split tasks into active / dormant / archived"
  ```

---

### Task 4: DAO — complete branch, wake, and dormant exclusion

**Files:**
- Modify: `lib/data/services/database/todo_dao.dart`
- Test: `test/data/todo_dao_test.dart` (append)

**Interfaces:**
- Consumes: `nextDueDate` (Task 1), recurrence columns (Task 2).
- Produces: `completeTask(id, now)` branches recurring→dormant / else→archive;
  `Future<void> wakeTask(int id)`; `Future<int> wakeDueTasks(DateTime now)`;
  `_nextTaskOrder` ignores dormant rows.

- [ ] **Step 1: Write the failing tests**

  Append to `test/data/todo_dao_test.dart` (inside `main`, a new group). It uses
  the existing `db` from `setUp`:

  ```dart
  group('recurrence', () {
    Future<int> makeRecurring(String name) async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final id = await db.todoDao.createTask(categoryId: cat, name: name);
      await db.todoDao.renameAndMove(
        id, name, null,
        recurrenceCount: 3, recurrenceUnit: RecurrenceUnit.days,
      );
      return id;
    }

    test('completing a recurring task sets nextDueAt, not archivedAt', () async {
      final id = await makeRecurring('Water');
      final now = DateTime(2026, 7, 4, 9);
      await db.todoDao.completeTask(id, now);
      final row = await (db.select(db.tasks)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.archivedAt, isNull);
      expect(row.nextDueAt, DateTime(2026, 7, 7, 9));
      expect(row.sortOrder, 0); // slot preserved
    });

    test('completing a non-recurring task still archives', () async {
      final cat = await db.todoDao.createCategory(name: 'Work', color: 2);
      final id = await db.todoDao.createTask(categoryId: cat, name: 'Ship');
      final now = DateTime(2026, 7, 4, 9);
      await db.todoDao.completeTask(id, now);
      final row = await (db.select(db.tasks)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.archivedAt, now);
      expect(row.nextDueAt, isNull);
    });

    test('wakeDueTasks clears only past-due nextDueAt', () async {
      final id = await makeRecurring('Water');
      await db.todoDao.completeTask(id, DateTime(2026, 7, 4, 9)); // due Jul 7
      final woken = await db.todoDao.wakeDueTasks(DateTime(2026, 7, 6));
      expect(woken, 0);
      final woken2 = await db.todoDao.wakeDueTasks(DateTime(2026, 7, 8));
      expect(woken2, 1);
      final row = await (db.select(db.tasks)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.nextDueAt, isNull);
    });

    test('wakeTask clears nextDueAt and keeps the slot', () async {
      final id = await makeRecurring('Water');
      await db.todoDao.completeTask(id, DateTime(2026, 7, 4, 9));
      await db.todoDao.wakeTask(id);
      final row = await (db.select(db.tasks)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.nextDueAt, isNull);
      expect(row.sortOrder, 0);
    });

    test('a dormant task is not counted when appending active order', () async {
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final a = await db.todoDao.createTask(categoryId: cat, name: 'A'); // order 0
      await db.todoDao.renameAndMove(a, 'A', null,
          recurrenceCount: 1, recurrenceUnit: RecurrenceUnit.days);
      await db.todoDao.completeTask(a, DateTime(2026, 7, 4)); // dormant
      final b = await db.todoDao.createTask(categoryId: cat, name: 'B');
      final rowB = await (db.select(db.tasks)
            ..where((t) => t.id.equals(b)))
          .getSingle();
      expect(rowB.sortOrder, 0); // dormant A did not occupy an active slot
    });
  });
  ```

  Add the imports at the top of the file if missing:
  `import 'package:nooka/domain/recurrence.dart';`

- [ ] **Step 2: Run tests to verify they fail**

  Run: `flutter test test/data/todo_dao_test.dart`
  Expected: FAIL — `wakeTask` / `wakeDueTasks` undefined and `renameAndMove` has
  no recurrence params (Task 5 adds it, but define its signature here so these
  compile — see Step 3).

- [ ] **Step 3: Implement DAO changes**

  In `lib/data/services/database/todo_dao.dart`, add the import
  `import '../../../domain/recurrence.dart';`, then:

  Extend `_nextTaskOrder`'s filter:

  ```dart
  final active = await (select(tasks)..where(
        (t) => t.categoryId.equals(categoryId) &
            t.archivedAt.isNull() &
            t.nextDueAt.isNull(),
      )).get();
  ```

  Replace `completeTask`:

  ```dart
  Future<void> completeTask(int id, DateTime now) async {
    final task = await (select(tasks)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (task == null) return;
    final count = task.recurrenceCount;
    final unit = task.recurrenceUnit;
    if (count != null && unit != null) {
      // Recurring: go dormant, keep the slot (leave a sortOrder gap like delete).
      await (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(nextDueAt: Value(nextDueDate(now, count, unit))),
      );
    } else {
      await (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(archivedAt: Value(now)),
      );
    }
  }
  ```

  Add near `restoreTask`:

  ```dart
  /// Wakes a dormant recurring task: clears nextDueAt, keeping sortOrder so it
  /// returns to its original slot. Used by "Return now" and by undo of a
  /// recurring completion.
  Future<void> wakeTask(int id) =>
      (update(tasks)..where((t) => t.id.equals(id)))
          .write(const TasksCompanion(nextDueAt: Value(null)));

  /// Clears nextDueAt for every dormant task due as of [now], revealing them in
  /// the active list. Returns the number woken. Runs at startup / resume.
  Future<int> wakeDueTasks(DateTime now) =>
      (update(tasks)..where(
            (t) => t.nextDueAt.isNotNull() &
                t.nextDueAt.isSmallerOrEqualValue(now),
          ))
          .write(const TasksCompanion(nextDueAt: Value(null)));
  ```

  (The `renameAndMove` recurrence params are added in Task 5; the tests above
  call it with the new named params. Implement that signature now as part of
  Step 3 so this task compiles — see Task 5 Step 3 for the exact body, and
  paste it here; Task 5 then adds only the `importReplace` change and its own
  test.)

  Extend `renameAndMove`:

  ```dart
  Future<void> renameAndMove(
    int id,
    String name,
    int? newCategoryId, {
    int? recurrenceCount,
    RecurrenceUnit? recurrenceUnit,
  }) => transaction(() async {
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        name: Value(name),
        recurrenceCount: Value(recurrenceCount),
        recurrenceUnit: Value(recurrenceUnit),
      ),
    );
    if (newCategoryId != null) await moveTask(id, newCategoryId);
  });
  ```

- [ ] **Step 4: Run tests to verify they pass**

  Run: `flutter test test/data/todo_dao_test.dart`
  Expected: PASS (new group + existing tests).

- [ ] **Step 5: Commit**

  ```bash
  just lint-ci
  git add lib/data/services/database/todo_dao.dart test/data/todo_dao_test.dart
  git commit -m "feat(dao): recurring complete goes dormant; wake + order exclusion"
  ```

---

### Task 5: DAO importReplace carries recurrence

**Files:**
- Modify: `lib/data/services/database/todo_dao.dart`
- Test: `test/data/todo_dao_test.dart` (append) — verified end-to-end with the
  codec in Task 7; here assert the insert path.

**Interfaces:**
- Consumes: `BackupTask.recurrenceCount/recurrenceUnit/nextDueAt` (added in
  Task 7). Since Task 7 adds those fields, do this task AFTER Task 7, OR
  temporarily reference them; to keep ordering simple, **do Task 7 before this
  task's Step 1** (the plan lists it here for locality — the executor may run
  Task 7 first). If running in order, defer this task until Task 7 completes.

- [ ] **Step 1: Add the failing test**

  Append to `test/data/todo_dao_test.dart` inside the `recurrence` group:

  ```dart
  test('importReplace round-trips recurrence + dormancy', () async {
    await db.todoDao.importReplace([
      BackupCategory(
        name: 'Home', color: 1, emoji: null, collapsed: false,
        sortOrder: 0, createdAt: DateTime(2026, 1, 1),
        tasks: [
          BackupTask(
            name: 'Water', sortOrder: 0, createdAt: DateTime(2026, 1, 1),
            archivedAt: null,
            recurrenceCount: 3, recurrenceUnit: RecurrenceUnit.weeks,
            nextDueAt: DateTime(2026, 8, 1),
          ),
        ],
      ),
    ]);
    final row = (await db.select(db.tasks).get()).single;
    expect(row.recurrenceCount, 3);
    expect(row.recurrenceUnit, RecurrenceUnit.weeks);
    expect(row.nextDueAt, DateTime(2026, 8, 1));
  });
  ```

  Ensure `import 'package:nooka/domain/models/backup_data.dart';` is present.

- [ ] **Step 2: Run to verify it fails**

  Run: `flutter test test/data/todo_dao_test.dart --plain-name "importReplace round-trips"`
  Expected: FAIL — inserted recurrence fields are null (not yet written).

- [ ] **Step 3: Write the recurrence fields in importReplace**

  In `importReplace`, extend the task insert:

  ```dart
  for (final t in c.tasks) {
    await into(tasks).insert(
      TasksCompanion.insert(
        categoryId: categoryId,
        name: t.name,
        sortOrder: t.sortOrder,
        createdAt: t.createdAt,
        archivedAt: Value(t.archivedAt),
        recurrenceCount: Value(t.recurrenceCount),
        recurrenceUnit: Value(t.recurrenceUnit),
        nextDueAt: Value(t.nextDueAt),
      ),
    );
  }
  ```

- [ ] **Step 4: Run to verify it passes**

  Run: `flutter test test/data/todo_dao_test.dart`
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  just lint-ci
  git add lib/data/services/database/todo_dao.dart test/data/todo_dao_test.dart
  git commit -m "feat(dao): importReplace persists recurrence + dormancy"
  ```

---

### Task 6: Repository + ViewModel + startup/resume wake

**Files:**
- Modify: `lib/data/repositories/todo_repository.dart`
- Modify: `lib/ui/home/home_view_model.dart`
- Modify (regenerated): `lib/ui/home/home_view_model.g.dart`
- Modify: `lib/main.dart`
- Modify: `lib/ui/home/home_screen.dart` (resume + archive-open wake only)
- Test: `test/ui/home_view_model_test.dart` (append)

**Interfaces:**
- Consumes: DAO `wakeTask`, `wakeDueTasks`, `renameAndMove(...)` recurrence.
- Produces: `TodoRepository.wakeTask(int)`, `TodoRepository.wakeDueTasks()`,
  `renameAndMove(..., {recurrenceCount, recurrenceUnit})`;
  `HomeViewModel.returnTaskNow(int)`, `HomeViewModel.wakeDueTasks()`,
  `HomeViewModel.editTask(id, name, from, to, {recurrenceCount, recurrenceUnit})`.

- [ ] **Step 1: Extend the repository**

  In `lib/data/repositories/todo_repository.dart`, add the import
  `import '../../domain/recurrence.dart';`, change `renameAndMove`, and add the
  wake pass-throughs:

  ```dart
  Future<void> renameAndMove(
    int id,
    String name,
    int? newCategoryId, {
    int? recurrenceCount,
    RecurrenceUnit? recurrenceUnit,
  }) => _dao.renameAndMove(
    id, name, newCategoryId,
    recurrenceCount: recurrenceCount, recurrenceUnit: recurrenceUnit,
  );

  Future<void> wakeTask(int id) => _dao.wakeTask(id);
  Future<int> wakeDueTasks() => _dao.wakeDueTasks(_clock.now());
  ```

- [ ] **Step 2: Write the failing VM tests**

  Append to `test/ui/home_view_model_test.dart` (a new group; reuse the existing
  `build()` helper). Include
  `import 'package:nooka/domain/recurrence.dart';` at the top:

  ```dart
  group('recurrence', () {
    test('editTask persists recurrence; completing goes dormant', () async {
      final (_, vm) = await build();
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final id = await db.todoDao.createTask(categoryId: cat, name: 'Water');
      expect(
        await vm.editTask(id, 'Water', cat, cat,
            recurrenceCount: 2, recurrenceUnit: RecurrenceUnit.weeks),
        CommandOutcome.success,
      );
      expect(await vm.completeTask(id), CommandOutcome.success);
      final row = await (db.select(db.tasks)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.nextDueAt, isNotNull);
      expect(row.archivedAt, isNull);
    });

    test('returnTaskNow wakes a dormant task', () async {
      final (_, vm) = await build();
      final cat = await db.todoDao.createCategory(name: 'Home', color: 1);
      final id = await db.todoDao.createTask(categoryId: cat, name: 'Water');
      await vm.editTask(id, 'Water', cat, cat,
          recurrenceCount: 1, recurrenceUnit: RecurrenceUnit.days);
      await vm.completeTask(id);
      expect(await vm.returnTaskNow(id), CommandOutcome.success);
      final row = await (db.select(db.tasks)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.nextDueAt, isNull);
    });
  });
  ```

- [ ] **Step 3: Run to verify it fails**

  Run: `flutter test test/ui/home_view_model_test.dart`
  Expected: FAIL — `editTask` has no recurrence params; `returnTaskNow` undefined.

- [ ] **Step 4: Extend the ViewModel**

  In `lib/ui/home/home_view_model.dart`, add
  `import '../../domain/recurrence.dart';`, then change `editTask` and add the
  wake intents:

  ```dart
  Future<CommandOutcome> editTask(
    int id,
    String name,
    int fromCategoryId,
    int toCategoryId, {
    int? recurrenceCount,
    RecurrenceUnit? recurrenceUnit,
  }) => _run(
    () => _repo.renameAndMove(
      id,
      name,
      fromCategoryId == toCategoryId ? null : toCategoryId,
      recurrenceCount: recurrenceCount,
      recurrenceUnit: recurrenceUnit,
    ),
  );

  /// Wakes a dormant recurring task now (undo of a recurring completion, and the
  /// Archive "Return now" action).
  Future<CommandOutcome> returnTaskNow(int id) =>
      _run(() => _repo.wakeTask(id));

  /// Reveals any dormant task whose interval has elapsed. Called at startup and
  /// on resume / archive open, alongside purge.
  Future<CommandOutcome> wakeDueTasks() => _run(() => _repo.wakeDueTasks());
  ```

- [ ] **Step 5: Regenerate Riverpod code**

  Run: `dart run build_runner build --delete-conflicting-outputs`
  Expected: succeeds.

- [ ] **Step 6: Wire startup wake in main.dart**

  In `lib/main.dart`, inside the existing startup-cleanup `try` block, after the
  purge line add:

  ```dart
      final woken = await container.read(todoRepositoryProvider).wakeDueTasks();
      debugPrint('Startup woke $woken due recurring task(s).');
  ```

- [ ] **Step 7: Wire resume + archive-open wake in home_screen.dart**

  In `didChangeAppLifecycleState`, wake on resume before rebuilding:

  ```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _dispatch(_vm.wakeDueTasks());
      setState(() {});
    }
  }
  ```

  In the segmented-button `onSelectionChanged`, wake when opening the archive
  (next to the existing purge):

  ```dart
  onSelectionChanged: (s) {
    setState(() => _view = s.first);
    if (s.first == _View.archive) {
      _dispatch(_vm.purgeExpired());
      _dispatch(_vm.wakeDueTasks());
    }
  },
  ```

- [ ] **Step 8: Run tests**

  Run: `flutter test test/ui/home_view_model_test.dart`
  Expected: PASS. Then `flutter test test/ui/home_screen_test.dart` to confirm no
  regression from the resume/archive wiring.

- [ ] **Step 9: Commit**

  ```bash
  just lint-ci
  git add lib/data/repositories/todo_repository.dart \
          lib/ui/home/home_view_model.dart lib/ui/home/home_view_model.g.dart \
          lib/main.dart lib/ui/home/home_screen.dart \
          test/ui/home_view_model_test.dart
  git commit -m "feat(vm): editTask recurrence, returnTaskNow, startup/resume wake"
  ```

---

### Task 7: Backup format v2 (backward compatible)

**Files:**
- Modify: `lib/domain/models/backup_data.dart`
- Modify: `lib/domain/backup_codec.dart`
- Modify: `lib/ui/settings/settings_view_model.dart` (applyImport wakes due)
- Test: `test/domain/backup_codec_test.dart` (append)

> Run this task BEFORE Task 5 if executing strictly in order (Task 5 consumes
> the new `BackupTask` fields).

**Interfaces:**
- Produces: `BackupTask.recurrenceCount` (`int?`), `.recurrenceUnit`
  (`RecurrenceUnit?`), `.nextDueAt` (`DateTime?`); codec reads/writes them;
  `decodeBackup` accepts versions 1 and 2.

- [ ] **Step 1: Add fields to BackupTask**

  In `lib/domain/models/backup_data.dart`, add the import
  `import '../recurrence.dart';` and extend `BackupTask`:

  ```dart
  class BackupTask {
    const BackupTask({
      required this.name,
      required this.sortOrder,
      required this.createdAt,
      required this.archivedAt,
      this.recurrenceCount,
      this.recurrenceUnit,
      this.nextDueAt,
    });
    final String name;
    final int sortOrder;
    final DateTime createdAt;
    final DateTime? archivedAt; // null = active
    final int? recurrenceCount;
    final RecurrenceUnit? recurrenceUnit;
    final DateTime? nextDueAt; // non-null = dormant
  }
  ```

- [ ] **Step 2: Write the failing codec tests**

  Append to `test/domain/backup_codec_test.dart`
  (`import 'package:nooka/domain/recurrence.dart';`):

  ```dart
  group('v2 recurrence', () {
    test('encodes version 2 and round-trips recurrence + dormancy', () {
      final data = BackupData(
        version: 2,
        exportedAt: DateTime.utc(2026, 7, 4),
        categories: [
          BackupCategory(
            name: 'Home', color: 1, emoji: null, collapsed: false,
            sortOrder: 0, createdAt: DateTime.utc(2026, 1, 1),
            tasks: [
              BackupTask(
                name: 'Water', sortOrder: 0, createdAt: DateTime.utc(2026, 1, 1),
                archivedAt: null,
                recurrenceCount: 3, recurrenceUnit: RecurrenceUnit.weeks,
                nextDueAt: DateTime.utc(2026, 8, 1),
              ),
            ],
          ),
        ],
      );
      final decoded = decodeBackup(encodeBackup(data));
      final t = decoded.categories.single.tasks.single;
      expect(decoded.version, 2);
      expect(t.recurrenceCount, 3);
      expect(t.recurrenceUnit, RecurrenceUnit.weeks);
      expect(t.nextDueAt, DateTime.utc(2026, 8, 1));
    });

    test('a v1 file (no recurrence keys) still decodes with nulls', () {
      const v1 = '''
      {"app":"nooka","version":1,"exportedAt":"2026-07-04T00:00:00.000Z",
       "categories":[{"name":"Home","color":1,"emoji":null,"collapsed":false,
       "sortOrder":0,"createdAt":"2026-01-01T00:00:00.000Z",
       "tasks":[{"name":"Water","sortOrder":0,
       "createdAt":"2026-01-01T00:00:00.000Z","archivedAt":null}]}]}''';
      final decoded = decodeBackup(v1);
      final t = decoded.categories.single.tasks.single;
      expect(decoded.version, 1);
      expect(t.recurrenceCount, isNull);
      expect(t.recurrenceUnit, isNull);
      expect(t.nextDueAt, isNull);
    });
  });
  ```

- [ ] **Step 3: Run to verify it fails**

  Run: `flutter test test/domain/backup_codec_test.dart`
  Expected: FAIL — encoder omits fields; decoder rejects version 1 / drops fields.

- [ ] **Step 4: Update the codec**

  In `lib/domain/backup_codec.dart`, add `import 'recurrence.dart';`, bump the
  version, emit the fields in `encodeBackup` (inside the task map):

  ```dart
  const int _currentVersion = 2;
  // ...
  'archivedAt': t.archivedAt?.toIso8601String(),
  'recurrenceCount': t.recurrenceCount,
  'recurrenceUnit': t.recurrenceUnit?.index,
  'nextDueAt': t.nextDueAt?.toIso8601String(),
  ```

  Accept both versions in `decodeBackup`:

  ```dart
  final version = root['version'];
  if (version is! int || version < 1 || version > _currentVersion) {
    throw BackupFormatException('Unsupported version: ${root['version']}.');
  }
  ```

  Read the fields tolerantly in `_task` (before the `return BackupTask(...)`):

  ```dart
  final recurrenceCount = item['recurrenceCount'];
  if (recurrenceCount != null && recurrenceCount is! int) {
    throw BackupFormatException('Task "$name" has an invalid recurrenceCount.');
  }
  final unitIndex = item['recurrenceUnit'];
  if (unitIndex != null &&
      (unitIndex is! int ||
          unitIndex < 0 ||
          unitIndex >= RecurrenceUnit.values.length)) {
    throw BackupFormatException('Task "$name" has an invalid recurrenceUnit.');
  }
  final nextDueRaw = item['nextDueAt'];
  final nextDueAt =
      nextDueRaw == null ? null : _date(nextDueRaw, 'task "$name" nextDueAt');
  ```

  and pass them:

  ```dart
  return BackupTask(
    name: name,
    sortOrder: sortOrder,
    createdAt: _date(item['createdAt'], 'task "$name" createdAt'),
    archivedAt: archivedAt,
    recurrenceCount: recurrenceCount as int?,
    recurrenceUnit:
        unitIndex == null ? null : RecurrenceUnit.values[unitIndex as int],
    nextDueAt: nextDueAt,
  );
  ```

  In `buildBackup`, populate the new fields from the row:

  ```dart
  BackupTask(
    name: t.name,
    sortOrder: t.sortOrder,
    createdAt: t.createdAt,
    archivedAt: t.archivedAt,
    recurrenceCount: t.recurrenceCount,
    recurrenceUnit: t.recurrenceUnit,
    nextDueAt: t.nextDueAt,
  ),
  ```

- [ ] **Step 5: Wake already-due tasks after import**

  In `lib/ui/settings/settings_view_model.dart`, after the successful
  `importReplace` + `RememberedCategory.forget()` in `applyImport`, add a
  best-effort wake so a restored, already-due dormant task appears immediately.
  Locate the `applyImport` success path and add:

  ```dart
  await ref.read(todoRepositoryProvider).wakeDueTasks();
  ```

  (Match the file's existing repo access pattern; if it already holds a repo
  reference, reuse it. Keep it inside the same try so a failure logs like the
  others.)

- [ ] **Step 6: Run tests**

  Run: `flutter test test/domain/backup_codec_test.dart`
  Expected: PASS. Then `flutter test test/data/backup_repository_test.dart
  test/ui/settings_view_model_test.dart` to confirm no regression (update any
  test that hard-asserts `version == 1` to expect `2` for fresh exports).

- [ ] **Step 7: Commit**

  ```bash
  just lint-ci
  git add lib/domain/models/backup_data.dart lib/domain/backup_codec.dart \
          lib/ui/settings/settings_view_model.dart \
          test/domain/backup_codec_test.dart
  git commit -m "feat(backup): format v2 with recurrence, still imports v1"
  ```

---

### Task 8: Localization keys (EN + RU)

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_ru.arb`
- Modify (regenerated): `lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces: `l10n.repeatLabel`, `l10n.recurrenceUnitDays/Weeks/Months`,
  `l10n.recurrenceEvery(count, unit)`, `l10n.recurrenceSummary(count, unit)`,
  `l10n.returnsInDays(count)`, `l10n.returnNow`. `unit` is passed as the enum's
  `.name` ("days" | "weeks" | "months").

- [ ] **Step 1: Add EN keys**

  In `lib/l10n/app_en.arb` add (keep valid JSON — mind commas):

  ```json
  "repeatLabel": "Repeat",
  "recurrenceUnitDays": "Days",
  "recurrenceUnitWeeks": "Weeks",
  "recurrenceUnitMonths": "Months",
  "returnNow": "Return now",
  "recurrenceEvery": "Every {unit, select, days{{count, plural, one{{count} day} other{{count} days}}} weeks{{count, plural, one{{count} week} other{{count} weeks}}} months{{count, plural, one{{count} month} other{{count} months}}} other{}}",
  "@recurrenceEvery": {
    "placeholders": { "count": { "type": "int" }, "unit": { "type": "String" } }
  },
  "recurrenceSummary": "Returns {unit, select, days{{count, plural, one{{count} day} other{{count} days}}} weeks{{count, plural, one{{count} week} other{{count} weeks}}} months{{count, plural, one{{count} month} other{{count} months}}} other{}} after you complete it.",
  "@recurrenceSummary": {
    "placeholders": { "count": { "type": "int" }, "unit": { "type": "String" } }
  },
  "returnsInDays": "Returns in {count, plural, =0{under a day} one{{count} day} other{{count} days}}",
  "@returnsInDays": {
    "placeholders": { "count": { "type": "int" } }
  }
  ```

- [ ] **Step 2: Add RU keys**

  In `lib/l10n/app_ru.arb` add the parallel keys with full CLDR forms. Provide
  these as the baseline (Artur may refine the wording later):

  ```json
  "repeatLabel": "Повтор",
  "recurrenceUnitDays": "Дни",
  "recurrenceUnitWeeks": "Недели",
  "recurrenceUnitMonths": "Месяцы",
  "returnNow": "Вернуть сейчас",
  "recurrenceEvery": "Каждые {unit, select, days{{count, plural, one{{count} день} few{{count} дня} many{{count} дней} other{{count} дня}}} weeks{{count, plural, one{{count} неделю} few{{count} недели} many{{count} недель} other{{count} недели}}} months{{count, plural, one{{count} месяц} few{{count} месяца} many{{count} месяцев} other{{count} месяца}}} other{}}",
  "recurrenceSummary": "Вернётся через {unit, select, days{{count, plural, one{{count} день} few{{count} дня} many{{count} дней} other{{count} дня}}} weeks{{count, plural, one{{count} неделю} few{{count} недели} many{{count} недель} other{{count} недели}}} months{{count, plural, one{{count} месяц} few{{count} месяца} many{{count} месяцев} other{{count} месяца}}} other{}} после выполнения.",
  "returnsInDays": "Вернётся через {count, plural, =0{меньше суток} one{{count} день} few{{count} дня} many{{count} дней} other{{count} дня}}"
  }
  ```

  (RU ARB has no `@`-metadata section — it mirrors the template; keep JSON valid.)

- [ ] **Step 3: Regenerate localizations**

  Run: `dart run build_runner build --delete-conflicting-outputs`
  (or `flutter gen-l10n` if that is how the repo generates — check the Justfile).
  Expected: succeeds; `AppLocalizations` gains the new getters/methods. If
  gen-l10n rejects the nested `select`+`plural`, split `recurrenceEvery` /
  `recurrenceSummary` into three per-unit plural keys
  (`recurrenceEveryDays/Weeks/Months`, `recurrenceSummaryDays/Weeks/Months`) and
  select the key by unit in Dart.

- [ ] **Step 4: Verify it builds**

  Run: `flutter analyze lib/l10n`
  Expected: no errors.

- [ ] **Step 5: Commit**

  ```bash
  just lint-ci
  git add lib/l10n/
  git commit -m "feat(i18n): recurrence strings (EN + RU plurals)"
  ```

---

### Task 9: Edit dialog Repeat control + active recurring sub-line

**Files:**
- Modify: `lib/ui/widgets/task_dialog.dart`
- Modify: `lib/ui/home/widgets/task_row_content.dart`
- Test: `test/ui/task_dialog_test.dart` (append), `test/ui/task_row_content_test.dart` (append)

**Interfaces:**
- Consumes: `RecurrenceUnit`, l10n keys (Task 8).
- Produces: `TaskDialogResult.recurrenceCount` (`int?`),
  `.recurrenceUnit` (`RecurrenceUnit?`); `showTaskDialog(..., {int?
  initialRecurrenceCount, RecurrenceUnit? initialRecurrenceUnit})`.

- [ ] **Step 1: Write the failing dialog test**

  Append to `test/ui/task_dialog_test.dart` a test that opens the edit dialog,
  toggles Repeat on, and asserts the result carries recurrence. Follow the
  file's existing harness for pumping `showTaskDialog`. Assert:
  - a `Key('task-repeat-toggle')` switch exists;
  - toggling it on reveals `Key('task-repeat-stepper')` and the unit segmented
    control `Key('task-repeat-unit')`;
  - confirming returns `TaskDialogResult` with `recurrenceCount == 1`,
    `recurrenceUnit == RecurrenceUnit.days` (the default when first enabled).

- [ ] **Step 2: Run to verify it fails**

  Run: `flutter test test/ui/task_dialog_test.dart`
  Expected: FAIL — no repeat toggle; `TaskDialogResult` has no recurrence fields.

- [ ] **Step 3: Extend TaskDialogResult + _TaskDialog**

  In `lib/ui/widgets/task_dialog.dart`:

  - Add the import `import '../../domain/recurrence.dart';`.
  - Extend the result:

    ```dart
    class TaskDialogResult {
      TaskDialogResult(
        this.name,
        this.categoryId, {
        this.recurrenceCount,
        this.recurrenceUnit,
      });
      final String name;
      final int categoryId;
      final int? recurrenceCount;
      final RecurrenceUnit? recurrenceUnit;
    }
    ```

  - Add the params to `showTaskDialog` and pass them to `_TaskDialog`:

    ```dart
    Future<TaskDialogResult?> showTaskDialog(
      BuildContext context, {
      required List<Category> categories,
      required int initialCategoryId,
      String? initialName,
      int? initialRecurrenceCount,
      RecurrenceUnit? initialRecurrenceUnit,
    }) {
      return showDialog<TaskDialogResult>(
        context: context,
        builder: (_) => _TaskDialog(
          categories: categories,
          initialCategoryId: initialCategoryId,
          initialName: initialName ?? '',
          initialRecurrenceCount: initialRecurrenceCount,
          initialRecurrenceUnit: initialRecurrenceUnit,
        ),
      );
    }
    ```

  - In `_TaskDialog` add matching fields, and state:

    ```dart
    late bool _repeat = widget.initialRecurrenceCount != null;
    late int _count = widget.initialRecurrenceCount ?? 1;
    late RecurrenceUnit _unit =
        widget.initialRecurrenceUnit ?? RecurrenceUnit.days;
    ```

  - After the category dropdown, add the control (inside the `Column` children):

    ```dart
    const SizedBox(height: 8),
    SwitchListTile(
      key: const Key('task-repeat-toggle'),
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.repeatLabel),
      value: _repeat,
      onChanged: (v) => setState(() => _repeat = v),
    ),
    if (_repeat) ...[
      Row(
        key: const Key('task-repeat-stepper'),
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: _count > 1 ? () => setState(() => _count--) : null,
          ),
          Text('$_count'),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => setState(() => _count++),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SegmentedButton<RecurrenceUnit>(
              key: const Key('task-repeat-unit'),
              segments: [
                ButtonSegment(
                  value: RecurrenceUnit.days,
                  label: Text(l10n.recurrenceUnitDays),
                ),
                ButtonSegment(
                  value: RecurrenceUnit.weeks,
                  label: Text(l10n.recurrenceUnitWeeks),
                ),
                ButtonSegment(
                  value: RecurrenceUnit.months,
                  label: Text(l10n.recurrenceUnitMonths),
                ),
              ],
              selected: {_unit},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.recurrenceSummary(_count, _unit.name),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
    ```

  - In the confirm button, return recurrence when enabled:

    ```dart
    Navigator.pop(
      context,
      TaskDialogResult(
        name,
        _categoryId,
        recurrenceCount: _repeat ? _count : null,
        recurrenceUnit: _repeat ? _unit : null,
      ),
    );
    ```

- [ ] **Step 4: Run dialog test**

  Run: `flutter test test/ui/task_dialog_test.dart`
  Expected: PASS.

- [ ] **Step 5: Add the active recurring sub-line + failing test**

  Append to `test/ui/task_row_content_test.dart` a test: a non-archived task
  with `recurrenceCount: 3, recurrenceUnit: RecurrenceUnit.weeks` renders a
  subtitle containing the localized "Every 3 weeks". Then implement in
  `lib/ui/home/widgets/task_row_content.dart` — compute state and set the
  subtitle for active recurring rows:

  ```dart
  final archived = task.archivedAt != null;
  final dormant = task.archivedAt == null && task.nextDueAt != null;
  final recurring =
      task.recurrenceCount != null && task.recurrenceUnit != null;
  // ...
  subtitle: archived
      ? Text(
          '${l10n.completedOn(DateFormat.yMMMd(localeName).format(task.archivedAt!))}'
          ' · ${l10n.autoRemovesIn(daysRemaining(task.archivedAt!, now))}',
        )
      : dormant
          ? Text('🔁 ${l10n.returnsInDays(daysUntilDue(task.nextDueAt!, now))}')
          : recurring
              ? Text('🔁 ${l10n.recurrenceEvery(task.recurrenceCount!, task.recurrenceUnit!.name)}')
              : null,
  ```

  Add imports: `import '../../../domain/recurrence.dart';`. `daysUntilDue` comes
  from `recurrence.dart`; `daysRemaining` from `archive.dart` (already imported).
  Also set the leading icon for dormant rows (e.g. `Icons.schedule` in `color`).

- [ ] **Step 6: Run row test**

  Run: `flutter test test/ui/task_row_content_test.dart`
  Expected: PASS.

- [ ] **Step 7: Commit**

  ```bash
  just lint-ci
  git add lib/ui/widgets/task_dialog.dart lib/ui/home/widgets/task_row_content.dart \
          test/ui/task_dialog_test.dart test/ui/task_row_content_test.dart
  git commit -m "feat(ui): edit-dialog Repeat control + recurring sub-line"
  ```

---

### Task 10: Wire recurrence through home_screen (edit + archive dormant actions)

**Files:**
- Modify: `lib/ui/home/home_screen.dart`
- Test: `test/ui/home_screen_test.dart` (append)

**Interfaces:**
- Consumes: `showTaskDialog(..., initialRecurrence*)`, `TaskDialogResult`
  recurrence, `HomeViewModel.editTask(..., recurrence*)`, `returnTaskNow`,
  `deleteTask`, `restoreTask`, `dormantTasks`, `daysUntilDue`, l10n keys.

- [ ] **Step 1: Write the failing widget tests**

  Append to `test/ui/home_screen_test.dart`:
  1. Editing an active task, toggling Repeat on and saving, then completing it,
     removes it from Active; switching to Archive shows a row with the localized
     "Returns in" text.
  2. In the Archive, tapping a dormant row opens a sheet with "Return now" and
     "Delete"; tapping "Return now" returns the task to Active.

  Follow the file's existing pump/harness conventions (in-memory DB overrides).

- [ ] **Step 2: Run to verify it fails**

  Run: `flutter test test/ui/home_screen_test.dart`
  Expected: FAIL — dormant tasks not rendered; edit passes no recurrence.

- [ ] **Step 3: Pass recurrence through the edit menu**

  In `_taskMenu`'s `'edit'` case, seed and forward recurrence:

  ```dart
  final r = await showTaskDialog(
    context,
    categories: [for (final c in cats) c.category],
    initialCategoryId: task.categoryId,
    initialName: task.name,
    initialRecurrenceCount: task.recurrenceCount,
    initialRecurrenceUnit: task.recurrenceUnit,
  );
  if (r != null) {
    await _dispatch(
      _vm.editTask(
        task.id, r.name, task.categoryId, r.categoryId,
        recurrenceCount: r.recurrenceCount,
        recurrenceUnit: r.recurrenceUnit,
      ),
    );
  }
  ```

- [ ] **Step 4: Route the completion undo by recurrence**

  In `_complete`, change the undo callback:

  ```dart
  _showUndoToast(
    message,
    () => task.recurrenceCount != null
        ? _dispatch(_vm.returnTaskNow(task.id))
        : _dispatch(_vm.restoreTask(task.id)),
  );
  ```

- [ ] **Step 5: Render dormant tasks in the Archive with a tap action sheet**

  In `_body`, widen the archive `visible` filter and the tasks passed, and route
  taps:

  ```dart
  final visible = archived
      ? [
          for (final cwt in cats)
            if (cwt.archivedTasks.isNotEmpty || cwt.dormantTasks.isNotEmpty) cwt,
        ]
      : cats;
  // ...
  CategorySection(
    category: cwt.category,
    tasks: [...cwt.dormantTasks, ...cwt.archivedTasks],
    archived: true,
    now: now,
    onToggleCollapsed: () => _dispatch(
      _vm.toggleCollapsed(cwt.category.id, !cwt.category.collapsed),
    ),
    onHeaderMenu: () => _categoryMenu(cwt),
    onTaskTap: (t) =>
        t.nextDueAt != null ? _dormantActions(t) : _restore(t),
    onTaskMenu: null,
  ),
  ```

  Add the action sheet:

  ```dart
  Future<void> _dormantActions(Task task) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('dormant-return-now'),
              leading: const Icon(Icons.undo),
              title: Text(l10n.returnNow),
              onTap: () => Navigator.pop(context, 'return'),
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(l10n.delete),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'return':
        await _dispatch(_vm.returnTaskNow(task.id));
      case 'delete':
        await _dispatch(_vm.deleteTask(task.id));
    }
  }
  ```

- [ ] **Step 6: Run tests**

  Run: `flutter test test/ui/home_screen_test.dart`
  Expected: PASS.

- [ ] **Step 7: Commit**

  ```bash
  just lint-ci
  git add lib/ui/home/home_screen.dart test/ui/home_screen_test.dart
  git commit -m "feat(ui): wire recurrence edit + Archive dormant actions"
  ```

---

### Task 11: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Regenerate + full lint + test + coverage**

  Run in order:
  ```bash
  dart run build_runner build --delete-conflicting-outputs
  just lint-ci
  just test
  just coverage
  ```
  Expected: all pass, coverage stays at/above the gate. If coverage dips, add
  targeted tests (e.g. codec v1-decode already covers the compat branch; add a
  `daysUntilDue` clamp case or a dormant-row widget assertion as needed).

- [ ] **Step 2: Commit any test additions**

  ```bash
  just lint-ci
  git add -A
  git commit -m "test(recurrence): close coverage gaps"
  ```

---

### Task 12: Architecture promotion + finalize summary

**Files:**
- Modify: `architecture/data-model.md`, `architecture/archive.md`,
  `architecture/home-coordination.md`, `architecture/backup-io.md`,
  `architecture/i18n-theming.md`
- Modify: `planning/changes/2026-07-04.01-recurring-tasks/design.md` (frontmatter
  `summary` → realized result)

- [ ] **Step 1: Hand-edit each architecture doc**

  Apply the edits enumerated in the spec's "Architecture docs to update"
  section — current-state prose (not changelog), one capability per file:
  - `data-model.md`: three recurrence columns; active/dormant/archived
    derivation; recurring completion sets `nextDueAt` (keeps slot, no renumber);
    wake clears it; `_nextTaskOrder` ignores dormant rows.
  - `archive.md`: dormant tasks shown as "Returns in N days"; wake at
    startup/resume/archive-open alongside purge; purge & "Clear archive" skip
    dormant; Return now / Delete actions.
  - `home-coordination.md`: `editTask` recurrence params; `returnTaskNow` and
    `wakeDueTasks` intents; completion undo routing.
  - `backup-io.md`: format v2 task fields; decoder accepts v1 + v2; applyImport
    wakes already-due restored tasks. Update the task-object field table.
  - `i18n-theming.md`: list the new recurrence keys (EN + RU plurals).

- [ ] **Step 2: Finalize the bundle summary**

  Confirm the `summary:` line in `design.md` states the realized result (it
  already does). Adjust only if scope shifted during implementation.

- [ ] **Step 3: Validate planning + final gate**

  ```bash
  just check-planning
  just lint-ci
  just test
  ```
  Expected: `planning: OK`; lint clean; tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add architecture/ planning/changes/2026-07-04.01-recurring-tasks/design.md
  git commit -m "docs(architecture): promote recurring-tasks behavior"
  ```

- [ ] **Step 5: Push and open the PR**

  ```bash
  git push -u origin feat/recurring-tasks
  gh pr create --fill
  ```
  Then watch CI to green (per project workflow: PR, never local-merge).

---

## Self-Review

**Spec coverage:** model + states (Tasks 2, 3) · pure interval math (Task 1) ·
DAO complete/wake/order (Task 4) · import persistence (Task 5) · repo/VM +
startup/resume wake (Task 6) · backup v2 backward-compat (Task 7) · i18n
(Task 8) · edit control + sub-line (Task 9) · archive dormant UI + undo routing
(Task 10) · verification (Task 11) · architecture promotion (Task 12). Every
spec section maps to a task.

**Ordering note:** Task 5 consumes `BackupTask` fields added in Task 7 — run
Task 7 before Task 5 if executing strictly in sequence (both are flagged
inline). Task 4 defines the `renameAndMove` recurrence signature so its own
tests compile; Task 5/6 build on it.

**Type consistency:** `RecurrenceUnit` everywhere; `nextDueDate` /
`daysUntilDue` names stable from Task 1 through Tasks 4/9; `recurrenceCount:int?`,
`recurrenceUnit:RecurrenceUnit?`, `nextDueAt:DateTime?` consistent across table,
row, backup, codec, dialog result. VM `editTask` optional recurrence params keep
existing call sites compiling until Task 10 supplies real values.
