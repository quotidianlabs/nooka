---
status: accepted
date: 2026-06-24
slug: todo-repository-is-the-data-test-seam
summary: Keep TodoRepository as the data port (the error-injection test seam) and deepen it with a Clock; leave createdAt as write-only metadata.
supersedes: null
superseded_by: null
pr: null
---

# TodoRepository is the data test-seam, deepened by the Clock

**Decision:** Retain `TodoRepository` as the data-layer port rather than
deleting it as a thin pass-through, and give it real depth via a `Clock` seam
(it becomes the injectable source of archive-lifecycle time). `createdAt` is
left as write-only metadata stamped by the DAO, not routed through the Clock.

## Context

An architecture review flagged `TodoRepository` as a shallow 1:1 delegation to a
deep `TodoDao` (Candidate 3) and flagged `DateTime.now()` being minted on both
sides of the repo↔DAO seam (Candidate 4). Options on the table: (a) delete the
repository and have the view model depend on the DAO directly; (b) keep it as-is
and document it; (c) keep it and deepen it. The deletion test only half-fires:
deleting the repo loses no behavior (the DAO stays deep), but loses the seam four
error-injection test doubles depend on.

## Decision & rationale

**Keep the repository (reject deletion).** Four doubles — `_ErrorStreamRepo`,
`_ThrowingMutationRepo` (×2), `_ThrowingCreateTaskRepo` — subclass it to inject
failures the view model must handle. "Two adapters make a seam real"; we have
four, so the seam earns its keep as a *port* whose leverage is substitutability,
not behavior. Deleting it would force subclassing the generated Drift
`DatabaseAccessor` (awkward) and you cannot make a real in-memory database throw
on a specific method, so error-handling paths would lose clean coverage.

**Deepen it with a Clock (resolve the half-true determinism claim).** The repo
now sources archive-lifecycle time (`archivedAt`, the purge cutoff) from an
injectable `Clock`, replacing a hardcoded `DateTime.now()` — giving the
production adapter genuine implementation and making those ops testable through
the repo's interface. See change `2026-06-24.02-clock-seam`.

**Leave `createdAt` as write-only metadata.** It is never sorted-by or
displayed, so routing it through the Clock would churn ~80 DAO-seed call sites
across the test suite for a value nobody asserts, and would leave a residual
`DateTime.now()` default inside the DAO. Documenting it precisely is the honest
fix.

## Revisit trigger

- **Reconsider deleting the repository** if the error-injection doubles go away
  (error paths covered another way) **or** the repository carries no production
  behavior beyond delegation + the Clock.
- **Route `createdAt` through the Clock** (and make the DAO fully deterministic)
  if `createdAt` becomes load-bearing — sorted-by or displayed.
