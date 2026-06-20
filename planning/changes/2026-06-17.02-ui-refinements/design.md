---
status: shipped
date: 2026-06-17
slug: ui-refinements
summary: Distinct category section-label headers, a single-grapheme relabeled icon field, and a reliably auto-dismissing undo toast.
supersedes: null
superseded_by: null
pr: null
outcome: 6d11b30 — distinct category section-label headers, single-grapheme relabeled icon field, and a reliably auto-dismissing undo toast.
---

# Nooka UI Refinements — Design Spec

**Date:** 2026-06-17
**Status:** Approved for planning
**Scope:** Three focused refinements to the existing Nooka app (categories+items to-do list). Small, single implementation plan. No data migration.

## Overview

Three changes from user feedback:

1. **Make category headers visually distinct from item rows.** Today both are near-identical `ListTile`s (leading circle + title + trailing ⋮), so a category header reads like just another task. Adopt a flat "section label" header.
2. **Fix and clarify the category "emoji" field.** It is a free `TextField` (max 2 chars, accepts any text, mislabeled "Emoji") whose purpose is unclear. Keep the feature but rename it to "Icon", restrict it to a single grapheme, and explain it.
3. **Fix the undo toast that "stays forever."** The bottom `SnackBar` never auto-dismisses on devices with animations/animator-duration-scale disabled. Make dismissal independent of the entrance animation.

## Current state (for reference)

- `lib/ui/home/widgets/category_section.dart`: the category header is a `ListTile` with `leading: CircleAvatar(color, radius 12)`, `title: Row[emoji?, name]`, `subtitle: openItemsCount`, `trailing: Row[⋮ menu, collapse chevron]`, `onTap: toggle collapse`. Item rows are `ListTile`s with an outline/check circle, name, optional date+countdown subtitle, trailing ⋮; active rows are wrapped in a `Dismissible` for swipe-to-complete.
- `lib/ui/widgets/category_dialog.dart`: an emoji `TextField` with `maxLength: 2`, label `l10n.emojiLabel` ("Emoji (optional)").
- `lib/ui/home/home_screen.dart` `_complete` / `_restore`: `messenger..hideCurrentSnackBar()..showSnackBar(SnackBar(content, action: Undo))` with the default duration.
- Data model: `Categories.emoji` is nullable text (`lib/data/services/database/database.dart`).

## Change 1 — Category header as a flat section label

Replace the category-header `ListTile` in `category_section.dart` with a slim custom header widget (still inside `CategorySection`). Requirements:

- **No leading color circle.**
- **Name** is rendered in the **category color, bold, sentence case** (exactly as the user typed it — no forced uppercase).
- If `category.emoji != null`, show the **icon immediately before the name**.
- Show the count after the name as a muted suffix, separated by ` · `, using the existing localized `openItemsCount(count)` (which already carries full Russian plural forms). This replaces the separate `subtitle` line.
- A **2px horizontal divider in the category color at ~25% opacity** sits directly below the header, visually binding the items to their category.
- **Trailing controls unchanged:** collapse chevron (`expand_less` / `expand_more`) + the `⋮` menu (`category-menu-{id}` key preserved). Tapping the header still toggles collapse (`category-header-{id}` key preserved).
- Header vertical padding is tighter/denser than a `ListTile` so it reads as a label, not a tappable row.
- **Item rows are unchanged** (outline circle / check circle, name, date+countdown for archived, ⋮ menu, swipe-to-complete). The hierarchy now comes from the header's color + weight + underline and the absence of a row affordance.

**Contrast guard (required):** palette colors at full saturation can fall below 4.5:1 on the light surface (and some are too dark on the dark surface). The colored name must be tonally adjusted per theme so it always meets ≥4.5:1 against `colorScheme.surface`. Approach: compute a readable variant of `category.color` (e.g. lighten on dark backgrounds / darken on light backgrounds via `HSLColor` lightness steps, or blend toward `onSurface`) until the WCAG contrast ratio ≥ 4.5:1; use that for the name text. The underline and the icon use the raw category color (decorative, not text, so the contrast rule does not gate them). Provide this as a small pure helper (e.g. `readableOn(Color color, Color surface)`) in the UI core so it is unit-testable.

