# AGENTS.md

Guidance for AI agents (Claude Code, etc.) working in this repository.

## Project Overview

Nooka is a local-first to-do list for iOS and Android, in English and Russian: Flutter, Riverpod
for state, Drift (SQLite) on device, with an optional manual backup to the user's own Google
Drive. [`CONTEXT.md`](CONTEXT.md) says what it is and owns the vocabulary. Read it before naming
a concept in code, a test name, or an issue title: the three task states in particular are
derived, not stored, and the glossary is where that is pinned down.

## Commands

`just` (task runner) and `flutter`. The [`Justfile`](Justfile) is the source of truth: run
`just --list`, or read it. Two things it does not say. Generated `*.g.dart` is committed, so run
`dart run build_runner build --delete-conflicting-outputs` after touching `@riverpod` or Drift
code. And an implementer's final gate is `just lint-ci`, not `just lint`: `lint` runs
`dart format`, which rewrites files in place, so it can pass while leaving the reformat
uncommitted and failing CI on a dirty tree.

## Architecture

Layered MVVM. `lib/ui/` holds screens, Riverpod view models and widgets; `lib/domain/` holds pure
logic and models; `lib/data/` holds the Drift DAO behind a repository port. Flow: view to
`HomeViewModel` to `TodoRepository` to `TodoDao` to SQLite, with `watchCategoriesWithTasks`
propagating changes back.

The layer rule is narrower than the usual formulation, because Drift rows *are* the domain models
and widgets render them directly. What actually holds, and what `test/architecture_test.dart`
enforces:

- `lib/domain/` depends on no Flutter- or Drift-ecosystem package. The whole ecosystem, not just
  the two root packages.
- Its only `lib/data/` dependency is the generated database library.
- Nothing under `lib/domain/` or `lib/data/` depends on `lib/ui/`.
- Nothing under `lib/ui/` depends on a DAO, and the shared widgets in `lib/ui/widgets/` read no
  providers.

`lib/main.dart` is the composition root and sits outside all of it. Those checks read `export` as
well as `import`, because a re-export propagates the same coupling.
[`docs/adr/0001-drift-rows-are-the-domain-model.md`](docs/adr/0001-drift-rows-are-the-domain-model.md)
is why, including the genuine `domain/` to `data/` cycle it tolerates and why the sibling repo has
one invariant this one does not.

What a single-file read will **not** tell you:

- **`HomeViewModel` owns all command coordination**, and every mutating intent returns an outcome
  rather than throwing. The widget has one dispatch point that maps failure to one localized
  message. Anything needing a `BuildContext` (dialogs, sheets, snackbars, haptics, navigation)
  stays in the widget; everything else belongs in the view model. Follow-on effects are gated on
  success *inside* the intent, never beside it, so a failed write leaves no stale side effect.
  See [`docs/adr/0005-failed-mutations-surface-as-an-outcome.md`](docs/adr/0005-failed-mutations-surface-as-an-outcome.md);
  there is deliberately no rollback, because the reactive stream re-renders the unchanged truth.
- **A task's state is derived from two nullable columns**, never stored. Archived carries a
  completion instant; dormant carries a return instant; active has neither. Adding a status
  column would create a second source of truth for something already decidable.
- **A drop on the drag board resolves against freshly re-read state**, not a build-time snapshot
  the stream may have invalidated mid-drag, and a stale drop collapses to a no-op. Category
  reordering deliberately does the opposite and uses the widget's snapshot, so the indices and
  the list they index always agree. Both planners are pure functions in `lib/domain/`.
- **Completing a recurring task keeps its slot.** It goes dormant rather than archived, so
  retention never purges it and "clear archive" never counts it, and its undo is waking it rather
  than restoring it. See
  [`docs/adr/0004-a-completed-recurring-task-goes-dormant.md`](docs/adr/0004-a-completed-recurring-task-goes-dormant.md).
- **The schema is locked by CI, not by convention.** `just schema-check` re-dumps and regenerates,
  then fails if the committed artifacts are stale. Migrations run step by step against pinned
  per-version snapshots, so the ritual after any `schemaVersion` bump is `just schema-dump` then
  `just schema-gen`, and commit the result.

## Sibling repo

[`quotidianlabs/habbits`](https://github.com/quotidianlabs/habbits) is this app's sibling: same
stack, same shape, built from the same lineage. **Tooling is kept in sync deliberately**: CI
workflows, the release pipeline, the `Justfile`, coverage configuration and lint configuration. A
change to any of those here is owed to habbits too, and vice versa.

Features and architecture are **divergent by design** and are not ported. That app has reminders
and streaks, this one has recurrence, archive retention and cloud backup, and the two resolved the
Drift-rows-as-models trade-off differently: it wraps rows in a projection, this one lets widgets
hold them.

## Workflow

Real work **not scheduled** becomes a GitHub issue.

An invariant is a test whose name is the claim, with a comment opening `INVARIANT:` and a second
paragraph naming **what breaks it**: design rationale, not a report of what this one test catches,
since a sibling test may be the one that trips. Nothing enforces that shape; it is read at review
time.

## Code Style

- Type-check and format through `just lint`; CI runs `just lint-ci`.
- Views watch a view model and call its intents. Shared widgets in `lib/ui/widgets/` take values
  and return user input, and the screen acts on it.
- All user-facing copy comes from `AppLocalizations`, including error text. Russian uses all four
  CLDR plural forms, so a new counter needs `one`, `few`, `many` and `other`, not an English
  `count == 1`.

## Agent skills

- **Issues and specs** - GitHub Issues on `quotidianlabs/nooka`, via `gh`:
  [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md)
- **Triage labels** - the five canonical roles: [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md)
- **Domain docs** - single-context, `CONTEXT.md` + `docs/adr/`: [`docs/agents/domain.md`](docs/agents/domain.md)
