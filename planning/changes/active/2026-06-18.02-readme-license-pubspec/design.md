---
status: approved
date: 2026-06-18
slug: readme-license-pubspec
supersedes: null
superseded_by: null
pr: null
outcome: null
---

# Design: README, LICENSE, pubspec, and screenshot infrastructure

## Summary

Replace nooka's default Flutter README with a real one (tagline, screenshot
gallery, features, architecture, getting-started, development, license), add an
MIT `LICENSE`, fix the `pubspec.yaml` description, and port habbits'
deterministic screenshot generator so the README's visual gallery ships with
real, reproducible shots. Brings nooka's repo presentation up to habbits'
level. Touches new test/driver files plus docs; the only app-facing change is
the one-line pubspec description.

## Motivation

nooka still carries the stock `README.md` ("A new Flutter project.") and
`pubspec.yaml` description, has no `LICENSE`, and no screenshots — while its
sibling `habbits` has a badge-topped README with a six-shot gallery generated
deterministically from the live app. A reader landing on the repo today learns
nothing about what nooka is. This bundle closes that gap and gives the README a
real visual centerpiece rather than a promise of screenshots that do not exist.

Per the bundle-2 brainstorm, the screenshot infrastructure is **folded into
this bundle** (rather than a later one) so the README ships complete with its
gallery, exactly as habbits did.

## Non-goals

- CI badge and GitHub Actions — the next bundle (`ci`). The README ships
  without a CI badge so there is no broken badge until the workflow exists.
- Release docs / Android signing — already deferred (`planning/deferred.md`).
- App-icon / branding / bundle-id changes — deferred.
- Bundling screenshots as in-app assets — the gallery is README-only
  (GitHub-rendered), so no `flutter: assets:` change.

## Design

### 1. Screenshot infrastructure

Port habbits' generator, adapted to nooka's wiring (nooka has **no**
notification service, so no stub is needed — simpler than habbits).

**`test_driver/integration_test.dart`** (new) — verbatim from habbits; writes
each captured shot to `assets/screenshots/<name>.png`:

```dart
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final file = File('assets/screenshots/$name.png');
          await file.create(recursive: true);
          await file.writeAsBytes(bytes);
          return true;
        },
  );
}
```

**`integration_test/screenshots_test.dart`** (new) — the generator. Structure:

- `seededDb()` — builds an in-memory `AppDatabase(NativeDatabase.memory())`,
  seeds via `db.todoDao` using the real API
  (`createCategory({required name, required color, String? emoji})`,
  `createTask({required categoryId, required name})`,
  `completeTask(id, DateTime now)`), drawing colors from `kCategoryPalette`
  (`lib/ui/core/category_colors.dart`). Seed content (themed to-do list):

  | Category | Color (`kCategoryPalette`) | Emoji | Active tasks | Completed (→ archive) |
  |----------|----------------------------|-------|--------------|------------------------|
  | Home | `0xFF009688` teal | 🏠 | Water the plants; Take out recycling; Vacuum living room | Replace air filter |
  | Work | `0xFF1E88E5` blue | 💼 | Email Priya; Draft Q3 deck | Book travel |
  | Groceries | `0xFF43A047` green | 🛒 | Oat milk; Spinach; Coffee beans | Bananas |

  The three `completeTask` calls populate the Archive view.

- `pumpApp(tester, Map<String, Object> prefs)` — sets
  `SharedPreferences.setMockInitialValues(prefs)`, builds the seeded db, and
  pumps `NookaApp` inside a `ProviderScope` overriding
  `appDatabaseProvider.overrideWithValue(db)` and
  `sharedPreferencesProvider.overrideWithValue(sp)`, then `pumpAndSettle()`.
  Pref tokens use the real keys/values: `{'theme': 'light'|'dark'}`,
  `{'locale': 'en'|'ru'}` (`SettingsRepository` keys `'theme'`/`'locale'`;
  `ThemeMode` tokens `light`/`dark`, `AppLocale` tokens `en`/`ru`).

- One `testWidgets('README screenshots', …)` with a `shoot(name)` helper that
  converts the Flutter surface to an image once on Android
  (`binding.convertFlutterSurfaceToImage()` guarded by `Platform.isAndroid`),
  `pumpAndSettle`s, then `binding.takeScreenshot(name)`.

### 2. Shot set (6)

nooka has no per-item detail screen, so habbits' `detail-en` is replaced by
`archive-en` — the Archive view (completion + 30-day countdown) is nooka's
signature surface.

