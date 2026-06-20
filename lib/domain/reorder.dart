/// Returns a new list with the item at [oldIndex] moved to [newIndex].
///
/// [newIndex] is the destination index *after* the dragged item is removed —
/// the convention of `ReorderableListView`'s `onReorder` callback when the
/// caller pre-adjusts for downward moves. The index is clamped to the
/// post-removal range, so an over-the-end index (a drop past the last row)
/// appends rather than throwing a `RangeError`. Does not mutate [ids].
List<int> reorderedIds(List<int> ids, int oldIndex, int newIndex) {
  final list = [...ids];
  final item = list.removeAt(oldIndex);
  list.insert(newIndex.clamp(0, list.length), item);
  return list;
}

/// Returns [ids] with [item] inserted at [index], clamped to `0..ids.length`.
/// Does not mutate [ids].
List<int> insertedAt(List<int> ids, int item, int index) {
  final list = [...ids];
  list.insert(index.clamp(0, list.length), item);
  return list;
}
