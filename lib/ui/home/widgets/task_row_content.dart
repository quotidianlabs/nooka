import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/services/database/database.dart';
import '../../../domain/archive.dart';
import '../../../l10n/app_localizations.dart';

/// The task ListTile for a category section row.
///
/// Archived rows show a check_circle in the category color and a subtitle with
/// completed-on + auto-removes-in text. Active rows show a semantic
/// radio_button_unchecked as the leading icon and no subtitle.
///
/// The trailing ⋮ menu button is shown only when [onTaskMenu] is non-null.
/// The [Dismissible] wrapper for active rows stays at the call site.
class TaskRowContent extends StatelessWidget {
  const TaskRowContent({
    super.key,
    required this.task,
    required this.color,
    required this.archived,
    required this.now,
    required this.onTaskTap,
    required this.onTaskMenu,
  });

  final Task task;
  final Color color;
  final bool archived;
  final DateTime now;
  final void Function(Task) onTaskTap;
  final void Function(Task)? onTaskMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    return ListTile(
      key: Key('task-${task.id}'),
      leading: archived
          ? Icon(Icons.check_circle, color: color)
          : Semantics(
              button: true,
              label: l10n.markDoneLabel,
              child: const Icon(Icons.radio_button_unchecked),
            ),
      title: Text(task.name),
      subtitle: archived
          ? Text(
              '${l10n.completedOn(DateFormat.yMMMd(localeName).format(task.archivedAt!))}'
              ' · ${l10n.autoRemovesIn(daysRemaining(task.archivedAt!, now))}',
            )
          : null,
      trailing: onTaskMenu == null
          ? null
          : IconButton(
              key: Key('task-menu-${task.id}'),
              icon: const Icon(Icons.more_vert),
              onPressed: () => onTaskMenu!(task),
            ),
      onTap: () => onTaskTap(task),
    );
  }
}
