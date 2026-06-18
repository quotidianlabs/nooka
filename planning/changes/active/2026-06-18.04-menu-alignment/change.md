---
status: approved
date: 2026-06-18
slug: menu-alignment
supersedes: null
superseded_by: null
pr: null
outcome: null
---

# Change: Align category-header and item ⋮ menus on one vertical line

**Lane:** lightweight — one file, ~one widget rewritten, no public-API change,
one new widget test plus a check that the existing header tests still pass.

## Goal

The category header's overflow (⋮) menu and the task rows' ⋮ menus don't share a
vertical line — the header builds a custom `Row` with right padding `4`, while
the rows are `ListTile`s whose trailing sits at the default ~`16` inset, so the
⋮ icons land at different x-positions and look ragged. Rebuild the header so its
leading icon, title, and ⋮ each align with the rows' corresponding columns.

## Approach

In `lib/ui/home/widgets/category_section.dart`, replace the header's hand-built
`InkWell` + `Padding` + `Row` (currently lines 50–97) with a `ListTile` that
uses the **same default metrics as the task rows** (chosen for robustness:
reusing ListTile's layout engine makes the three columns line up by
construction, with no version-specific pixel constants to drift):

- `key: Key('category-header-${category.id}')` — unchanged.
- `onTap: onToggleCollapsed` — unchanged behavior (tap the header to collapse).
- `leading:` the collapse chevron —
  `Icon(category.collapsed ? Icons.expand_more : Icons.expand_less, color: scheme.onSurfaceVariant)`.
  This sits in the same leading-icon column as a row's
  `radio_button_unchecked` / `check_circle`.
- `title:` the existing `Text.rich` unchanged — optional `emoji + ' '` span,
  then the bold category-color name (`titleMedium`, `nameColor`), then the muted
  `'  ·  ${l10n.openItemsCount(tasks.length)}'` span; `maxLines: 1`,
  `overflow: TextOverflow.ellipsis`. Same font and colors as today.
- `trailing:` the ⋮ menu, unchanged —
  `IconButton(key: Key('category-menu-${category.id}'), icon: Icon(Icons.more_vert), onPressed: onHeaderMenu)`.

The thin colored underline `Container` (currently lines 99–103) stays exactly as
is, immediately below the header. The previous in-row chevron `Icon` (between the
`Expanded` text and the menu) is removed — the chevron now leads the row.

**Net effect:** the chevron aligns under the rows' checkbox column, the category
name and task names start on the same vertical line, and the ⋮ menus form one
clean column. The only visual change is the header gaining ListTile's standard
row height (a few px taller than its current compact padding); item rows are
untouched — same height, font, padding, and leading icons.

This makes the header a `ListTile` again, softening the earlier
"flat section-label, intentionally not a ListTile" decision
([`ui-refinements`](../archive/2026-06-17.02-ui-refinements/design.md), commit
`6b434ef`); the flat-label *look* is preserved via the bold colored title and
the colored underline, so it still reads as a section header, not a task row.

## Files

- `lib/ui/home/widgets/category_section.dart` — rewrite the header block
  (InkWell/Padding/Row → ListTile); keep the underline `Container` and all row
  code unchanged.
- `test/ui/home_screen_test.dart` — add an alignment regression test (below).
  The three existing header tests are expected to still pass unchanged:
  "collapses and expands" (taps the `category-header` key), "flat label with no
  leading circle" (a chevron is not a `CircleAvatar`, so `find.byType(
  CircleAvatar)` is still `findsNothing`), and "icon before the name"
  (`'🛒 Shopping'` is still in the title).

## Verification

- [ ] **Failing test first.** Add to `test/ui/home_screen_test.dart`: seed one
  category with one active task, pump, then assert the ⋮ columns and leading
  columns align:

  ```dart
  testWidgets('header and row ⋮ menus align on one vertical line', (
    tester,
  ) async {
    final cat = await db.todoDao.createCategory(
      name: 'Home',
      color: 0xFF009688,
    );
    final task = await db.todoDao.createTask(categoryId: cat, name: 'Sweep');
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    final headerMenu = tester.getCenter(find.byKey(Key('category-menu-$cat')));
    final rowMenu = tester.getCenter(find.byKey(Key('task-menu-$task')));
    expect(headerMenu.dx, moreOrLessEquals(rowMenu.dx, epsilon: 0.5));

    final chevron = tester.getCenter(find.byIcon(Icons.expand_less));
    final radio = tester.getCenter(
      find.byIcon(Icons.radio_button_unchecked),
    );
    expect(chevron.dx, moreOrLessEquals(radio.dx, epsilon: 0.5));
  });
  ```

  Run: `flutter test test/ui/home_screen_test.dart` — expect the new test FAILS
  on the `dx` mismatch (the current header menu is ~12px off the row menu).

- [ ] **Apply the change** — rewrite the header to the `ListTile` above.
- [ ] **New test passes** —
  `flutter test test/ui/home_screen_test.dart` green, including the three
  existing header tests.
- [ ] `just test` — full suite green (36 tests: the prior 35 + this one).
- [ ] `just lint` — `dart format` clean, `flutter analyze` "No issues found!".
- [ ] **Eyeball it** — regenerate the screenshots
  (`docs/screenshots.md`) or run the app; confirm the ⋮ column is flush in
  `home-en` and the chevron leads the header in the checkbox column.
