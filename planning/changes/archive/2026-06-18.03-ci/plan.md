---
status: approved
date: 2026-06-18
slug: ci
spec: ci
pr: null
---

# GitHub Actions CI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Actions workflow that runs `just lint-ci` and
`just test` on push-to-`main` and every PR, and add the CI badge to the README.

**Architecture:** A single workflow file (`.github/workflows/ci.yml`) with two
parallel `ubuntu-latest` jobs that set up `just` + Flutter 3.44.2 and run the
existing `Justfile` targets. The README gains a CI status badge pointing at
that workflow. No application code and no `Justfile` change.

**Tech Stack:** GitHub Actions (`actions/checkout@v4`,
`extractions/setup-just@v3`, `subosito/flutter-action@v2`), Flutter 3.44.2,
the existing `Justfile` (`lint-ci`, `test`, `install` targets).

**Spec:** [`design.md`](./design.md)

**Branch:** `chore/ci` (already checked out; the `design.md` is already
committed on it).

**Commit strategy:** Per-task commits.

## Global Constraints

- Flutter version pinned to **3.44.2**, channel **stable**.
- Repo is `quotidianlabs/nooka` — the badge URL uses that path.
- Workflow file is `.github/workflows/ci.yml` (the badge references it by this
  filename).
- No `Justfile` change — `lint-ci`, `test`, and `install` targets already
  exist.
- No integration/screenshot job (needs a simulator/emulator).

---

### Task 1: Add the CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the existing `Justfile` targets `install`, `lint-ci`, `test`.
- Produces: a workflow at path `.github/workflows/ci.yml` that Task 2's README
  badge links to.

- [ ] **Step 1: Verify the Justfile targets CI will call exist**

  Run: `just --list`
  Expected: the list includes `install`, `lint-ci`, and `test`.

- [ ] **Step 2: Create `.github/workflows/ci.yml`**

  Create the file with exactly:

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

- [ ] **Step 3: Verify the YAML parses**

  Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('valid')"`
  Expected: `valid`

- [ ] **Step 4: Run the exact commands CI will run, locally**

  Run: `just install lint-ci`
  Expected: `flutter pub get` resolves, `dart format` reports nothing to change,
  `flutter analyze` prints "No issues found!".

  Run: `just install test`
  Expected: "All tests passed!" (35 tests).

- [ ] **Step 5: Commit**

  ```bash
  git add .github/workflows/ci.yml
  git commit -m "ci: GitHub Actions — lint + test on push and PRs

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 2: Add the CI badge to the README

**Files:**
- Modify: `README.md` (the badge row, currently lines 5–6)

**Interfaces:**
- Consumes: the workflow filename `ci.yml` from Task 1.

- [ ] **Step 1: Add the CI badge as the first badge**

  In `README.md`, the badge row currently reads:

  ```markdown
  [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
  ![Flutter](https://img.shields.io/badge/Flutter-3.44.2-02569B?logo=flutter)
  ```

  Insert the CI badge as a new first line, so the row becomes:

  ```markdown
  [![CI](https://github.com/quotidianlabs/nooka/actions/workflows/ci.yml/badge.svg)](https://github.com/quotidianlabs/nooka/actions/workflows/ci.yml)
  [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
  ![Flutter](https://img.shields.io/badge/Flutter-3.44.2-02569B?logo=flutter)
  ```

- [ ] **Step 2: Verify lint is still clean**

  Run: `just lint`
  Expected: `dart format` 0 changed, `flutter analyze` "No issues found!" (the
  README change touches no Dart).

- [ ] **Step 3: Commit**

  ```bash
  git add README.md
  git commit -m "docs: add CI status badge to the README

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

## Post-implementation (not part of task commits)

This bundle ships via PR (the repo squash-merges PRs). After opening the PR,
confirm both CI jobs run and go green on the PR and that the README badge
resolves. On merge, **promote** per `planning/README.md`: move
`planning/changes/active/2026-06-18.03-ci/` to `planning/changes/archive/`,
set its `design.md` frontmatter to `status: shipped` with the merge `pr`/
`outcome`, and move its README Index line from **Active** to **Archived** — in
a follow-up promotion PR, as with bundles 1–2.
