---
status: draft
date: 2026-06-18
slug: app-icon
supersedes: null
superseded_by: null
pr: null
outcome: null
---

# Design: Custom app icon — ticked checkbox

## Summary

Replace the default Flutter launcher icon with a custom mark: a **contained
ticked checkbox** in white on brand teal (`#009688`), applied to iOS and
Android via the standard `flutter_launcher_icons` package. No Dart or behavior
change — this is platform config plus image assets. The icon echoes the app's
own content (a checked to-do item), the same content-echo logic the sibling
`habbits` repo used with its activity-grid icon.

## Motivation

The app still ships the stock Flutter `flutter_logo` launcher icon. The bundle
id and visible name were already branded (`io.github.quotidianlabs.nooka`,
commit `7265e70`); the icon is the remaining default. A real icon is needed
before the app reads as finished on a launcher/home screen.

## Non-goals

- Splash / launch screen — separate, not part of this change.
- In-app branding (no in-UI logo today; out of scope).
- App Store / Play Store listing assets.
- Bundle id / visible app name — already done.

## Design

### 1. Source art — `assets/icon/` (SVG is the source of truth)

SVG is authored by hand; the PNGs that `flutter_launcher_icons` consumes are
rendered from the SVGs and committed, so the build never needs a renderer.

`assets/icon/icon.svg` — full-bleed 220×220, teal fills to the edges. It must
**not** be pre-rounded: iOS and legacy Android apply their own corner mask. The
checkbox sits in the central ~50% — well inside Android's 66% adaptive safe
zone, so masking never clips it.

```svg
<svg viewBox="0 0 220 220" xmlns="http://www.w3.org/2000/svg">
  <rect width="220" height="220" fill="#009688"/>
  <rect x="60" y="60" width="100" height="100" rx="24"
        fill="none" stroke="#ffffff" stroke-width="11"/>
  <path d="M84 110 l18 20 l40 -48" fill="none" stroke="#ffffff"
        stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
```

`assets/icon/icon_foreground.svg` — the checkbox marks only, on a transparent
canvas, for the Android adaptive foreground (the teal comes from
`adaptive_icon_background`). Identical geometry, no background rect:

```svg
<svg viewBox="0 0 220 220" xmlns="http://www.w3.org/2000/svg">
  <rect x="60" y="60" width="100" height="100" rx="24"
        fill="none" stroke="#ffffff" stroke-width="11"/>
  <path d="M84 110 l18 20 l40 -48" fill="none" stroke="#ffffff"
        stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
```

Rendered and committed: `assets/icon/icon.png` (1024×1024) and
`assets/icon/icon_foreground.png` (1024×1024, transparent).

### 2. Rendering the PNGs

Render each SVG to a 1024×1024 PNG with `rsvg-convert` (confirmed on PATH):

```
rsvg-convert -w 1024 -h 1024 assets/icon/icon.svg -o assets/icon/icon.png
rsvg-convert -w 1024 -h 1024 assets/icon/icon_foreground.svg \
  -o assets/icon/icon_foreground.png
```

The foreground render must preserve transparency (`rsvg-convert` does by
default — no background flag).

### 3. `flutter_launcher_icons` config (`pubspec.yaml`)

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.0

flutter_launcher_icons:
  image_path: "assets/icon/icon.png"
  android: true
  ios: true
  remove_alpha_ios: true
  adaptive_icon_background: "#009688"
  adaptive_icon_foreground: "assets/icon/icon_foreground.png"
  min_sdk_android: 21
```

`dart run flutter_launcher_icons` regenerates:
- iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/*` (+ `Contents.json`).
- Android: `mipmap-*/ic_launcher.png`, `mipmap-anydpi-v26/ic_launcher.xml`
  (adaptive), and the `#009688` background color resource.

The `assets/icon/` source files do **not** need declaring under `flutter:
assets:` — they are build-time inputs, not bundled runtime assets.

## Testing

- `flutter pub get`, then `dart run flutter_launcher_icons` (regenerates icons).
- `just lint` clean; `just test` green (no Dart changes).
- Eyeball the rendered `icon.png` at small size before finalizing — nudge stroke
  weight if it reads muddy.
- Build both platforms and confirm the new icon on the launcher/home screen.
  Cold-restart the simulator/emulator (or reinstall) to drop the OS icon cache.

## Risk

- **Low.** No behavior change. `flutter_launcher_icons` produces a large but
  fully-generated diff (many PNGs + `Contents.json`); commit it as-is.
- Source SVG accidentally pre-rounded → double-rounded corners after the OS
  mask. Mitigation: the source is a full-bleed square rect (above).
- Foreground geometry drifting outside the 66% adaptive safe zone → clipped on
  Android. Mitigation: box spans the central ~50%, verified under circle mask.
