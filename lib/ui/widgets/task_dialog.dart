import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/database/database.dart';
import '../../l10n/app_localizations.dart';
import 'dialog_constants.dart';

/// Result of creating/editing a task: the name and the chosen category id.
class TaskDialogResult {
  TaskDialogResult(this.name, this.categoryId);
  final String name;
  final int categoryId;
}

/// Shows a dialog to create or edit a to-do item. [categories] must be
/// non-empty. Returns null on cancel.
Future<TaskDialogResult?> showTaskDialog(
  BuildContext context, {
  required List<Category> categories,
  required int initialCategoryId,
  String? initialName,
}) {
  return showDialog<TaskDialogResult>(
    context: context,
    builder: (_) => _TaskDialog(
      categories: categories,
      initialCategoryId: initialCategoryId,
      initialName: initialName ?? '',
    ),
  );
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({
    required this.categories,
    required this.initialCategoryId,
    required this.initialName,
  });
  final List<Category> categories;
  final int initialCategoryId;
  final String initialName;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late int _categoryId = widget.initialCategoryId;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.initialName.isNotEmpty;
    return AlertDialog(
      title: Text(isEdit ? l10n.editTask : l10n.addTask),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('task-name-field'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.taskNameLabel),
            inputFormatters: [LengthLimitingTextInputFormatter(kMaxNameLength)],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: const Key('task-category-dropdown'),
            initialValue: _categoryId,
            decoration: InputDecoration(labelText: l10n.categoryLabel),
            items: [
              for (final c in widget.categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('task-confirm'),
          onPressed: _name.text.trim().isEmpty
              ? null
              : () {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(context, TaskDialogResult(name, _categoryId));
                },
          child: Text(isEdit ? l10n.save : l10n.add),
        ),
      ],
    );
  }
}

/// Keep-keyboard-open quick add. Calls [onAdd] for each item; the field clears
/// and refocuses after every Add so several items can be entered in a row. The
/// dialog stays open until the user taps Done. [onAdd] receives the chosen
/// category so the caller can remember it as the new default.
Future<void> showQuickAddDialog(
  BuildContext context, {
  required List<Category> categories,
  required int initialCategoryId,
  required Future<void> Function(String name, int categoryId) onAdd,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _QuickAddDialog(
      categories: categories,
      initialCategoryId: initialCategoryId,
      onAdd: onAdd,
    ),
  );
}

class _QuickAddDialog extends StatefulWidget {
  const _QuickAddDialog({
    required this.categories,
    required this.initialCategoryId,
    required this.onAdd,
  });
  final List<Category> categories;
  final int initialCategoryId;
  final Future<void> Function(String name, int categoryId) onAdd;

  @override
  State<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<_QuickAddDialog> {
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode();
  late int _categoryId = widget.initialCategoryId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) return;
    _busy = true;
    _name.clear(); // clear synchronously, before the await
    try {
      await widget.onAdd(name, _categoryId);
    } finally {
      _busy = false;
    }
    if (!mounted) return; // L5: dialog may have been dismissed mid-await
    _focus.requestFocus(); // keep the keyboard up for the next item
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addTask),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('quick-add-field'),
            controller: _name,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: l10n.taskNameLabel),
            inputFormatters: [LengthLimitingTextInputFormatter(kMaxNameLength)],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: const Key('quick-add-category'),
            initialValue: _categoryId,
            decoration: InputDecoration(labelText: l10n.categoryLabel),
            items: [
              for (final c in widget.categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('quick-add-done'),
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.done),
        ),
        TextButton(
          key: const Key('quick-add-confirm'),
          onPressed: (_busy || _name.text.trim().isEmpty) ? null : _submit,
          child: Text(l10n.add),
        ),
      ],
    );
  }
}
