# Device backup is left on

**Decision:** The operating system's own device backup is allowed to copy the app's data. The
Android manifest deliberately sets no `android:allowBackup`, `fullBackupContent` or
`dataExtractionRules`, so Android Auto Backup uses its defaults: the SQLite database and the
app's preferences go into the user's own Google account backup, and they move to a new phone
through device-to-device transfer. The same stance holds for iOS device backup once iOS ships.
The missing attributes are a choice, not an oversight, so do not add `allowBackup="false"` as
hygiene.

The trade-off is data residency against data loss, and loss is the worse failure here. The
app's own backup is manual, and Drive backup needs Google Play Services, which many RuStore
users do not have (ADR-0009). For those users, device backup is the only thing that survives a
lost or replaced phone without them having acted in advance. Turning it off would make "no data
leaves the device" literally true, at the price of silently losing everything for anyone who
never tapped "Back up now".

The data still goes only to an account the user already owns, encrypted in transit and, on
Android 9 and later with a screen lock, end-to-end. The privacy policy already discloses this
backup and the copy it may leave after uninstall. It is also consistent with ADR-0003: the OS
restores the whole database onto a fresh install before the app first runs, so nothing is ever
merged.

Restricting cloud backup to devices that can encrypt it end-to-end was considered and not
taken. It is cheap, but it can only be verified by hand on a device, and it narrows the safety
net on exactly the older devices where it matters most.

**Revisit trigger:** automatic cloud backup ships (#57), giving users an off-device copy the app
controls; or a store or regulation requires opting out. Either one moves the balance toward
turning device backup off.
