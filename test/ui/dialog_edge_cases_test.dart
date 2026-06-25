import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/widgets/category_dialog.dart';
import 'package:nooka/ui/widgets/confirm_delete_dialog.dart';
import 'package:nooka/ui/widgets/task_dialog.dart';

/// Hosts a single button that runs [onPressed] with a valid BuildContext under
/// the localization delegates, so each dialog opens the way the app opens it.
Widget _host(Future<void> Function(BuildContext) onPressed) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => onPressed(context),
        child: const Text('open'),
      ),
    ),
  ),
);

Category _cat(int id, String name) => Category(
  id: id,
  name: name,
  color: 0xFF009688,
  emoji: null,
  collapsed: false,
  sortOrder: id,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets('confirmClearArchive returns false on cancel', (
    WidgetTester tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      _host(
        (context) async =>
            result = await confirmClearArchive(context, count: 3),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel')); // l10n.cancel
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('edit-task dialog: changing the category updates the result', (
    WidgetTester tester,
  ) async {
    TaskDialogResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await showTaskDialog(
          context,
          categories: [_cat(1, 'A'), _cat(2, 'B')],
          initialCategoryId: 1,
          initialName: 'Sweep',
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-category-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('B').last,
    ); // pick category B → onChanged (line 90)
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-confirm')));
    await tester.pumpAndSettle();

    expect(result?.categoryId, 2);
  });

  testWidgets('quick-add: submit via keyboard + change category', (
    WidgetTester tester,
  ) async {
    int? addedCategory;
    String? addedName;
    await tester.pumpWidget(
      _host((context) async {
        await showQuickAddDialog(
          context,
          categories: [_cat(1, 'A'), _cat(2, 'B')],
          initialCategoryId: 1,
          onAdd: (name, categoryId) async {
            addedName = name;
            addedCategory = categoryId;
          },
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quick-add-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last); // onChanged (line 210)
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('quick-add-field')), 'Mop');
    await tester.testTextInput.receiveAction(
      TextInputAction.done,
    ); // onSubmitted (line 197)
    await tester.pumpAndSettle();

    expect(addedName, 'Mop');
    expect(addedCategory, 2);
  });

  testWidgets('category dialog: tap a color swatch, then cancel', (
    WidgetTester tester,
  ) async {
    CategoryDialogResult? result;
    await tester.pumpWidget(
      _host((context) async => result = await showCategoryDialog(context)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap the second palette swatch → onTap setState (line 111).
    await tester.tap(find.byType(CircleAvatar).at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel')); // cancel (line 126)
    await tester.pumpAndSettle();

    expect(result, isNull); // cancel returns null
  });
}
