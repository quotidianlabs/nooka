import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/l10n/app_localizations.dart';
import 'package:nooka/ui/widgets/confirm_delete_dialog.dart';

Widget _host(Future<void> Function(BuildContext) onOpen) => MaterialApp(
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

void main() {
  testWidgets('confirmDeleteCategory returns true on confirm', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      _host((context) async {
        answer = await confirmDeleteCategory(
          context,
          name: 'Home',
          itemCount: 2,
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('confirmDeleteCategory returns false on cancel', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      _host((context) async {
        answer = await confirmDeleteCategory(
          context,
          name: 'Home',
          itemCount: 2,
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });

  testWidgets('confirmClearArchive returns true on confirm', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      _host((context) async {
        answer = await confirmClearArchive(context, count: 3);
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-clear-archive')));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });
}
