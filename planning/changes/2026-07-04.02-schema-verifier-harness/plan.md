# Schema-verifier migration harness — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-written raw-SQL migration test with Drift's
schema-snapshot tooling — exported per-version schemas, generated
`SchemaVerifier` tests (schema + data integrity), and a `stepByStep` `onUpgrade`
pinned to the v2 schema.

**Spec:** [`design.md`](./design.md)

**Branch:** `chore/schema-verifier-harness` (already created and checked out;
the design.md commit is on it).

**Commit strategy:** Per-task commits. The migration refactor is
behavior-preserving; the new tests replace the old.

## Global Constraints

- Stack: Flutter, Drift `^2.34.0` + `drift_dev ^2.34.0` (dev-dependency — it
  MUST stay dev-only; do not move it to `dependencies`), sqlite3, `just`.
- Generated Dart is committed. Generated files in this change:
  `drift_schemas/*.json`, `lib/data/services/database/database.steps.dart`,
  `test/generated_migrations/*.dart`.
- The `stepByStep` migration must be **behavior-identical** to the shipped 1→2
  migration (the same three `addColumn`s); `schemaVersion` stays `2`; the
  `beforeOpen` `PRAGMA foreign_keys = ON` is preserved.
- The runtime `validateDatabaseSchema()` guard is explicitly OUT of scope (it
  would force drift_dev into runtime deps).
- Migration steps reference the **pinned** generated `schema` parameter
  (`schema.tasks.*`), never the live `tasks` table.
- Imports at module level; annotate function arguments.
- Before every commit: `just lint-ci` clean (NOT `just lint`), `just test` green,
  and `just coverage` at the 100% gate. `just check-planning` OK for the docs task.
- Conventional commits; no "Claude Code" in the body; end each commit body with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- drift_dev command reference (all run from the repo root unless noted):
  - dump:     `dart run drift_dev schema dump lib/data/services/database/database.dart drift_schemas/`
  - steps:    `dart run drift_dev schema steps drift_schemas/ lib/data/services/database/database.steps.dart`
  - generate: `dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated_migrations/`

---

### Task 1: Export the v1 and v2 schema snapshots

**Files:**
- Create: `drift_schemas/drift_schema_v1.json` (dumped from commit `8506235`)
- Create: `drift_schema_v2.json` under `drift_schemas/` (dumped from `main`/HEAD)

Produces the authentic per-version snapshots every later task consumes. No app
code changes.

