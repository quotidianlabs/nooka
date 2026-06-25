# app-icon — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a custom white-ticked-checkbox-on-teal launcher icon for iOS and
Android, generated from committed source art.

**Spec:** [`design.md`](./design.md)

**Branch:** `feat/app-icon`

**Commit strategy:** Single commit (source art + config + the generated
platform diff land together; the generated files are meaningless without the
config that produced them).

## Global constraints

- Brand teal: `#009688`. Marks: white `#ffffff`.
- Source SVG is the truth; PNGs are rendered from it and committed (the build
  must never require a renderer).
- `icon.svg` is full-bleed and **not** pre-rounded — the OS applies its own mask.
- Android adaptive foreground geometry stays in the central ~50% (inside the 66%
  safe zone).
- No Dart or behavior change.

---

### Task 1: Author source art + rendered PNGs

**Files:**
- Create: `assets/icon/icon.svg`
- Create: `assets/icon/icon_foreground.svg`
- Create: `assets/icon/icon.png` (generated, committed)
- Create: `assets/icon/icon_foreground.png` (generated, committed)

Create the SVG sources and render the 1024×1024 PNGs `flutter_launcher_icons`
consumes.

- [ ] **Step 1: Write `assets/icon/icon.svg`** (full-bleed, teal background)

  ```svg
  <svg viewBox="0 0 220 220" xmlns="http://www.w3.org/2000/svg">
    <rect width="220" height="220" fill="#009688"/>
    <rect x="60" y="60" width="100" height="100" rx="24"
          fill="none" stroke="#ffffff" stroke-width="11"/>
    <path d="M84 110 l18 20 l40 -48" fill="none" stroke="#ffffff"
          stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
  ```

- [ ] **Step 2: Write `assets/icon/icon_foreground.svg`** (marks only, transparent)

  ```svg
  <svg viewBox="0 0 220 220" xmlns="http://www.w3.org/2000/svg">
    <rect x="60" y="60" width="100" height="100" rx="24"
          fill="none" stroke="#ffffff" stroke-width="11"/>
    <path d="M84 110 l18 20 l40 -48" fill="none" stroke="#ffffff"
          stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
  ```

- [ ] **Step 3: Render the PNGs**

  ```bash
  rsvg-convert -w 1024 -h 1024 assets/icon/icon.svg -o assets/icon/icon.png
  rsvg-convert -w 1024 -h 1024 assets/icon/icon_foreground.svg \
    -o assets/icon/icon_foreground.png
  ```

- [ ] **Step 4: Verify the renders**

  ```bash
  file assets/icon/icon.png assets/icon/icon_foreground.png
  ```
  Expected: both `PNG image data, 1024 x 1024`. Open `icon.png` and confirm a
  white checkbox on teal; open `icon_foreground.png` and confirm the same marks
  on a transparent background (no teal fill).

---

### Task 2: Wire `flutter_launcher_icons` and generate

**Files:**
- Modify: `pubspec.yaml`

Add the dev-dependency and config, then run the generator.

- [ ] **Step 1: Add the dev-dependency** under `dev_dependencies:` in
  `pubspec.yaml`

  ```yaml
  flutter_launcher_icons: ^0.14.0
  ```

- [ ] **Step 2: Add the config block** at the top level of `pubspec.yaml`
  (sibling of `flutter:`)

  ```yaml
  flutter_launcher_icons:
    image_path: "assets/icon/icon.png"
    android: true
    ios: true
    remove_alpha_ios: true
    adaptive_icon_background: "#009688"
    adaptive_icon_foreground: "assets/icon/icon_foreground.png"
    min_sdk_android: 21
  ```

- [ ] **Step 3: Fetch deps + generate**

  ```bash
  flutter pub get
  dart run flutter_launcher_icons
  ```
  Expected: "Successfully generated launcher icons" (or equivalent). Generates
  `ios/Runner/Assets.xcassets/AppIcon.appiconset/*`,
  `android/app/src/main/res/mipmap-*/ic_launcher.png`,
  `mipmap-anydpi-v26/ic_launcher.xml`, and the `#009688` background resource.

- [ ] **Step 4: Confirm the generated diff**

  ```bash
  git status --short android/app/src/main/res ios/Runner/Assets.xcassets
  ```
  Expected: modified/added launcher PNGs, the adaptive XML, and the background
  color resource.

---

### Task 3: Verify

**Files:** none (verification only).

- [ ] **Step 1: Lint**

  ```bash
  just lint
  ```
  Expected: clean (no analyzer issues; formatter makes no changes).

- [ ] **Step 2: Test**

  ```bash
  just test
  ```
  Expected: full suite green (no Dart change, so unchanged from baseline).

- [ ] **Step 3: Visual check on a device/emulator**

  Build and launch on both an iOS simulator and an Android emulator. Cold-restart
  (or reinstall) to drop the OS icon cache, then confirm the white checkbox on
  teal appears on the home screen at normal size — legible, not muddy.

---

### Task 4: Commit

- [ ] **Step 1: Stage source art, config, and the generated diff**

  ```bash
  git add assets/icon pubspec.yaml pubspec.lock \
    android/app/src/main/res ios/Runner/Assets.xcassets \
    planning/changes/active/2026-06-18.01-app-icon planning/README.md
  ```

- [ ] **Step 2: Commit**

  ```bash
  git commit -m "feat: custom ticked-checkbox app icon

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```
