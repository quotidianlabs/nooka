---
status: shipped
date: 2026-06-24
slug: clock-seam
summary: Deepen TodoRepository with a Clock seam so it sources archive-lifecycle time injectably; retain the repository as the data test-seam (port).
supersedes: null
superseded_by: null
pr: null
outcome: Added Clock/SystemClock/FixedClock + clockProvider; TodoRepository sources archivedAt + purge cutoff from the injectable Clock (was hardcoded DateTime.now()), tested through the repo interface. createdAt left as DAO-stamped metadata (zero test churn). Repo-as-port + createdAt decision recorded. 130 tests green, just lint-ci clean.
---

# Design: Clock seam — deepen the data repository with injectable time

## Summary

`TodoRepository` is a near-pure 1:1 pass-through to a deep `TodoDao`; its only
leverage today is as the substitutable seam four error-injection test doubles
hang on. This change keeps the repository as that deliberate **port** and gives
it genuine depth: a small `Clock` seam makes the repository the single,
injectable source of **archive-lifecycle time** (`archivedAt` on `completeTask`,
the cutoff on `purgeExpired`), replacing the hardcoded `DateTime.now()` it calls
now. `createdAt` stays write-only metadata the DAO stamps directly. The
resolution (retain the port; leave `createdAt` alone) is recorded as a decision
so future architecture reviews don't re-litigate it.

## Motivation

Architecture-review Candidate 3 flagged the repository as a shallow seam, and
Candidate 4 flagged time minted on both sides of the repo↔DAO seam (the repo for
`completeTask`/`purgeExpired`, the DAO for `createdAt`) — so the repository's own
doc claim, "commands inject time here so the DAO stays deterministic for tests,"
is only half-true. Two facts shape the fix:

- The repository's pass-through-ness is **not** a defect to delete: four doubles
  (`_ErrorStreamRepo`, `_ThrowingMutationRepo` ×2, `_ThrowingCreateTaskRepo`)
  subclass it to inject failures the VM must handle. "Two adapters = a real
  seam"; we have four. Deleting it would force subclassing the generated
  `DatabaseAccessor` and you cannot make a real in-memory DB throw on demand.
- The repository's hardcoded `DateTime.now()` makes its `completeTask` /
  `purgeExpired` **non-injectable** — tests that need a fixed archive time today
  bypass the repo and call the DAO directly. A Clock fixes that and gives the
  production adapter real implementation (interface < implementation).

## Non-goals

- **Not deleting `TodoRepository`** — it is retained as the data port (see the
  decision record).
- **Widget display-time out of scope** — the archive countdown's build-time
  `now` is presentation, recomputed on resume; it keeps minting its own.
- **`createdAt` not routed through the Clock** — write-only metadata (never
  sorted-by, never displayed); the DAO keeps stamping it. No DAO signature
  change, so no test churn.
- **No `package:clock`** — its ambient `Zone`-based clock clashes with this
  codebase's explicit-DI style.

## Design

### 1. The Clock seam (`domain/clock.dart`)

```dart
abstract class Clock {
  const Clock();
  DateTime now();
}

class SystemClock extends Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

class FixedClock extends Clock {
  const FixedClock(this._instant);
  final DateTime _instant;
  @override
  DateTime now() => _instant;
}
```

Pure (no Flutter/Drift), alongside the time-aware domain functions in
`archive.dart`. Named so the architecture doc and decision record can refer to
"the Clock seam"; `FixedClock` reads clearly at test call sites.

### 2. Provider + repository wiring

A `@Riverpod(keepAlive: true) Clock clock(Ref) => const SystemClock();`
(data-layer, near the other providers). The repository takes the clock as an
**optional named** dependency defaulting to `const SystemClock()`:

```dart
TodoRepository(this._dao, {Clock clock = const SystemClock()}) : _clock = clock;
```

`SystemClock` is a safe production default, so the four error-injection doubles
stay untouched (`super(dao)`); the production provider wires the overridable
clock: `TodoRepository(ref.watch(todoDaoProvider), clock: ref.watch(clockProvider))`.
Time-determinism tests override `clockProvider` (or construct the repo with a
`FixedClock`) — they never need to touch the doubles.

### 3. Repository sources archive-lifecycle time

```dart
Future<void> completeTask(int id) => _dao.completeTask(id, _clock.now());
Future<int>  purgeExpired()       => _dao.purgeExpired(_clock.now());
```

The DAO is unchanged (its `completeTask(id, now)` / `purgeExpired(now)` already
take an explicit instant). The repository is now the Clock-based source for the
archive lifecycle, and those two ops are injectable through the repo's interface.

### 4. `createdAt` stays write-only metadata

`createCategory` / `createTask` keep stamping `createdAt` in the DAO. The
repository's doc comment is corrected to the precise claim: the repo sources
archive-lifecycle time from the Clock; `createdAt` is non-injected write-only
metadata. (Revisit trigger recorded if `createdAt` ever becomes load-bearing.)

## Testing

TDD: Clock class (red) → repo clock-sourcing (red) → implement.

- **`test/domain/clock_test.dart`** — `FixedClock(instant).now()` returns the
  instant; `SystemClock().now()` sanity check. No fakes.
- **`test/data/todo_repository_test.dart`** (new — the repo finally has behavior
  worth testing at its seam): with `TodoRepository(dao, clock: FixedClock(t))`,
  `completeTask` stamps `archivedAt == t`, and `purgeExpired` purges relative to
  `t`. Doubles as the regression guard that the repo no longer hardcodes
  `DateTime.now()`.
- **Existing tests untouched** — no DAO signature change. `archive_flow_test`
  keeps its direct `db.todoDao.completeTask(id, now-29d)` bypass: it backdates to
  two distinct instants, which an explicit per-call `now` expresses naturally and
  a single `FixedClock` cannot.

## Risk

- **Doubles break on the new constructor param** (low × low). Mitigated by the
  optional-named default — the doubles use `super(dao)` unchanged.
- **Reviewers re-flag the retained thin repo / the un-clocked `createdAt`**
  (med × low). Mitigated by the decision record with both revisit triggers.
