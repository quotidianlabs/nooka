---
status: draft
date: 2026-06-20
slug: hardening-audit-and-tests
summary: Whole-app bug-hunt audit (findings doc) plus a test pass that adds regression guards for confirmed bugs and fills coverage on the untested drag-board widgets, dialogs, and controllers.
supersedes: null
superseded_by: null
pr: null
outcome: null
---

# Design: Whole-app hardening — bug-hunt audit + test pass

## Summary

Harden nooka before adding more product surface. Two work-products: a
**whole-app bug-hunt audit** that produces a severity-ranked findings doc, and
a **test pass** that adds a regression guard for every confirmed bug *and*
fills coverage on the code that has none today (the drag-board widgets, the
task/confirm-delete dialogs, the locale/theme controllers). Confirmed-bug
fixes are spawned as separate change bundles after triage — this spec fixes the
audit's scope/method and the test targets, not the emergent fix list.

## Motivation

nooka has shipped seven changes in four days, the last (`drag-reorder-board`,
#9) being the most invariant-heavy: transactional `sortOrder` renumbering and a
new cross-category `moveTaskToCategoryAt`. No bug-hunt has run across the app,
and test coverage is uneven:

- **Well-covered:** `todo_dao` (174-line test), `home_screen` (330-line test).
- **Zero/thin coverage:** the drag-board widgets (`category_section`,
  `task_row_content`, `category_header_content` — the newest, most complex
  feature), `task_dialog`, `confirm_delete_dialog`, and the `locale_controller`
  / `theme_controller`.

"Harden what exists" before the next feature: find the bugs, guard them, and
light up the dark corners.

## Non-goals

- No new product features — due dates, search, export stay deferred.
- No fixes land in *this* bundle's branch; confirmed findings spawn their own
  fix changes, sized at triage (Lightweight batch for small/cohesive fixes,
  Full bundle for any fix needing design judgment).
- No refactoring beyond what a confirmed bug's fix strictly requires.
- The thin pass-through `todo_repository` / `home_view_model` get no direct
  unit tests — they delegate, and the DAO/view-model behavior is exercised
  through DAO and widget tests.

## Design

### 1. Audit — whole-app sweep

Produces `planning/audits/2026-06-20-whole-app-hardening.md`: severity-ranked
findings, each with location, repro/reasoning, and a proposed fix. Six areas,
with the specific hazards hunted in each:

1. **Data (DAO):** `sortOrder` renumbering on `reorderTasks` /
   `moveTaskToCategoryAt` / `insertedAt`; cascade-delete; the archive purge
   boundary (off-by-one at exactly `archiveRetentionDays`; `daysRemaining`
   rounding); restore re-append ordering; transaction atomicity under
   interleaved mutations.
2. **Domain:** `archive` retention math; `reorder` / `insertedAt` edge cases —
   empty list, out-of-range index, duplicate or missing ids.
3. **UI + view model:** cross-category drag; dragging into/out of a collapsed
   category; add-task default-category persistence; dialog validation (empty,
   whitespace-only, very long names, emoji handling); confirm-delete flows.
4. **Controllers:** `locale` / `theme` persistence round-trip and startup
   defaults.
5. **i18n:** en/ru ARB key parity; Russian plural forms (one/few/many/other) on
   every counter and the archive countdown; missing-key fallback behavior.
6. **Cross-cutting:** DB-failure error handling; `archivedAt` null handling;
   `DateTime.now()` local-vs-UTC and day-boundary behavior.

Method: fan out parallel read-only agents (one per area), then synthesize into
the single findings doc. After it is written, **triage the findings with the
user** — confirm which are real, set severity/priority — before any fix work.

### 2. Test pass

Shipped from this same bundle (the audit and the test pass are one change;
only the confirmed-bug *fixes* spawn separate bundles). Closes the coverage
gaps:

- **Drag-board widgets** (`category_section`, `task_row_content`,
  `category_header_content`) — widget tests: within-category reorder and
  cross-category drag land the task at the expected `sortOrder`.
- **`task_dialog`, `confirm_delete_dialog`** — widget tests: validation
  (empty/whitespace names), confirm vs cancel.
- **`locale_controller`, `theme_controller`** — unit tests: persistence
  round-trip and startup default.
- **One regression test per confirmed audit bug**, co-located with the unit it
  guards.
- **One integration test** (`integration_test/`): full add → complete →
  archive → purge → restore flow — the highest-value end-to-end guard.

## Testing

The test pass *is* the testable deliverable: `just test` green with the new
suites, `just lint` clean. Each confirmed audit finding is considered closed
only when its fix change ships with a guarding test that fails before the fix
and passes after.

## Risk

- **Audit finds little** (low × low) — coverage gaps still get filled; the
  sweep doubles as a documented "we looked" baseline.
- **A finding needs a schema migration** (low × high) — e.g. a data-integrity
  bug requiring a `schemaVersion` bump. Escalates that fix to its own Full
  bundle with a migration test; flagged at triage, not absorbed silently.
- **Widget tests for `drag_and_drop_lists` are brittle** (med × low) — drive
  the view model directly where the gesture layer is hard to simulate, and
  assert on resulting `sortOrder`/state rather than on drag mechanics.
