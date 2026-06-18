---
status: shipped
date: 2026-06-17
slug: ui-refinements
spec: ui-refinements
pr: null
---

# Nooka UI Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make category headers read as distinct section labels, clarify the category "icon" field (single grapheme, relabeled), and fix the undo toast that never auto-dismisses when device animations are off.

**Architecture:** Three mostly-independent changes to the existing Nooka Flutter app (layered MVVM + Riverpod). A new pure `readableOn` contrast helper backs the colored header text; the header is rebuilt inside `category_section.dart`; the icon field is in `category_dialog.dart` + ARB; the toast fix is a shared helper in `home_screen.dart`.

**Tech Stack:** Flutter, Material 3, ARB localization (`flutter gen-l10n`). No new dependencies, no data migration. Generated `.g.dart` / `app_localizations*.dart` are committed.

---

## Conventions for every task

- Run `dart format . && flutter analyze` before each commit — both must be clean.
- After editing any `.arb` file, run `flutter gen-l10n` and commit the regenerated `lib/l10n/app_localizations*.dart`.
- Run tests with `flutter test`. The repo currently has 28 passing tests; don't regress them.
- Work from `/Users/kevinsmith/src/tasks`. Commit after each task with the message shown.

## File Structure

```
lib/ui/core/color_contrast.dart           NEW — readableOn() WCAG-contrast helper (pure)
lib/ui/widgets/category_dialog.dart        MOD — icon field: relabel, helper, single grapheme
lib/ui/home/widgets/category_section.dart  MOD — flat section-label header
lib/ui/home/home_screen.dart               MOD — reliable undo toast (_showUndoToast + backstop timer)
lib/l10n/app_en.arb, app_ru.arb            MOD — iconLabel, iconHelper (remove emojiLabel)
test/ui/color_contrast_test.dart           NEW
test/ui/category_dialog_test.dart          NEW
test/ui/home_screen_test.dart              MOD — header tests + ru assertion fix + toast test
```

---

## Task 1: `readableOn` contrast helper (TDD)

**Files:**
- Create: `lib/ui/core/color_contrast.dart`
- Test: `test/ui/color_contrast_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/ui/core/color_contrast.dart';

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const lightSurface = Color(0xFFFFFFFF);
  const darkSurface = Color(0xFF121212);

  test('raises a low-contrast color to >= 4.5:1 on a light surface', () {
    const orange = Color(0xFFFB8C00); // palette orange: weak on white
    final out = readableOn(orange, lightSurface);
    expect(_ratio(out, lightSurface), greaterThanOrEqualTo(4.5));
  });

  test('raises a low-contrast color to >= 4.5:1 on a dark surface', () {
    const purple = Color(0xFF5E35B1); // palette purple: weak on near-black
    final out = readableOn(purple, darkSurface);
    expect(_ratio(out, darkSurface), greaterThanOrEqualTo(4.5));
  });

  test('returns the color unchanged when it already passes', () {
    const black = Color(0xFF000000);
    expect(readableOn(black, lightSurface), black);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/color_contrast_test.dart`
Expected: FAIL — `color_contrast.dart` / `readableOn` not defined.

- [ ] **Step 3: Implement `color_contrast.dart`**

```dart
import 'package:flutter/material.dart';

/// Returns a variant of [color] whose WCAG contrast ratio against [surface] is
/// at least [minRatio] (AA for normal text = 4.5). If [color] already passes it
/// is returned unchanged. Otherwise its HSL lightness is stepped away from the
/// surface (darker on light surfaces, lighter on dark ones) until the ratio is
/// met or the color reaches black/white.
Color readableOn(Color color, Color surface, {double minRatio = 4.5}) {
  if (_contrastRatio(color, surface) >= minRatio) return color;
  final hsl = HSLColor.fromColor(color);
  final darken = surface.computeLuminance() > 0.5;
  var lightness = hsl.lightness;
  for (var i = 0; i < 100; i++) {
    lightness = (darken ? lightness - 0.02 : lightness + 0.02).clamp(0.0, 1.0);
    final candidate = hsl.withLightness(lightness).toColor();
    if (_contrastRatio(candidate, surface) >= minRatio) return candidate;
    if (lightness == 0.0 || lightness == 1.0) return candidate;
  }
  return hsl.withLightness(darken ? 0.0 : 1.0).toColor();
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/color_contrast_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
dart format . && flutter analyze
git add lib/ui/core/color_contrast.dart test/ui/color_contrast_test.dart
git commit -m "feat: readableOn WCAG contrast helper for colored category names"
```