| Shot | Prefs | Navigation in the test |
|------|-------|------------------------|
| `home-en` | `{'theme':'light'}` | seeded home (Active) |
| `archive-en` | (same pump) | tap the **Archive** segment — `find.text(l10n.archiveTab)` |
| `settings-en` | (same pump) | back to Active, tap `Key('settings-button')` |
| `create-en` | (same pump) | back, tap `Key('add-category-button')`, `FocusManager.instance.primaryFocus?.unfocus()` to hide the keyboard → category dialog with color swatches |
| `home-ru` | fresh pump `{'locale':'ru','theme':'light'}` | seeded home |
| `home-dark` | fresh pump `{'theme':'dark'}` | seeded home |

Between locale/theme switches, replace the tree with `SizedBox.shrink()` and
`pumpAndSettle()` before the fresh `pumpApp`, matching habbits.

### 3. README rewrite

Replace `README.md` wholesale, following habbits' section order with nooka
content:

- **Title + tagline:** "A local-first to-do list. Your data, on your device."
- **Badges:** License-MIT and Flutter-version (the version read from
  `flutter --version` at implementation time). **No CI badge** yet.
- **Pitch paragraph:** built on two ideas — (1) you own your data (on-device
  SQLite, no account, no backend); (2) finishing a task gets it out of your
  way (complete → archive → auto-cleanup 30 days after completion). iOS +
  Android, English + Russian.
- **Screenshot gallery:** two tables referencing the six PNGs by path
  (`assets/screenshots/<name>.png`).
- **Features:** colored categories holding tasks; complete → archive with
  30-day retention and per-item countdown; restore from archive; drag-reorder;
  undo toasts; per-category color + single-grapheme icon; light/dark Material 3
  themes; English + Russian following device locale with in-app override; iOS
  and Android from one Flutter codebase. Each as a bullet with an emoji marker
  (habbits style), drawn from nooka's actual capabilities.
- **Architecture:** the layered MVVM / Riverpod summary from
  `architecture/README.md`, with links into `planning/` (e.g. the archived
  [`todo-list`](planning/changes/archive/2026-06-17.01-todo-list/design.md)
  bundle and the [`adopt-planning-convention`](planning/changes/archive/2026-06-18.01-adopt-planning-convention/design.md)
  bundle).
- **Getting started / Development:** `flutter pub get` / `flutter run`; the
  build_runner note; `just lint` / `just test` (with the current test count);
  the integration flow command.
- **License:** MIT © 2026 quotidianlabs.

### 4. LICENSE + pubspec

- `LICENSE` (new) — standard MIT text, copyright line `© 2026 quotidianlabs`
  (matches the `quotidianlabs/nooka` remote and habbits).
- `pubspec.yaml` — change `description:` from `"A new Flutter project."` to the
  tagline. No other pubspec change; screenshots are not app assets.

### 5. `docs/screenshots.md`

Port habbits' regeneration guide, adapted: the test/driver paths, the
`flutter drive` command, the iOS-simulator note, and the current shot list
(`home-en`, `archive-en`, `settings-en`, `create-en`, `home-ru`, `home-dark`).
Note that the committed shots come from an iOS simulator and that the exact
device/resolution is whatever simulator is used (recorded here when first
generated).

## Operations

Generating the screenshots requires an iOS simulator (or Android emulator) on
the build machine. The `flutter drive` run boots it and writes the PNGs; the
committed images are the artifact. No other out-of-repo steps.

## Testing

- `just test` — full unit/widget suite green (the screenshot test is an
  integration test, not part of `flutter test`).
- `flutter drive --driver=test_driver/integration_test.dart
  --target=integration_test/screenshots_test.dart -d <ios-sim>` — produces six
  non-empty PNGs under `assets/screenshots/`.
- `just lint` (`dart format` + `flutter analyze`) clean, including the two new
  Dart files.
- Every image path and link in `README.md` resolves to an existing file.

## Risk

Low-to-moderate. The screenshot run is environment-dependent (simulator must be
available and booted) — mitigated by `docs/screenshots.md` capturing the exact
command, and by the shots being committed artifacts so a missing simulator
never blocks a normal build. The new Dart files must compile/lint cleanly — the
generator deliberately reuses the existing public provider/DAO API (no
production code touched), so the analyze surface is limited to the test files.
Secondary risk is README link rot — mitigated by the link-resolution check.
