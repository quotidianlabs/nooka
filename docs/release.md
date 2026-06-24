# Releasing via GitHub Releases

How nooka ships a build: pushing an `X.Y.Z` tag builds a signed **universal**
APK and publishes a GitHub Release with it attached. Driven by
[`.github/workflows/release.yml`](../.github/workflows/release.yml).

This is a sideload distribution channel (download the APK from the release page
and install it). There is no Play Store `.aab` pipeline.

## Signing

Release signing is wired in `android/app/build.gradle.kts`: it loads
`android/key.properties` into `signingConfigs.release` and uses it for the
`release` build type when present, else falls back to the debug key. Both the
keystore and `key.properties` are gitignored (`android/.gitignore`).

`android/key.properties` format:

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

> The CI build reconstructs this file from the org secrets below; you only need
> a local `key.properties` to produce a signed build *on your machine*.

### Verify a build is upload-signed (not debug)

A `release` build without `key.properties` silently falls back to the debug key
— fine for `flutter run --release`, **wrong** for anything you distribute. After
building, confirm the signing identity:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
# The certificate DN must NOT be CN=Android Debug.
```

## Signing secrets (inherited from the org)

The workflow consumes four secrets that are defined **at the GitHub org level**
and shared with this repo — the same ones habbits uses. There is no per-repo
setup and no separate keystore to create:

| Secret | Value |
|--------|-------|
| `ANDROID_KEYSTORE_BASE64` | base64 of `upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_PASSWORD` | the key password (often same as store) |
| `ANDROID_KEY_ALIAS` | `upload` |

The workflow fails loudly if `ANDROID_KEYSTORE_BASE64` is missing — it will
never silently fall back to debug-signing.

> **Distinct app, shared upload key.** The APK is signed with the org upload key
> under nooka's `applicationId` (`io.github.quotidianlabs.nooka`). It is a
> different app from habbits despite sharing the key — no install conflict.

## Versioning

`pubspec.yaml` → `version: X.Y.Z+N`:

- `X.Y.Z` → `versionName` (the human version shown to users).
- `+N` → `versionCode` (an integer used for ordering).

Bump `+N` (and `X.Y.Z` when appropriate) before each release. The release
workflow checks the **tag's core `X.Y.Z`** against `pubspec.yaml` and fails if
they disagree.

## Cutting a release

1. Bump `pubspec.yaml` `version: X.Y.Z+N` and merge to `main`.
2. (Optional) Write user-facing notes to `planning/releases/X.Y.Z.md`. If
   present, they become the release body; GitHub's auto-generated "What's
   Changed" PR list is appended either way.
3. Tag and push — the tag `X.Y.Z` **must** match `pubspec.yaml` `X.Y.Z`:

   ```bash
   git tag 1.0.0
   git push origin 1.0.0
   ```

4. The workflow builds `nooka-X.Y.Z.apk` and publishes the GitHub Release.

### Pre-releases (alpha / beta / rc)

Tag with a semver pre-release suffix to ship a test build:

```bash
git tag 1.0.0-beta.1
git push origin 1.0.0-beta.1
```

The workflow accepts `X.Y.Z-<suffix>` tags, matches the **core** `X.Y.Z`
against `pubspec.yaml` (the pubspec carries no `-suffix`), and flags the GitHub
Release as a **pre-release** so it is not marked "Latest". Notes resolve from
`planning/releases/<tag>.md` (e.g. `planning/releases/1.0.0-beta.1.md`).

> The APK's internal `versionName` comes from `pubspec.yaml` (`X.Y.Z`), so a
> beta and its final share a `versionName`; the differing `versionCode` (`+N`)
> is what orders installs. The `-beta.1` label lives in the tag, asset name, and
> GitHub Release, not inside the APK.
