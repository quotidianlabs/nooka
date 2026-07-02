---
status: accepted
summary: Upload the Play AAB with the r0adkll/upload-google-play GitHub Action (binary only), not fastlane supply or Gradle Play Publisher; store listing stays manual in the console.
supersedes: null
superseded_by: null
---

# Play uploads use the r0adkll GitHub Action, binary only

**Decision:** CI uploads the release AAB to Google Play with the maintained
`r0adkll/upload-google-play` action, fed a service-account JSON secret. Store
listing text, screenshots, and graphics are managed manually in the Play
Console; publishing metadata as code is not adopted.

## Context

The `2026-07-02.01-publish-google-play` change needs a CI-to-Play upload path.
Three mechanisms were on the table:

1. **`r0adkll/upload-google-play`** — a GitHub Action wrapping the Play Developer
   API. Thin CI step, service-account JSON, uploads the AAB to a chosen track.
   Binary only.
2. **fastlane `supply`** — Ruby-based; can also sync listing text, screenshots,
   and metadata as code, but adds a Ruby toolchain, `Gemfile`, and fastlane
   config to the repo.
3. **Gradle Play Publisher (Triple-T)** — publishing wired into the Android
   Gradle build via a plugin + `gradlew` task; couples build and release and sits
   awkwardly under Flutter's Gradle.

## Decision & rationale

Chose option 1. It matches nooka's existing lean-CI style (`release.yml` is a
sequence of small shell/action steps) and adds **no new toolchain** — no Ruby,
no Gradle plugin coupling. The upload is a single guarded step alongside the
existing APK/GitHub-Release steps.

fastlane's one real advantage over the action is **metadata-as-code**, and that
advantage does not pay for its cost here: the first store listing (title,
descriptions, 512 icon, 1024×500 feature graphic, EN+RU screenshots) must be
created manually in the console for the initial submission regardless, and the
listing changes rarely afterward. Paying a permanent Ruby-toolchain tax to
manage text that changes a few times a year is a poor trade for a solo
maintainer. Gradle Play Publisher was rejected for coupling release into the
build and for the Flutter-Gradle friction, with no offsetting benefit over the
action.

## Revisit trigger

Reopen if listing metadata starts changing often enough that manual console edits
become a burden (e.g. frequent A/B copy tests or many locales), or if the
`r0adkll` action becomes unmaintained — at which point migrating to fastlane
`supply` for metadata-as-code, or Gradle Play Publisher, is reconsidered.
