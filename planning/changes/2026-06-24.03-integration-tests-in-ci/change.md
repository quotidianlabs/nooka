---
status: draft
date: 2026-06-24
slug: integration-tests-in-ci
summary: Run the critical-flow integration test in CI on a KVM-accelerated Android emulator, with Gradle + system-image caching to keep the job fast.
supersedes: null
superseded_by: null
pr: null
outcome: null
---

# Change: Run integration tests in CI

**Lane:** lightweight — one new job in `.github/workflows/ci.yml`. No source or
test change: `integration_test/critical_flow_test.dart` already exists and is a
real pass/fail test. Ports habbits' current `ci.yml` (its PRs #28 + #29).

## Goal

`integration_test/critical_flow_test.dart` runs only locally; CI's `just test`
is `flutter test` (unit/widget only). That gap lets an on-device regression rot
red unnoticed. Add a CI job that runs the critical-flow test on an emulator so
the regression surfaces automatically — and cache the Gradle build + emulator
system image so the job stays fast on warm runs.

## Approach

A new `integration` job in `.github/workflows/ci.yml`, on `ubuntu-latest`, using
[`reactivecircus/android-emulator-runner@v2`](https://github.com/ReactiveCircus/android-emulator-runner)
with KVM hardware acceleration. Steps: checkout → `subosito/flutter-action`
(flutter 3.44.2, matching the other jobs) → enable KVM (udev rule) →
`flutter pub get` → Gradle cache → system-image cache → emulator-runner whose
`script` is `flutter test integration_test/critical_flow_test.dart`. Config:
`api-level: 34`, `target: google_apis`, `arch: x86_64`, headless emulator
options, `timeout-minutes: 20`.

Runs on the existing triggers (PRs + push to main), in parallel with lint/test —
so it catches rot *before* merge without slowing unit feedback.

The Gradle `assembleDebug` build dominates the job (~76% of wall time in
habbits' measurement), so cache `~/.gradle` (deps + build cache, keyed on the
gradle files + `pubspec.lock`) and the api-34 system image. Cold run populates;
warm runs reuse.

### Why this shape (rejected alternatives)

- **`ubuntu-latest`, not a macOS runner.** GitHub gave standard Linux runners KVM
  hardware acceleration in April 2024; the action's docs recommend Ubuntu as
  2–3× faster than macOS, which also costs ~10× the minutes.
- **`integration_test`, not Patrol.** Patrol earns its keep only for *native*
  interactions (permission dialogs, system UI); the critical-flow test needs none.
- **Self-hosted emulator-runner, not Firebase Test Lab.** FTL adds an external
  service, auth, and cost for a single test — disproportionate.
- **Gradle + system-image caching, but no AVD *snapshot* caching.** Snapshot
  caching only shortens the ~39s cold boot (<10%) and carries
  snapshot-corruption/hang gotchas — not worth it. The build cache is where the
  real speedup is.
- **Only `critical_flow_test.dart`.** `screenshots_test.dart` is a screenshot
  *generator*, not a pass/fail test — kept out of CI.

## Files

- `.github/workflows/ci.yml` — add the `integration` job (emulator run + caching).

## Verification

- [ ] Push the branch; the `integration` job appears and **passes** on the real
      runner (the only true test of a CI workflow — can't be run locally).
- [ ] Emulator boots with KVM accel and `flutter test
      integration_test/critical_flow_test.dart` is green in the job log.
- [ ] Warm run reuses the Gradle + system-image caches (cache-hit in the log).
- [ ] `lint` + `test` jobs unaffected.
