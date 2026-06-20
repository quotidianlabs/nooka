import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/data/services/database/database.dart';
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
          onAdd: (name, categoryId) async {
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
          onAdd: (name, categoryId) async {},
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
            onAdd: (name, categoryId) async => gate.future,
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
}
