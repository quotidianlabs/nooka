/// Returns a new list with the item at [oldIndex] moved to [newIndex].
///
/// [newIndex] is the destination index *after* the dragged item is removed —
/// the convention of `ReorderableListView`'s `onReorder` callback when the
/// caller pre-adjusts for downward moves. Does not mutate [ids].
List<int> reorderedIds(List<int> ids, int oldIndex, int newIndex) {
  final list = [...ids];
  final item = list.removeAt(oldIndex);
  list.insert(newIndex, item);
  return list;
}
