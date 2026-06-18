# Planning

Specs, plans, and change history for nooka. This directory records *how the
system got to where it is*. The living truth about *what it does now* lives in
[`architecture/`](../architecture/README.md) at the repo root.

## Conventions

> This section is the portable convention — identical across the sibling repos.
> The Index below is repo-specific. To adopt elsewhere, copy this section plus
> [`_templates/`](_templates/) and point that repo's `CLAUDE.md` workflow at it.

### Two axes, never mixed

- **`architecture/` (repo root) — the present.** One file per capability,
  living prose, updated whenever a change ships. The truth home.
- **`planning/changes/` — the past-and-pending.** One folder per change, frozen
  once shipped.

Shipping a change **promotes** its conclusions into the affected
`architecture/<capability>.md` by hand, then archives the bundle.

### Change bundles

A change is a folder `changes/active/YYYY-MM-DD.NN-<slug>/`:

- `YYYY-MM-DD` — proposal date; `.NN` — zero-padded intra-day counter that
  breaks same-date ties so the timeline sorts stably.
- `<slug>` — kebab-case description, not a story ID.

On merge the folder moves to `changes/archive/` with `status: shipped`, `pr:`,
and `outcome:` filled, and its line moves from **Active** to **Archived** below.

### Three lanes

| Lane | Artifacts | Use when |
|------|-----------|----------|
| **Full** | `design.md` + `plan.md` | design judgment; new file/module; public-API change; cross-cutting/multi-file; non-trivial test design |
| **Lightweight** | `change.md` | small-but-real: ≲30 LOC net, ≤2 files, no new file, no public-API change, single straightforward test |
| **Tiny** | none — conventional commit | typo, dep bump, linter/formatter/CI tweak, mechanical rename, single-line config |

Heavier lane wins on ambiguity. A `change.md` that outgrows its lane splits into
`design.md` + `plan.md`.

### Artifacts at a glance

- **`design.md`** — the spec: the *thinking* (why, design, trade-offs, scope).
- **`plan.md`** — the plan: the *sequencing* (the executor's task checklist).
- **`change.md`** — both, condensed, for the lightweight lane.
- **`deferred.md`** — real-but-unscheduled items, each with a revisit trigger.

Templates live in [`_templates/`](_templates/).

### Frontmatter

`design.md` / `change.md`: `status` (draft|approved|shipped|superseded), `date`,
`slug`, `supersedes`, `superseded_by`, `pr`, `outcome`. `plan.md`: `status`,
`date`, `slug`, `spec`, `pr`. Files in `architecture/` carry **no** frontmatter.

## Index

### Active

_None._

### Archived (shipped)

- **[adopt-planning-convention](changes/archive/2026-06-18.01-adopt-planning-convention/design.md)**
  (775dcef, 2026-06-18) — Stand up `planning/` mirroring habbits, add
  `CLAUDE.md`, and migrate the two superpowers specs into archive bundles.
- **[ui-refinements](changes/archive/2026-06-17.02-ui-refinements/design.md)**
  (6d11b30, 2026-06-17) — Distinct category section-label headers, a
  single-grapheme relabeled icon field, and a reliably auto-dismissing undo
  toast.
- **[todo-list](changes/archive/2026-06-17.01-todo-list/design.md)**
  (38ee702, 2026-06-17) — Initial local-first to-do list: colored categories
  holding tasks, complete→archive with 30-day retention, drag-reorder, undo
  toasts, light/dark themes, en/ru.
