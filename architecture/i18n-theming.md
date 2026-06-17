# i18n & theming

ARB files in `lib/l10n` (`app_en.arb` template, `app_ru.arb`). Russian uses all
four CLDR plural forms (one/few/many/other) for counters and the archive
countdown. `LocaleController` and `ThemeController` persist the choice via
`SettingsRepository` (shared_preferences). Material 3 light/dark from
`appLightTheme()` / `appDarkTheme()`.
