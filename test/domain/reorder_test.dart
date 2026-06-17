import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/domain/reorder.dart';

void main() {
  test('moves an item down (ReorderableListView index convention)', () {
    expect(reorderedIds([1, 2, 3], 0, 2), [2, 3, 1]);
  });
  test('moves an item up', () {
    expect(reorderedIds([1, 2, 3], 2, 0), [3, 1, 2]);
  });
  test('does not mutate the input', () {
    final input = [1, 2, 3];
    reorderedIds(input, 0, 2);
    expect(input, [1, 2, 3]);
  });
}
