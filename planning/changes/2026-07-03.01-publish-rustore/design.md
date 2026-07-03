---
summary: RuStore publishing added — a guarded CI upload of the existing signed universal APK via the cianru Gradle plugin 0.5.5 (stable tags only, publishRustoreRelease), reusing the GitHub Pages privacy policy, plus an account/listing runbook; the unverifiable Google Play path is dropped.
---

# Design: Publish nooka to RuStore

## Summary

Distribute nooka on **RuStore** (VK's Russian Android store) as a third channel
next to the existing GitHub-Releases APK sideload. On a **stable** version tag,
the release job uploads the **already-built signed universal APK** to RuStore via
the community `ru.cian.rustore-publish-gradle-plugin`, **guarded** on a new
`RUSTORE_CREDENTIALS` secret so tags still cut a GitHub Release before the
RuStore account exists. The GitHub Pages **privacy policy** and its deploy
workflow (carried onto this branch from the closed Play PR) are reused verbatim —
RuStore also requires a privacy policy. A new `docs/rustore-release.md` runbook
covers the manual account, listing, and first-upload steps. No app behavior
changes: the same build ships everywhere, and the optional Google Drive backup
degrades gracefully on devices without Google Play Services.

## Motivation

nooka's only store-independent channel is a sideload APK from GitHub Releases;
there is no app-store presence. Google Play is **not attainable** for the
maintainer: Play verifies identity against the payment-profile country, the
maintainer holds only Russian documents (which cannot match the Germany profile,
and the account country cannot be changed), and Play payments are unavailable
from Russia. The Play pipeline (branch/PR #40) was therefore **closed unmerged**.

RuStore is the realistic store for a maintainer in Russia: an **individual**
developer account needs only a **VK ID** to create and a **passport photo** to
verify — no fee, no foreign payment method, and no closed-testing gate. RuStore
accepts a self-signed APK directly, so most of the release plumbing already
exists. This gets nooka into a real store with a small, guarded addition to the
current pipeline.

## Non-goals

- **Google Play.** Dropped entirely (unverifiable for this maintainer). The
  Play-specific AAB build, upload step, `play-release.md`, and
  `play-data-safety.md` are **not** carried over from PR #40.
- **AAB on RuStore.** We upload the universal **APK** we already build for GitHub
  Releases. RuStore's separate-AAB-signature handling buys nothing here for a
  small app.
- **A Google-free build flavor.** No separate RuStore flavor that strips the
  Drive backup. The one build ships everywhere; Drive backup degrades gracefully
  where Google Play Services is absent (see §4).
- **Monetization.** nooka is free with no ads, so no self-employed/самозанятый
  registration or RuStore billing SDK.
- **RuStore SDK integration.** No in-app updates / push / billing SDK; basic
  publishing needs none.
- **Prerelease uploads to RuStore.** RuStore has no closed-test track; only
  stable tags publish there. Prerelease tags stay GitHub-Releases-only.

## Design

### 1. The published artifact

Upload the **signed universal APK** the release job already produces for the
GitHub Release: `build/app/outputs/flutter-apk/app-release.apk`. RuStore has **no
Play-style app signing** — the APK's own signature is the app's identity, so the
existing upload keystore (reconstructed in CI from org secrets) is all that is
needed. No new signing config, no new artifact type.

### 2. CI upload via the cianru Gradle plugin (`release.yml` + `build.gradle.kts`)

RuStore's public API authenticates by **RSA-signing a timestamp with a private
key** to obtain a short-lived JWE token — fiddly to hand-roll in shell, and there
is no first-party GitHub Action. The maintained `ru.cian.rustore-publish-gradle-plugin`
encapsulates that auth, so it is the sensible automation path (this is the
opposite of the Play decision, where a thin action existed — recorded in
`decisions/`).

- **Plugin application.** Apply `ru.cian.rustore-publish-gradle-plugin` (pinned
  **0.5.5**) in `android/app/build.gradle.kts`'s `plugins {}` block — the
  documented, robust pattern (conditional apply would require naming the plugin's
  extension class, which is undocumented; not guessed). It registers only inert
  `publishRustore*` tasks, so it changes no build output. `flutter analyze` and
  `flutter test` are pure-Dart and never touch Gradle; only `flutter build` /
  Gradle resolves the plugin (cached), and the upload task runs solely in the
  guarded release step below. Configure a `rustorePublish` instance for the
  `release` variant: `buildFormat = APK`, `buildFile` at the Flutter APK output,
  `credentialsPath` = a file written from the secret, `publishType`,
  `developerContacts`, and a static `ru-RU` `releaseNotes` file.
- **Workflow step (`release.yml`).** After the existing APK build, on **stable
  tags only** and **guarded** on `RUSTORE_CREDENTIALS`:

  ```yaml
  - name: Check RuStore credentials
    id: rustore
    env:
      RS: ${{ secrets.RUSTORE_CREDENTIALS }}
    run: |
      set -euo pipefail
      if [ -n "${RS:-}" ] && [ "${{ steps.meta.outputs.prerelease }}" = "false" ]; then
        echo "enabled=true" >> "$GITHUB_OUTPUT"
      else
        echo "::notice::RuStore upload skipped (no creds or prerelease tag)."
        echo "enabled=false" >> "$GITHUB_OUTPUT"
      fi

  - name: Upload APK to RuStore
    if: steps.rustore.outputs.enabled == 'true'
    working-directory: android
    env:
      RUSTORE_CREDENTIALS: ${{ secrets.RUSTORE_CREDENTIALS }}
    run: |
      set -euo pipefail
      printf '%s' "$RUSTORE_CREDENTIALS" > rustore-credentials.json
      ./gradlew :app:publishRustoreRelease \
        --buildFile="$GITHUB_WORKSPACE/build/app/outputs/flutter-apk/nooka-${GITHUB_REF_NAME}.apk"
  ```

  Absent secret or a prerelease tag → the step is skipped with a `::notice::`;
  the GitHub Release still ships. The plugin version is **pinned**; the exact
  task name, credential JSON field names (`key_id` / `client_secret`), and CLI
  flags are confirmed against the plugin README during implementation, not
  assumed. `publishType` defaults to `INSTANTLY` (auto-submit to RuStore
  moderation), matching the Play pipeline's auto intent; switching to `MANUAL`
  (upload as a draft, submit by hand) is a one-line change.

### 3. Track / trigger & versioning

RuStore has no closed-testing gate, so the mapping is simply: **stable tag
(`X.Y.Z`) → RuStore**; prerelease tags are skipped (GitHub-Releases only).
`versionCode` stays sourced from `pubspec.yaml` `+N` (existing convention);
RuStore, like Play, requires it **strictly increasing**.

### 4. Google Drive backup on RuStore devices

The optional cloud backup uses `google_sign_in` (Google Play Services). RuStore
runs on ordinary Android devices, most of which in Russia still ship GMS, so the
feature works for those users. On a **GMS-less device**, connecting Drive fails
and surfaces the existing localized error snackbar (per
`architecture/error-handling.md`); the local file **export/import** path (which
uses no Google APIs) works everywhere. We therefore **ship the same build** and
document the limitation — no Google-free flavor. This preserves a single build
and keeps YAGNI.

### 5. Listing & privacy (manual, runbook)

RuStore listing is Russian-first: 512×512 icon, ≥1 screenshot, description
(≤4000 chars), and an age rating. The **privacy policy** reuses the GitHub Pages
site already on this branch — `https://quotidianlabs.github.io/nooka/privacy`.
`docs/rustore-release.md` sequences: create + verify the individual account (VK
ID + passport), create the app, generate an API key in RuStore Console and store
it as `RUSTORE_CREDENTIALS`, enable GitHub Pages (source = GitHub Actions), build
the listing, and submit.

## Relationship to the Google Play work (PR #40)

PR #40 (branch `publish-google-play`) is **closed unmerged**. Its
channel-agnostic parts — the static privacy site (`site/`) and the Pages deploy
workflow (`.github/workflows/pages.yml`) — are **cherry-picked** onto the
`publish-rustore` branch and reused. The Play-specific parts (the AAB build step,
the r0adkll upload, `docs/play-release.md`, `docs/play-data-safety.md`, and the
`2026-07-02.01-publish-google-play` planning bundle) are **not** brought over.

## Operations

Manual, by the maintainer, in `docs/rustore-release.md`: RuStore individual
account creation + passport verification; app creation; API-key generation and
the `RUSTORE_CREDENTIALS` GitHub secret; enabling GitHub Pages (source = GitHub
Actions) for the privacy URL; and the Russian-language store listing (icon,
screenshots, description, age rating). No DNS.

## Testing

- **Workflow YAML validity** (`python3 -c yaml.safe_load`).
- **Guarded skip:** with `RUSTORE_CREDENTIALS` unset — or on a prerelease tag —
  the RuStore step is skipped with a notice and the GitHub Release still ships
  (verifiable by tagging before the secret exists).
- **Plugin wiring:** `./gradlew :app:tasks` (from `android/`) lists a
  `publishRustoreRelease` task, and `./gradlew :app:help` configures cleanly with
  the plugin applied (proving the `rustorePublish {}` block is valid).
- **Upload proof:** RuStore Console accepting the APK after a stable tag (the
  plugin fails loudly on bad credentials or a duplicate `versionCode`).
- **Docs:** `docs/release.md` gains a RuStore section. No `architecture/`
  capability change — this is release infra. Final gate: `just lint-ci` +
  `just check-planning` clean.

## Risk

- **Third-party plugin as a build/CI dependency (medium × medium).** The cianru
  plugin is community-maintained. Mitigation: pin the version (0.5.5); it
  registers only inert tasks so it does not change build output, and the upload
  runs only on guarded stable-tag pushes.
- **RuStore auth/credential-format drift (medium × medium).** RuStore has evolved
  its API-key schemes (companyId+private-key vs key_id+client_secret).
  Mitigation: confirm the plugin's expected credential JSON and RuStore's current
  key-generation flow during implementation; the runbook records the exact steps.
- **GMS-less Drive-backup failure (medium × low).** On devices without Google
  Play Services the Drive feature cannot connect. Mitigation: it fails gracefully
  to a localized snackbar; local export/import is the universal fallback;
  documented in the listing/runbook.
- **RuStore moderation rejection (medium × low).** Missing assets or age-rating
  gaps bounce a submission. Mitigation: the runbook enumerates every required
  asset up front.
- **Duplicate `versionCode` (low × low).** RuStore rejects a reused code.
  Mitigation: bump `pubspec.yaml` `+N` every release; the plugin surfaces the
  rejection.
