# Architecture

Layered MVVM with Riverpod, mirroring the `habbits` app.

- `domain/` — pure logic, no Flutter/Drift imports (archive retention, reorder, models)
- `data/` — Drift `TodoDao` + `TodoRepository` seam + `SettingsRepository`
- `ui/` — feature-first screens + view models (`home/`, `settings/`, shared `widgets/`, `core/`)

Flow: `view → home_view_model → todo_repository → todo_dao → SQLite`.
Reactive `watchCategoriesWithTasks()` propagates changes back to the UI.

## Capability index
- [Data model](data-model.md)
- [Archive & retention](archive.md)
- [i18n & theming](i18n-theming.md)
