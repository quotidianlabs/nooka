import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/home/widgets/category_header_content.dart';

Category _cat({String? emoji}) => Category(
  id: 7,
  name: 'Home',
  color: 0xFF009688,
  emoji: emoji,
  collapsed: false,
  sortOrder: 0,
  createdAt: DateTime(2026, 1, 1),
);

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('renders name, count, and emoji; fires callbacks', (
    tester,
  ) async {
    var toggled = 0;
    var menu = 0;
    await tester.pumpWidget(
      _host(
        CategoryHeaderContent(
          category: _cat(emoji: '🏠'),
          taskCount: 3,
          onToggleCollapsed: () => toggled++,
          onHeaderMenu: () => menu++,
        ),
      ),
    );
    expect(find.textContaining('🏠 Home'), findsOneWidget);
    expect(find.textContaining('3 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('category-header-7')));
    expect(toggled, 1);

    await tester.tap(find.byKey(const Key('category-menu-7')));
    expect(menu, 1);
  });
}
