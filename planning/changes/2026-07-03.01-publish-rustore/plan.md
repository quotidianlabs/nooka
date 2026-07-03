# Publish to RuStore — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a stable version tag, upload the existing signed universal APK to
RuStore via the cianru Gradle plugin (guarded on a credentials secret), and add
the account/listing runbook.

**Spec:** [`design.md`](./design.md)

**Branch:** `publish-rustore` (already created; carries the privacy site + Pages
workflow cherry-picked from the closed Play PR).

**Commit strategy:** Per-task commits.

## Global constraints

Copied verbatim from the spec; every task inherits these.

- **Plugin:** `ru.cian.rustore-publish-gradle-plugin`, pinned **0.5.5**. Version
  declared in `android/settings.gradle.kts` (`apply false`), applied in
  `android/app/build.gradle.kts`'s `plugins {}` block. It registers only inert
  `publishRustore*` tasks — no build-output change.
- **Artifact:** the universal APK the release job already builds,
  `build/app/outputs/flutter-apk/app-release.apk`. `buildFormat = APK`. No signing
  changes — RuStore has no app signing; the APK's own signature (existing upload
  keystore) is the identity.
- **Task name:** `publishRustoreRelease`. **Credentials JSON:**
  `{ "key_id": "...", "client_secret": "..." }` written to
  `android/rustore-credentials.json` (gitignored) from the `RUSTORE_CREDENTIALS`
  secret.
- **Guarded upload:** runs only when `RUSTORE_CREDENTIALS` is set **and** the tag
  is a stable `X.Y.Z` (not a prerelease). Absent secret or prerelease → skip with
  a `::notice::`, **do not fail** — the GitHub Release still ships. Uses the
  existing `meta` step's `prerelease` output.
- **`publishType = INSTANTLY`** (auto-submit to RuStore moderation).
  `developerContacts` email `me@shiriev.ru`, website
  `https://github.com/quotidianlabs/nooka`. `releaseNotes` = a static `ru-RU`
  file.
- **versionCode** stays from `pubspec.yaml` `+N`; RuStore requires it strictly
  increasing.
- **Release infra, not app behavior:** no `architecture/` change. Update
  `docs/release.md` and finalize the bundle `summary`.
- **Final gate:** `just lint-ci` clean (`dart format --set-exit-if-changed`,
  `flutter analyze`, `python3 planning/index.py --check`).

---

### Task 1: Wire the RuStore publish plugin into the Android build

**Files:**
- Modify: `android/settings.gradle.kts:20-24` (plugins block)
- Modify: `android/app/build.gradle.kts` (plugins block + a new `rustorePublish` block)
- Create: `android/app/rustore-release-notes-ru.txt`
- Modify: `android/.gitignore` (ignore the credentials file)

Applies the plugin and configures the `release` upload instance, so a
`publishRustoreRelease` task exists and the project configures cleanly. No upload
happens here (that needs credentials + the CI step in Task 2).

- [ ] **Step 1: Declare the plugin version in settings**

  In `android/settings.gradle.kts`, add the RuStore plugin to the `plugins {}`
  block (after the kotlin line):

  ```kotlin
  plugins {
      id("dev.flutter.flutter-plugin-loader") version "1.0.0"
      id("com.android.application") version "9.0.1" apply false
      id("org.jetbrains.kotlin.android") version "2.3.20" apply false
      id("ru.cian.rustore-publish-gradle-plugin") version "0.5.5" apply false
  }
  ```

- [ ] **Step 2: Apply the plugin in the app module**

  In `android/app/build.gradle.kts`, add the plugin to the `plugins {}` block
  (after the Flutter plugin):

  ```kotlin
  plugins {
      id("com.android.application")
      // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
      id("dev.flutter.flutter-gradle-plugin")
      id("ru.cian.rustore-publish-gradle-plugin")
  }
  ```

- [ ] **Step 3: Create the static Russian release-notes file**

  `android/app/rustore-release-notes-ru.txt`:

  ```
  Исправления ошибок и улучшения стабильности.
  ```