---

## Task 2: Icon field (relabel, helper text, single grapheme)

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ru.arb`
- Modify: `lib/ui/widgets/category_dialog.dart`
- Test: `test/ui/category_dialog_test.dart`

- [ ] **Step 1: Update the ARB files**

In `lib/l10n/app_en.arb`, replace the line `"emojiLabel": "Emoji (optional)",` with:

```json
  "iconLabel": "Icon (optional)",
  "iconHelper": "A single emoji or character shown next to the name.",
```

In `lib/l10n/app_ru.arb`, replace the existing `emojiLabel` line with:

```json
  "iconLabel": "Иконка (необязательно)",
  "iconHelper": "Один эмодзи или символ рядом с названием.",
```

- [ ] **Step 2: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: regenerates `lib/l10n/app_localizations*.dart`; `emojiLabel` getter is gone, `iconLabel`/`iconHelper` added. (`flutter analyze` will now fail until Step 3 — expected.)

- [ ] **Step 3: Confirm no stragglers reference the old key**

Run: `grep -rn "emojiLabel\|category-emoji-field" lib test`
Expected: only `lib/ui/widgets/category_dialog.dart` (handled next). If any test references them, note it and update in Step 5.

- [ ] **Step 4: Update `category_dialog.dart`**

Replace the imports block and the icon `TextField`. Final file:

```dart
import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../core/category_colors.dart';

/// Result of editing/creating a category.
class CategoryDialogResult {
  CategoryDialogResult(this.name, this.color, this.emoji);
  final String name;
  final int color;
  final String? emoji; // a single grapheme, or null
}

