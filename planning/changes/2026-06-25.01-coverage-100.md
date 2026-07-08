---
summary: Drive coverage to a meaningful 100% (production DB glue excluded); replace tool/coverage.py with coverde and migrate the CI gate off deprecated very_good_coverage.
---

# Design: Drive line coverage to a meaningful 100% on off-the-shelf tooling

## Summary

Raise hand-written-code coverage from 87.6% to a **meaningful 100%** — every
line that can sanely run under `flutter test` is tested; the only lines left out
are the irreducible production I/O glue (the real database file-open), which is
covered by the existing emulator integration test, not by unit coverage. Along
the way, replace the bespoke `tool/coverage.py` filter+summary script with the
Dart-native `coverde` CLI, move exclusions into a `coverde.yaml` config (no more
inline flag-walls), and migrate the CI gate off the now-deprecated
`very_good_coverage` action to `coverde check`.

## Motivation

`flutter test --coverage` reports **87.6% (735/839 lines, generated excluded)**,
gated at 85%. The 104 uncovered lines fall into three buckets:

- **Easily coverable (~40)** — plain logic/UI: `todo_repository` (7),
  `settings_repository` (2), `home_view_model` branches (8), dialogs and
  screens (`task_dialog` 3, `category_dialog` 2, `settings_screen` 2,
  `confirm_delete_dialog` 1, `task_row_content` 1, `color_contrast` 1).
- **Coverable but laborious (~37)** — `home_screen.dart`: bottom-sheet menus
  (category edit/add/delete, task edit), archive-view rendering, settings
  navigation, and the `DragAndDropLists` reorder callbacks.
- **Genuinely unrunnable under `flutter test` (~27)** — the production
  `driftDatabase(name: 'nooka')` file-open and the providers that build a real
  DB; the Drift table column getters in `database.dart`.

Two tooling facts shape the fix. First, **no conventional Dart tool honors
line-level `// coverage:ignore` comments** — `flutter test --coverage`,
`remove_from_coverage`, and `very_good_coverage` all exclude by path/glob only.
So the clean way to drop unrunnable lines is to isolate them into their own files
and glob-exclude those, not to sprinkle bespoke ignore markers. Second,
**`very_good_coverage` (the current gate) was archived/deprecated on
2026-03-31**, so the gate needs to move regardless.

## Non-goals

- Testing the production database file-open path in unit tests — Drift's own
  docs keep it as injectable glue; it is exercised by the existing KVM emulator
  integration test (`341d12e`).
- Migration tests (`drift_dev schema generate` / `SchemaVerifier`) — the schema
  is at version 1 with no migrations to test yet.
- A runtime `validateDatabaseSchema()` self-check — deferred (see Out of scope).
- Any behavior change. This is tests + CI tooling + a test-only code split.

## Design

### 1. Off-the-shelf pipeline: `coverde` replaces `tool/coverage.py`

Delete `tool/coverage.py`. Coverage filtering, the gate, and (optionally) reports
all come from `coverde` (`dart pub global activate coverde`) — Dart-native, no
system dependency, no third-party service.

`just coverage` and CI run:

```sh
flutter test --coverage
coverde transform --input coverage/lcov.info --transformations preset=exclude-untestable
coverde check --input coverage/lcov.info 100
```

`coverde transform` filters by a named preset; `coverde check <min>` is the gate.
Only the `100` threshold is a CLI arg. The per-area Markdown job-summary table
that `coverage.py` emitted is dropped.

> **Amended at ship:** the `lcov-reporter-action` per-file PR comment is also
> removed. Under a hard 100% gate it carries no signal — when coverage is 100%
> every file shows green, and when it drops `coverde check` fails the job first
> and logs the uncovered lines + content. A static `coverage 100%` README badge
> (truthful because the gate enforces it) replaces the at-a-glance number.

### 2. Exclusions live in `coverde.yaml`, not command args

A repo-root `coverde.yaml` defines the preset. Presets compose, so adding a file
later (e.g. `main.dart` if its `runApp` wiring proves unrunnable) is a one-line
edit:

