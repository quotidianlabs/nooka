import 'dart:async';

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

// A throwaway Category row for the dropdown. Field names + the required
// createdAt match the generated `Category` data class in database.g.dart.
Category _cat(int id, String name) => Category(
  id: id,
  name: name,
  color: 0xFF009688,
  emoji: null,
  collapsed: false,
  sortOrder: 0,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets('rapid double-tap on quick-add only adds once', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(
      _host(
        (context) => showQuickAddDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
          onAdd: (name, categoryId, recurrenceCount, recurrenceUnit) async {
            calls++;
            await gate.future; // hold the await open
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('quick-add-field')), 'Milk');
    await tester
        .pump(); // flush the listener-driven setState so confirm is enabled
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pump(); // start the first _submit; field clears synchronously
    // Field is already empty, so the second tap reads empty and no-ops; the
    // _busy guard would also reject it.
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('quick-add confirm is disabled until the name is non-empty', (
    tester,
  ) async {
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

    TextButton confirm() =>
        tester.widget<TextButton>(find.byKey(const Key('quick-add-confirm')));
    expect(confirm().onPressed, isNull); // empty -> disabled

    await tester.enterText(find.byKey(const Key('quick-add-field')), '   ');
    await tester.pump();
    expect(confirm().onPressed, isNull); // whitespace-only -> still disabled

    await tester.enterText(find.byKey(const Key('quick-add-field')), 'Milk');
    await tester.pump();
    expect(confirm().onPressed, isNotNull); // non-empty -> enabled

    await tester.enterText(find.byKey(const Key('quick-add-field')), 'x' * 200);
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const Key('quick-add-field')),
    );
    expect(field.controller!.text.length, 100); // capped at kMaxNameLength
  });

  testWidgets(
    'dismissing quick-add mid-await does not requestFocus on a disposed node',
    (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        _host(
          (context) => showQuickAddDialog(
            context,
            categories: [_cat(1, 'Home')],
            initialCategoryId: 1,
            onAdd: (name, categoryId, recurrenceCount, recurrenceUnit) async =>
                gate.future,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('quick-add-field')), 'Milk');
      await tester
          .pump(); // flush the listener-driven setState so confirm is enabled
      await tester.tap(find.byKey(const Key('quick-add-confirm')));
      await tester.pump(); // _submit awaits onAdd

      // Close the dialog while the await is still pending.
      await tester.tap(find.byKey(const Key('quick-add-done')));
      await tester.pumpAndSettle();

      gate.complete();
      await tester.pumpAndSettle();
      // No "requestFocus after dispose" / setState-after-dispose error -> pass.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('quick-add passes recurrence and resets Repeat after each add', (
    tester,
  ) async {
    final added = <(String, int?, RecurrenceUnit?)>[];
    await tester.pumpWidget(
      _host(
        (context) => showQuickAddDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
          onAdd:
              (
                String name,
                int categoryId,
                int? recurrenceCount,
                RecurrenceUnit? recurrenceUnit,
              ) async {
                added.add((name, recurrenceCount, recurrenceUnit));
              },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Repeat every 2 weeks.
    await tester.tap(find.byKey(const Key('task-repeat-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('task-repeat-stepper')),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('task-repeat-unit')),
        matching: find.text('Weeks'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('quick-add-field')),
      'Water plants',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pumpAndSettle();

    expect(added.single, ('Water plants', 2, RecurrenceUnit.weeks));
    // Repeat reset to off for the next entry: the stepper is gone again.
    expect(find.byKey(const Key('task-repeat-stepper')), findsNothing);

    // A second add without touching Repeat passes nulls.
    await tester.enterText(find.byKey(const Key('quick-add-field')), 'Milk');
    await tester.pump();
    await tester.tap(find.byKey(const Key('quick-add-confirm')));
    await tester.pumpAndSettle();
    expect(added.last, ('Milk', null, null));

    // Repeat's own controls reset to the defaults too, not just the toggle.
    await tester.tap(find.byKey(const Key('task-repeat-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('task-repeat-stepper')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<RecurrenceUnit>>(
            find.byKey(const Key('task-repeat-unit')),
          )
          .selected,
      {RecurrenceUnit.days},
    );
  });

  testWidgets('showTaskDialog returns the result on confirm', (tester) async {
    TaskDialogResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await showTaskDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('task-name-field')), 'Sweep');
    await tester.pump(); // flush listener-driven setState so confirm is enabled
    await tester.tap(find.byKey(const Key('task-confirm')));
    await tester.pumpAndSettle();
    expect(result?.name, 'Sweep');
    expect(result?.categoryId, 1);
  });

  testWidgets('showTaskDialog returns null on cancel', (tester) async {
    Object? sentinel = 'unset';
    await tester.pumpWidget(
      _host((context) async {
        sentinel = await showTaskDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sentinel, isNull);
  });

  testWidgets(
    'showTaskDialog seeded with an existing recurrence opens with Repeat on',
    (tester) async {
      TaskDialogResult? result;
      await tester.pumpWidget(
        _host((context) async {
          result = await showTaskDialog(
            context,
            categories: [_cat(1, 'Home')],
            initialCategoryId: 1,
            initialName: 'Water plants',
            initialRecurrenceCount: 2,
            initialRecurrenceUnit: RecurrenceUnit.weeks,
          );
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Repeat is already on -- no toggle tap needed.
      expect(find.byKey(const Key('task-repeat-stepper')), findsOneWidget);
      expect(find.byKey(const Key('task-repeat-unit')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('task-repeat-stepper')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('task-confirm')));
      await tester.pumpAndSettle();

      expect(result?.recurrenceCount, 2);
      expect(result?.recurrenceUnit, RecurrenceUnit.weeks);
    },
  );

  testWidgets('toggling Repeat on reveals the stepper + unit control and '
      'returns the default recurrence', (tester) async {
    TaskDialogResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await showTaskDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
          initialName: 'Water plants',
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-repeat-toggle')), findsOneWidget);
    expect(find.byKey(const Key('task-repeat-stepper')), findsNothing);
    expect(find.byKey(const Key('task-repeat-unit')), findsNothing);

    await tester.tap(find.byKey(const Key('task-repeat-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-repeat-stepper')), findsOneWidget);
    expect(find.byKey(const Key('task-repeat-unit')), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-confirm')));
    await tester.pumpAndSettle();

    expect(result?.name, 'Water plants');
    expect(result?.recurrenceCount, 1);
    expect(result?.recurrenceUnit, RecurrenceUnit.days);
  });

  testWidgets('tapping the stepper + button increments the recurrence count', (
    tester,
  ) async {
    TaskDialogResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await showTaskDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
          initialName: 'Water plants',
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-repeat-toggle')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('task-repeat-stepper')),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-confirm')));
    await tester.pumpAndSettle();

    expect(result?.recurrenceCount, 2);
  });

  testWidgets('selecting a different recurrence unit updates the result', (
    tester,
  ) async {
    TaskDialogResult? result;
    await tester.pumpWidget(
      _host((context) async {
        result = await showTaskDialog(
          context,
          categories: [_cat(1, 'Home')],
          initialCategoryId: 1,
          initialName: 'Water plants',
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-repeat-toggle')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('task-repeat-unit')),
        matching: find.text('Weeks'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('task-confirm')));
    await tester.pumpAndSettle();

    expect(result?.recurrenceUnit, RecurrenceUnit.weeks);
  });
}