/// Shows a dialog to create or edit a category. Returns null on cancel.
Future<CategoryDialogResult?> showCategoryDialog(
  BuildContext context, {
  String? initialName,
  int? initialColor,
  String? initialEmoji,
}) {
  return showDialog<CategoryDialogResult>(
    context: context,
    builder: (_) => _CategoryDialog(
      initialName: initialName ?? '',
      initialColor: initialColor ?? kDefaultCategoryColor,
      initialEmoji: initialEmoji,
    ),
  );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.initialName,
    required this.initialColor,
    required this.initialEmoji,
  });
  final String initialName;
  final int initialColor;
  final String? initialEmoji;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _icon = TextEditingController(
    text: widget.initialEmoji ?? '',
  );
  late int _color = widget.initialColor;

  @override
  void dispose() {
    _name.dispose();
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.initialName.isNotEmpty;
    return AlertDialog(
      title: Text(isEdit ? l10n.editCategory : l10n.addCategory),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('category-name-field'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.categoryNameLabel),
          ),
          TextField(
            key: const Key('category-icon-field'),
            controller: _icon,
            decoration: InputDecoration(
              labelText: l10n.iconLabel,
              helperText: l10n.iconHelper,
            ),
            inputFormatters: [
              // Keep at most one user-perceived character (grapheme), so a
              // multi-codepoint emoji counts as one and a word can't be typed.
              TextInputFormatter.withFunction((oldValue, newValue) {
                if (newValue.text.characters.length <= 1) return newValue;
                final clipped = newValue.text.characters.take(1).toString();
                return TextEditingValue(
                  text: clipped,
                  selection: TextSelection.collapsed(offset: clipped.length),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in kCategoryPalette)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    backgroundColor: Color(c),
                    radius: 14,
                    child: _color == c
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('category-confirm'),
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final icon = _icon.text.trim();
            Navigator.pop(
              context,
              CategoryDialogResult(name, _color, icon.isEmpty ? null : icon),
            );
          },
          child: Text(isEdit ? l10n.save : l10n.add),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Write the dialog widget test**

Create `test/ui/category_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/widgets/category_dialog.dart';

void main() {
  testWidgets('icon field shows helper and keeps only one grapheme', (
    tester,
  ) async {
    CategoryDialogResult? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showCategoryDialog(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('A single emoji or character shown next to the name.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('category-icon-field')), 'ab');
    await tester.pump();
    expect(find.text('ab'), findsNothing); // second char rejected
    expect(find.text('a'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('category-name-field')), 'Home');
    await tester.tap(find.byKey(const Key('category-confirm')));
    await tester.pumpAndSettle();

    expect(result?.name, 'Home');
    expect(result?.emoji, 'a');
  });
}
```

- [ ] **Step 6: Run tests + lint**

Run: `flutter test test/ui/category_dialog_test.dart && flutter test`
Expected: new test passes; full suite still green. Then `dart format . && flutter analyze` clean.

- [ ] **Step 7: Commit**

```bash
git add lib/l10n/ lib/ui/widgets/category_dialog.dart test/ui/category_dialog_test.dart
git commit -m "feat: relabel category icon field, restrict to one grapheme, add helper"
```

---

## Task 3: Flat section-label category header

**Files:**
- Modify: `lib/ui/home/widgets/category_section.dart`
- Modify: `test/ui/home_screen_test.dart`

- [ ] **Step 1: Replace `category_section.dart`**

Full new file (the header becomes a flat label; the item rows are unchanged):

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../data/services/database/database.dart';
import '../../../domain/archive.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/color_contrast.dart';

/// A collapsible category section: a flat section-label header plus its rows.
/// Used in both Active and Archive views; [archived] selects which rows + row
/// behavior to show. Active rows support swipe-right-to-complete (with haptic)
/// in addition to the tap fallback.
class CategorySection extends StatelessWidget {
  const CategorySection({
    super.key,
    required this.category,
    required this.tasks,
    required this.archived,
    required this.onToggleCollapsed,
    required this.onHeaderMenu,
    required this.onTaskTap,
    required this.onTaskMenu,
    required this.now,
  });

  final Category category;
  final List<Task> tasks;
  final bool archived;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onHeaderMenu;
  final void Function(Task) onTaskTap;
  final void Function(Task)? onTaskMenu;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(category.color);
    final nameColor = readableOn(color, scheme.surface);
    final localeName = Localizations.localeOf(context).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Flat section-label header (intentionally NOT a ListTile row): the
        // category name in its color (bold), optional icon before it, a muted
        // count, then the collapse chevron + menu. Tapping toggles collapse.
        InkWell(
          key: Key('category-header-${category.id}'),
          onTap: onToggleCollapsed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (category.emoji != null)
                          TextSpan(
                            text: '${category.emoji!} ',
                            style: TextStyle(color: color),
                          ),
                        TextSpan(
                          text: category.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: nameColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  ${l10n.openItemsCount(tasks.length)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  category.collapsed ? Icons.expand_more : Icons.expand_less,
                  color: scheme.onSurfaceVariant,
                ),
                IconButton(
                  key: Key('category-menu-${category.id}'),
                  icon: const Icon(Icons.more_vert),
                  onPressed: onHeaderMenu,
                ),
              ],
            ),
          ),
        ),
        // Thin colored underline binding the items to their category.
        Container(
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 2),
          height: 2,
          color: color.withValues(alpha: 0.25),
        ),
        if (!category.collapsed)
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8, top: 4),
              child: Text(
                archived ? l10n.emptyArchive : l10n.emptyCategory,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (final task in tasks)
              Builder(
                builder: (context) {
                  final tile = ListTile(
                    key: Key('task-${task.id}'),
                    leading: archived
                        ? Icon(Icons.check_circle, color: color)
                        : Semantics(
                            button: true,
                            label: l10n.markDoneLabel,
                            child: const Icon(Icons.radio_button_unchecked),
                          ),
                    title: Text(task.name),
                    subtitle: archived
                        ? Text(
                            '${l10n.completedOn(DateFormat.yMMMd(localeName).format(task.archivedAt!))}'
                            ' · ${l10n.autoRemovesIn(daysRemaining(task.archivedAt!, now))}',
                          )
                        : null,
                    trailing: onTaskMenu == null
                        ? null
                        : IconButton(
                            key: Key('task-menu-${task.id}'),
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => onTaskMenu!(task),
                          ),
                    onTap: () => onTaskTap(task),
                  );
                  if (archived) return tile;
                  // Active rows: swipe right to complete (tap still works too).
                  return Dismissible(
                    key: ValueKey('dismiss-${task.id}'),
                    direction: DismissDirection.startToEnd,
                    background: Container(
                      color: color,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 24),
                      child: const Icon(Icons.check, color: Colors.white),
                    ),
                    confirmDismiss: (_) async {
                      HapticFeedback.mediumImpact();
                      onTaskTap(task); // completes; stream removes the row
                      return false; // don't let Dismissible remove it itself
                    },
                    child: tile,
                  );
                },
              ),
      ],
    );
  }
}
```

- [ ] **Step 2: Fix the existing Russian test (count moved into a `Text.rich`)**

In `test/ui/home_screen_test.dart`, the Russian test currently asserts the count with an exact `find.text('5 дел')`. The count is now part of the header's `Text.rich`, so change that one assertion to a substring match. Find:

```dart
    expect(find.text('5 дел'), findsOneWidget);
