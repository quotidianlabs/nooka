---
status: draft
date: 2026-06-24
slug: clock-seam
spec: clock-seam
pr: null
---

# clock-seam — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deepen `TodoRepository` with a `Clock` seam so it injectably sources
archive-lifecycle time; retain the repository as the data port.

**Spec:** [`design.md`](./design.md)

**Branch:** `feat/clock-seam`

**Commit strategy:** Per-task commits.

TDD throughout: failing test first, then implement. Run
`dart run build_runner build --delete-conflicting-outputs` after touching the
`@riverpod` clock provider. Final gate is `just lint-ci` on a clean,
already-committed tree, then `just test`.

---

### Task 1: The `Clock` seam

**Files:**
- Create: `lib/domain/clock.dart`
- Create: `test/domain/clock_test.dart`

`Clock` abstract + `SystemClock` + `FixedClock`. Pure, no Flutter/Drift.

- [ ] **Step 1: Write the test (red)**

  `FixedClock(instant).now()` returns the instant; `SystemClock().now()` returns
  a time within a small window of `DateTime.now()`.

- [ ] **Step 2: Implement (green)**

  `flutter test test/domain/clock_test.dart` passes.

- [ ] **Step 3: Commit**

  ```bash
  git add lib/domain/clock.dart test/domain/clock_test.dart
  git commit -m "feat(domain): Clock seam (SystemClock + FixedClock)

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 2: `clockProvider` + repository clock-sourcing

**Files:**
- Modify: `lib/data/repositories/todo_repository.dart`
- Create: `test/data/todo_repository_test.dart`

Add the provider, the optional-named clock dependency, and route the repo's
archive-lifecycle ops through it.

- [ ] **Step 1: Write the repo test (red)**

  With `TodoRepository(dao, clock: FixedClock(t))` over an in-memory DB:
  `completeTask` stamps `archivedAt == t`; `purgeExpired` purges relative to `t`
  (e.g. an item archived at `t - 31d` is purged, one at `t - 1d` is kept). Fails
  today because the repo hardcodes `DateTime.now()`.

- [ ] **Step 2: Implement + generate (green)**

  `@Riverpod(keepAlive: true) Clock clock(Ref) => const SystemClock();`. Repo
  constructor `TodoRepository(this._dao, {Clock clock = const SystemClock()})`;
  `completeTask`/`purgeExpired` use `_clock.now()`; production provider passes
  `clock: ref.watch(clockProvider)`. Correct the class doc comment to the precise
  determinism claim. Run build_runner. Tests pass; the four existing doubles
  still compile unchanged.

- [ ] **Step 3: Commit**

  ```bash
  git add lib/data/repositories/todo_repository.dart lib/data/repositories/todo_repository.g.dart test/data/todo_repository_test.dart
  git commit -m "feat(data): source archive-lifecycle time from a Clock seam

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 3: Architecture promotion, decision record, ship bookkeeping

**Files:**
- Modify: `architecture/archive.md`
- Create: `planning/decisions/2026-06-24-todo-repository-is-the-data-test-seam.md`
- Modify: `planning/changes/2026-06-24.02-clock-seam/design.md`

- [ ] **Step 1: Promote into `architecture/archive.md`**

  Note that `archivedAt` and the purge cutoff are sourced from the Clock seam
  (injectable for tests), while `createdAt` is write-only metadata the DAO
  stamps directly. (The precise repo doc comment landed in Task 2.)

- [ ] **Step 2: Record the decision**

  Already drafted at `planning/decisions/2026-06-24-todo-repository-is-the-data-test-seam.md`
  — verify it reflects what shipped (port retained; `createdAt` left as metadata;
  both revisit triggers). Set its `pr`.

- [ ] **Step 3: Ship bookkeeping + final gate**

  Set the design's frontmatter `status: shipped`, fill `pr` + `outcome`. Run
  `just index` to confirm the change and decision list. Then:

  ```bash
  just lint-ci && just test
  git add architecture/ planning/
  git commit -m "docs: promote Clock seam to archive.md + record repo-port decision

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```
