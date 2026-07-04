import 'dart:convert';

import 'models/backup_data.dart';
import 'models/category_with_tasks.dart';
import 'recurrence.dart';

const String _appMarker = 'nooka';
const int _currentVersion = 2;

/// Serializes [data] to pretty-printed JSON.
String encodeBackup(BackupData data) {
  final map = <String, Object?>{
    'app': _appMarker,
    'version': data.version,
    'exportedAt': data.exportedAt.toIso8601String(),
    'categories': [
      for (final c in data.categories)
        {
          'name': c.name,
          'color': c.color,
          'emoji': c.emoji,
          'collapsed': c.collapsed,
          'sortOrder': c.sortOrder,
          'createdAt': c.createdAt.toIso8601String(),
          'tasks': [
            for (final t in c.tasks)
              {
                'name': t.name,
                'sortOrder': t.sortOrder,
                'createdAt': t.createdAt.toIso8601String(),
                'archivedAt': t.archivedAt?.toIso8601String(),
                'recurrenceCount': t.recurrenceCount,
                'recurrenceUnit': t.recurrenceUnit?.index,
                'nextDueAt': t.nextDueAt?.toIso8601String(),
              },
          ],
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

/// Parses and strictly validates a Nooka backup (versions 1 and 2). Throws
/// [BackupFormatException] on the first violation, before returning anything.
BackupData decodeBackup(String source) {
  final Object? root;
  try {
    root = jsonDecode(source);
  } catch (_) {
    throw const BackupFormatException('Not valid JSON.');
  }
  if (root is! Map<String, dynamic>) {
    throw const BackupFormatException('Root is not an object.');
  }
  if (root['app'] != _appMarker) {
    throw const BackupFormatException('Not a Nooka backup.');
  }
  final version = root['version'];
  if (version is! int || version < 1 || version > _currentVersion) {
    throw BackupFormatException('Unsupported version: ${root['version']}.');
  }
  final exportedAt = _date(root['exportedAt'], 'exportedAt');
  final categoriesRaw = root['categories'];
  if (categoriesRaw is! List) {
    throw const BackupFormatException('Missing categories list.');
  }
  return BackupData(
    version: version,
    exportedAt: exportedAt,
    categories: [for (final c in categoriesRaw) _category(c)],
  );
}

BackupCategory _category(Object? item) {
  if (item is! Map<String, dynamic>) {
    throw const BackupFormatException('Invalid category entry.');
  }
  final name = item['name'];
  if (name is! String || name.isEmpty) {
    throw const BackupFormatException('A category is missing its name.');
  }
  final color = item['color'];
  if (color is! int) {
    throw BackupFormatException('Category "$name" has an invalid color.');
  }
  final emoji = item['emoji'];
  if (emoji != null && emoji is! String) {
    throw BackupFormatException('Category "$name" has an invalid emoji.');
  }
  final collapsed = item['collapsed'];
  if (collapsed is! bool) {
    throw BackupFormatException('Category "$name" has an invalid collapsed.');
  }
  final sortOrder = item['sortOrder'];
  if (sortOrder is! int) {
    throw BackupFormatException('Category "$name" has an invalid sortOrder.');
  }
  final tasksRaw = item['tasks'];
  if (tasksRaw is! List) {
    throw BackupFormatException('Category "$name" has an invalid tasks list.');
  }
  return BackupCategory(
    name: name,
    color: color,
    emoji: emoji as String?,
    collapsed: collapsed,
    sortOrder: sortOrder,
    createdAt: _date(item['createdAt'], 'category "$name" createdAt'),
    tasks: [for (final t in tasksRaw) _task(t, name)],
  );
}

BackupTask _task(Object? item, String categoryName) {
  if (item is! Map<String, dynamic>) {
    throw BackupFormatException(
      'Category "$categoryName" has an invalid task.',
    );
  }
  final name = item['name'];
  if (name is! String || name.isEmpty) {
    throw BackupFormatException(
      'A task in "$categoryName" is missing its name.',
    );
  }
  final sortOrder = item['sortOrder'];
  if (sortOrder is! int) {
    throw BackupFormatException('Task "$name" has an invalid sortOrder.');
  }
  final archivedRaw = item['archivedAt'];
  final archivedAt = archivedRaw == null
      ? null
      : _date(archivedRaw, 'task "$name" archivedAt');
  final recurrenceCount = item['recurrenceCount'];
  if (recurrenceCount != null && recurrenceCount is! int) {
    throw BackupFormatException('Task "$name" has an invalid recurrenceCount.');
  }
  final unitIndex = item['recurrenceUnit'];
  if (unitIndex != null &&
      (unitIndex is! int ||
          unitIndex < 0 ||
          unitIndex >= RecurrenceUnit.values.length)) {
    throw BackupFormatException('Task "$name" has an invalid recurrenceUnit.');
  }
  final nextDueRaw = item['nextDueAt'];
  final nextDueAt = nextDueRaw == null
      ? null
      : _date(nextDueRaw, 'task "$name" nextDueAt');
  return BackupTask(
    name: name,
    sortOrder: sortOrder,
    createdAt: _date(item['createdAt'], 'task "$name" createdAt'),
    archivedAt: archivedAt,
    recurrenceCount: recurrenceCount as int?,
    recurrenceUnit: unitIndex == null
        ? null
        : RecurrenceUnit.values[unitIndex as int],
    nextDueAt: nextDueAt,
  );
}

DateTime _date(Object? value, String field) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) {
    throw BackupFormatException('Invalid $field.');
  }
  return parsed;
}

/// Builds a [BackupData] snapshot from DB rows; [now] stamps `exportedAt`.
/// Tasks are emitted in `sortOrder` for stable diffs.
BackupData buildBackup(List<CategoryWithTasks> rows, DateTime now) {
  return BackupData(
    version: _currentVersion,
    exportedAt: now,
    categories: [
      for (final r in rows)
        BackupCategory(
          name: r.category.name,
          color: r.category.color,
          emoji: r.category.emoji,
          collapsed: r.category.collapsed,
          sortOrder: r.category.sortOrder,
          createdAt: r.category.createdAt,
          tasks: [
            for (final t in [
              ...r.tasks,
            ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
              BackupTask(
                name: t.name,
                sortOrder: t.sortOrder,
                createdAt: t.createdAt,
                archivedAt: t.archivedAt,
                recurrenceCount: t.recurrenceCount,
                recurrenceUnit: t.recurrenceUnit,
                nextDueAt: t.nextDueAt,
              ),
          ],
        ),
    ],
  );
}
