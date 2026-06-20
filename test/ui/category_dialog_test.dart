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

    await tester.enterText(
      find.byKey(const Key('category-name-field')),
      'Home',
    );
    await tester.pump(); // flush the listener-driven setState before tapping
    await tester.tap(find.byKey(const Key('category-confirm')));
    await tester.pumpAndSettle();

    expect(result?.name, 'Home');
    expect(result?.emoji, 'a');
  });

  testWidgets('category confirm is disabled until the name is non-empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCategoryDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    TextButton confirm() =>
        tester.widget<TextButton>(find.byKey(const Key('category-confirm')));
    expect(confirm().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('category-name-field')),
      'Home',
    );
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
  });
}
