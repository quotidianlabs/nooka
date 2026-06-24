import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/domain/default_category.dart';

void main() {
  test('returns the stored id when it still exists', () {
    expect(defaultCategoryId(2, [1, 2, 3]), 2);
  });
  test('falls back to the first id when stored is null', () {
    expect(defaultCategoryId(null, [1, 2, 3]), 1);
  });
  test('falls back to the first id when stored no longer exists', () {
    expect(defaultCategoryId(99, [1, 2, 3]), 1);
  });
  test('returns null when there are no categories', () {
    expect(defaultCategoryId(null, <int>[]), isNull);
  });
  test('returns null when stored is set but there are no categories', () {
    expect(defaultCategoryId(2, <int>[]), isNull);
  });
}