- [ ] **Step 4: Configure the RuStore upload instance**

  In `android/app/build.gradle.kts`, append at the end of the file (after the
  `flutter { source = "../.." }` block) a `rustorePublish` block. Fully-qualified
  type names avoid imports:

  ```kotlin
  // RuStore publishing (cianru plugin). Inert unless `publishRustoreRelease` is
  // invoked with a credentials file present — see .github/workflows/release.yml.
  rustorePublish {
      instances {
          create("release") {
              credentialsPath = "$rootDir/rustore-credentials.json"
              buildFormat = ru.cian.rustore.publish.BuildFormat.APK
              // Flutter writes the universal APK here (repo-root/build/...).
              buildFile = "$rootDir/../build/app/outputs/flutter-apk/app-release.apk"
              publishType = ru.cian.rustore.publish.PublishType.INSTANTLY
              developerContacts = ru.cian.rustore.publish.DeveloperContacts(
                  email = "me@shiriev.ru",
                  website = "https://github.com/quotidianlabs/nooka",
                  vkCommunity = null,
              )
              releaseNotes = listOf(
                  ru.cian.rustore.publish.ReleaseNote(
                      lang = "ru-RU",
                      filePath = "$rootDir/app/rustore-release-notes-ru.txt",
                  ),
              )
          }
      }
  }
  ```

- [ ] **Step 5: Gitignore the credentials file**

  Append to `android/.gitignore`:

  ```
  rustore-credentials.json
  ```

- [ ] **Step 6: Verify the plugin applies and the project configures**

  From the repo root:

  ```bash
  cd android && ./gradlew :app:tasks --all -q 2>&1 | grep -i publishRustore; cd ..
  ```

  Expected: the output lists `publishRustoreRelease` (proves the plugin is
  applied and the `rustorePublish {}` block configured without error).

  > If this machine has no Android SDK / network to resolve the plugin and the
  > command fails for environment reasons (not a config error), report that as a
  > concern with the exact error — do not fake the result.

- [ ] **Step 7: Verify a normal analyze is unaffected**

  ```bash
  flutter analyze 2>&1 | tail -3
  ```

  Expected: `No issues found!` (analyze is pure-Dart; the plugin does not affect it).

- [ ] **Step 8: Commit**

  ```bash
  git add android/settings.gradle.kts android/app/build.gradle.kts \
          android/app/rustore-release-notes-ru.txt android/.gitignore
  git commit -m "build(android): wire RuStore publish plugin (cianru 0.5.5)"
  ```

---

### Task 2: Guarded RuStore upload in the release workflow

**Files:**
- Modify: `.github/workflows/release.yml` (append two steps after the final "Publish GitHub Release" step)

**Interfaces:**
- Consumes: `steps.meta.outputs.prerelease` (existing `meta` step), the
  `publishRustoreRelease` Gradle task (Task 1), and the built APK at
  `build/app/outputs/flutter-apk/app-release.apk`.

Uploads the APK to RuStore on stable tags only, guarded on the credentials
secret so tags still cut a GitHub Release before the RuStore account exists.

- [ ] **Step 1: Append the guard + upload steps**

  After the existing `- name: Publish GitHub Release` step (the last step in the
  job), append:

  ```yaml
      # Upload to RuStore only on stable tags (RuStore has no closed-test track)
      # and only when credentials are configured — so tags still cut a GitHub
      # Release before the RuStore account exists.
      - name: Check RuStore credentials
        id: rustore
        env:
          RS: ${{ secrets.RUSTORE_CREDENTIALS }}
        run: |
          set -euo pipefail
          if [ -n "${RS:-}" ] && [ "${{ steps.meta.outputs.prerelease }}" = "false" ]; then
            echo "enabled=true" >> "$GITHUB_OUTPUT"
          else
            echo "::notice::RuStore upload skipped (no credentials or prerelease tag)."
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
            --buildFile="$GITHUB_WORKSPACE/build/app/outputs/flutter-apk/app-release.apk"
  ```

- [ ] **Step 2: Verify the workflow YAML parses**

  ```bash
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
  ```

  Expected: `YAML OK`.

