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
- **Runtime schema self-check + migration tests** — Drift's debug-only
  `validateDatabaseSchema()` in `beforeOpen`, plus a `SchemaVerifier`
  migration-test harness (`drift_dev schema generate`). *Revisit when* the
  first real migration lands (`schemaVersion` reaches 2).
