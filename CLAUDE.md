# nooka — project guide

Local-first to-do list (Flutter, iOS + Android, English + Russian).

## Architecture

Layered MVVM with Riverpod: `domain/` (pure logic) → `data/` (Drift DAO +
repository seams) → `ui/` (feature-first screens + view models). Flow:
`view → home_view_model → todo_repository → todo_dao → SQLite`, with a
reactive watch propagating changes back to the UI.

The living, code-current account of each capability lives in
[`architecture/`](architecture/README.md) (one file per capability). **When a
change alters a capability's behavior, hand-edit the matching
`architecture/<capability>.md` in the same PR** — that promotion is what keeps
`architecture/` true. This applies to subagent-implemented tasks too, so name
the affected doc in the task.

| Capability | File |
|---|---|
| Data model | [data-model.md](architecture/data-model.md) |
| Home coordination | [home-coordination.md](architecture/home-coordination.md) |
| Archive & retention | [archive.md](architecture/archive.md) |
| Error handling | [error-handling.md](architecture/error-handling.md) |
| i18n & theming | [i18n-theming.md](architecture/i18n-theming.md) |
| Backup I/O | [backup-io.md](architecture/backup-io.md) |

## Workflow

Design + plan for every non-trivial change live in `planning/`. Start at the
[Quick path](planning/README.md#quick-path-start-here) in `planning/README.md`
to choose a lane (Full / Lightweight / Tiny) and create a bundle. The change
listing is generated — run `just index`; validate bundles with
`just check-planning`.

## Commands

`just lint` (`dart format` + `flutter analyze`), `just test` (`flutter test`),
`just coverage` (gated %) — see the `Justfile` (`just --list`). Generated
`*.g.dart` is committed; run
`dart run build_runner build --delete-conflicting-outputs` after touching
`@riverpod`/Drift code.

An implementer's final pre-commit gate is `just lint-ci`, not `just lint`:
`lint` runs `dart format`, which rewrites files in place, so it can pass while
leaving the reformat uncommitted (a dirty tree that then fails CI). Format with
`just lint` while iterating, but verify a clean, already-committed tree with
`just lint-ci` last.