- [ ] **Step 1: Dump the current (v2) schema**

  ```bash
  mkdir -p drift_schemas
  dart run drift_dev schema dump lib/data/services/database/database.dart drift_schemas/
  ```
  Expected: writes `drift_schemas/drift_schema_v2.json` (the command keys the
  filename by the code's current `schemaVersion`, which is 2). If the tool errors
  that it can't find generated code, run `dart run build_runner build --delete-conflicting-outputs` first, then retry.

- [ ] **Step 2: Dump the v1 schema from the pre-migration commit via a worktree**

  ```bash
  WT=/private/tmp/claude-501/-Users-kevinsmith-src-tasks/b0b269ba-81c9-42f9-8387-9e27c9c9a4e3/scratchpad/schema-v1-worktree
  REPO=$(git rev-parse --show-toplevel)
  git worktree add "$WT" 8506235
  ( cd "$WT" && flutter pub get && \
    dart run drift_dev schema dump lib/data/services/database/database.dart "$REPO/drift_schemas/" )
  git worktree remove "$WT" --force
  git worktree prune
  ```
  Expected: writes `drift_schemas/drift_schema_v1.json` (that worktree's
  `schemaVersion` is 1). The worktree is removed afterward; only the JSON lands
  in the main tree.

- [ ] **Step 3: Verify the snapshots are correct and distinct**

  ```bash
  ls drift_schemas/
  grep -c recurrence_count drift_schemas/drift_schema_v1.json   # expect 0
  grep -c recurrence_count drift_schemas/drift_schema_v2.json   # expect >= 1
  ```
  Expected: both files present; v1 has NO `recurrence_count` column, v2 has it.
  (Column names in the JSON are snake_case.)

- [ ] **Step 4: Commit**

  ```bash
  git add drift_schemas/
  git commit -m "chore(db): export v1 + v2 drift schema snapshots"
  ```

---

### Task 2: Convert onUpgrade to stepByStep

**Files:**
- Create: `lib/data/services/database/database.steps.dart` (generated)
- Modify: `lib/data/services/database/database.dart`
- Modify: `coverde.yaml`

**Interfaces:**
- Consumes: `drift_schemas/` from Task 1.
- Produces: `database.steps.dart` exporting `stepByStep(from1To2: ...)` and the
  pinned `Schema2` type whose `.tasks` exposes `recurrenceCount` / `recurrenceUnit`
  / `nextDueAt` columns.

- [ ] **Step 1: Generate the step-by-step helper**

  ```bash
  dart run drift_dev schema steps drift_schemas/ lib/data/services/database/database.steps.dart
  ```
  Expected: creates `lib/data/services/database/database.steps.dart` (contains
  `stepByStep`, `Schema1`, `Schema2`).

- [ ] **Step 2: Wire stepByStep into database.dart**

  Replace the body of `lib/data/services/database/database.dart` with (keep the
  existing imports, add the steps import):

  ```dart
  import 'package:drift/drift.dart';

  import '../../../domain/recurrence.dart';
  import 'connection.dart';
  import 'database.steps.dart';
  import 'tables.dart';
  import 'todo_dao.dart';

  part 'database.g.dart';

  @DriftDatabase(tables: [Categories, Tasks], daos: [TodoDao])
  class AppDatabase extends _$AppDatabase {
    AppDatabase([QueryExecutor? executor]) : super(resolveExecutor(executor));

    @override
    int get schemaVersion => 2;

    // Extracted to a static field with an inferred type so the step closes over
    // the *pinned* v2 schema snapshot (via its `schema` parameter), never the
    // live database schema — drift's recommended structure.
    static final _upgrade = stepByStep(
      from1To2: (m, schema) async {
        await m.addColumn(schema.tasks, schema.tasks.recurrenceCount);
        await m.addColumn(schema.tasks, schema.tasks.recurrenceUnit);
        await m.addColumn(schema.tasks, schema.tasks.nextDueAt);
      },
    );

    @override
    MigrationStrategy get migration => MigrationStrategy(
      onUpgrade: _upgrade,
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
  ```

  If `stepByStep`, the `from1To2` parameter name, or `schema.tasks.<col>` getters
  differ from the generated `database.steps.dart`, match the generated API
  verbatim (use `var`/`final` inference for `_upgrade`, no explicit type
  annotation). Do NOT add an `onCreate` — the base `_$AppDatabase` default
  (`m.createAll()`) is unchanged.

- [ ] **Step 3: Exclude the generated steps file from coverage**

  In `coverde.yaml`, add after the `tables.dart` glob (line ~18):

  ```yaml
    - type: skip-by-glob
      glob: "**/data/services/database/database.steps.dart"
  ```

- [ ] **Step 4: Verify it compiles and behavior is unchanged**

  ```bash
  flutter analyze lib/data/services/database/
  flutter test test/data/migration_test.dart
  ```
  Expected: analyze clean; the EXISTING raw-SQL migration test still PASSES
  (the stepByStep migration performs the identical three `addColumn`s). If the
  test fails, the migration behavior diverged — do not proceed; fix or report.

- [ ] **Step 5: Full gates**

  ```bash
  just test
  just coverage
  just lint-ci
  ```
  Expected: all green; coverage 100% (database.steps.dart now excluded;
  database.dart's `_upgrade` is exercised by the migration test).

- [ ] **Step 6: Commit**

  ```bash
  git add lib/data/services/database/database.dart \
          lib/data/services/database/database.steps.dart coverde.yaml
  git commit -m "refactor(db): stepByStep onUpgrade pinned to v2 schema"
  ```

---

### Task 3: SchemaVerifier migration tests

**Files:**
- Create: `test/generated_migrations/schema.dart`, `schema_v1.dart`,
  `schema_v2.dart` (generated)
- Rewrite: `test/data/migration_test.dart`

**Interfaces:**
- Consumes: `drift_schemas/` (Task 1); `AppDatabase` migration (Task 2);
  generated `GeneratedHelper`, `v1.DatabaseAtV1`/`v1.CategoriesCompanion`/
  `v1.TasksCompanion`, `v2.DatabaseAtV2`.

- [ ] **Step 1: Generate the verifier + versioned helpers**

  ```bash
  dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated_migrations/
  ls test/generated_migrations/
  ```
  Expected: creates `schema.dart` (with `GeneratedHelper`) plus `schema_v1.dart`
  and `schema_v2.dart`. If the generated filenames differ, note the actual names
  and adjust the imports in Step 2 accordingly.

- [ ] **Step 2: Rewrite the migration test with SchemaVerifier**

  Replace the entire contents of `test/data/migration_test.dart`:

  ```dart
  import 'package:drift_dev/api/migrations_native.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nooka/data/services/database/database.dart';

  import '../generated_migrations/schema.dart';
  import '../generated_migrations/schema_v1.dart' as v1;
  import '../generated_migrations/schema_v2.dart' as v2;

  void main() {
    late SchemaVerifier verifier;

    setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

    test('migrates v1 -> v2 to the declared schema', () async {
      final connection = await verifier.startAt(1);
      final db = AppDatabase(connection);
      // Fails if the migrated database does not match the declared v2 schema.
      await verifier.migrateAndValidate(db, 2);
      await db.close();
    });

    test('v1 -> v2 preserves rows and defaults recurrence to null', () async {
      final schema = await verifier.schemaAt(1);

      // Seed a category + task using the v1 schema.
      final oldDb = v1.DatabaseAtV1(schema.newConnection());
      final catId = await oldDb.into(oldDb.categories).insert(
            v1.CategoriesCompanion.insert(
              name: 'Home',
              color: 1,
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          );
      await oldDb.into(oldDb.tasks).insert(
            v1.TasksCompanion.insert(
              categoryId: catId,
              name: 'Water plants',
              sortOrder: 0,
              createdAt: DateTime(2026, 1, 1),
            ),
          );
      await oldDb.close();

      // Run the migration through the real AppDatabase.
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 2);
      await db.close();

      // Read back with the v2 schema: row survived, recurrence columns null.
      final migrated = v2.DatabaseAtV2(schema.newConnection());
      final t = await migrated.select(migrated.tasks).getSingle();
      expect(t.name, 'Water plants');
      expect(t.recurrenceCount, isNull);
      expect(t.recurrenceUnit, isNull);
      expect(t.nextDueAt, isNull);
      await migrated.close();
    });
  }
  ```

  If the generated companion constructors require different named args (e.g. a
  different required set for v1 `CategoriesCompanion`/`TasksCompanion`), match the
  generated `schema_v1.dart` signatures. The old raw-SQL `sqlite3`-based test is
  fully removed by this overwrite.

- [ ] **Step 3: Run the new tests**

  ```bash
  flutter test test/data/migration_test.dart
  ```
  Expected: both tests PASS.

- [ ] **Step 4: Fault-injection sanity check (prove the harness isn't vacuous)**

  Temporarily break the migration: in `database.dart`, comment out the
  `schema.tasks.recurrenceCount` `addColumn` line in `from1To2`. Then:

  ```bash
  flutter test test/data/migration_test.dart
  ```
  Expected: the `migrates v1 -> v2 to the declared schema` test now FAILS
  (`migrateAndValidate` reports the migrated schema is missing a column). Record
  the observed failure message in the task report. Then **revert** the change
  (restore the line) and re-run:

  ```bash
  flutter test test/data/migration_test.dart
  ```
  Expected: PASS again. Confirm `git diff lib/data/services/database/database.dart`
  is empty before committing.

- [ ] **Step 5: Full gates**

  ```bash
  just test
  just coverage
  just lint-ci
  ```
  Expected: all green; coverage still 100% (`test/generated_migrations/` is under
  `test/`, which `flutter test --coverage` does not instrument, so no exclusion
  is needed for it).

- [ ] **Step 6: Commit**

  ```bash
  git add test/generated_migrations/ test/data/migration_test.dart
  git commit -m "test(db): SchemaVerifier migration tests (schema + data integrity)"
  ```

---

### Task 4: Developer workflow + docs

**Files:**
- Modify: `Justfile`
- Modify: `architecture/data-model.md`
- Modify: `planning/deferred.md`

- [ ] **Step 1: Add Justfile targets for the schema ritual**

  Append to `Justfile`:

  ```makefile
  # Dump the current schema snapshot into drift_schemas/ (run after bumping
  # schemaVersion, before generating steps).
  schema-dump:
      dart run drift_dev schema dump lib/data/services/database/database.dart drift_schemas/

  # Regenerate migration step helpers + SchemaVerifier test helpers from the
  # snapshots in drift_schemas/.
  schema-gen:
      dart run drift_dev schema steps drift_schemas/ lib/data/services/database/database.steps.dart
      dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated_migrations/
  ```
  (Use tab/4-space recipe indentation matching the existing recipes.)

- [ ] **Step 2: Verify the new recipes run**

  ```bash
  just --list | grep -E "schema-dump|schema-gen"
  just schema-gen
  git status --porcelain   # expect no changes: regeneration is idempotent
  ```
  Expected: both recipes listed; `just schema-gen` reproduces the committed
  generated files with no diff.

- [ ] **Step 3: Promote to architecture/data-model.md**

  Append a short paragraph to `architecture/data-model.md` (present-tense truth,
  no changelog):

  ```markdown
  Migrations use Drift's `stepByStep` `onUpgrade` (`database.steps.dart`), whose
  steps run against the *pinned* schema snapshot for their version, and are
  verified by `SchemaVerifier` (`test/data/migration_test.dart`) against the
  per-version snapshots in `drift_schemas/` — checking both that each version
  migrates to the declared current schema and that data survives. Per-migration
  ritual after bumping `schemaVersion` and writing a `fromNToN+1` step:
  `just schema-dump` then `just schema-gen`, and commit the regenerated files.
  ```

- [ ] **Step 4: Update planning/deferred.md**

  Edit the "Runtime schema self-check + migration tests" bullet: the
  migration-test harness is now done; only the runtime guard remains deferred.
  Replace that bullet with:

  ```markdown
  - **Runtime schema self-check** — Drift's debug-only
    `validateDatabaseSchema()` in `beforeOpen`. Not adopted with the migration
    harness (2026-07-04.02) because it forces `drift_dev` into the app's runtime
    dependencies for a check the CI `SchemaVerifier` harness already covers.
    *Revisit when* a code-vs-DB schema mismatch slips past CI in practice, or if
    drift ships a lighter runtime-only validation path.
  ```

- [ ] **Step 5: Validate + commit**

  ```bash
  just check-planning
  just lint-ci
  git add Justfile architecture/data-model.md planning/deferred.md
  git commit -m "docs(db): schema-harness workflow, promote to architecture, update deferred"
  ```
  Expected: `planning: OK`; lint clean.

---

## Self-Review

**Spec coverage:** snapshots — Task 1; generated harness helpers — Task 3;
stepByStep migration pinned to v2 — Task 2; SchemaVerifier schema + data-integrity
tests replacing the raw-SQL test — Task 3; fault-injection sanity check — Task 3
Step 4; coverde exclusion for `database.steps.dart` — Task 2; Justfile ritual +
`data-model.md` promotion + `deferred.md` update — Task 4; runtime guard
explicitly out of scope — honored (no `validateDatabaseSchema`, drift_dev stays
dev-only). Every spec section maps to a task.

**Ordering:** Task 1 (snapshots) → Task 2 (steps file + migration) and Task 3
(verifier helpers + tests) both consume the snapshots; Task 2 before Task 3 so
the migration under test exists first (Task 3's fault-injection edits the Task 2
code). Task 4 is docs/workflow last.

**Placeholder scan:** no TBDs; every code/command step is concrete. The one
flagged uncertainty (exact generated `stepByStep`/companion signatures) is
handled by "match the generated API verbatim" instructions, since the generator
output can't be transcribed until it runs.

**Type consistency:** `AppDatabase`, `schemaVersion => 2`, the three columns
`recurrenceCount`/`recurrenceUnit`/`nextDueAt`, and `GeneratedHelper` /
`DatabaseAtV1` / `DatabaseAtV2` names are used consistently across tasks and
match the drift 2.34 tooling output.