## Change 2 — "Icon" field (keep, fixed & clarified)

In `category_dialog.dart` and localization:

- Rename the label from `emojiLabel` to **`iconLabel`**: en `"Icon (optional)"`, ru `"Иконка (необязательно)"`.
- Add **helper text** below the field: new key `iconHelper` — en `"A single emoji or character shown next to the name."`, ru `"Один эмодзи или символ рядом с названием."` Render via the field's `InputDecoration.helperText`.
- **Restrict to a single grapheme cluster.** Replace `maxLength: 2` with enforcement that the stored value is at most one user-perceived character (`String.characters`), so a flag/ZWJ emoji counts as one and a word cannot be entered. Implementation: an `inputFormatter` (or `onChanged` normalization) that truncates to `value.characters.take(1)`, and on save store `null` if empty else the single grapheme.
- **Data model unchanged** — `Categories.emoji` stays nullable text; no migration. (The column name `emoji` may remain internally; only the user-facing label changes. Renaming the DB column is out of scope.)
- The header (Change 1) shows this icon before the name.

## Change 3 — Undo toast reliable auto-dismiss

In `home_screen.dart` `_complete` and `_restore` (and any other `showSnackBar` call):

- Show the SnackBar with `behavior: SnackBarBehavior.floating` and an explicit `duration: const Duration(seconds: 4)`.
- **Backstop dismissal (required):** capture the controller returned by `messenger.showSnackBar(...)` and schedule `Future.delayed(const Duration(seconds: 4, milliseconds: 250), () => controller.close())` (guarded so it is a no-op if already closed). This guarantees the toast disappears even when the device has animations / animator-duration-scale disabled, where the SnackBar's built-in timer (which starts only after the entrance animation completes) never fires. Keep `hideCurrentSnackBar()` before showing so toasts don't stack.
- Preserve the **Undo** action (restore on complete; re-complete on restore).
- Extract the show logic into a small private helper (e.g. `_showUndoToast(String message, VoidCallback onUndo)`) so `_complete` and `_restore` share one correct implementation.

**Root-cause note:** the original bug is the well-known Flutter behavior where `SnackBar` auto-dismiss is tied to `AnimationStatus.completed`; with animations off, that status path does not arm the timer, so the toast lingers. The backstop timer makes dismissal independent of the animation.

## Localization

- Add: `iconLabel`, `iconHelper`. Remove the now-unused `emojiLabel`. Update both `app_en.arb` and `app_ru.arb`; regenerate with `flutter gen-l10n`.
- The header count: if a bare number with a separator (` · 3`) is used, no new plural is needed. If a localized "N items" is desired in the header, reuse the existing `openItemsCount` (which already has full Russian plural forms). Decision: use `openItemsCount(count)` in the header so it stays localized and pluralized; render it in muted style after the name.

## Testing

- **Unit:** `readableOn(color, surface)` returns a color with contrast ratio ≥ 4.5:1 against the surface for representative palette colors on both light and dark surfaces.
- **Widget (category_section):** header shows the category name with **no leading `CircleAvatar`**; the colored underline is present; when `emoji` is set the icon appears before the name; the `category-header-{id}` and `category-menu-{id}` keys still work (collapse toggle + menu).
- **Widget (category_dialog):** entering a two-character string leaves a single grapheme in the field; the helper text is shown; saving an empty icon stores null.
- **Widget (toast):** after completing an item, the undo SnackBar appears, and after advancing time past the duration it is gone (fake-async covers the backstop timer). Assert `SnackBarBehavior.floating`.
- **Manual (on-device):** with system animations disabled, complete an item and confirm the toast auto-dismisses within ~5s.
- Existing tests must keep passing; update any test that referenced `emojiLabel` or asserted the old header structure (leading circle).

## Out of scope

Renaming the `emoji` DB column; drag-reorder UI; any change to archive/cleanup behavior; icon **picker** grid (explicitly deferred — the field stays free-entry, just single-grapheme and clarified).
