/// The category id to preselect for quick-add: the [stored] id when it still
/// exists among [categoryIds], otherwise the first category, or null when there
/// are no categories. Pure — the remembered-category rule with no persistence.
int? defaultCategoryId(int? stored, List<int> categoryIds) {
  if (categoryIds.isEmpty) return null;
  if (stored != null && categoryIds.contains(stored)) return stored;
  return categoryIds.first;
}
