import 'package:flutter/material.dart';

import '../../../data/services/database/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/color_contrast.dart';

/// The header ListTile for a category section: leading collapse chevron,
/// Text.rich title (optional emoji + bold name in readable color + item count),
/// and trailing ⋮ menu button.
///
/// Behavior-neutral extraction from [CategorySection]; callers supply all
/// callbacks so this widget stays stateless and easily testable.
class CategoryHeaderContent extends StatelessWidget {
  const CategoryHeaderContent({
    super.key,
    required this.category,
    required this.taskCount,
    required this.onToggleCollapsed,
    required this.onHeaderMenu,
  });

  final Category category;
  final int taskCount;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onHeaderMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(category.color);
    final nameColor = readableOn(color, scheme.surface);
    return ListTile(
      key: Key('category-header-${category.id}'),
      onTap: onToggleCollapsed,
      leading: Icon(
        category.collapsed ? Icons.expand_more : Icons.expand_less,
        color: scheme.onSurfaceVariant,
      ),
      title: Text.rich(
        TextSpan(
          children: [
            if (category.emoji != null)
              TextSpan(
                text: '${category.emoji!} ',
                style: TextStyle(color: color),
              ),
            TextSpan(
              text: category.name,
              style: theme.textTheme.titleMedium?.copyWith(
                color: nameColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: '  ·  ${l10n.openItemsCount(taskCount)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        key: Key('category-menu-${category.id}'),
        icon: const Icon(Icons.more_vert),
        onPressed: onHeaderMenu,
      ),
    );
  }
}
