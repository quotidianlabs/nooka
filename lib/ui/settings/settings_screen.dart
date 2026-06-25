import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../core/locale_controller.dart';
import '../core/theme_controller.dart';
import 'settings_view_model.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = ref.watch(themeControllerProvider);
    final locale = ref.watch(localeControllerProvider);
    ref.watch(
      settingsViewModelProvider,
    ); // keep the notifier alive across dialogs

    String themeName(AppThemeMode m) => switch (m) {
      AppThemeMode.system => l10n.themeSystem,
      AppThemeMode.light => l10n.themeLight,
      AppThemeMode.dark => l10n.themeDark,
    };
    String localeName(AppLocale l) => switch (l) {
      AppLocale.system => l10n.langSystem,
      AppLocale.en => l10n.langEnglish,
      AppLocale.ru => l10n.langRussian,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            key: const Key('theme-tile'),
            title: Text(l10n.themeLabel),
            trailing: DropdownButton<AppThemeMode>(
              value: theme,
              items: [
                for (final m in AppThemeMode.values)
                  DropdownMenuItem(value: m, child: Text(themeName(m))),
              ],
              onChanged: (m) {
                if (m != null) {
                  ref.read(themeControllerProvider.notifier).set(m);
                }
              },
            ),
          ),
          ListTile(
            key: const Key('language-tile'),
            title: Text(l10n.languageLabel),
            trailing: DropdownButton<AppLocale>(
              value: locale,
              items: [
                for (final l in AppLocale.values)
                  DropdownMenuItem(value: l, child: Text(localeName(l))),
              ],
              onChanged: (l) {
                if (l != null) {
                  ref.read(localeControllerProvider.notifier).set(l);
                }
              },
            ),
          ),
          ListTile(
            key: const Key('export-tile'),
            title: Text(l10n.exportData),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            key: const Key('import-tile'),
            title: Text(l10n.importData),
            onTap: () => _import(context, ref),
          ),
        ],
      ),
    );
  }
}

Future<void> _export(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await ref
      .read(settingsViewModelProvider.notifier)
      .export(l10n.exportShareSubject);
  if (!ok && context.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.actionFailed)));
  }
}

Future<void> _import(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final vm = ref.read(settingsViewModelProvider.notifier);
  final pick = await vm.pickImport();
  if (!context.mounted) return;
  switch (pick) {
    case ImportPickCancelled():
      return;
    case ImportPickInvalid():
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.importInvalidFile)));
    case ImportPickFailed():
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.actionFailed)));
    case ImportPickReady(:final data):
      final count = data.categories.length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.importReplaceTitle),
          content: Text(l10n.importReplaceBody(count)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('confirm-import'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.replace),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final ok = await vm.applyImport(data);
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? l10n.importDone(count) : l10n.actionFailed),
        ),
      );
  }
}
