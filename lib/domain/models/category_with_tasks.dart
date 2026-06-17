import '../../data/services/database/database.dart';

/// A category together with all of its tasks (active and archived), in
/// sortOrder. Produced by the DAO's grouping of the categories ⋈ tasks join.
class CategoryWithTasks {
  CategoryWithTasks(this.category, this.tasks);
  final Category category;
  final List<Task> tasks;

  /// Active (not yet archived) tasks, in sortOrder.
  List<Task> get activeTasks => [
    for (final t in tasks)
      if (t.archivedAt == null) t,
  ];

  /// Archived tasks, newest-completed first.
  List<Task> get archivedTasks => [
    for (final t in tasks)
      if (t.archivedAt != null) t,
  ]..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));
}
