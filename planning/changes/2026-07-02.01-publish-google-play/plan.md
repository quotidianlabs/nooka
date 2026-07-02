# Publish to Google Play — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the release pipeline to build and upload a signed Play AAB, and
add the privacy policy, Data Safety mapping, and signup/closed-testing runbook
that a Google Play listing requires.

**Spec:** [`design.md`](./design.md)

**Branch:** `publish-google-play` (already created).

**Commit strategy:** Per-task commits.

## Global constraints

Copied verbatim from the spec; every task inherits these.

- **Play package name:** `io.github.quotidianlabs.nooka` (the app's
  `applicationId`; permanent once uploaded — never change it).
- **versionCode:** stays sourced from `pubspec.yaml` `version: X.Y.Z+N`. Play
  requires it **strictly increasing**; bump `+N` every release.
- **No signing changes:** the AAB is signed by the same reconstructed upload
  keystore as the APK (`signingConfigs.release` in
  `android/app/build.gradle.kts` applies to all release build types). Do not
  touch signing config.
- **Play upload is guarded:** the upload step runs only when the
  `PLAY_SERVICE_ACCOUNT_JSON` secret is present. Absent → skip with a notice,
  **do not fail** the release (so tags still cut a GitHub Release before the Play
  account exists).
- **Track mapping (reuses the prerelease convention):** prerelease tag
  (`X.Y.Z-*`) → closed testing track from repo variable `vars.PLAY_CLOSED_TRACK`
  (default `alpha`); stable tag (`X.Y.Z`) → `production`.
- **Action inputs/versions (verified):** `r0adkll/upload-google-play@v1`
  (v1.1.5) — the AAB input is `tracks` (plural; `track` is deprecated). Pages:
  `actions/configure-pages@v5`, `actions/upload-pages-artifact@v3`,
  `actions/deploy-pages@v5`, `actions/checkout@v5`.
- **Privacy site is static HTML** under `site/`; no Jekyll/Gemfile. Deployed URL:
  `https://quotidianlabs.github.io/nooka/privacy`.
- **Contact email:** `me@shiriev.ru`. **Policy last-updated date:** 2026-07-02.
- **This is release infra, not app behavior:** no `architecture/` capability doc
  changes. Update `docs/release.md` and finalize the bundle `summary` in this PR.
- **Final gate:** `just lint-ci` clean (runs `dart format --set-exit-if-changed`,
  `flutter analyze`, and `python3 planning/index.py --check`).

---

### Task 1: Build a signed release AAB in CI

**Files:**
- Modify: `.github/workflows/release.yml` (insert after the "Build signed release APK" step, ~line 97)

Adds `flutter build appbundle --release` so the release job produces the Play
artifact alongside the existing APK. No upload yet — that is Task 2.

- [ ] **Step 1: Insert the AAB build step**

  In `.github/workflows/release.yml`, immediately **after** the existing
  `- name: Build signed release APK` step and **before** `- name: Rename APK`,
  insert:

  ```yaml
      # Same dart-define and reconstructed upload keystore as the APK build.
      # Output: build/app/outputs/bundle/release/app-release.aab
      - name: Build signed release AAB
        run: |
          flutter build appbundle --release \
            --dart-define=GOOGLE_SERVER_CLIENT_ID=103089031104-03r0mq3lfdkg6snffok3ptfjae4cmq17.apps.googleusercontent.com
  ```

- [ ] **Step 2: Verify the workflow YAML still parses**

  Run:

  ```bash
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
  ```

  Expected: `YAML OK` (no traceback).

- [ ] **Step 3: Confirm the AAB output path the workflow will produce**

  `flutter build appbundle` writes to
  `build/app/outputs/bundle/release/app-release.aab`. This is the path Task 2's
  upload step references — they must match. Confirm the step text uses no custom
  `--output` that would move it:

  ```bash
  grep -n "flutter build appbundle" .github/workflows/release.yml
  ```

  Expected: one line, no `--output` flag.

- [ ] **Step 4: Commit**

  ```bash
  git add .github/workflows/release.yml
  git commit -m "ci(release): build signed AAB for Google Play"
  ```

