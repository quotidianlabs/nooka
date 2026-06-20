---
status: shipped
date: 2026-06-18
slug: adopt-planning-convention
summary: Stand up planning/ mirroring habbits, add CLAUDE.md, and migrate the two superpowers specs into archive bundles.
supersedes: null
superseded_by: null
pr: 775dcef
outcome: 775dcef — planning/ stood up (convention README, templates, active/archive tree, deferred.md), CLAUDE.md added, two superpowers specs migrated into archive bundles.
---

# Design: Adopt the portable planning convention

## Summary

Bootstrap nooka's `planning/` directory with the same portable convention the
sibling `habbits` repo uses: a convention README, change-bundle templates, an
`active/` + `archive/` change tree, and a seeded `deferred.md`. Create the
missing `CLAUDE.md` to point the project workflow at `planning/`, and migrate
the two existing superpowers spec+plan pairs into archive bundles so planning
history has a single home. No application code changes.

## Motivation

nooka currently records its design history in `docs/superpowers/specs/` and
`docs/superpowers/plans/` — the superpowers default — while `habbits`, its
sibling, uses the portable `planning/` convention (`planning/README.md` plus
`_templates/`, designed to be copied verbatim across sibling repos). The two
repos diverge on process, and nooka has no `CLAUDE.md` at all, so an agent
opening the repo has no workflow guidance. Adopting the same convention here
gives both repos one shared, documented process and a single source of truth
for "how the system got here."

The `architecture/` truth-home already exists in nooka (four capability docs:
`README`, `data-model`, `archive`, `i18n-theming`) and already fits the
convention (prose, no frontmatter), so it needs no change.

## Non-goals

- Expanding or rewriting the `architecture/` capability docs — out of scope.
- Any of the polish bundles (README/LICENSE/pubspec, screenshot infra, CI) —
  each is its own later bundle; this one only stands up the structure they
  live in.
- Release docs and Android signing — explicitly deferred (recorded in
  `deferred.md`).
- Changing the bundle id or branding — recorded as a deferred item, not done.

## Design

### 1. Directory scaffold

Create the `planning/` tree, mirroring habbits:

```
planning/
  README.md           # portable convention section (verbatim) + nooka Index
  deferred.md         # seeded (see §4)
  _templates/
    design.md         # copied verbatim from habbits
    plan.md           # copied verbatim from habbits
    change.md         # copied verbatim from habbits
  changes/
    active/.gitkeep
    archive/.gitkeep
```

`planning/README.md` reuses habbits' **Conventions** section verbatim (it is
the portable part, explicitly identical across sibling repos: two axes, change
bundles, three lanes, artifacts, frontmatter). The **Index** section is
nooka-specific: an _Active_ list (this bundle, until it merges) and an
_Archived (shipped)_ list (the two migrated bundles, see §3). The intro
paragraph points at nooka's `architecture/` as the truth-home.

### 2. `CLAUDE.md` (new — nooka has none)

Create a project guide mirroring habbits' in shape:

- One-line project description: local-first to-do list (Flutter, iOS +
  Android, English + Russian), layered MVVM with Riverpod.
- **Workflow** section: design + plan for every non-trivial change live in
  `planning/`; read `planning/README.md` for the convention; bundles in
  `changes/active/` → `changes/` on merge; unscheduled items in
  `planning/deferred.md`; `architecture/` capability docs are the truth-home.
- **Commands** section: `just lint` (`dart format` + `flutter analyze`) and
  `just test` (`flutter test`); CI uses `just lint-ci`; regenerate generated
  `*.g.dart` with `dart run build_runner build --delete-conflicting-outputs`
  after touching `@riverpod`/Drift code.

Content is adapted to nooka's actual facts (it is a to-do app, not a habit
tracker; no reminders/screenshots/release docs exist yet, so those pointers
are omitted until their bundles land).

### 3. Migrate existing history into archive bundles

The two superpowers spec+plan pairs describe already-shipped work (the to-do
list foundation and the UI-refinements pass — both merged). Move them with
`git mv` to preserve `--follow` history, give each bundle a `design.md` +
`plan.md`, and add habbits-style frontmatter:

| From | To |
|------|----|
| `docs/superpowers/specs/2026-06-17-todo-list-design.md` | `planning/changes/2026-06-17.01-todo-list/design.md` |
| `docs/superpowers/plans/2026-06-17-todo-list.md` | `planning/changes/2026-06-17.01-todo-list/plan.md` |
| `docs/superpowers/specs/2026-06-17-ui-refinements-design.md` | `planning/changes/2026-06-17.02-ui-refinements/design.md` |
| `docs/superpowers/plans/2026-06-17-ui-refinements.md` | `planning/changes/2026-06-17.02-ui-refinements/plan.md` |

Frontmatter added on migration: `status: shipped`, `date` (proposal date),
`slug`, and `pr`/`outcome` (the merge commit short-SHA where no PR number
exists, matching habbits' `(<sha>, <date>)` index style — `38ee702` for
to-do list, `6d11b30` for ui-refinements). After the move, remove the now-empty
`docs/superpowers/` tree.

Both bundles get an entry in the README Index _Archived_ list with a one- to
two-sentence outcome summary.

### 4. Seed `deferred.md`

Reuse habbits' header (real-but-unscheduled items, each with a revisit
trigger). Seed with:

- **Release docs + Android signing** — port habbits' `docs/release.md` runbook
  and upload-key signing. *Revisit when* a Play release is actually cut.
- **Bundle-id consistency** — nooka uses `com.nooka.nooka` while habbits uses
  `io.github.quotidianlabs.habbits`. *Revisit when* branding/app-icon work is
  scheduled, or before first store upload.
- **Due dates + reminders** — per-task due dates and on-device local
  notifications (habbits has per-habit reminders). *Revisit when* nooka moves
  from list to planner.
- **JSON export/import** — full-DB export/import for data portability (habbits
  ships this). *Revisit when* the local-first/your-data story needs
  reinforcing.
- **Search / filter** — find tasks across categories; filter active/archived.
  *Revisit when* the task list grows large enough to need it.

## Out of scope

Covered under Non-goals. The three follow-on polish bundles
(`readme-license-pubspec`, `screenshot-infra`, `ci`) are sequenced in the
epic but each gets its own design→plan→implement cycle.

## Testing

This is a docs/scaffold change touching no Dart, so verification is:

- `just lint` clean (`dart format` no-op, `flutter analyze` unchanged) —
  confirms no source was disturbed.
- Every relative link in `planning/README.md` and `CLAUDE.md` resolves to an
  existing path.
- `git log --follow planning/changes/2026-06-17.01-todo-list/design.md`
  shows the pre-move history — confirms the migration preserved provenance.
- `docs/superpowers/` no longer exists; no stray references to it remain
  (`grep -r superpowers . --include=*.md` finds only `.superpowers/` tooling,
  if any).

## Risk

Low. The main risk is a botched `git mv` losing history — mitigated by using
`git mv` (not delete+create) and verifying with `git log --follow`. Secondary
risk is link rot in the new README/CLAUDE.md — mitigated by the link-resolution
check above. No runtime behavior changes, so no app-level regression surface.
