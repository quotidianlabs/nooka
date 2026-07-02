---
summary: Release workflow now builds a signed AAB and uploads it to Google Play (prerelease->closed track, stable->production, guarded on a service-account secret); adds a GitHub Pages privacy policy, a Data Safety mapping doc, and a signup/closed-testing runbook.
---

# Design: Publish nooka to Google Play

## Summary

Ship nooka on Google Play in addition to the existing sideload channel. The
current release pipeline (`.github/workflows/release.yml`) builds a signed
universal **APK** on an `X.Y.Z` tag and attaches it to a GitHub Release. This
change adds a Play track on top of it, with two interleaved parts. **(A) Repo/CI
work, buildable now:** extend the same release job to also `flutter build
appbundle --release` and upload the **AAB** to Play via the maintained
`r0adkll/upload-google-play` action, keyed by a service-account secret; publish
a **privacy policy** to GitHub Pages (required because of the Google Drive
backup OAuth); and add a **Data Safety** mapping doc so the console form is
reproducible. **(B) Manual console/account work, only the maintainer can do:** a
sequenced runbook (`docs/play-release.md`) covering account signup, Play App
Signing, the Google Cloud service account, store listing + assets, content
rating, Data Safety, closed testing, and the first upload. The CI is designed to
run **before the Play account exists** — a tag still cuts the GitHub Release and
cleanly skips the Play upload when the secret is absent. The app id
(`io.github.quotidianlabs.nooka`), version scheme (`pubspec` `X.Y.Z+N`), and
signing keystore are unchanged.

## Motivation

nooka is distributed only as a sideload APK from GitHub Releases (see
`docs/release.md`): users must download an `.apk` and enable "install unknown
apps". That is a real adoption barrier and excludes the discovery, auto-update,
and trust that a Play listing provides. The app is feature-complete enough to
publish (v1.2.1, bilingual EN+RU, local-first with optional Drive backup), so
the blocker is purely distribution plumbing and store compliance, not product
work.

