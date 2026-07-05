import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/domain/recurrence.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/widgets/repeat_field.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('off: only the toggle shows; switching on reports the change', (
    tester,
  ) async {
    (bool, int, RecurrenceUnit)? reported;
    await tester.pumpWidget(
      _host(
        RepeatField(
          repeat: false,
          count: 1,
          unit: RecurrenceUnit.days,
          onChanged: (bool repeat, int count, RecurrenceUnit unit) =>
              reported = (repeat, count, unit),
        ),
      ),
    );

    expect(find.byKey(const Key('task-repeat-toggle')), findsOneWidget);
    expect(find.byKey(const Key('task-repeat-stepper')), findsNothing);
    expect(find.byKey(const Key('task-repeat-unit')), findsNothing);

    await tester.tap(find.byKey(const Key('task-repeat-toggle')));
    expect(reported, (true, 1, RecurrenceUnit.days));
  });

  testWidgets('on: minus is disabled at count 1; plus reports count+1', (
    tester,
  ) async {
    (bool, int, RecurrenceUnit)? reported;
    await tester.pumpWidget(
      _host(
        RepeatField(
          repeat: true,
          count: 1,
          unit: RecurrenceUnit.days,
          onChanged: (bool repeat, int count, RecurrenceUnit unit) =>
              reported = (repeat, count, unit),
        ),
      ),
    );

    final minus = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.byIcon(Icons.remove),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(minus.onPressed, isNull);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('task-repeat-stepper')),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(reported, (true, 2, RecurrenceUnit.days));
  });

  testWidgets('on: minus reports count-1 when count > 1', (tester) async {
    (bool, int, RecurrenceUnit)? reported;
    await tester.pumpWidget(
      _host(
        RepeatField(
          repeat: true,
          count: 3,
          unit: RecurrenceUnit.days,
          onChanged: (bool repeat, int count, RecurrenceUnit unit) =>
              reported = (repeat, count, unit),
        ),
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('task-repeat-stepper')),
        matching: find.byIcon(Icons.remove),
      ),
    );
    expect(reported, (true, 2, RecurrenceUnit.days));
  });

  testWidgets('unit selection reports the new unit, keeping the count', (
    tester,
  ) async {
    (bool, int, RecurrenceUnit)? reported;
    await tester.pumpWidget(
      _host(
        RepeatField(
          repeat: true,
          count: 2,
          unit: RecurrenceUnit.days,
          onChanged: (bool repeat, int count, RecurrenceUnit unit) =>
              reported = (repeat, count, unit),
        ),
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('task-repeat-unit')),
        matching: find.text('Weeks'),
      ),
    );
    expect(reported, (true, 2, RecurrenceUnit.weeks));
  });
}
