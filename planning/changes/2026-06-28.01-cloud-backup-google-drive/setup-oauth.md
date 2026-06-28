# Google OAuth / Drive setup checklist (maintainer)

One-time, out-of-repo setup required before the cloud-backup feature works on a
real device. No app code is *required* by this checklist, but see the
[Android `serverClientId` note](#android-runtime-note--likely-one-line-code-follow-up)
— Android sign-in will most likely need a one-line change once you have the Web
client ID. The whole thing is ~30 minutes of clicking.

Nothing here is needed for CI or the test suite — those use a fake seam and
never touch the real Google API. This is purely to light up the live "Connect
Google Drive" path.

## App identifiers (already set, for reference)

| | Value |
|---|---|
| Android `applicationId` | `io.github.quotidianlabs.nooka` |
| iOS bundle id | `io.github.quotidianlabs.nooka` |
| Drive scope requested | `https://www.googleapis.com/auth/drive.appdata` (non-sensitive) |

## Why `drive.appdata` matters

We deliberately request only the **`drive.appdata`** scope (a hidden per-app
folder), which Google classifies as **non-sensitive**. That should keep you out
of Google's full OAuth verification / security-assessment process. You still
configure the consent screen below, but you should avoid the audit that broader
Drive scopes trigger. If Google ever flags the app for verification, the manual
file export remains a complete fallback.

---

## 1. Create / pick a Google Cloud project

You can do this two ways. **Firebase is the easier path** because it generates
both platform config files and creates the OAuth clients for you.

- **Recommended — Firebase:** at <https://console.firebase.google.com>, create a
  project (this also creates the underlying Google Cloud project). You'll add
  the Android and iOS apps in steps 3–4 and download their config files.
- **Manual — Google Cloud Console:** at <https://console.cloud.google.com>,
  create a project and create each OAuth client by hand (no config files are
  generated; you pass the client IDs to the app instead).

The rest of this checklist assumes the Firebase path and notes the manual
differences inline.

## 2. Enable the Drive API + configure the consent screen

In the **Google Cloud Console** for the project (Firebase projects appear here
automatically):

- [ ] **APIs & Services → Library → Google Drive API → Enable.**
- [ ] **APIs & Services → OAuth consent screen:**
  - User type **External**.
  - App name `nooka`, your support email, developer contact email.
  - **Scopes → Add** `.../auth/drive.appdata` (it should list as non-sensitive).
  - While the app is in **Testing**, add your Google account(s) under
    **Test users** — only listed users can sign in until you publish.

## 3. Android client + `google-services.json`

- [ ] Get your signing **SHA-1** (and SHA-256). From the repo root:

  ```bash
  cd android && ./gradlew :app:signingReport
  ```

  Use the **debug** variant's SHA-1 for local testing; add your **release**
  keystore's SHA-1 as well before shipping. (Equivalent: `keytool -list -v
  -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
  -keypass android`.)

- [ ] **Firebase → Project settings → Add app → Android:** package name
  `io.github.quotidianlabs.nooka`, paste the SHA-1 (and SHA-256). Download
  **`google-services.json`** into `android/app/`.
  - *Manual path:* create an **Android** OAuth client (package + SHA-1) and a
    **Web application** OAuth client in the Cloud Console instead; there is no
    `google-services.json` to download — you'll use the Web client ID as the
    `serverClientId` (see the runtime note below).

## 4. iOS client + Info.plist

- [ ] **Firebase → Add app → iOS:** bundle id `io.github.quotidianlabs.nooka`.
  Download **`GoogleService-Info.plist`** into `ios/Runner/`.
  - *Manual path:* create an **iOS** OAuth client (bundle id) in the Cloud
    Console; it gives you a `CLIENT_ID` and `REVERSED_CLIENT_ID`.

- [ ] Add these to `ios/Runner/Info.plist` (the app's `initialize()` takes no
  `clientId`, so the plugin reads `GIDClientID` from here):

  ```xml
  <key>GIDClientID</key>
  <!-- the CLIENT_ID from GoogleService-Info.plist -->
  <string>YOUR_IOS_CLIENT_ID.apps.googleusercontent.com</string>

  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <!-- the REVERSED_CLIENT_ID from GoogleService-Info.plist -->
        <string>com.googleusercontent.apps.YOUR_IOS_CLIENT_ID</string>
      </array>
    </dict>
  </array>
  ```

## 5. Android runtime note — likely one-line code follow-up

`GoogleDriveBackupIo` calls `GoogleSignIn.instance.initialize()` with **no
arguments** (`lib/data/services/backup/google_drive_backup_io.dart`). That is
enough on **iOS** (it reads `GIDClientID` from Info.plist), but on **Android**
the v7 plugin (Credential Manager) generally needs the **Web application client
ID** to authenticate, supplied one of two ways:

- **Apply the google-services Gradle plugin** so `google-services.json`'s web
  client entry is consumed at build time (this repo does **not** currently apply
  that plugin — confirmed: no `com.google.gms.google-services` in
  `android/`), **or**
- **Pass it explicitly** — the simpler change here:

  ```dart
  // in _ensureInitialized()
  _initFuture ??= GoogleSignIn.instance.initialize(
    serverClientId: '<WEB client ID>.apps.googleusercontent.com',
  );
  ```

  (and `clientId:` for iOS if you prefer not to use Info.plist).

Decide on first device test: if Android `connect()` fails while iOS works, add
the `serverClientId`. This is a deliberately small, isolated change in the
coverage-excluded Drive leaf — no test impact.

## 6. Keep config files out of git

`google-services.json` and `GoogleService-Info.plist` contain client IDs (not
secrets, but environment-specific). Add them to `.gitignore` (they are not there
today) unless you intend to commit them:

```
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
```

The iOS `GIDClientID` / `REVERSED_CLIENT_ID` you paste into `Info.plist` are
fine to commit (client IDs are public by design).

## 7. Verify on a device/emulator

1. [ ] `flutter run` on a real device or emulator signed with the SHA-1 you
   registered, using a **test-user** Google account.
2. [ ] Settings → **Connect Google Drive** → complete sign-in → the section
   shows "Connected as <email>".
3. [ ] **Back up now** → succeeds (the review flagged this as the first thing to
   confirm: a successful `connect()` followed immediately by an upload must not
   throw `StateError` — if it does, the per-account auth wiring needs another
   look).
4. [ ] **Restore from Drive** → the backup is listed → confirm replace → data
   matches.
5. [ ] On a second clean install (same account), restore brings the data back —
   the end-to-end "new phone" recovery path.
