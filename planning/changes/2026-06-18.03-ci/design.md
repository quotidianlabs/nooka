---
status: shipped
date: 2026-06-18
slug: ci
summary: GitHub Actions running just lint-ci + just test on push and PRs, plus the README CI badge.
supersedes: null
superseded_by: null
pr: 3
outcome: PR #3 — GitHub Actions lint + test workflow on push/PR, plus the README CI badge.
---

# Design: GitHub Actions CI

## Summary

Add a GitHub Actions workflow that runs `just lint-ci` and `just test` on every
push to `main` and every pull request, and add the CI status badge to the
README. Faithful port of the sibling `habbits` repo's workflow. No application
code changes; the `Justfile` already has the needed targets.

## Motivation

nooka has no CI — nothing guards `main` against a broken build, a failing test,
or unformatted code, and the README (bundle 2) was intentionally shipped
without a CI badge because no workflow existed yet. habbits runs exactly this
two-job workflow; mirroring it gives nooka the same automated gate and
completes the README's badge row.

## Non-goals

- Integration / screenshot tests in CI — they need a simulator or emulator;
  habbits' CI deliberately skips them, and so does this. The screenshot
  generator stays a local, on-demand tool (`docs/screenshots.md`).
- Coverage upload (Codecov) — on habbits' own deferred list; not adopted here.
- Release / publishing automation — release work is already deferred
  (`planning/deferred.md`).
- Any `Justfile` change — `lint-ci` and `test` targets already exist.

## Design

### 1. `.github/workflows/ci.yml` (new)

Port habbits' workflow verbatim in structure, with nooka's facts:

```yaml
name: main

on:
  push:
    branches: [main]
  pull_request: {}

concurrency:
  group: ${{ github.head_ref || github.run_id }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: extractions/setup-just@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.2
          channel: stable
          cache: true
      - run: just install lint-ci

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: extractions/setup-just@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.2
          channel: stable
          cache: true
      - run: just install test
```

- Two independent `ubuntu-latest` jobs run in parallel. `lint` runs
  `just install lint-ci` (`flutter pub get`, then `dart format
  --set-exit-if-changed` + `flutter analyze`); `test` runs `just install test`
  (`flutter pub get`, then `flutter test`).
- `concurrency` with `cancel-in-progress` drops superseded runs on the same
  branch / PR.
- Flutter pinned to **3.44.2** stable with action caching, matching the
  project's toolchain and the README badge.

### 2. README CI badge

Add the badge as the first entry in the badge row (matching habbits' order:
CI → License → Flutter):

```markdown
[![CI](https://github.com/quotidianlabs/nooka/actions/workflows/ci.yml/badge.svg)](https://github.com/quotidianlabs/nooka/actions/workflows/ci.yml)
```

The existing License-MIT and Flutter-3.44.2 badges are unchanged and follow it.

## Testing

- Run the exact commands CI runs, locally: `just install lint-ci` and
  `just install test` — both succeed (35 tests), proving the workflow will pass.
- `.github/workflows/ci.yml` parses as valid YAML.
- The badge URL is well-formed (`quotidianlabs/nooka`, path
  `actions/workflows/ci.yml`).
- On the PR that introduces the workflow, both jobs run and go green, and the
  README badge resolves — confirmed on the PR itself.

## Risk

Low. The workflow is a proven port; the only environment difference from local
runs is the Linux runner, which `flutter analyze` / `flutter test` handle
identically (no platform-specific code in the suite). If the runner's Flutter
3.44.2 surfaces a format/analyze nit that the local machine masks, the `lint`
job catches it on the PR before merge — which is the workflow doing its job.
The README badge shows "no status" only until the first run completes.
