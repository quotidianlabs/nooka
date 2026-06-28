# i18n & theming

ARB files in `lib/l10n` (`app_en.arb` template, `app_ru.arb`). Russian uses all
four CLDR plural forms (one/few/many/other) for counters and the archive
countdown. User-facing errors are localized too — the stream-error screen
(`errorLoading`) and the failed-mutation SnackBar (`actionFailed`); see
[error handling](error-handling.md). `LocaleController` and `ThemeController`
persist the choice via `SettingsRepository` (shared_preferences). Material 3
light/dark from `appLightTheme()` / `appDarkTheme()`.

The cloud backup feature (`2026-06-28.01`) added the following bilingual EN + RU
keys: `cloudBackupSection`, `cloudConnect`, `cloudDisconnect`,
`cloudConnectedAs` (parametric: `{email}`), `cloudBackupNow`, `cloudBackupDone`,
`cloudRestore`, `cloudNoBackups`, `cloudLatest`.
