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
    await tester.tap(find.byKey(const Key('category-confirm')));
    await tester.pumpAndSettle();

    expect(result?.name, 'Home');
    expect(result?.emoji, 'a');
  });
}