Google Play requires an **AAB**, not an APK; the current pipeline produces only
an APK. It also requires a hosted **privacy policy** and a **Data Safety**
declaration, which the Drive-backup OAuth surface makes mandatory. And a
**new personal developer account** (the maintainer's situation) cannot publish
straight to production: Google requires a **closed test with 12+ testers
opted-in for 14 continuous days** first. So the design is inherently phased, and
the automation must tolerate a long pre-production window.

## Non-goals

- **Store-listing metadata as code.** The `r0adkll` action uploads the binary
  only; listing text, screenshots, and graphics are managed manually in the
  console (they are one-time creative work). fastlane `supply` / metadata-as-code
  is explicitly rejected here (see `decisions/`).
- **Replacing the GitHub Release / sideload channel.** The APK → GitHub Release
  steps stay; Play is added alongside, not instead.
- **Staged / percentage rollout.** First releases publish at 100% (`completed`
  status). Staged rollout (`inProgress` + `userFraction`) is a later toggle.
- **iOS App Store.** Out of scope; this change is Android/Play only.
- **Automatic versionCode derivation.** `versionCode` stays sourced from
  `pubspec` `+N` (the existing convention); no CI-run-number scheme.
- **Managing the 14-day closed test in code.** Enrolling testers and the waiting
  period are manual console operations captured in the runbook.

## Design

### 1. AAB build + Play upload (extends `release.yml`)

The existing `release` job already reconstructs the keystore and
`android/key.properties` from org secrets and runs `flutter build apk --release`
with a `GOOGLE_SERVER_CLIENT_ID` dart-define. Add, in the **same job** after the
existing APK/GitHub-Release steps:

```yaml
- name: Build signed release AAB
  run: |
    flutter build appbundle --release \
      --dart-define=GOOGLE_SERVER_CLIENT_ID=103089031104-03r0mq3lfdkg6snffok3ptfjae4cmq17.apps.googleusercontent.com

# Guard: only attempt Play upload when the service-account secret is present.
# This lets tags cut a GitHub Release (and skip Play) before the account exists.
- name: Check Play credentials
  id: play
  env:
    SA_JSON: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
  run: |
    if [ -n "${SA_JSON:-}" ]; then
      echo "enabled=true" >> "$GITHUB_OUTPUT"
    else
      echo "::notice::PLAY_SERVICE_ACCOUNT_JSON not set — skipping Play upload."
      echo "enabled=false" >> "$GITHUB_OUTPUT"
    fi

- name: Upload AAB to Google Play
  if: steps.play.outputs.enabled == 'true'
  uses: r0adkll/upload-google-play@v1        # v1.1.5 at time of writing
  with:
    serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
    packageName: io.github.quotidianlabs.nooka
    releaseFiles: build/app/outputs/bundle/release/app-release.aab
    tracks: ${{ steps.meta.outputs.play_track }}   # `tracks` (plural); `track` is deprecated
    status: completed
```

The AAB is signed by the same reconstructed upload keystore as the APK (the
`signingConfigs.release` in `android/app/build.gradle.kts` applies to every
release build type, AAB included). No signing changes.

**Track mapping — reuses the existing prerelease convention.** The workflow
already computes `prerelease` from a `-suffix` tag. Extend the `meta` step to
also emit `play_track`:

- prerelease tag (`X.Y.Z-beta.N`) → **closed testing** track, name from repo
  variable `vars.PLAY_CLOSED_TRACK` (default `alpha`).
- stable tag (`X.Y.Z`) → `production`.

This makes the closed-testing period (prerelease tags → closed track) and the
eventual production cutover (stable tag → production) fall out of the tag naming
already in use, and structurally prevents a beta from landing in production.

Pin `r0adkll/upload-google-play` to a specific released major (`@v1`); confirm
the exact current tag against the action's releases during implementation rather
than assuming.

### 2. Privacy policy on GitHub Pages

Play requires a publicly reachable privacy policy URL, and the Drive-backup
OAuth makes it mandatory. Serve it from this repo without exposing the developer
`docs/`:

- Source: **plain static HTML** — `site/privacy/index.html` (policy) +
  `site/index.html` (minimal landing). Static HTML (not Jekyll/markdown) keeps
  the pipeline build-free and deterministic: no Gemfile, no theme, no `baseurl`
  handling (links are relative), and each file opens locally for verification.
- A new `.github/workflows/pages.yml` uploads only the `site/` directory as the
  Pages artifact and deploys it via the official Pages actions
  (`actions/configure-pages@v5`, `actions/upload-pages-artifact@v3`,
  `actions/deploy-pages@v5`), with the Pages source set to **GitHub Actions**.
  Only `site/` is published — the dev `docs/` and `planning/` stay private.
- URL: `https://quotidianlabs.github.io/nooka/privacy` (served by
  `site/privacy/index.html` as the directory index).

Policy content, matching the code (`architecture/backup-io.md`): nooka is
local-first; **no developer backend, analytics, ads, or tracking**; all task
data is stored on-device in SQLite; the optional Google Drive backup writes
**only** to the user's own hidden `appDataFolder` via the non-sensitive
`drive.appdata` scope, invisible to the developer and other apps; the Google
account **email** is read solely to display "connected as" in Settings and is
never transmitted to the developer; data deletion = uninstall the app and/or
delete the backup files from the user's own Drive; plus a contact email and a
last-updated date.

### 3. Data Safety mapping doc

Add `docs/play-data-safety.md` translating section 2 into the exact answers the
Play Console **Data Safety** form expects, so the declaration is reproducible
and defensible: which data types are collected/shared **by the developer**
(none — the app has no backend; the Drive backup is the user acting on their own
account), that data is **encrypted in transit** (Google APIs over HTTPS), and
the deletion story. This doc is the single source of truth for what gets typed
into the console.

### 4. Runbook `docs/play-release.md` (the manual track, sequenced)

A step-by-step operator guide, ordered with explicit blocking dependencies:

1. **Register** a Google Play Console developer account ($25 one-time + identity
   verification). Note: new personal accounts face the 12-tester / 14-day
   closed-test gate before production.
2. **Create the app** entry `io.github.quotidianlabs.nooka` (default language
   English; add Russian localization; category + tags).
3. **Play App Signing:** opt in at first upload. The existing upload-keystore
   becomes the **upload key**; Google generates and holds the **app signing
   key**. This is **irreversible** — call it out.
4. **Service account:** in Google Cloud, enable the *Google Play Android
   Developer API*, create a service account + JSON key; in Play Console →
   Users & permissions, invite the service-account email with release
   permission. Wait for propagation (can be hours). Store the JSON as GitHub
   secret `PLAY_SERVICE_ACCOUNT_JSON`; set repo variable `PLAY_CLOSED_TRACK`.
5. **Store listing:** title, short description (≤80), full description (≤4000),
   512×512 icon, 1024×500 feature graphic, ≥2 phone screenshots — in **both
   EN and RU** (the app is bilingual).
6. **Content rating** (IARC questionnaire).
7. **Data Safety** form (from `docs/play-data-safety.md`) + the privacy policy
   URL from section 2.
8. **Target audience / ads** declaration (no ads).
9. **Seed the closed track:** push a prerelease tag → CI uploads the AAB to the
   closed track. Enroll 12+ testers (Google Group or email list); run 14 days.
10. **Production:** after the 14-day test, apply for production access; once
    granted, push a stable `X.Y.Z` tag → CI publishes to `production`.

## Operations

All out-of-repo, by the maintainer, captured in the runbook above: Play Console
registration + verification, app creation, Play App Signing enrollment, Google
Cloud service-account creation and Play permission grant, GitHub secret
(`PLAY_SERVICE_ACCOUNT_JSON`) + variable (`PLAY_CLOSED_TRACK`) configuration,
store assets, and enabling GitHub Pages for the repo. No DNS.

## Out of scope

See Non-goals: metadata-as-code, replacing the sideload APK, staged rollout,
iOS, CI-derived versionCode, and automating the closed-test enrollment.

## Testing

- **AAB build & signing.** CI produces `app-release.aab`; verify it is
  **upload-signed, not debug**, mirroring the existing apksigner/`jarsigner`
  check documented for the APK in `docs/release.md`. Locally, `flutter build
  appbundle --release` with a present `key.properties` must succeed.
- **Guarded skip.** With `PLAY_SERVICE_ACCOUNT_JSON` unset, a pushed tag must
  still cut the GitHub Release and skip the Play step with a notice (this is the
  pre-account behavior). Verifiable by tagging before the secret exists.
- **Play upload.** The integration proof is the Play Console accepting the AAB on
  the closed track after a prerelease tag; the action fails loudly on a bad
  service account, duplicate `versionCode`, or track error.
- **Privacy Pages.** After `pages.yml` runs, the deployed
  `https://quotidianlabs.github.io/nooka/privacy` URL renders the policy.
- **Docs.** Update `docs/release.md` to document the AAB/Play pipeline alongside
  the APK/GitHub-Release one. No `architecture/` capability doc changes — this is
  release infrastructure, not app behavior. Final gate: `just lint-ci` clean.

## Risk

- **Play policy / listing rejection (likely x medium).** Data Safety mismatch,
  missing screenshots, or content-rating gaps can bounce a submission.
  Mitigation: the Data Safety mapping doc keeps the form honest and reproducible;
  the runbook enumerates every required asset up front.
- **Service-account permission propagation (medium x medium).** The action fails
  until the service account's Play permission propagates (can take hours).
  Mitigation: runbook flags the delay; the guarded skip means an early tag does
  not hard-fail the whole release.
- **Duplicate versionCode rejection (medium x low).** Play rejects a
  `versionCode` already used. Mitigation: runbook mandates bumping `pubspec` `+N`
  every release; the upload step surfaces the rejection loudly.
- **14-day closed-test gate misunderstood (medium x medium).** Expecting instant
  production is the most likely process failure. Mitigation: the phased track
  mapping (prerelease→closed, stable→production) and the runbook make the gate
  explicit and unavoidable.
- **Play App Signing is irreversible (low x high).** Enrolling with the wrong
  upload key is permanent for the app. Mitigation: the runbook has the operator
  enroll with the known existing upload-keystore and verify signing before the
  first production release.
- **Action supply-chain / version drift (low x medium).** A third-party publish
  action is a CI dependency. Mitigation: pin to a released major and confirm the
  current tag during implementation; the action only ever runs on tag pushes.
```
