# Deferred

Real-but-unscheduled items. Each has a revisit trigger. Promote one into a
change bundle when its trigger fires.

- **Release docs + Android signing** — port habbits' `docs/release.md` runbook
  and upload-key signing (gitignored keystore + `key.properties`). *Revisit
  when* a Play Store release is actually cut.
- **Due dates + reminders** — per-task due dates and on-device local
  notifications (habbits ships per-habit reminders). *Revisit when* nooka
  moves from a list to a planner.
- **JSON export/import** — full-DB export/import for data portability (habbits
  ships this). *Revisit when* the local-first / your-data story needs
  reinforcing.
- **Search / filter** — find tasks across categories; filter active vs
  archived. *Revisit when* the task list grows large enough to need it.

## From the 2026-06-20 hardening audit

Low-severity findings triaged as defer (see
[`audits/2026-06-20-whole-app-hardening.md`](audits/2026-06-20-whole-app-hardening.md)).

- **L2 — guard `reorderedIds` against bad input** — `reorder.dart`'s
  `removeAt`/`insert` throw `RangeError` on out-of-range/empty input. Contract-safe
  today (only `ReorderableListView` calls it). *Revisit when* a non-framework
  caller is added; then add an `assert` documenting the precondition.
- **L7 — calendar-day vs elapsed-24h retention** — retention uses
  `Duration(days: 30)` + `inDays`, so a DST transition nudges the boundary by an
  hour. *Revisit when* exact calendar-day semantics are required (the M1 `ceil`
  fix already removes the user-visible "0 days" mismatch).
- **L8 — stale `now` across midnight** — the archive countdown captures `now`
  once per build and doesn't refresh until the next rebuild. Cosmetic,
  self-corrects on interaction. *Revisit when* a long-lived foreground session
  needs a live countdown (recompute on `AppLifecycleState.resumed`).
