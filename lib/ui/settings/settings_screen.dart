import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../core/locale_controller.dart';
import '../core/theme_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = ref.watch(themeControllerProvider);
    final locale = ref.watch(localeControllerProvider);

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
        ],
      ),
    );
  }
}
