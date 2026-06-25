# ci-release — implementation plan

**Goal:** A pushed `X.Y.Z` tag builds a signed universal APK and publishes a
GitHub Release; release builds are upload-signed, not debug-signed.

**Spec:** [`design.md`](./design.md)

**Branch:** `feat/ci-release`

**Commit strategy:** Single commit (one coherent infra port).

---

### Task 1: Wire real release signing into the Android build

**Files:**
- Modify: `android/app/build.gradle.kts`

Replace Flutter's debug-signing scaffold stub with `key.properties`-driven
release signing (graceful debug fallback when the keystore is absent).

- [x] Load `android/key.properties` if present; define `signingConfigs.release`
      from it; `buildTypes.release` uses it when present, else the debug key.

### Task 2: Add the tag-driven release workflow

**Files:**
- Create: `.github/workflows/release.yml`

Port habbits' workflow: tag → verify-vs-pubspec → decode keystore from org
secrets (hard-fail if missing) → build `nooka-X.Y.Z.apk` → publish GitHub
Release. `actions/checkout@v4` to match `ci.yml`; pre-release detection on
`-suffix` tags.

- [x] Workflow created with the verify, decode, build, and publish steps.

### Task 3: Document the release process

**Files:**
- Create: `docs/release.md`
- Create: `planning/releases/1.0.0.md`

Sideload-channel docs (signing, inherited org secrets, cutting a release,
pre-releases, the `apksigner` verify step) and a seed release-notes file.

- [x] `docs/release.md` written (no Play `.aab` content, per scope).
- [x] `planning/releases/1.0.0.md` seeded.

### Task 4: Verify and commit

- [x] `just lint-ci` clean on a committed tree.
- [x] `just index` lists the new change.
- [x] `flutter build apk --release` locally (with the existing
      `android/key.properties` → `/Users/kevinsmith/upload-keystore.jks`) is
      **upload-signed, not debug**: `apksigner` signer DN is `CN=Unknown` (not
      `CN=Android Debug`) and its cert SHA-256 matches the keystore exactly.
- [x] Commit all files on `feat/ci-release`.
- [ ] (out of band) Push an `X.Y.Z` tag to exercise the workflow end-to-end.