```yaml
# coverde.yaml
transformations:
  exclude-untestable:
    - type: skip-by-glob
      glob: "**/*.g.dart"
    - type: skip-by-glob
      glob: "**/*.freezed.dart"
    - type: skip-by-glob
      glob: "**/app_localizations*.dart"
    - type: skip-by-glob
      glob: "**/data/services/database/connection.dart"
    - type: skip-by-glob
      glob: "**/data/services/database/database_providers.dart"
```

This is the single home for exclusions, mirroring the prior `coverage.py`
philosophy but with a standard tool and config format.

### 3. Isolate the unrunnable DB glue into its own files

So the exclusion globs hit precisely the I/O glue and nothing testable:

- **`connection.dart`** — holds `driftDatabase(name: 'nooka')` (the real
  file-open). `AppDatabase`'s production constructor branch delegates to it.
  *Excluded* (covered by the emulator integration test).
- **`database_providers.dart`** — the two providers can only build a real DB;
  pure wiring. *Excluded as a whole file.*
- `database.dart` keeps `AppDatabase`; its in-memory constructor branch stays
  measured and covered by DAO tests.

**Table column getters** (`database.dart:9-25`) are *not* excluded by default.
They execute when the schema is built, so a schema-creation test (open an
in-memory DB and force `migration.onCreate` / `m.createAll()`) should cover them.
Implementation verifies this experimentally; **only if** coverage still credits
them to generated code do the table classes move to a `tables.dart` that gets a
glob-exclude entry. Preference order: cover, then exclude.

### 4. Database interaction is tested the conventional Drift way

Per Drift's testing guide, DAO/repository query logic is tested against an
in-memory database — exactly what `todo_dao_test.dart` already does:

```dart
database = AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);
```

The uncovered `todo_repository` / `settings_repository` lines are filled with
ordinary in-memory tests, not mocks or exclusions.

### 5. Extract drag callbacks instead of gesture-testing them

The `home_screen.dart` `DragAndDropLists` `onListReorder` / `onItemReorder`
closure bodies move into named methods on the State. Tests invoke those methods
directly (the view-model reorder logic they call is already 100%), avoiding
flaky drag-gesture simulation. The remaining `home_screen` lines — bottom-sheet
menus, archive rendering, settings navigation — get widget tests that tap
through the modal sheets and dialogs.

### 6. CI gate migration

Replace the deprecated `very_good_coverage` step in `.github/workflows/ci.yml`
with `dart pub global activate coverde` + the `coverde transform`/`coverde check
... 100` invocation from §1. Pin the `coverde` version so the
`transform`/`filter` flag surface does not drift. Remove `lcov-reporter-action`
and its `pull-requests: write` permission — redundant under the hard 100% gate
(see the amendment in §1).

## Operations

None out-of-repo. CI installs `coverde` via `dart pub global activate`.

## Out of scope

- **`validateDatabaseSchema()` runtime self-check** — deferred to `deferred.md`.
  *Revisit when* the first real migration lands (`schemaVersion` reaches 2),
  where comparing runtime vs. migration-defined schema actually earns its keep.
- **Migration test harness** (`SchemaVerifier`) — same revisit trigger.

## Testing

- `just coverage` (now `coverde check ... 100`) passes locally and in CI at the
  100% threshold over the filtered lcov.
- New/expanded tests: in-memory DAO + repository tests; `home_view_model` branch
  tests; widget tests for `home_screen` menus / archive / settings nav; direct
  unit tests for the extracted drag-callback methods; dialog and `color_contrast`
  edge cases; a schema-creation test for the table getters.
- `just lint-ci` clean on an already-committed tree.

## Risk

- **Table getters may stay credited to generated code** (medium likelihood, low
  impact) — fallback is the `tables.dart` split + glob-exclude; design already
  accounts for it.
- **`coverde` flag/preset surface changes** (low × medium) — `filter` is already
  deprecated in favour of `transform`; mitigate by pinning the version in CI.
- **Hidden unrunnable lines surface once the gate is 100%** (medium × low) —
  e.g. `main.dart` `runApp` wiring. Mitigation: presets compose, so excluding an
  additional glue file is a one-line `coverde.yaml` edit; the design treats the
  exclusion list as extensible, not fixed.
