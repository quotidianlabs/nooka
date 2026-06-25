/// A single task inside a backup. Row ids are never serialized; the parent
/// link is implicit in [BackupCategory.tasks].
class BackupTask {
  const BackupTask({
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.archivedAt,
  });
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime? archivedAt; // null = active
}

/// A category and its tasks inside a backup.
class BackupCategory {
  const BackupCategory({
    required this.name,
    required this.color,
    required this.emoji,
    required this.collapsed,
    required this.sortOrder,
    required this.createdAt,
    required this.tasks,
  });
  final String name;
  final int color;
  final String? emoji;
  final bool collapsed;
  final int sortOrder;
  final DateTime createdAt;
  final List<BackupTask> tasks;
}

/// A whole-database backup: format [version], when it was [exportedAt], and the
/// ordered [categories].
class BackupData {
  const BackupData({
    required this.version,
    required this.exportedAt,
    required this.categories,
  });
  final int version;
  final DateTime exportedAt;
  final List<BackupCategory> categories;
}

/// Thrown by `decodeBackup` when a file is not a valid v1 Nooka backup. The
/// [message] is English, for logs and tests; the UI shows a localized message.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}
