# Deferred

Real-but-unscheduled items. Each has a revisit trigger. Promote one into a
change file when its trigger fires.

- **Due dates + reminders** — per-task due dates and on-device local
  notifications (habbits ships per-habit reminders). *Revisit when* nooka
  moves from a list to a planner.
- **Search / filter** — find tasks across categories; filter active vs
  archived. *Revisit when* the task list grows large enough to need it.
- **Runtime schema self-check** — Drift's debug-only
  `validateDatabaseSchema()` in `beforeOpen`. Not adopted with the migration
  harness (2026-07-04.02) because it forces `drift_dev` into the app's runtime
  dependencies for a check the CI `SchemaVerifier` harness already covers.
  *Revisit when* a code-vs-DB schema mismatch slips past CI in practice, or if
  drift ships a lighter runtime-only validation path.
- **Disable OS-level device backup** — set `android:allowBackup="false"`
  (+ iOS backup-exclusion on the SQLite file) so the DB is not copied off-device
  by Android Auto Backup / iOS device backup. Trade-off: removes transparent
  task migration on device replacement. The privacy policy discloses the current
  (backup-enabled) behavior. *Revisit when* deciding the on-device data
  residency stance, or if a store review requires OS backups excluded.
