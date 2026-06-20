---
status: approved
date: 2026-06-18
slug: adopt-planning-convention
spec: adopt-planning-convention
pr: null
---

# Adopt the planning convention — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up nooka's `planning/` directory mirroring the sibling
`habbits` repo, create the missing `CLAUDE.md`, and migrate the two existing
superpowers spec+plan pairs into archive bundles so planning history has a
single home.

**Architecture:** Pure docs/scaffolding change. Copy the portable convention
(README Conventions section + `_templates/`) verbatim from
`../habbits/planning/`, write a nooka-specific intro + Index, and `git mv` the
existing specs into `changes/` with YAML frontmatter prepended. No Dart
is touched.

**Tech Stack:** Markdown, git, `just` (existing `Justfile`). The sibling repo
`../habbits` is on the same machine and is the verbatim source for the portable
parts.

**Spec:** [`design.md`](./design.md)

**Branch:** `chore/adopt-planning-convention` (already checked out; the
`design.md` is already committed on it).

**Commit strategy:** Per-task commits.

## Global Constraints

- The portable parts (README **## Conventions** section, all of `_templates/`)
  are copied **verbatim** from `../habbits/planning/` — do not paraphrase.
- Repo-specific parts (README intro, README **## Index**, `CLAUDE.md`,
  `deferred.md` items) describe **nooka** facts: a local-first to-do list
  (Flutter, iOS + Android, English + Russian), layered MVVM with Riverpod.
- Migrations use `git mv` (never delete + recreate) so `git log --follow`
  preserves provenance.
- Migrated bundle dates/slugs/SHAs are fixed:
  `2026-06-17.01-todo-list` (merge `38ee702`) and
  `2026-06-17.02-ui-refinements` (merge `6d11b30`).
- This change touches no `*.dart`, so `flutter analyze` output must be
  unchanged from `main`.

---

### Task 1: Migrate the two superpowers spec+plan pairs into archive bundles

**Files:**
- Create dir: `planning/changes/2026-06-17.01-todo-list/`
- Create dir: `planning/changes/2026-06-17.02-ui-refinements/`
- Move: `docs/superpowers/specs/2026-06-17-todo-list-design.md` → `…/2026-06-17.01-todo-list/design.md`
- Move: `docs/superpowers/plans/2026-06-17-todo-list.md` → `…/2026-06-17.01-todo-list/plan.md`
- Move: `docs/superpowers/specs/2026-06-17-ui-refinements-design.md` → `…/2026-06-17.02-ui-refinements/design.md`
- Move: `docs/superpowers/plans/2026-06-17-ui-refinements.md` → `…/2026-06-17.02-ui-refinements/plan.md`
- Delete (after move): the now-empty `docs/superpowers/` tree

Moves the already-shipped planning history into the new archive, preserving git
history, and stamps each file with habbits-style YAML frontmatter.

- [ ] **Step 1: Create the archive bundle directories**

  ```bash
  mkdir -p planning/changes/2026-06-17.01-todo-list \
           planning/changes/2026-06-17.02-ui-refinements
  ```

- [ ] **Step 2: Move the four files with `git mv`**

  ```bash
  git mv docs/superpowers/specs/2026-06-17-todo-list-design.md \
         planning/changes/2026-06-17.01-todo-list/design.md
  git mv docs/superpowers/plans/2026-06-17-todo-list.md \
         planning/changes/2026-06-17.01-todo-list/plan.md
  git mv docs/superpowers/specs/2026-06-17-ui-refinements-design.md \
         planning/changes/2026-06-17.02-ui-refinements/design.md
  git mv docs/superpowers/plans/2026-06-17-ui-refinements.md \
         planning/changes/2026-06-17.02-ui-refinements/plan.md
  ```

- [ ] **Step 3: Prepend YAML frontmatter to `2026-06-17.01-todo-list/design.md`**

  Insert at the very top of the file (before the existing `# Nooka — To-Do
  List Design Spec` heading):

  ```yaml
  ---
  status: shipped
  date: 2026-06-17
  slug: todo-list
  supersedes: null
  superseded_by: null
  pr: null
  outcome: 38ee702 — initial local-first to-do list; colored categories holding tasks, complete→archive with 30-day retention, drag-reorder, undo toasts, light/dark, en/ru.
  ---

  ```

- [ ] **Step 4: Prepend YAML frontmatter to `2026-06-17.01-todo-list/plan.md`**

  Insert at the very top (before the existing `# To-Do List Implementation
  Plan` heading):

  ```yaml
  ---
  status: shipped
  date: 2026-06-17
  slug: todo-list
  spec: todo-list
  pr: null
  ---

  ```

- [ ] **Step 5: Prepend YAML frontmatter to `2026-06-17.02-ui-refinements/design.md`**

  Insert at the very top (before `# Nooka UI Refinements — Design Spec`):

  ```yaml
  ---
  status: shipped
  date: 2026-06-17
  slug: ui-refinements
  supersedes: null
  superseded_by: null
  pr: null
  outcome: 6d11b30 — distinct category section-label headers, single-grapheme relabeled icon field, and a reliably auto-dismissing undo toast.
  ---

  ```

- [ ] **Step 6: Prepend YAML frontmatter to `2026-06-17.02-ui-refinements/plan.md`**

  Insert at the very top (before `# Nooka UI Refinements Implementation Plan`):

  ```yaml
  ---
  status: shipped
  date: 2026-06-17
  slug: ui-refinements
  spec: ui-refinements
  pr: null
  ---

  ```

- [ ] **Step 7: Remove the now-empty `docs/superpowers/` tree**

  ```bash
  rm -rf docs/superpowers
  rmdir docs 2>/dev/null || true   # only succeeds if docs/ is now empty
  ```

  `docs/` currently holds only `superpowers/`, so it should be removed too. If
  `rmdir` fails, `docs/` has other content — leave it.

- [ ] **Step 8: Verify history is preserved**

  Run: `git log --follow --oneline planning/changes/2026-06-17.01-todo-list/design.md | head -3`
  Expected: shows commits predating this branch (e.g. the original spec commit),
  not just the move — proving `--follow` traced through the rename.

- [ ] **Step 9: Commit**

  ```bash
  git add -A
  git commit -m "docs: migrate superpowers specs into planning archive bundles

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 2: Scaffold `planning/` (templates, deferred, README)

**Files:**
- Create: `planning/_templates/design.md`, `plan.md`, `change.md` (copied verbatim)
- Create: `planning/changes/active/.gitkeep`, `planning/changes/.gitkeep`
- Create: `planning/deferred.md`
- Create: `planning/README.md`

Stands up the convention container around the already-committed
`design.md`/`plan.md` of this bundle and the archive bundles from Task 1.

- [ ] **Step 1: Copy the templates verbatim from habbits**

  ```bash
  cp -R ../habbits/planning/_templates planning/_templates
  ls planning/_templates   # expect: change.md  design.md  plan.md
  ```

- [ ] **Step 2: Add `.gitkeep` placeholders (mirrors habbits)**

  ```bash
  touch planning/changes/active/.gitkeep planning/changes/.gitkeep
  ```

- [ ] **Step 3: Create `planning/deferred.md`**

  Write this exact content:

  ```markdown
  # Deferred

  Real-but-unscheduled items. Each has a revisit trigger. Promote one into a
  change bundle when its trigger fires.

  - **Release docs + Android signing** — port habbits' `docs/release.md` runbook
    and upload-key signing (gitignored keystore + `key.properties`). *Revisit
    when* a Play Store release is actually cut.
  - **Bundle-id consistency** — nooka uses `com.nooka.nooka` while habbits uses
    `io.github.quotidianlabs.habbits`. *Revisit when* app-icon/branding work is
    scheduled, or before the first store upload.
  - **Due dates + reminders** — per-task due dates and on-device local
    notifications (habbits ships per-habit reminders). *Revisit when* nooka
    moves from a list to a planner.
  - **JSON export/import** — full-DB export/import for data portability (habbits
    ships this). *Revisit when* the local-first / your-data story needs
    reinforcing.
  - **Search / filter** — find tasks across categories; filter active vs
    archived. *Revisit when* the task list grows large enough to need it.
  ```

- [ ] **Step 4: Write the `planning/README.md` intro**

  Create `planning/README.md` starting with this exact intro:

  ```markdown
  # Planning

  Specs, plans, and change history for nooka. This directory records *how the
  system got to where it is*. The living truth about *what it does now* lives in
  [`architecture/`](../architecture/README.md) at the repo root.

  ```

- [ ] **Step 5: Append the portable Conventions section verbatim from habbits**

  Append the habbits **## Conventions** section (everything from the
  `## Conventions` line up to, but not including, its `## Index` line):

  ```bash
  sed -n '/^## Conventions/,/^## Index/p' ../habbits/planning/README.md \
    | sed '$d' >> planning/README.md
  ```

  The trailing `sed '$d'` drops the `## Index` marker line so only the portable
  Conventions block lands. Confirm the appended block ends with the
  **### Frontmatter** subsection.

- [ ] **Step 6: Append the nooka-specific Index**

  Append this exact section to `planning/README.md`:

  ```markdown
  ## Index

  ### Active

  - **[adopt-planning-convention](changes/active/2026-06-18.01-adopt-planning-convention/design.md)**
    (2026-06-18) — Stand up `planning/` mirroring habbits, add `CLAUDE.md`, and
    migrate the two superpowers specs into archive bundles.

  ### Archived (shipped)

  - **[ui-refinements](changes/2026-06-17.02-ui-refinements/design.md)**
    (6d11b30, 2026-06-17) — Distinct category section-label headers, a
    single-grapheme relabeled icon field, and a reliably auto-dismissing undo
    toast.
  - **[todo-list](changes/2026-06-17.01-todo-list/design.md)**
    (38ee702, 2026-06-17) — Initial local-first to-do list: colored categories
    holding tasks, complete→archive with 30-day retention, drag-reorder, undo
    toasts, light/dark themes, en/ru.
  ```

- [ ] **Step 7: Verify the README links resolve**

  ```bash
  for p in architecture/README.md \
           planning/changes/active/2026-06-18.01-adopt-planning-convention/design.md \
           planning/changes/2026-06-17.01-todo-list/design.md \
           planning/changes/2026-06-17.02-ui-refinements/design.md; do
    [ -e "$p" ] && echo "OK  $p" || echo "MISSING  $p"; done
  ```
  Expected: four `OK` lines, no `MISSING`.

- [ ] **Step 8: Commit**

  ```bash
  git add planning/
  git commit -m "docs: scaffold planning/ — convention README, templates, deferred

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 3: Create `CLAUDE.md` and run final verification

**Files:**
- Create: `CLAUDE.md` (repo root)

Adds the project workflow guide (nooka has none) and gates the whole bundle on
a clean lint + link + no-stray-reference check.

- [ ] **Step 1: Create `CLAUDE.md`**

  Write this exact content:

  ```markdown
  # nooka — project guide

  Local-first to-do list (Flutter, iOS + Android, English + Russian).
  Architecture: layered MVVM with Riverpod — see the `architecture/` capability
  docs and the shipped change bundles in `planning/`.

  ## Workflow

  Design + plan for every non-trivial change live in `planning/`. Read
  `planning/README.md` for the full convention. In short:

  - A change is a bundle `planning/changes/active/YYYY-MM-DD.NN-<slug>/` with
    `design.md` + `plan.md` (Full lane) or `change.md` (Lightweight); on merge it
    moves to `planning/changes/`.
  - Real-but-unscheduled items live in `planning/deferred.md`.
  - The `architecture/` capability docs live at the repo root (one file per
    capability) and are the living truth-home for what the system does now.

  ## Commands

  `just lint` (`dart format` + `flutter analyze`) and `just test`
  (`flutter test`) — see the `Justfile`; `just lint-ci` is the check-only
  variant for CI. Generated `*.g.dart` is committed; run
  `dart run build_runner build --delete-conflicting-outputs` after touching
  `@riverpod`/Drift code.
  ```

- [ ] **Step 2: Verify no stray references to the old path remain**

  Run: `grep -rn 'docs/superpowers' --include='*.md' . || echo "clean"`
  Expected: `clean` (the migrated plan bodies still mention the
  `superpowers:` *skills* by name — that is correct; only the
  `docs/superpowers/` **path** must be gone).

- [ ] **Step 3: Verify the lint is clean (no Dart disturbed)**

  Run: `just lint`
  Expected: `dart format` reports nothing changed and `flutter analyze` reports
  "No issues found!" — confirming the docs-only change left source untouched.

- [ ] **Step 4: Verify `CLAUDE.md` links resolve**

  ```bash
  for p in architecture planning/README.md planning/deferred.md Justfile; do
    [ -e "$p" ] && echo "OK  $p" || echo "MISSING  $p"; done
  ```
  Expected: four `OK` lines.

- [ ] **Step 5: Commit**

  ```bash
  git add CLAUDE.md
  git commit -m "docs: add CLAUDE.md pointing the workflow at planning/

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

## Post-implementation (not part of task commits)

When this bundle merges, **promote** it: move
`planning/changes/active/2026-06-18.01-adopt-planning-convention/` to
`planning/changes/`, set its `design.md` frontmatter to
`status: shipped` with the merge `pr`/`outcome`, and move its README Index line
from **Active** to **Archived**. This is the convention's own merge ritual — do
it as part of merging, per `planning/README.md`.
