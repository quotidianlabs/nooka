# Retro: Whole-app hardening initiative (2026-06-20)

## What this was

"What's next?" → harden before adding features → a whole-app bug-hunt
[audit](../audits/2026-06-20-whole-app-hardening.md), three reviewed fix
bundles, and a deferred-lows cleanup. Shipped as PRs #11, #12, #13.

## By the numbers

- 1 audit, 6 parallel area-sweeps → **19 findings** (5 high, 5 med, 9 low).
  i18n, transactions, cascade-delete, and settings round-trips verified *clean*.
- 3 themed fix bundles — A (error resilience), B (drag board & dialogs),
  C (archive countdown, ordering, coverage) — ~25 subagent-driven tasks.
- **2 further real bugs** found *during* the fix work (not in the original
  audit) and fixed before merge.
- Tests **46 → 93**. Lint + CI green on every PR. No schema migrations; the only
  new ARB keys were Bundle A's two error strings.

## What worked

**Audit-first, theme-bundled.** Six read-only agents over distinct areas
produced findings fast, and the "Checked & OK" sections (i18n parity, Russian
CLDR plurals, transaction wrapping) bounded the risk as much as the bugs drove
the work. Grouping findings into themed bundles gave a clean execution order,
natural PR boundaries, and a shared seam (`_guard`) introduced in A and reused
by B and C.

**Layered review, each layer catching what the last missed.** The standout:
- Per-task reviews caught scoped defects.
- The **final whole-branch review** (run on the strongest model) caught the
  **M4 × `_guard`** bug: M4 reordered persistence correctly relative to the
  *old* code, but routing the add through `_guard` — which catches and returns
  `void` — meant the "remember last category" persistence ran even when the add
  failed. No single-task view could see it; the bug lived only in the
  interaction.
- **External review** caught **L1's tiebreaker positioned where it couldn't take
  effect**: the `categories.id` term sat *after* `tasks.sortOrder` in the
  `ORDER BY`, so a category sortOrder collision was resolved by task contents,
  not by id. The column was present but inert. Per-task review, the final
  review, *and* the fix-time self-check all reasoned about the tiebreaker's
  *presence*, never its lexicographic *position*.

**Testability pressure improved a design.** The plan's original drag-reorder
test drove the DAO directly and could not fail without the fix — a tautology.
Surfacing that in pre-flight led to extracting a pure `planReorder()` from the
private gesture handler; six real unit tests replaced one fake. The hard-to-test
code got better because we refused to fake the test.

**Model-tiering by task complexity.** haiku for mechanical transcription (when
the brief carried complete code), sonnet for integration/judgment, opus for the
final whole-branch review. Kept cost down without weakening the reviews that
mattered.

## What didn't — and what to change

**"The tiebreak exists" ≠ "the tiebreak takes effect."** The L1 bug is the
sharpest lesson. For ordering/precedence changes, test the *collision at the
level it manifests* (a category collision, not just a task collision) and reason
about lexicographic *position*, not just column presence.

**Swallowing helpers need a success signal from day one.** `_guard` shipped in
Bundle A as `Future<void>` (catch → SnackBar). The moment a caller needed to
gate behavior on success (M4), that `void` contract became a latent bug.
Changing `void → bool` later was backward-compatible — but only by luck. If a
shared helper swallows errors and *any* caller will branch on success, it should
report success from the start.

**Tests that assert nothing slipped into plans.** `expect(at30, isNotNull)` (an
int), `expect([a, b, c], isNotEmpty)` (a literal), `expect(cat, isA<int>())`
(warning suppression). These were *spec-prescribed* — the plan author wrote them.
Plan authorship doesn't grade its own tests; the plan-writing self-review should
scan for assert-nothing scaffolding, not leave it to the task review.

**Don't trust subagent reports — verify git state.** One coverage subagent
reported "3 commits, 88/88" with a single tool-use and left an uncommitted
`dart format` diff, so the *committed* state wasn't lint-clean. Independent
`git status` / `git log` caught it. A `just lint-ci` (check-only) step in the
implementer contract would catch format-after-commit automatically.

**Minor infra friction.** CI once didn't register a run on push (needed a fresh
commit), and the concurrency `cancel-in-progress` made the run list noisy
(cancelled ≠ failed).

## Lessons worth carrying forward

1. Run a real audit before a hardening push — the clean areas bound risk as much
   as the findings drive work.
2. A final whole-branch review on the strongest model earns its cost:
   cross-task bugs are invisible per-task.
3. External eyes still find what internal review misses — *position vs. presence*
   is a real blind spot.
4. When logic is hard to test, extract the decision into a pure function and let
   testability pressure improve the design.
5. A helper that swallows errors must report success if anyone will branch on it.
6. Verify subagent claims against git, not the report.

## Follow-ups (none blocking)

- Consider adding `just lint-ci` to the implementer/subagent contract to catch
  post-commit format drift.
- The audit backlog is fully closed; nothing outstanding.
