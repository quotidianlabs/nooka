import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/domain/recurrence.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/widgets/task_dialog.dart';

Widget _host(void Function(BuildContext) onOpen) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => onOpen(context),
          child: const Text('open'),
        ),
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
  sortOrder: 0,
  createdAt: DateTime(2026, 1, 1),
);

/// iPhone SE (3rd gen): 375x667 logical @2x, with a ~300pt keyboard held up —
/// the narrowest supported profile. Any RenderFlex overflow throws and fails
/// the test.
void _seSized(WidgetTester tester) {
  tester.view.physicalSize = const Size(750, 1334);
  tester.view.devicePixelRatio = 2.0;
  tester.view.viewInsets = const FakeViewPadding(bottom: 600);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('quick-add with Repeat on fits an SE screen with keyboard up', (
    tester,
  ) async {
    _seSized(tester);
    await tester.pumpWidget(
      _host(
        (context) => showQuickAddDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
          onAdd: (name, categoryId, recurrenceCount, recurrenceUnit) async {},
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The dialog scrolls on this profile; bring the toggle into view first,
    // as a user would.
    await tester.ensureVisible(find.byKey(const Key('task-repeat-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-repeat-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-repeat-unit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'edit dialog seeded recurring fits an SE screen with keyboard up',
    (tester) async {
      _seSized(tester);
      await tester.pumpWidget(
        _host(
          (context) => showTaskDialog(
            context,
            categories: [_cat(1, 'Home')],
            initialCategoryId: 1,
            initialName: 'Water plants',
            initialRecurrenceCount: 2,
            initialRecurrenceUnit: RecurrenceUnit.weeks,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('task-repeat-unit')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