```

Replace with:

```dart
    expect(find.textContaining('5 дел'), findsOneWidget);
```

(Leave the `find.textContaining('дней')` archive assertion as-is — that's an item subtitle, still a plain `Text`.)

- [ ] **Step 3: Add header widget tests**

Append these tests inside `main()` in `test/ui/home_screen_test.dart`:

```dart
  testWidgets('category header is a flat label with no leading circle', (
    tester,
  ) async {
    await db.todoDao.createCategory(name: 'Home', color: 0xFF009688);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    // The old header used a CircleAvatar swatch; the flat label has none, and
    // item rows use icons, so there should be no CircleAvatar on the screen.
    expect(find.byType(CircleAvatar), findsNothing);
    // Name + localized count render in the header rich text.
    expect(find.textContaining('Home'), findsOneWidget);
    expect(find.textContaining('0 items'), findsOneWidget);
  });

  testWidgets('category header shows the icon before the name when set', (
    tester,
  ) async {
    await db.todoDao.createCategory(
      name: 'Shopping',
      color: 0xFF1E88E5,
      emoji: '🛒',
    );
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();
    expect(find.textContaining('🛒'), findsOneWidget);
    expect(find.textContaining('Shopping'), findsOneWidget);
  });
```

- [ ] **Step 4: Run tests + lint**

Run: `flutter test`
Expected: all pass (existing + 2 new header tests; Russian test still green with the substring fix).
Then `dart format . && flutter analyze` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/home/widgets/category_section.dart test/ui/home_screen_test.dart
git commit -m "feat: flat section-label category header, distinct from item rows"
```

---

## Task 4: Reliable undo toast (fix "stays forever")

**Files:**
- Modify: `lib/ui/home/home_screen.dart`
- Test: `test/ui/home_screen_test.dart`

- [ ] **Step 1: Add `dart:async` import**

At the top of `lib/ui/home/home_screen.dart`, add (keep the other imports):

```dart
import 'dart:async';
```

- [ ] **Step 2: Add a toast field + dispose, and a shared `_showUndoToast` helper**

In `_HomeScreenState`, add a timer field near `_lastCategoryId`:

```dart
  int? _lastCategoryId; // remembered default for quick add
  Timer? _toastTimer;

  static const _toastDuration = Duration(seconds: 4);

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }
```

Then add the helper (place it next to `_complete`/`_restore`, under the `// ---- commands + toasts ----` comment):

```dart
  /// Shows a floating undo toast that reliably auto-dismisses. The built-in
  /// SnackBar timer only arms after the entrance animation completes, so on
  /// devices with animations disabled it never fires and the toast lingers
  /// forever. We add a backstop timer that closes it regardless of animation.
  void _showUndoToast(String message, VoidCallback onUndo) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    _toastTimer?.cancel();
    final controller = messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: _toastDuration,
        content: Text(message),
        action: SnackBarAction(label: l10n.undoAction, onPressed: onUndo),
      ),
    );
    var closed = false;
    controller.closed.then((_) => closed = true);
    _toastTimer = Timer(_toastDuration + const Duration(milliseconds: 300), () {
      if (!closed) controller.close();
    });
  }
```

- [ ] **Step 3: Rewrite `_complete` and `_restore` to use the helper**

