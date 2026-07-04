---
summary: Adopt Drift's schema-snapshot migration harness — exported per-version schemas, generated SchemaVerifier tests (schema + data integrity), and a stepByStep onUpgrade pinned to the v2 schema — replacing the hand-written raw-SQL migration test.
---

# Design: Schema-verifier migration harness

## Summary

Replace nooka's hand-written raw-SQL migration test with Drift's official
schema-snapshot tooling. We export a JSON schema snapshot per `schemaVersion`
into `drift_schemas/`, generate `SchemaVerifier` helpers into
`test/generated_migrations/`, and rewrite `test/data/migration_test.dart` to
verify — against authentic generated snapshots — that every prior schema
migrates to the declared current schema **and** preserves data. We also convert
the `onUpgrade` body to the modern `stepByStep` helper, whose migration steps
run against a *pinned* schema snapshot rather than the live one. The runtime
`validateDatabaseSchema()` guard is deliberately **not** adopted (it would force
`drift_dev` into the app's runtime dependencies); the CI harness covers the same
risk. This is the deferred "runtime schema self-check + migration tests" item,
whose revisit trigger ("first real migration lands, `schemaVersion` reaches 2")
fired with the 1.3.0 recurring-tasks release.

## Motivation

The recurring-tasks release shipped nooka's first real migration
(`schemaVersion` 1 → 2, adding three columns to `Tasks`). It is covered today by
a single hand-written test (`test/data/migration_test.dart`) that fabricates a
v1 database from **hand-typed raw SQL DDL** (snake_case column names, an assumed
`DateTime`-as-int storage) and asserts the upgrade. That approach has two
problems that compound with every future migration:

- **The hand-written v1 DDL can silently drift from what Drift actually
  generated.** It is a manual restatement of the schema, exactly the kind of
  hand-authored schema the tooling exists to eliminate.
- **It does not scale.** Each new `schemaVersion` needs another hand-written
  fixture, and nothing checks that a migration produces a schema *matching the
  declared tables* — only that the specific columns the author remembered to
  assert exist.

Drift's `SchemaVerifier` solves both: snapshots are generated from the real
schema, and `migrateAndValidate` compares the migrated database against the
declared schema in full, catching any drift automatically for every version pair
from here on.

## Non-goals

- **Runtime `validateDatabaseSchema()` in `beforeOpen`.** It is imported from
  `drift_dev`, so calling it from `lib/` forces `drift_dev` (analyzer + build
  stack) into the app's *runtime* dependency graph. The `kDebugMode` guard
  tree-shakes the call in release but the package still joins dependency
  resolution. The harness already catches migration/schema drift in CI — the
  runtime guard only adds a dev-time app-startup check. Deferred (see
  `deferred.md`); can be added later if wanted.
- **The `make-migrations` convenience wrapper / a `build.yaml`.** We use the
  explicit `schema dump` / `schema steps` / `schema generate` commands, which
  produce the identical `stepByStep` + `SchemaVerifier` artifacts without adding
  a `build.yaml`. `make-migrations` can be adopted later with no rework.
- **Any change to the shipped 1 → 2 migration's behavior.** The `stepByStep`
  rewrite is behavior-preserving (same three `addColumn`s).

## Design

### 1. Schema snapshots — `drift_schemas/` (committed)

Two JSON snapshots, produced by
`dart run drift_dev schema dump lib/data/services/database/database.dart drift_schemas/`
(the command writes `drift_schema_v<N>.json` keyed by the code's current
`schemaVersion`):

- `drift_schema_v1.json` — dumped from a throwaway `git worktree` checked out at
  commit **`8506235`** (the last `schemaVersion == 1` commit, verified same drift
  2.34 tooling), so it is the *authentic* v1 schema, not a hand restatement.
- `drift_schema_v2.json` — dumped from `main` (`schemaVersion == 2`).

The worktree is removed after the dump; only the two JSON files are committed.

### 2. Generated harness — `test/generated_migrations/` (committed, coverage-excluded)

`dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated_migrations/`
generates:

- `schema.dart` — the `GeneratedHelper` that `SchemaVerifier` consumes.
- `schema_v1.dart` / `schema_v2.dart` — versioned `DatabaseAtV1` / `DatabaseAtV2`
  classes plus data classes and companions, used for data-integrity assertions.

The `--data-classes --companions` flags are required for the data-integrity test
(inserting typed rows at v1).

### 3. `stepByStep` migration — `database.steps.dart` (generated, committed, coverage-excluded)

`dart run drift_dev schema steps drift_schemas/ lib/data/services/database/database.steps.dart`
generates the `stepByStep` helper. `database.dart` changes from an inline
`onUpgrade` closure to:

```dart
import 'database.steps.dart';

class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(resolveExecutor(executor));

  @override
  int get schemaVersion => 2;

  // Extracted to a static field so the step always closes over the *pinned*
  // schema snapshot, never the live database schema (drift's guidance).
  static final MigrationStepWithVersion _upgrade = stepByStep(
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

`schema.tasks.*` is the v2-pinned schema, so a future `from2To3` step cannot
accidentally reference v3 columns in the 1→2 path. Behavior is identical to the
shipped migration (same three `addColumn`s, still guarded implicitly by the
version pair). The exact type of `_upgrade` (`MigrationStepWithVersion` /
`OnUpgrade`) is whatever `stepByStep` returns in drift 2.34 — the implementer
uses the generated signature verbatim.

### 4. Migration tests — rewrite `test/data/migration_test.dart`

Using `import 'package:drift_dev/api/migrations_native.dart';` (test-only;
`drift_dev` stays a **dev**-dependency) and the generated helpers:

- **Schema correctness** — `SchemaVerifier(GeneratedHelper())`, `startAt(1)` to
  build a v1 database, construct `AppDatabase(connection)`, then
  `migrateAndValidate(db, 2)`. This fails if the migrated schema does not match
  the declared v2 schema in full — the auto-extending guard for every future
  version pair.
- **Data integrity** — `schemaAt(1)`, insert a category + task via
  `v1.DatabaseAtV1`, run `migrateAndValidate(db, 2)`, then read via
  `v2.DatabaseAtV2` and assert the row survived and `recurrenceCount` /
  `recurrenceUnit` / `nextDueAt` are null. This subsumes every assertion of the
  retired raw-SQL test, against authentic snapshots.

The hand-written raw-SQL v1 fixture is deleted.

### 5. Developer workflow + hygiene

- **`Justfile` targets** documenting the ritual:
  - `just schema-dump` → `dart run drift_dev schema dump lib/data/services/database/database.dart drift_schemas/` (run after every `schemaVersion` bump).
  - `just schema-gen` → runs both `schema steps` (→ `database.steps.dart`) and
    `schema generate --data-classes --companions` (→ `test/generated_migrations/`).
- **`coverde.yaml`** gains skip-by-glob entries for
  `**/data/services/database/database.steps.dart` and
  `**/test/generated_migrations/**` (generated Dart, like the existing `*.g.dart`
  exclusion) so the 100% line-coverage gate holds.
- **`architecture/data-model.md`** gains a short note: migrations are tested with
  Drift's `SchemaVerifier` against `drift_schemas/` snapshots; bump ritual =
  `just schema-dump` + `just schema-gen` + a `fromNToN+1` step.
- **`planning/deferred.md`** — the "runtime schema self-check + migration tests"
  item is updated: the migration-test harness is now done; the runtime
  `validateDatabaseSchema()` guard remains deferred with its own revisit note.

## Operations

None. No infra, no store, no runtime behavior change. Pure test/tooling +
behavior-preserving migration refactor.

## Out of scope

See Non-goals: the runtime guard, `make-migrations`/`build.yaml`, and any change
to migration behavior.

## Testing

- `just test` runs the rewritten `SchemaVerifier` migration tests (schema
  correctness + data integrity). These replace and subsume the raw-SQL test.
- **Fault-injection sanity check during implementation** (not committed):
  temporarily break the `from1To2` step (e.g. drop one `addColumn`) and confirm
  `migrateAndValidate` fails — proving the harness actually catches drift, not
  just passes vacuously. Revert before commit; note the result in the task
  report.
- `just coverage` stays at the 100% gate (generated `database.steps.dart` and
  `test/generated_migrations/**` excluded; `database.dart` remains covered — the
  `stepByStep` field is exercised by the migration test).
- `just lint-ci` clean; `just check-planning` OK.

## Risk

- **`schema dump` at `8506235` produces a subtly different v1 than what shipped**
  (low × medium): mitigated because `8506235` *is* the shipped v1 code at drift
  2.34 — the dump reflects exactly those table definitions. The data-integrity
  test further confirms a real v1 row migrates cleanly.
- **`stepByStep` type/API differs slightly in drift 2.34** (low × low): the
  implementer copies the generated signature verbatim; the migration test and a
  fault-injection check confirm the wiring.
- **Generated files drift from source if a future migration skips the ritual**
  (low × medium): mitigated by documenting `just schema-dump` / `just schema-gen`
  in `data-model.md` and the Justfile; a future enhancement could add a CI
  "schema is current" check (noted, not built here).
- **Coverage gate breaks on the new generated files** (low × low): the coverde
  glob exclusions are added in the same change and verified by `just coverage`.

## Architecture docs to update (same PR)

- `architecture/data-model.md` — migrations use `stepByStep` against pinned
  snapshots and are verified by `SchemaVerifier` over `drift_schemas/`; the
  per-migration ritual (`just schema-dump` + `just schema-gen` + a `fromNToN+1`
  step).
