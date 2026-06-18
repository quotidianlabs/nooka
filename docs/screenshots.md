# Regenerating the README screenshots

The screenshots in [`README.md`](../README.md) live in `assets/screenshots/`
and are generated deterministically — never hand-captured — so they stay
consistent and easy to refresh when the UI changes.

## How it works

- **Test:** [`integration_test/screenshots_test.dart`](../integration_test/screenshots_test.dart)
  pumps the real [`NookaApp`](../lib/main.dart) with two overrides: a seeded
  in-memory database (`seededDb()` — three colored categories with tasks, a
  few completed so the Archive view is populated) and a mocked
  `SharedPreferences` so locale and theme are forced per shot
  (`{'theme': 'dark'}`, `{'locale': 'ru'}`, …). It navigates the live screens
  and calls `binding.takeScreenshot('<name>')` at each point.
- **Driver:** [`test_driver/integration_test.dart`](../test_driver/integration_test.dart)
  receives each shot via `onScreenshot` and writes
  `assets/screenshots/<name>.png`.

## Regenerate

Run on an iOS simulator:

```bash
open -a Simulator
xcrun simctl boot "iPhone 17"   # if not already booted
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart \
  -d <device-id>
```

The PNGs are overwritten in place; review the diff and commit them with any
README change. Android also works — the test guards the Android-only
`convertFlutterSurfaceToImage()`; that emulator's resolution differs from the
committed iOS shots.

## Current shots

`home-en`, `archive-en`, `settings-en`, `create-en` (new-category dialog),
`home-ru`, `home-dark`.
