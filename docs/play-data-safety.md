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
