import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../core/category_colors.dart';

/// Result of editing/creating a category.
class CategoryDialogResult {
  CategoryDialogResult(this.name, this.color, this.emoji);
  final String name;
  final int color;
  final String? emoji;
}

/// Shows a dialog to create or edit a category. Returns null on cancel.
Future<CategoryDialogResult?> showCategoryDialog(
  BuildContext context, {
  String? initialName,
  int? initialColor,
  String? initialEmoji,
}) {
  return showDialog<CategoryDialogResult>(
    context: context,
    builder: (_) => _CategoryDialog(
      initialName: initialName ?? '',
      initialColor: initialColor ?? kDefaultCategoryColor,
      initialEmoji: initialEmoji,
    ),
  );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.initialName,
    required this.initialColor,
    required this.initialEmoji,
  });
  final String initialName;
  final int initialColor;
  final String? initialEmoji;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _emoji = TextEditingController(
    text: widget.initialEmoji ?? '',
  );
  late int _color = widget.initialColor;

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.initialName.isNotEmpty;
    return AlertDialog(
      title: Text(isEdit ? l10n.editCategory : l10n.addCategory),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('category-name-field'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.categoryNameLabel),
          ),
          TextField(
            key: const Key('category-emoji-field'),
            controller: _emoji,
            maxLength: 2,
            decoration: InputDecoration(labelText: l10n.emojiLabel),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in kCategoryPalette)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    backgroundColor: Color(c),
                    radius: 14,
                    child: _color == c
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('category-confirm'),
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final emoji = _emoji.text.trim();
            Navigator.pop(
              context,
              CategoryDialogResult(name, _color, emoji.isEmpty ? null : emoji),
            );
          },
          child: Text(isEdit ? l10n.save : l10n.add),
        ),
      ],
    );
  }
}