---

### Task 2: Upload the AAB to Google Play (track mapping + guarded step)

**Files:**
- Modify: `.github/workflows/release.yml` (extend the `meta` step ~line 107; add two steps after "Publish GitHub Release" ~line 128)

**Interfaces:**
- Consumes: `build/app/outputs/bundle/release/app-release.aab` (Task 1).
- Produces: `steps.meta.outputs.play_track` (`alpha`/custom for prerelease,
  `production` for stable), consumed by the upload step.

Extends release metadata to compute the Play track from the tag, then uploads the
AAB via `r0adkll/upload-google-play@v1` — guarded so a missing service-account
secret skips the upload instead of failing the release.

- [ ] **Step 1: Extend the `meta` step to emit `play_track`**

  Replace the existing `- name: Resolve release metadata` step (id `meta`) with
  this version (adds the `env:` block and the two `play_track` lines):

  ```yaml
      - name: Resolve release metadata
        id: meta
        env:
          PLAY_CLOSED_TRACK: ${{ vars.PLAY_CLOSED_TRACK }}
        run: |
          set -euo pipefail
          notes="planning/releases/${GITHUB_REF_NAME}.md"
          if [ -f "$notes" ]; then
            echo "body_path=$notes" >> "$GITHUB_OUTPUT"
          fi
          if [[ "$GITHUB_REF_NAME" == *-* ]]; then
            echo "prerelease=true" >> "$GITHUB_OUTPUT"
            # Prerelease tags feed the closed testing track (default: alpha).
            echo "play_track=${PLAY_CLOSED_TRACK:-alpha}" >> "$GITHUB_OUTPUT"
          else
            echo "prerelease=false" >> "$GITHUB_OUTPUT"
            echo "play_track=production" >> "$GITHUB_OUTPUT"
          fi
  ```

- [ ] **Step 2: Add the guard + upload steps at the end of the job**

  After the existing `- name: Publish GitHub Release` step (the last step),
  append:

  ```yaml
      # Only upload to Play when the service-account secret is configured. This
      # keeps tag pushes working (GitHub Release still ships) before the Play
      # account/service account exist.
      - name: Check Play credentials
        id: play
        env:
          SA_JSON: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
        run: |
          set -euo pipefail
          if [ -n "${SA_JSON:-}" ]; then
            echo "enabled=true" >> "$GITHUB_OUTPUT"
          else
            echo "::notice::PLAY_SERVICE_ACCOUNT_JSON not set — skipping Play upload."
            echo "enabled=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Upload AAB to Google Play
        if: steps.play.outputs.enabled == 'true'
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
          packageName: io.github.quotidianlabs.nooka
          releaseFiles: build/app/outputs/bundle/release/app-release.aab
          tracks: ${{ steps.meta.outputs.play_track }}
          status: completed
  ```

- [ ] **Step 3: Verify the workflow YAML parses**

  Run:

  ```bash
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
  ```

  Expected: `YAML OK`.

- [ ] **Step 4: Unit-test the track-mapping logic locally**

  The mapping is pure shell, so exercise it directly. Save and run this scratch
  script (it mirrors the `meta` logic):

  ```bash
  cat > /tmp/track_test.sh <<'SH'
  set -euo pipefail
  track_for() {
    local ref="$1"; local closed="${2:-}"
    if [[ "$ref" == *-* ]]; then echo "${closed:-alpha}"; else echo "production"; fi
  }
  [ "$(track_for 1.2.1)"              = "production" ] || { echo "FAIL stable"; exit 1; }
  [ "$(track_for 1.2.1-beta.1)"       = "alpha"      ] || { echo "FAIL prerelease default"; exit 1; }
  [ "$(track_for 1.2.1-beta.1 closed)" = "closed"    ] || { echo "FAIL prerelease var"; exit 1; }
  echo "track mapping OK"
  SH
  bash /tmp/track_test.sh
  ```

  Expected: `track mapping OK`.

- [ ] **Step 5: Commit**

  ```bash
  git add .github/workflows/release.yml
  git commit -m "ci(release): upload AAB to Google Play with tag-based track"
  ```

