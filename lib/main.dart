import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repositories/settings_repository.dart';
import 'data/repositories/todo_repository.dart';
import 'l10n/app_localizations.dart';
import 'ui/core/locale_controller.dart';
import 'ui/core/theme.dart';
import 'ui/core/theme_controller.dart';
import 'ui/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  // Startup cleanup: purge archived items past their 30-day retention. Must
  // never block boot — log failures and continue.
  try {
    final purged = await container.read(todoRepositoryProvider).purgeExpired();
    debugPrint('Startup purge removed $purged expired item(s).');
  } catch (e, st) {
    debugPrint('Startup purge failed (continuing): $e\n$st');
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const NookaApp()),
  );
}

class NookaApp extends ConsumerWidget {
  const NookaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocale = ref.watch(localeControllerProvider);
    final themeMode = ref.watch(themeControllerProvider);
    return MaterialApp(
      title: 'Nooka',
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      debugShowCheckedModeBanner: false,
      theme: appLightTheme(),
      darkTheme: appDarkTheme(),
      themeMode: themeMode.themeMode,
      locale: appLocale.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    );
  }
}
