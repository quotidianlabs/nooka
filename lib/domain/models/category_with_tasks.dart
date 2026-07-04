import '../../data/services/database/database.dart';

/// A category together with all of its tasks (active and archived), in
/// sortOrder. Produced by the DAO's grouping of the categories ⋈ tasks join.
class CategoryWithTasks {
  CategoryWithTasks(this.category, this.tasks);
  final Category category;
  final List<Task> tasks;

  /// Active tasks: not archived and not dormant, in sortOrder.
  List<Task> get activeTasks => [
    for (final t in tasks)
      if (t.archivedAt == null && t.nextDueAt == null) t,
  ];

  /// Dormant recurring tasks (completed, waiting to return), soonest first.
  List<Task> get dormantTasks => [
    for (final t in tasks)
      if (t.archivedAt == null && t.nextDueAt != null) t,
  ]..sort((a, b) => a.nextDueAt!.compareTo(b.nextDueAt!));

  /// Archived tasks, newest-completed first.
  List<Task> get archivedTasks => [
    for (final t in tasks)
      if (t.archivedAt != null) t,
  ]..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));
}

extension CategoryIds on List<CategoryWithTasks> {
  /// The category ids in their current order.
  List<int> get categoryIds => [for (final c in this) c.category.id];
}
