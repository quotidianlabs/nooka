import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/services/database/database.dart';
import '../../../l10n/app_localizations.dart';
import 'category_header_content.dart';
import 'task_row_content.dart';

/// A collapsible category section: a flat section-label header plus its rows.
/// Used in both Active and Archive views; [archived] selects which rows + row
/// behavior to show. Active rows support swipe-right-to-complete (with haptic)
/// in addition to the tap fallback.
class CategorySection extends StatelessWidget {
  const CategorySection({
    super.key,
    required this.category,
    required this.tasks,
    required this.archived,
    required this.onToggleCollapsed,
    required this.onHeaderMenu,
    required this.onTaskTap,
    required this.onTaskMenu,
    required this.now,
  });

  final Category category;
  final List<Task> tasks;
  final bool archived;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onHeaderMenu;
  final void Function(Task) onTaskTap;
  final void Function(Task)? onTaskMenu;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = Color(category.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header as a ListTile so its leading chevron, title, and ⋮
        // menu align with the item rows' columns. The bold category-color name
        // + count and the colored underline below keep it reading as a flat
        // section label rather than a task row. Tapping toggles collapse.
        CategoryHeaderContent(
          category: category,
          taskCount: tasks.length,
          onToggleCollapsed: onToggleCollapsed,
          onHeaderMenu: onHeaderMenu,
        ),
        // Thin colored underline binding the items to their category.
        Container(
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 2),
          height: 2,
          color: color.withValues(alpha: 0.25),
        ),
        if (!category.collapsed)
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8, top: 4),
              child: Text(
                archived ? l10n.emptyArchive : l10n.emptyCategory,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (final task in tasks)
              Builder(
                builder: (context) {
                  final tile = TaskRowContent(
                    task: task,
                    color: color,
                    now: now,
                    onTaskTap: onTaskTap,
                    onTaskMenu: onTaskMenu,
                  );
                  if (archived) return tile;
                  // Active rows: swipe right to complete (tap still works too).
                  return Dismissible(
                    key: ValueKey('dismiss-${task.id}'),
                    direction: DismissDirection.startToEnd,
                    background: Container(
                      color: color,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 24),
                      child: const Icon(Icons.check, color: Colors.white),
                    ),
                    confirmDismiss: (_) async {
                      HapticFeedback.mediumImpact();
                      onTaskTap(task); // completes; stream removes the row
                      return false; // don't let Dismissible remove it itself
                    },
                    child: tile,
                  );
                },
              ),
      ],
    );
  }
}