---

### Task 3: Privacy policy static site

**Files:**
- Create: `site/index.html`
- Create: `site/privacy/index.html`

The publicly-hosted privacy policy (mandatory for the Drive-backup OAuth) plus a
minimal landing page, as static HTML.

- [ ] **Step 1: Create the landing page**

  `site/index.html`:

  ```html
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>nooka</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 42rem; margin: 3rem auto;
             padding: 0 1rem; line-height: 1.6; }
      a { color: #2563eb; }
    </style>
  </head>
  <body>
    <h1>nooka</h1>
    <p>A local-first to-do list for iOS and Android.</p>
    <p><a href="privacy/">Privacy policy</a></p>
  </body>
  </html>
  ```

- [ ] **Step 2: Create the privacy policy**

  `site/privacy/index.html` (contact email and date per Global constraints —
  adjust the email if a different public address is preferred):

  ```html
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>nooka — Privacy Policy</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 42rem; margin: 3rem auto;
             padding: 0 1rem; line-height: 1.6; }
      h1, h2 { line-height: 1.25; }
      code { background: #f3f4f6; padding: 0 .25rem; border-radius: .25rem; }
    </style>
  </head>
  <body>
    <h1>nooka — Privacy Policy</h1>
    <p><em>Last updated: 2026-07-02</em></p>

    <p>nooka is a local-first to-do list. Your task data lives on your device.
      The developer runs no server and operates no backend: there is no account
      system, no analytics, no advertising, and no tracking.</p>

    <h2>Data stored on your device</h2>
    <p>Your categories and tasks are stored locally on your device in an SQLite
      database. This data never leaves your device unless <em>you</em> choose to
      export or back it up (see below).</p>

    <h2>Optional Google Drive backup</h2>
    <p>nooka offers an optional backup and restore feature to <em>your own</em>
      Google Drive. If you use it:</p>
    <ul>
      <li>Backups are written only to Google Drive's hidden per-app
        <code>appDataFolder</code>, using the non-sensitive
        <code>drive.appdata</code> scope. They are invisible to other apps and to
        the developer.</li>
      <li>Your Google account email is read solely to display which account is
        connected, inside the app. It is never transmitted to the developer.</li>
      <li>The developer has no access to your Google account or your backups. The
        data stays within your own Google Drive, governed by Google's own
        privacy terms.</li>
    </ul>

    <h2>Optional file export</h2>
    <p>You can export your data to a JSON file via the system share sheet. Where
      that file goes is entirely your choice; nooka does not upload it anywhere.</p>

    <h2>Data sharing</h2>
    <p>The developer does not collect, sell, or share any of your data with third
      parties. Data transmitted to your own Google Drive (if you enable backup)
      travels over encrypted HTTPS connections.</p>

    <h2>Deleting your data</h2>
    <p>Uninstalling the app removes all on-device data. To remove cloud backups,
      delete them from within the app or from your Google Drive. You can also
      revoke nooka's Drive access in your Google account settings.</p>

    <h2>Children</h2>
    <p>nooka is a general-audience productivity app and is not directed at
      children.</p>

    <h2>Contact</h2>
    <p>Questions about this policy: <a href="mailto:me@shiriev.ru">me@shiriev.ru</a>.</p>
  </body>
  </html>
  ```

- [ ] **Step 3: Verify both files exist and contain the required anchors**

  Run:

  ```bash
  test -f site/index.html && test -f site/privacy/index.html && \
  grep -q "Privacy Policy" site/privacy/index.html && \
  grep -q "drive.appdata" site/privacy/index.html && \
  grep -q "me@shiriev.ru" site/privacy/index.html && \
  echo "privacy site OK"
  ```

  Expected: `privacy site OK`. (Optionally open `site/privacy/index.html` in a
  browser to eyeball rendering.)

- [ ] **Step 4: Commit**

  ```bash
  git add site/index.html site/privacy/index.html
  git commit -m "docs(site): add privacy policy static site"
  ```

---

### Task 4: GitHub Pages deploy workflow

