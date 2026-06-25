# Architecture

Layered MVVM with Riverpod, mirroring the `habbits` app.

- `domain/` — pure logic, no Flutter/Drift imports (archive retention, reorder, models)
- `data/` — Drift `TodoDao` + `TodoRepository` seam + `SettingsRepository`
- `ui/` — feature-first screens + view models (`home/`, `settings/`, shared `widgets/`, `core/`)

Flow: `view → home_view_model → todo_repository → todo_dao → SQLite`.
Reactive `watchCategoriesWithTasks()` propagates changes back to the UI.

This directory is the living **truth home** — one file per capability,
describing what the system does *now*. Dated by git, no frontmatter.

## Capability index
- [Data model](data-model.md)
- [Home coordination](home-coordination.md)
- [Archive & retention](archive.md)
- [Error handling](error-handling.md)
- [i18n & theming](i18n-theming.md)
- [Backup I/O](backup-io.md)

## Promotion rule

When a change alters a capability's behavior, hand-edit the matching
`architecture/<capability>.md` **in the same PR** — the promotion rides with
the code, never as a follow-up. That edit is what keeps this directory true.
