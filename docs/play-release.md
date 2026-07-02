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