**Files:**
- Create: `.github/workflows/pages.yml`

**Interfaces:**
- Consumes: the `site/` directory (Task 3).

Deploys `site/` to GitHub Pages via the official Pages actions. Publishes only
`site/`, so dev `docs/` and `planning/` stay private.

- [ ] **Step 1: Create the workflow**

  `.github/workflows/pages.yml`:

  ```yaml
  name: pages

  on:
    push:
      branches: [main]
      paths:
        - 'site/**'
        - '.github/workflows/pages.yml'
    workflow_dispatch:

  # Least-privilege permissions required by the Pages deploy actions.
  permissions:
    contents: read
    pages: write
    id-token: write

  # One Pages deployment at a time; don't cancel an in-progress deploy.
  concurrency:
    group: pages
    cancel-in-progress: false

  jobs:
    deploy:
      runs-on: ubuntu-latest
      environment:
        name: github-pages
        url: ${{ steps.deployment.outputs.page_url }}
      steps:
        - uses: actions/checkout@v5
        - uses: actions/configure-pages@v5
        # Static HTML — upload site/ as-is, no build step.
        - uses: actions/upload-pages-artifact@v3
          with:
            path: site
        - id: deployment
          uses: actions/deploy-pages@v5
  ```

- [ ] **Step 2: Verify the workflow YAML parses**

  Run:

  ```bash
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pages.yml')); print('YAML OK')"
  ```

  Expected: `YAML OK`.

- [ ] **Step 3: Commit**

  ```bash
  git add .github/workflows/pages.yml
  git commit -m "ci(pages): deploy privacy site to GitHub Pages"
  ```

  > Note: the deploy only succeeds once the repo's Pages **source is set to
  > "GitHub Actions"** (Settings → Pages). That manual step is in the runbook
  > (Task 6). Until then the workflow is committed but the first run needs the
  > setting enabled.

---

### Task 5: Data Safety mapping doc

**Files:**
- Create: `docs/play-data-safety.md`

The reproducible source of truth for the answers typed into the Play Console
Data Safety form.

- [ ] **Step 1: Write the doc**

  `docs/play-data-safety.md`:

  ```markdown
  # Play Data Safety — declaration mapping

  The exact answers for the Play Console **Data Safety** form. This app has no
  backend; the only data movement is the user backing up their own data to their
  own Google Drive. Keep this in sync with
  [`architecture/backup-io.md`](../architecture/backup-io.md) and the
  [privacy policy](https://quotidianlabs.github.io/nooka/privacy).

  ## Summary answers

  | Question | Answer |
  |---|---|
  | Does your app collect or share any of the required user data types? | **No** — the developer collects and shares nothing. |
  | Is all user data encrypted in transit? | **Yes** — the optional Drive backup uses Google APIs over HTTPS. |
  | Do you provide a way for users to request data deletion? | **Yes** — uninstall removes on-device data; users delete cloud backups from the app or their Drive, and can revoke Drive access in their Google account. |

  ## Rationale (why "no data collected")

  - **Task data** (categories, tasks) is stored only on-device in SQLite. It is
    never sent to the developer.
  - **Google Drive backup** is optional and writes to the user's *own* hidden
    `appDataFolder` via the non-sensitive `drive.appdata` scope. The developer
    has no backend and no access to it. Under Play's definition this is the user
    handling their own data, not developer collection or sharing.
  - **Account email** is read only to display "connected as" in Settings; it is
    not transmitted to the developer or stored off-device.
  - **No analytics, ads, crash reporting, or third-party SDKs** that would
    collect data.

  ## If the reviewer disputes the Drive backup

  If Play's review treats the Drive backup as "collection," the honest and
  minimal declaration is: data type **Files and docs** (the backup JSON),
  purpose **App functionality**, **not shared**, **encrypted in transit**, with
  the deletion method above. It is still never shared with the developer or third
  parties.
  ```

- [ ] **Step 2: Verify the file exists and links resolve to real paths**

  Run:

  ```bash
  test -f docs/play-data-safety.md && test -f architecture/backup-io.md && \
  grep -q "Encrypted in transit\|encrypted in transit" docs/play-data-safety.md && \
  echo "data-safety doc OK"
  ```

  Expected: `data-safety doc OK`.

