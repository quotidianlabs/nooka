# Deferred

Real-but-unscheduled items. Each has a revisit trigger. Promote one into a
change bundle when its trigger fires.

- **Due dates + reminders** — per-task due dates and on-device local
  notifications (habbits ships per-habit reminders). *Revisit when* nooka
  moves from a list to a planner.
- **Search / filter** — find tasks across categories; filter active vs
  archived. *Revisit when* the task list grows large enough to need it.
- **Runtime schema self-check + migration tests** — Drift's debug-only
  `validateDatabaseSchema()` in `beforeOpen`, plus a `SchemaVerifier`
  migration-test harness (`drift_dev schema generate`). *Revisit when* the
  first real migration lands (`schemaVersion` reaches 2).
- **Disable OS-level device backup** — set `android:allowBackup="false"`
  (+ iOS backup-exclusion on the SQLite file) so the DB is not copied off-device
  by Android Auto Backup / iOS device backup. Trade-off: removes transparent
  task migration on device replacement. The privacy policy discloses the current
  (backup-enabled) behavior. *Revisit when* deciding the on-device data
  residency stance, or if a store review requires OS backups excluded.
