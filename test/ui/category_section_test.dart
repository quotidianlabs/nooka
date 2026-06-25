import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/home/widgets/category_section.dart';

Category _cat() => Category(
  id: 1,
  name: 'Home',
  color: 0xFF009688,
  emoji: null,
  collapsed: false,
  sortOrder: 0,
  createdAt: DateTime(2026, 1, 1),
);

Task _task(int id, String name, {DateTime? archivedAt}) => Task(
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
  home: Scaffold(body: ListView(children: [child])),
);

void main() {
  testWidgets('active section renders rows and fires tap + toggle', (
    tester,
  ) async {
    var tapped = 0;
    var toggled = 0;
    await tester.pumpWidget(
      _host(
        CategorySection(
          category: _cat(),
          tasks: [_task(1, 'Sweep')],
          archived: false,
          now: DateTime(2026, 6, 20),
          onToggleCollapsed: () => toggled++,
          onHeaderMenu: () {},
          onTaskTap: (_) => tapped++,
          onTaskMenu: (_) {},
        ),
      ),
    );
    expect(find.text('Sweep'), findsOneWidget);

    await tester.tap(find.byKey(const Key('category-header-1')));
    expect(toggled, 1);

    await tester.tap(find.byKey(const Key('task-1')));
    expect(tapped, 1);
  });

  testWidgets('archived section shows the countdown subtitle, no menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CategorySection(
          category: _cat(),
          tasks: [_task(1, 'Sweep', archivedAt: DateTime(2026, 6, 1))],
          archived: true,
          now: DateTime(2026, 6, 20),
          onToggleCollapsed: () {},
          onHeaderMenu: () {},
          onTaskTap: (_) {},
          onTaskMenu: null,
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.textContaining('Auto-removes in'), findsOneWidget);
    expect(find.byKey(const Key('task-menu-1')), findsNothing);
  });

  testWidgets('shows empty-category text when expanded with no tasks', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CategorySection(
          category: _cat(),
          tasks: const [],
          archived: false,
          now: DateTime(2026, 6, 25),
          onToggleCollapsed: () {},
          onHeaderMenu: () {},
          onTaskTap: (_) {},
          onTaskMenu: (_) {},
        ),
      ),
    );

    expect(find.text('No items'), findsOneWidget); // l10n.emptyCategory
  });

  testWidgets('swiping an active row right invokes onTaskTap (complete)', (
    WidgetTester tester,
  ) async {
    Task? completed;
    final t = _task(1, 'Sweep');
    await tester.pumpWidget(
      _host(
        CategorySection(
          category: _cat(),
          tasks: [t],
          archived: false,
          now: DateTime(2026, 6, 25),
          onToggleCollapsed: () {},
          onHeaderMenu: () {},
          onTaskTap: (task) => completed = task,
          onTaskMenu: (_) {},
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('dismiss-1')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    expect(completed?.id, 1); // confirmDismiss ran onTaskTap
  });
}