- [ ] **Step 3: Unit-test the guard logic locally**

  ```bash
  cat > /tmp/rustore_guard.sh <<'SH'
  set -euo pipefail
  enabled() { # $1=creds $2=prerelease
    if [ -n "$1" ] && [ "$2" = "false" ]; then echo true; else echo false; fi
  }
  [ "$(enabled creds false)" = true  ] || { echo "FAIL stable+creds"; exit 1; }
  [ "$(enabled '' false)"    = false ] || { echo "FAIL no-creds"; exit 1; }
  [ "$(enabled creds true)"  = false ] || { echo "FAIL prerelease"; exit 1; }
  echo "rustore guard OK"
  SH
  bash /tmp/rustore_guard.sh
  ```

  Expected: `rustore guard OK`.

- [ ] **Step 4: Commit**

  ```bash
  git add .github/workflows/release.yml
  git commit -m "ci(release): guarded RuStore APK upload on stable tags"
  ```

---

### Task 3: RuStore runbook + release-doc update

**Files:**
- Create: `docs/rustore-release.md`
- Modify: `docs/release.md` (intro line + a new "## RuStore" section)

The manual account/listing/first-upload runbook, and a pointer from the release
doc.

- [ ] **Step 1: Write the runbook**

  `docs/rustore-release.md`:

  ```markdown
  # Publishing nooka to RuStore

  How nooka reaches RuStore (VK's Russian Android store). The CI half (build +
  upload) is automated in
  [`.github/workflows/release.yml`](../.github/workflows/release.yml); this doc is
  the **manual** half. Steps are ordered by dependency.

  ## 1. Create and verify the developer account
  - Register at the RuStore Console with a **VK ID** (an individual account needs
    nothing more to create). No fee.
  - Complete **verification** by uploading a photo of your passport. Monetization
    (self-employed) is not needed — nooka is free with no ads.

  ## 2. Create the app
  - Create an app with package name **`io.github.quotidianlabs.nooka`** (must match
    the APK; RuStore matches uploads by package name).

  ## 3. Generate an API key for CI
  - In RuStore Console, open the API-keys section and create a key. It yields a
    **`key_id`** and a **`client_secret`**.
  - In GitHub → repo **Settings → Secrets and variables → Actions**, add secret
    **`RUSTORE_CREDENTIALS`** with this exact JSON:

    ```json
    { "key_id": "<KEY_ID>", "client_secret": "<CLIENT_SECRET>" }
    ```

  ## 4. Enable the privacy site (GitHub Pages)
  - Repo **Settings → Pages → Source: GitHub Actions**. The `pages` workflow then
    serves the policy at `https://quotidianlabs.github.io/nooka/privacy` — use
    this as the app's privacy-policy URL.

  ## 5. Complete the store listing (Russian-first)
  - 512×512 icon, at least one screenshot, a description (≤4000 chars), and an
    **age rating**. Set the privacy-policy URL from step 4.

  ## 6. Publish
  - Ensure `pubspec.yaml` `+N` is higher than any previous RuStore upload, merge
    to `main`, then push a **stable tag** (e.g. `1.3.0`, matching `pubspec.yaml`).
    CI builds the signed APK and uploads it to RuStore
    (`publishRustoreRelease`, `publishType = INSTANTLY` → submitted to moderation).
  - The first upload can also be done **manually** in the Console (upload
    `nooka-<tag>.apk` from the GitHub Release) if you want to establish the app
    before wiring the secret.

  ## Notes
  - **Google Drive backup** needs Google Play Services. On RuStore devices without
    it, connecting Drive fails to a localized error; the local file export/import
    works everywhere.
  - **Version code already used** → bump `pubspec.yaml` `+N` and re-tag.
  - A tag before the account/secret exists is fine: the RuStore step is skipped
    with a notice and the GitHub Release still ships.
  ```

- [ ] **Step 2: Update `docs/release.md` intro**

  In `docs/release.md`, replace the second paragraph (starting "This is a sideload
  distribution channel"):

  ```markdown
  This is a sideload distribution channel (download the APK from the release page
  and install it). The same stable tag also uploads that APK to **RuStore** when
  credentials are configured — see [`rustore-release.md`](rustore-release.md).
  ```

- [ ] **Step 3: Append a RuStore section to `docs/release.md`**

  Append at the end of `docs/release.md`:

  ```markdown

  ## RuStore

  On a **stable** tag, the release job uploads the same signed universal APK to
  RuStore via `ru.cian.rustore-publish-gradle-plugin` (task
  `publishRustoreRelease`). The upload is **guarded**: it runs only when the
  `RUSTORE_CREDENTIALS` secret is set and the tag is not a prerelease, so tags
  still cut a GitHub Release otherwise. RuStore has no Play-style app signing —
  the APK's own signature (the existing upload keystore) is the app identity.

  Account signup, API-key generation, and the Russian store listing are in
  [`rustore-release.md`](rustore-release.md).
  ```

- [ ] **Step 4: Verify docs**

  ```bash
  test -f docs/rustore-release.md && \
  grep -q "RuStore" docs/release.md && \
  grep -q "RUSTORE_CREDENTIALS" docs/rustore-release.md && \
  grep -q "io.github.quotidianlabs.nooka" docs/rustore-release.md && \
  echo "rustore docs OK"
  ```

  Expected: `rustore docs OK`.

- [ ] **Step 5: Commit**

  ```bash
  git add docs/rustore-release.md docs/release.md
  git commit -m "docs: add RuStore publishing runbook; link from release doc"
  ```

---

### Task 4: Finalize the bundle and run the full gate

**Files:**
- Modify: `planning/changes/2026-07-03.01-publish-rustore/design.md` (frontmatter `summary`)
- Modify: `planning/deferred.md` (re-add the OS-backup item that rode on the closed Play branch)

- [ ] **Step 1: Confirm the design `summary` is the realized result**

  In `design.md`, ensure the frontmatter `summary:` reads (single line):

  ```yaml
  summary: RuStore publishing added — a guarded CI upload of the existing signed universal APK via the cianru Gradle plugin 0.5.5 (stable tags only, publishRustoreRelease), reusing the GitHub Pages privacy policy, plus an account/listing runbook; the unverifiable Google Play path is dropped.
  ```

- [ ] **Step 2: Re-add the deferred OS-backup item**

  The privacy policy (carried onto this branch) still discloses OS-level device
  backup. Append to `planning/deferred.md`:

  ```markdown
  - **Disable OS-level device backup** — set `android:allowBackup="false"`
    (+ iOS backup-exclusion on the SQLite file) so the DB is not copied off-device
    by Android Auto Backup / iOS device backup. Trade-off: removes transparent
    task migration on device replacement. The privacy policy discloses the current
    (backup-enabled) behavior. *Revisit when* deciding the on-device data
    residency stance, or if a store review requires OS backups excluded.
  ```

- [ ] **Step 3: Run the gates**

  ```bash
  just check-planning
  just lint-ci
  ```

  Expected: `planning: OK`; `lint-ci` exits 0 (no Dart source changed, so
  `dart format` and `flutter analyze` are clean; `check-planning` passes).

- [ ] **Step 4: Confirm a clean tree**

  ```bash
  git status --porcelain
  ```

  Expected: empty.

- [ ] **Step 5: Commit**

  ```bash
  git add planning/changes/2026-07-03.01-publish-rustore/design.md planning/deferred.md
  git commit -m "docs(planning): finalize RuStore summary; re-log OS-backup deferral"
  ```

---

## Post-merge (maintainer, out of band)

Not code — tracked here so it is not forgotten. Follow
[`docs/rustore-release.md`](../../../docs/rustore-release.md): create + verify the
RuStore account (VK ID + passport), create the app
`io.github.quotidianlabs.nooka`, generate the API key and set the
`RUSTORE_CREDENTIALS` secret, enable Pages (source = GitHub Actions), build the
Russian listing (icon, screenshots, description, age rating, privacy URL), then
push a stable tag to publish.
