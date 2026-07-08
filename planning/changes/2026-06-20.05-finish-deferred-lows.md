---
summary: Close out the three deferred audit lows — make reorderedIds total (L2), document the elapsed-24h retention semantics (L7), and refresh the archive countdown on app resume (L8).
---

# Finish deferred audit lows (L2 / L7 / L8)

Closes the three low-severity findings parked in
[`deferred.md`](../../deferred.md) from the
[2026-06-20 hardening audit](../../audits/2026-06-20-whole-app-hardening.md).
Small, mechanical, low-risk — no design judgment, hence the Lightweight lane.

## L2 — make `reorderedIds` total

`lib/domain/reorder.dart`'s `reorderedIds` already clamps its `insert` index
(added during the PR #11 review), but `list.removeAt(oldIndex)` still throws a
`RangeError` on an out-of-range `oldIndex` or an empty list. The sole caller
(`planReorder`) bounds-checks before calling, so this is contract-safe today —
but H4's whole intent is "the reorder primitives never throw." Guard it the same
way `insertedAt` is defensive: if `oldIndex` is out of range, return an
unchanged copy (you cannot move an item that isn't there).

```dart
List<int> reorderedIds(List<int> ids, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= ids.length) return [...ids];
  final list = [...ids];
  final item = list.removeAt(oldIndex);
  list.insert(newIndex.clamp(0, list.length), item);
  return list;
}
```

**Tests** (`test/domain/reorder_test.dart`): empty list → `[]`; out-of-range
`oldIndex` → unchanged copy; `oldIndex == newIndex` → no-op (already holds).

## L7 — document the retention semantics

Retention is measured in elapsed 24-hour periods (`Duration(days: 30)`), not
local calendar days, so a DST transition can shift the boundary ~1h relative to
the wall clock. The M1 ceil already removed the user-visible "0 days" mismatch,
and the trigger for true calendar-day accuracy has not fired — so this is a
documentation change only: make the intent explicit at the top of
`lib/domain/archive.dart` and note that calendar-day math (flooring to local
midnight) is the path if exact calendar-day retention is ever required. No
behavior change, no test change.

## L8 — refresh the archive countdown on resume

`HomeScreen.build` captures `final now = DateTime.now()` once per build, so the
archive view's "auto-removes in N days" can read stale if the app sits
foregrounded across midnight with no other rebuild. Make `_HomeScreenState` a
`WidgetsBindingObserver`; on `AppLifecycleState.resumed`, `setState(() {})` so
the next build recomputes `now`. Register in `initState`, unregister in
`dispose`.

**Test** (`test/ui/home_screen_test.dart`): a resume lifecycle event
(`tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed)`)
rebuilds the screen without error and the archive view still renders. (The
across-midnight refresh itself isn't unit-testable without injecting a clock,
which is out of scope for a cosmetic fix; the test guards the wiring.)

## Out of scope

- No clock injection / fake-time harness (would be needed to assert the L8
  countdown actually changes across midnight; not worth it for a cosmetic fix).
- No calendar-day retention math (L7 stays elapsed-24h by decision).

## Verification

`just test` green (new L2 + L8 tests), `just lint` clean. No schema change, no
new ARB keys.
