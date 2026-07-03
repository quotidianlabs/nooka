---
status: accepted
summary: Upload to RuStore with the cianru Gradle plugin (applied only under -PrustorePublish), not a hand-rolled API script or manual-only uploads; the plugin encapsulates RuStore's RSA-JWE auth.
supersedes: null
superseded_by: null
---

# RuStore uploads use the cianru Gradle plugin

**Decision:** CI uploads the release APK to RuStore with
`ru.cian.rustore-publish-gradle-plugin`, applied in `android/app/build.gradle.kts`
only when `-PrustorePublish` is passed, fed a `key_id`/`client_secret` credential
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
build (the very thing the Play decision avoided) — is neutralized by applying it
**only under `-PrustorePublish`**, so normal `flutter build` / `analyze` / `test`
never resolve or run it, and it executes only on stable-tag release runs.

## Revisit trigger

Reopen if the cianru plugin becomes unmaintained or breaks against a RuStore API
change, or if RuStore ships a first-party GitHub Action / a simple
token-exchange auth (no local key signing) — at which point a thin CI script
becomes the lighter option, matching the Play approach.
