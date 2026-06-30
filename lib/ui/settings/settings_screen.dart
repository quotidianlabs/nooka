import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/backup/cloud_backup_io.dart';
import '../../domain/models/backup_data.dart';
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
          const _CloudBackupSection(),
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
      await _confirmAndApply(context, ref, data);
  }
}

/// Shows the replace-all confirm dialog; on confirmation calls [applyImport]
/// and shows the result snackbar. Used by both the local-file import path and
/// the cloud-restore path to ensure the destructive-replace invariant is
/// never duplicated.
Future<void> _confirmAndApply(
  BuildContext context,
  WidgetRef ref,
  BackupData data,
) async {
  final l10n = AppLocalizations.of(context);
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
  final ok = await ref
      .read(settingsViewModelProvider.notifier)
      .applyImport(data);
  messenger.showSnackBar(
    SnackBar(content: Text(ok ? l10n.importDone(count) : l10n.actionFailed)),
  );
}

// ---------------------------------------------------------------------------
// Cloud backup section
// ---------------------------------------------------------------------------

class _CloudBackupSection extends ConsumerStatefulWidget {
  const _CloudBackupSection();

  @override
  ConsumerState<_CloudBackupSection> createState() =>
      _CloudBackupSectionState();
}

class _CloudBackupSectionState extends ConsumerState<_CloudBackupSection> {
  CloudAccount? _account;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    setState(() => _loading = true);
    final account = await ref
        .read(settingsViewModelProvider.notifier)
        .cloudAccount();
    if (!mounted) return;
    setState(() {
      _account = account;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final header = ListTile(
      key: const Key('cloud-section-header'),
      title: Text(
        l10n.cloudBackupSection,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );

    if (_account == null) {
      return Column(
        children: [
          header,
          ListTile(
            key: const Key('cloud-connect-tile'),
            title: Text(l10n.cloudConnect),
            enabled: !_loading,
            onTap: _loading ? null : _connect,
          ),
        ],
      );
    }

    return Column(
      children: [
        header,
        ListTile(title: Text(l10n.cloudConnectedAs(_account!.email))),
        ListTile(
          key: const Key('cloud-backup-now-tile'),
          title: Text(l10n.cloudBackupNow),
          enabled: !_loading,
          onTap: _loading ? null : _backupNow,
        ),
        ListTile(
          key: const Key('cloud-restore-tile'),
          title: Text(l10n.cloudRestore),
          enabled: !_loading,
          onTap: _loading ? null : _restore,
        ),
        ListTile(
          key: const Key('cloud-disconnect-tile'),
          title: Text(l10n.cloudDisconnect),
          enabled: !_loading,
          onTap: _loading ? null : _disconnect,
        ),
      ],
    );
  }

  Future<void> _connect() async {
    setState(() => _loading = true);
    final account = await ref
        .read(settingsViewModelProvider.notifier)
        .connectCloud();
    if (!mounted) return;
    setState(() {
      _account = account;
      _loading = false;
    });
  }

  Future<void> _disconnect() async {
    setState(() => _loading = true);
    await ref.read(settingsViewModelProvider.notifier).disconnectCloud();
    if (!mounted) return;
    setState(() {
      _account = null;
      _loading = false;
    });
  }

  Future<void> _backupNow() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      final vm = ref.read(settingsViewModelProvider.notifier);
      final ok = await vm.cloudBackupNow();
      if (!mounted) return;
      // DIAGNOSTIC (temporary): show the real error text instead of the generic
      // message so on-device backup failures can be triaged without adb.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          content: Text(
            ok ? l10n.cloudBackupDone : (vm.lastCloudError ?? l10n.actionFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      final refs = await ref
          .read(settingsViewModelProvider.notifier)
          .cloudBackups();
      if (!mounted) return;

      if (refs == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.actionFailed)));
        return;
      }

      if (refs.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.cloudNoBackups)));
        return;
      }

      final picked = await showDialog<CloudBackupRef>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(l10n.cloudRestore),
          children: [
            for (var i = 0; i < refs.length; i++)
              SimpleDialogOption(
                key: Key('cloud-backup-entry-$i'),
                onPressed: () => Navigator.pop(ctx, refs[i]),
                child: Text(
                  i == 0 ? l10n.cloudLatest : _formatDate(refs[i].createdAt),
                ),
              ),
          ],
        ),
      );

      if (picked == null || !mounted) return;

      final pick = await ref
          .read(settingsViewModelProvider.notifier)
          .fetchCloudBackup(picked.id);
      if (!mounted) return;

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
          await _confirmAndApply(context, ref, data);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
