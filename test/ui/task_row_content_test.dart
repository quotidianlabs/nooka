import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/home/widgets/task_row_content.dart';

// Field names + required createdAt match the generated `Task` data class.
Task _task({
  int id = 1,
  String name =
      'A very very very long task name that would overflow the row badly',
  DateTime? archivedAt,
}) => Task(
  id: id,
  categoryId: 1,
  name: name,
  sortOrder: 0,
  createdAt: DateTime(2026, 1, 1),
  archivedAt: archivedAt,
);

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('long title is clipped to two lines with ellipsis', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TaskRowContent(
          task: _task(),
          color: const Color(0xFF009688),
          now: DateTime(2026, 6, 20),
          onTaskTap: (_) {},
          onTaskMenu: null,
        ),
      ),
    );
    final title = tester.widget<Text>(find.text(_task().name));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('active task (archivedAt null) shows radio and no subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TaskRowContent(
          task: _task(),
          color: const Color(0xFF009688),
          now: DateTime(2026, 6, 20),
          onTaskTap: (_) {},
          onTaskMenu: null,
        ),
      ),
    );
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.textContaining('Auto-removes in'), findsNothing);
  });

  testWidgets('archived task (archivedAt set) shows check_circle + subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TaskRowContent(
          task: _task(archivedAt: DateTime(2026, 6, 1)),
          color: const Color(0xFF009688),
          now: DateTime(2026, 6, 20),
          onTaskTap: (_) {},
          onTaskMenu: null,
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    expect(find.textContaining('Auto-removes in'), findsOneWidget);
  });

  testWidgets('tapping the row fires onTaskTap with the task', (tester) async {
    Task? tapped;
    await tester.pumpWidget(
      _host(
        TaskRowContent(
          task: _task(),
          color: const Color(0xFF009688),
          now: DateTime(2026, 6, 20),
          onTaskTap: (t) => tapped = t,
          onTaskMenu: null,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('task-1')));
    expect(tapped?.id, 1);
  });

  testWidgets('tapping the trailing menu button invokes onTaskMenu', (
    WidgetTester tester,
  ) async {
    Task? tapped;
    final t = _task(id: 5, name: 'Sweep');
    await tester.pumpWidget(
      _host(
        TaskRowContent(
          task: t,
          color: const Color(0xFF009688),
          now: DateTime(2026, 6, 25),
          onTaskTap: (_) {},
          onTaskMenu: (task) => tapped = task,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('task-menu-5')));
    await tester.pump();

    expect(tapped?.id, 5);
  });
}