Replace the existing `_complete` and `_restore` methods with:

```dart
  Future<void> _complete(Task task) async {
    final message = AppLocalizations.of(context).undoCompleteMessage;
    await _vm.completeTask(task.id);
    if (!mounted) return;
    _showUndoToast(message, () => _vm.restoreTask(task.id));
  }

  Future<void> _restore(Task task) async {
    final message = AppLocalizations.of(context).undoRestoreMessage;
    await _vm.restoreTask(task.id);
    if (!mounted) return;
    _showUndoToast(message, () => _vm.completeTask(task.id));
  }
```

- [ ] **Step 4: Add the toast widget test**

Append inside `main()` in `test/ui/home_screen_test.dart`:

```dart
  testWidgets('undo toast is floating and auto-dismisses', (tester) async {
    final cat = await db.todoDao.createCategory(name: 'Home', color: 0xFF009688);
    await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump(); // flush the completeTask await
    await tester.pump(const Duration(milliseconds: 300)); // snackbar entrance
    expect(find.text('Item completed'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
      SnackBarBehavior.floating,
    );

    // Advance past duration + backstop; the toast must be gone.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Item completed'), findsNothing);
  });
```

- [ ] **Step 5: Run tests + lint**

Run: `flutter test`
Expected: all pass. If any pre-existing toast-triggering test (e.g. the swipe/complete tests) now fails with "A Timer is still pending", it means that test ends while the backstop timer is unfired — add `await tester.pump(const Duration(seconds: 5));` before its final assertions so the timer fires (and is then cancelled by `dispose`). The `dispose` cancel should normally prevent this; only add the pump if a failure actually appears.
Then `dart format . && flutter analyze` — clean.

- [ ] **Step 6: Run the full suite + integration test**

Run: `flutter test && flutter test integration_test/critical_flow_test.dart -d flutter-tester`
Expected: all unit/widget tests pass; integration test passes.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/home/home_screen.dart test/ui/home_screen_test.dart
git commit -m "fix: undo toast reliably auto-dismisses (floating + backstop timer)"
```

---

## Task 5: Manual on-device verification + rebuild APK

**Files:** none (verification only)

- [ ] **Step 1: Build the release-style debug APK**

Run: `flutter build apk --debug`
Expected: build succeeds.

- [ ] **Step 2: Copy to Downloads**

Run: `cp build/app/outputs/flutter-apk/app-debug.apk ~/Downloads/nooka-debug.apk && ls -la ~/Downloads/nooka-debug.apk`
Expected: file present.

- [ ] **Step 3: Manual check (record result, do not fake it)**

On a device/emulator **with system animations turned off** (Android Developer options → Window/Transition/Animator scale = Off): create a category, add an item, complete it, and confirm the undo toast disappears within ~5 seconds. Also visually confirm category headers read as distinct section labels and the icon field accepts only one character. If a device is unavailable, state that this manual step was not run and that the widget test + backstop-timer logic cover dismissal in CI.

- [ ] **Step 4: No commit** (verification only; the APK is a build artifact, already gitignored under `build/`).

---

## Self-Review notes (incorporated)

- **Spec coverage:** flat section-label header (Task 3), no leading circle + colored name + underline + count + icon-before-name (Task 3), contrast guard via `readableOn` (Task 1), icon field relabel + helper + single grapheme + no migration (Task 2), reliable toast with floating + backstop timer (Task 4), tests per spec (Tasks 1–4), manual on-device animations-off check (Task 5).
- **Coupling note:** Task 2 removes `emojiLabel`, which the dialog references — both are changed in the same task so the tree compiles before commit. Task 3 depends on Task 1's `readableOn`.
- **Test fragility handled:** moving the count into a `Text.rich` breaks the exact-match `find.text('5 дел')`; Task 3 Step 2 switches it to `find.textContaining`. The backstop `Timer` is cancelled in `dispose` to avoid pending-timer failures; Task 4 Step 5 documents the fallback if one still appears.
- **Type consistency:** `readableOn(Color, Color, {minRatio})`, `_showUndoToast(String, VoidCallback)`, `_toastDuration`, `_toastTimer`, key `category-icon-field`, `CategoryDialogResult.emoji` (unchanged) are used consistently across tasks.
```