- [ ] **Step 3: Commit**

  ```bash
  git add docs/play-data-safety.md
  git commit -m "docs: add Play Data Safety declaration mapping"
  ```

---

### Task 6: Publishing runbook + update release doc

**Files:**
- Create: `docs/play-release.md`
- Modify: `docs/release.md:7-8` (drop "no `.aab` pipeline"); add a Google Play section

The operator's sequenced guide for the manual account/console work, and a pointer
to it from the existing release doc.

- [ ] **Step 1: Write the runbook**

  `docs/play-release.md`:

  ```markdown
  # Publishing nooka to Google Play

  How nooka reaches the Play Store. The CI half (build + upload) is automated in
  [`.github/workflows/release.yml`](../.github/workflows/release.yml); this doc
  is the **manual** half only the maintainer can do. Steps are ordered by
  dependency — do them top to bottom.

  > **New-account gate.** A new personal Play developer account cannot publish
  > straight to production. Google requires a **closed test with at least 12
  > testers opted in for 14 continuous days** first. Plan for that two-week
  > window.

  ## 1. Register the developer account
  - Sign up at the Play Console (~$25 one-time fee) and complete identity
    verification.

  ## 2. Create the app
  - Create an app with package name **`io.github.quotidianlabs.nooka`** (this is
    permanent and must match the app's `applicationId`).
  - Set default language English; add Russian; pick a category and tags.

  ## 3. Enrol in Play App Signing (at first upload)
  - Opt into **Play App Signing**. The existing org **upload keystore** becomes
    the *upload key*; Google generates and holds the *app signing key*.
  - This is **irreversible** for the app — verify you are uploading with the
    known upload key (same one CI uses; see [`release.md`](release.md#signing))
    before the first production release.

  ## 4. Create the CI service account
  - In Google Cloud, create/select a project and enable the **Google Play
    Android Developer API**.
  - Create a **service account** and a **JSON key**.
  - In Play Console → **Users & permissions**, invite the service account's email
    and grant it release permission. Permission propagation can take hours.
  - In GitHub → repo **Settings → Secrets and variables → Actions**:
    - Add secret **`PLAY_SERVICE_ACCOUNT_JSON`** = the full JSON key contents.
    - (Optional) Add variable **`PLAY_CLOSED_TRACK`** if your closed track is not
      named `alpha`.

  ## 5. Enable the privacy site (GitHub Pages)
  - Repo **Settings → Pages → Source: GitHub Actions**. The `pages` workflow then
    publishes `site/` to
    `https://quotidianlabs.github.io/nooka/privacy` on the next push to `main`
    touching `site/`.

  ## 6. Complete the store listing
  - Title, short description (≤80 chars), full description (≤4000 chars).
  - Graphics: 512×512 app icon, 1024×500 feature graphic, **≥2 phone
    screenshots** — provide **English and Russian** sets (the app is bilingual).

  ## 7. Content rating
  - Complete the IARC content-rating questionnaire.

  ## 8. Data Safety + privacy policy
  - Fill the Data Safety form using [`play-data-safety.md`](play-data-safety.md).
  - Set the privacy policy URL to
    `https://quotidianlabs.github.io/nooka/privacy`.

  ## 9. Target audience & ads
  - Declare target audience (general/adult) and **no ads**.

  ## 10. Seed the closed test
  - Ensure `pubspec.yaml` `+N` is higher than any previous Play upload, merge to
    `main`, then push a **prerelease tag** (e.g. `1.3.0-beta.1`). CI builds the
    AAB and uploads it to the closed track (`PLAY_CLOSED_TRACK`, default
    `alpha`).
  - Add **12+ testers** (a Google Group or an email list) to the closed track and
    have them opt in. Keep the test running **14 continuous days**.

  ## 11. Go to production
  - After the 14-day test, apply for production access in the console.
  - Once granted, push a **stable tag** (`X.Y.Z`, matching `pubspec.yaml`). CI
    uploads the AAB to `production`.

  ## Troubleshooting
  - **Upload rejected: version code already used** → bump `pubspec.yaml` `+N` and
    re-tag.
  - **Action fails on auth** → the service account's Play permission has not
    propagated yet, or the JSON secret is malformed. Wait and/or re-add the
    secret.
  - **A tag before the account exists** → expected: the Play step is skipped with
    a notice and the GitHub Release still ships.
  ```

- [ ] **Step 2: Update `docs/release.md` intro (remove the "no aab" line)**

  Replace lines 7-8 (the paragraph starting "This is a sideload distribution
  channel"):

  ```markdown
  This is a sideload distribution channel (download the APK from the release page
  and install it). The same tag push also builds an `.aab` and, when Play
  credentials are configured, uploads it to Google Play — see
  [`play-release.md`](play-release.md).
  ```

- [ ] **Step 3: Add a Google Play section to `docs/release.md`**

  Append at the end of `docs/release.md`:

  ```markdown

  ## Google Play

  Alongside the APK, the release job builds a signed **AAB**
  (`flutter build appbundle --release`) and uploads it with
  `r0adkll/upload-google-play`. The upload is **guarded**: it runs only when the
  `PLAY_SERVICE_ACCOUNT_JSON` secret is set, so tags still cut a GitHub Release
  before the Play account exists. The track follows the tag — a prerelease tag
  goes to the closed testing track (`vars.PLAY_CLOSED_TRACK`, default `alpha`), a
  stable tag goes to `production`.

  The one-time account signup, store listing, Data Safety, and closed-testing
  steps live in [`play-release.md`](play-release.md).
  ```

- [ ] **Step 4: Verify docs exist and release.md no longer claims "no aab"**

  Run:

  ```bash
  test -f docs/play-release.md && \
  ! grep -q "no Play Store" docs/release.md && \
  grep -q "Google Play" docs/release.md && \
  echo "release docs OK"
  ```

  Expected: `release docs OK`.

- [ ] **Step 5: Commit**

  ```bash
  git add docs/play-release.md docs/release.md
  git commit -m "docs: add Play publishing runbook; link from release doc"
  ```

---

### Task 7: Finalize the planning bundle and run the full gate

**Files:**
- Modify: `planning/changes/2026-07-02.01-publish-google-play/design.md` (frontmatter `summary`)

Finalize the bundle summary to the realized result and confirm the repo is
clean and valid.

- [ ] **Step 1: Finalize the `summary`**

  In `design.md`, ensure the frontmatter `summary:` reads the realized result,
  e.g.:

  ```yaml
  summary: Release workflow now builds a signed AAB and uploads it to Google Play (prerelease->closed track, stable->production, guarded on a service-account secret); adds a GitHub Pages privacy policy, a Data Safety mapping doc, and a signup/closed-testing runbook.
  ```

- [ ] **Step 2: Validate planning + lint gate**

  Run:

  ```bash
  just check-planning
  just lint-ci
  ```

  Expected: `planning: OK`, and `lint-ci` exits 0 (no Dart files changed, so
  `dart format` and `flutter analyze` should be clean; `check-planning` passes).

- [ ] **Step 3: Confirm a clean tree**

  Run:

  ```bash
  git status --porcelain
  ```

  Expected: empty (all work committed).

- [ ] **Step 4: Commit the finalized summary (if changed)**

  ```bash
  git add planning/changes/2026-07-02.01-publish-google-play/design.md
  git commit -m "docs(planning): finalize publish-google-play summary"
  ```

---

## Post-merge (maintainer, out of band)

Not code — tracked here so it is not forgotten. Follow
[`docs/play-release.md`](../../../docs/play-release.md): register the account,
create the app, enrol in Play App Signing, create the service account and set
`PLAY_SERVICE_ACCOUNT_JSON` / `PLAY_CLOSED_TRACK`, enable Pages (source = GitHub
Actions), build the store listing (EN+RU assets), complete content rating and
Data Safety, seed the closed test with 12+ testers for 14 days, then apply for
production and push a stable tag.
