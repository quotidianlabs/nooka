---
status: accepted
summary: Upload to RuStore with the cianru Gradle plugin (applied unconditionally; it only registers inert publishRustore* tasks), not a hand-rolled API script or manual-only uploads; the plugin encapsulates RuStore's RSA-JWE auth.
supersedes: null
superseded_by: null
---

# RuStore uploads use the cianru Gradle plugin

**Decision:** CI uploads the release APK to RuStore with
`ru.cian.rustore-publish-gradle-plugin`, applied unconditionally in
`android/app/build.gradle.kts`'s `plugins {}` block, fed a `key_id`/`client_secret` credential
from the `RUSTORE_CREDENTIALS` secret.

## Context

The `2026-07-03.01-publish-rustore` change needs a CI-to-RuStore upload path.
Unlike Google Play (where the thin `r0adkll/upload-google-play` action existed —
see `2026-07-02-play-upload-via-r0adkll-action`), RuStore has **no first-party
GitHub Action**, and its public API authenticates by **RSA-signing a timestamp
with a private key** to mint a short-lived JWE token. Options:

1. **cianru Gradle plugin** — encapsulates the RuStore API auth and upload;
   `./gradlew publishRustoreRelease`. Couples publishing into the Gradle build.
2. **Custom shell/Python API script** — thin CI step, but we hand-maintain the
   RSA signing, JWE handling, and the multi-call upload/submit flow.
3. **Manual upload** — no automation; upload each APK in the RuStore Console.

## Decision & rationale

Chose option 1. The RuStore auth is exactly the kind of fiddly crypto that a
maintained plugin should own; re-implementing RSA-JWE signing in shell (option 2)
is fragile and a poor use of a solo maintainer's time, with no offsetting
benefit. Manual upload (option 3) was rejected because the maintainer wanted the
Play-equivalent automation, and RuStore uploads are frequent enough to be worth
automating.

The plugin's one real downside — coupling publishing into the Android Gradle
build (the very thing the Play decision avoided) — is mitigated instead by the
plugin registering only **inert** `publishRustore*` tasks (no build-output
change), with the upload running solely in the guarded stable-tag release step.
Conditional application under `-PrustorePublish` was considered but rejected:
configuring the `rustorePublish` extension that way requires naming the
plugin's extension class, which is undocumented. `flutter analyze` and
`flutter test` are pure-Dart and never touch Gradle; only `flutter build`
resolves the pinned, cached plugin.

## Revisit trigger

Reopen if the cianru plugin becomes unmaintained or breaks against a RuStore API
change, or if RuStore ships a first-party GitHub Action / a simple
token-exchange auth (no local key signing) — at which point a thin CI script
becomes the lighter option, matching the Play approach.
