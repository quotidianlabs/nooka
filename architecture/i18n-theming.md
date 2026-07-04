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

The recurring-tasks feature added the following bilingual EN + RU keys:
`repeatLabel` ("Repeat", the edit dialog's toggle), `recurrenceUnitDays` /
`recurrenceUnitWeeks` / `recurrenceUnitMonths` (segmented-control unit labels),
`returnNow` ("Return now", the dormant-row action), `recurrenceEvery`
(the active list's "🔁 Every N …" sub-line) and `recurrenceSummary` (the edit
dialog's live "Returns N … after you complete it." line) — both a nested
ICU `select` on `{unit}` with a `plural` on `{count}` inside each branch — and
`returnsInDays({count})` (the Archive's dormant-row label, with a `=0` "under a
day" branch). Russian declines all three parametric keys with the full four
CLDR plural forms (one/few/many/other) per unit, the same pattern the archive
countdown (`daysRemaining`) already uses.
