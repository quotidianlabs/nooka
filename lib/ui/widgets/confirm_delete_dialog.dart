import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Confirms cascade-deleting a category. Returns true if confirmed.
Future<bool> confirmDeleteCategory(
  BuildContext context, {
  required String name,
  required int itemCount,
}) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(l10n.deleteCategoryTitle),
      content: Text(l10n.deleteCategoryBody(name, itemCount)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('confirm-delete'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Confirms deleting every archived item. Returns true if confirmed.
Future<bool> confirmClearArchive(
  BuildContext context, {
  required int count,
}) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(l10n.clearArchiveTitle),
      content: Text(l10n.clearArchiveBody(count)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('confirm-clear-archive'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}
