import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../core/category_colors.dart';
import 'dialog_constants.dart';

/// Result of editing/creating a category.
class CategoryDialogResult {
  CategoryDialogResult(this.name, this.color, this.emoji);
  final String name;
  final int color;
  final String? emoji; // a single grapheme, or null
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
  late final TextEditingController _icon = TextEditingController(
    text: widget.initialEmoji ?? '',
  );
  late int _color = widget.initialColor;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _icon.dispose();
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
            inputFormatters: [LengthLimitingTextInputFormatter(kMaxNameLength)],
          ),
          TextField(
            key: const Key('category-icon-field'),
            controller: _icon,
            decoration: InputDecoration(
              labelText: l10n.iconLabel,
              helperText: l10n.iconHelper,
            ),
            inputFormatters: [
              // Keep at most one user-perceived character (grapheme), so a
              // multi-codepoint emoji counts as one and a word can't be typed.
              TextInputFormatter.withFunction((oldValue, newValue) {
                if (newValue.text.characters.length <= 1) return newValue;
                final clipped = newValue.text.characters.take(1).toString();
                return TextEditingValue(
                  text: clipped,
                  selection: TextSelection.collapsed(offset: clipped.length),
                );
              }),
            ],
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
          onPressed: _name.text.trim().isEmpty
              ? null
              : () {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  final icon = _icon.text.trim();
                  Navigator.pop(
                    context,
                    CategoryDialogResult(
                      name,
                      _color,
                      icon.isEmpty ? null : icon,
                    ),
                  );
                },
          child: Text(isEdit ? l10n.save : l10n.add),
        ),
      ],
    );
  }
}
