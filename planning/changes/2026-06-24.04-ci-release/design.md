---
status: shipped
date: 2026-06-24
slug: ci-release
summary: Tag-driven CI release — a pushed X.Y.Z tag builds a signed universal APK and publishes a GitHub Release, plus real release signing wired into the Android build.
supersedes: null
superseded_by: null
pr: 22
outcome: |
  Ported habbits' release apparatus (CI GitHub-Release channel only). Replaced
  the gradle scaffold stub that debug-signed release builds with
  key.properties-driven upload signing (graceful debug fallback when keyless).
  Added .github/workflows/release.yml: a pushed X.Y.Z/X.Y.Z-suffix tag verifies
  against pubspec, decodes the org keystore secrets (hard-fail if missing),
  builds nooka-X.Y.Z.apk, and publishes a GitHub Release with notes from
  planning/releases/<tag>.md. Added docs/release.md (sideload channel) and a
  1.0.0 notes seed. No ci.yml or app-code change; no Play .aab/compileSdk pin
  (out of scope), no desugaring (nooka has no notifications). Signing fix proven
  locally: flutter build apk --release is upload-signed (apksigner DN CN=Unknown,
  cert SHA-256 matches the keystore), not debug. Workflow end-to-end unexercised
  — only fires on a real tag push.
---

# Design: Tag-driven CI release with signed Android builds

## Summary

nooka's CI already lints, tests, and runs the critical-flow integration test,
but there is no way to *cut a release*. Port habbits' release apparatus: a
pushed `X.Y.Z` tag triggers `.github/workflows/release.yml`, which builds a
**signed universal APK** and publishes a GitHub Release with the APK attached
and notes resolved from `planning/releases/<tag>.md`. Wiring this up also fixes
a standing bug — nooka's `android/app/build.gradle.kts` still carries Flutter's
scaffold stub (`signingConfig = signingConfigs.getByName("debug")`), so today a
local `flutter build apk --release` is **debug-signed**.

## Motivation

- **No release path.** There is no automated, repeatable way to produce a
  shippable artifact. habbits solved this (its release.yml + signing config);
  nooka should match.
- **Release builds are debug-signed.** The gradle `release` build type signs
  with the debug key. A debug-signed "release" APK is rejected by Play and is a
  weak/identifiable signing identity for sideload. This is the concrete bug the
  port closes.

## Non-goals

- **No Play Store apparatus.** No `.aab` build, no `compileSdk`/`targetSdk` pin
  to 36, no Play upload docs. Scope is the CI GitHub-Release sideload channel
  only. (habbits documents both; nooka takes the CI half.)
- **No `ci.yml` change.** nooka's existing CI (lint/test/integration) is current
  and untouched.
- **No app/source code change.** Build infrastructure only.
- **No desugaring.** habbits enables core-library desugaring for
  `flutter_local_notifications`; nooka has no notifications dependency, so its
  gradle port is leaner.

## Design

### 1. Release signing (`android/app/build.gradle.kts`)

Replace the scaffold stub with habbits' `key.properties`-driven signing,
minus the notification-specific desugaring:

- Load `android/key.properties` (already gitignored in nooka) if it exists.
- Define `signingConfigs.release` from those properties **only when the file is
  present**.
- `buildTypes.release` uses the `release` signing config when the keystore is
  present, else **falls back to the debug key**.

The graceful local fallback is deliberate: a contributor without the keystore
can still `flutter run --release`. The guards against an *accidental*
debug-signed release live elsewhere — the workflow hard-fails if the keystore
secret is missing (§2), and the release docs give an explicit verify command
(§3). `compileSdk`/`targetSdk` stay on the Flutter defaults (no Play pin).

### 2. Release workflow (`.github/workflows/release.yml`)

Straight port of habbits' workflow, on push of a tag matching `X.Y.Z` or
`X.Y.Z-<suffix>`, with `permissions: contents: write`:

1. Checkout + `subosito/flutter-action` (flutter 3.44.2, matching `ci.yml`).
2. **Verify tag matches pubspec** — the tag's core `X.Y.Z` (suffix stripped)
   must equal `pubspec.yaml` `version: X.Y.Z+N`, else fail.
3. **Decode the signing keystore** from `ANDROID_KEYSTORE_BASE64`; hard-fail if
   the secret is empty/missing (never silently debug-sign).
4. **Write `android/key.properties`** from the store/key/alias secrets.
5. `flutter pub get` → `flutter build apk --release` → rename to
   `nooka-X.Y.Z.apk`.
6. **Resolve metadata** — notes from `planning/releases/<tag>.md` if present;
   flag as a GitHub pre-release when the tag carries a `-<suffix>`.
7. **Publish** via `softprops/action-gh-release@v3` with the APK attached and
   `generate_release_notes: true`.

Project-specific deltas from habbits' file: asset name `nooka-*` (not
`habbits-*`); action major versions pinned to match nooka's existing `ci.yml`
(`actions/checkout@v4`) for repo-internal consistency.

### 3. Release docs (`docs/release.md`)

The sideload-channel sections only: signing model, the inherited org secrets,
cutting a release (bump `pubspec`, optional notes, tag + push), pre-releases,
and the **upload-signed verification** command
(`apksigner verify --print-certs` → DN must not be `CN=Android Debug`). No Play
`.aab` / target-API content.

### 4. Release notes (`planning/releases/`)

Create the directory (`planning/README.md` already documents
`releases/<semver>.md`) and seed `1.0.0.md` with first-release notes, mirroring
habbits.

## Operations

**Signing secrets are inherited from the org** — the same
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`,
`ANDROID_KEY_ALIAS` that habbits consumes. No per-repo secret creation and no
new keystore: the org upload key already exists. The only repo-side requirement
is that the org secrets are visible to this repo (already true for habbits).
The APK is signed with that org upload key under nooka's distinct
`applicationId` (`io.github.quotidianlabs.nooka`) — no conflict with habbits.

## Testing

- `just lint-ci` passes on a clean, committed tree (gradle is not
  dart-formatted, but the tree must be clean).
- **Signing fix is locally verifiable** once a keystore + `key.properties`
  exist: `flutter build apk --release` then `apksigner verify --print-certs`
  shows a non-debug DN.
- **End-to-end** is verifiable only by pushing a real tag (the org secrets make
  the build self-contained): the workflow builds `nooka-X.Y.Z.apk` and the
  GitHub Release appears with the asset attached.

## Risk

- **Wrong/absent secret visibility** → build fails loudly at the decode step
  (by design — better than a silent debug-sign). Mitigation: org secrets are
  already proven by habbits.
- **Tag/pubspec drift** → caught by the verify-tag step before any build.
- **Local debug-signed release slips through** → mitigated by the documented
  `apksigner` verify step; the gradle fallback stays for `flutter run --release`
  ergonomics rather than hard-failing every keyless build.
