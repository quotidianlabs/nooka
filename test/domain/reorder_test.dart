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
  test('clamps an over-the-end index to the tail instead of throwing', () {
    // newIndex == original length: after removeAt the list is one shorter, so
    // an unclamped insert would RangeError. Clamp makes it a move-to-end.
    expect(reorderedIds([1, 2, 3], 0, 3), [2, 3, 1]);
  });

  group('insertedAt', () {
    test('inserts at the head', () {
      expect(insertedAt([2, 3], 1, 0), [1, 2, 3]);
    });
    test('inserts in the middle', () {
      expect(insertedAt([1, 3], 2, 1), [1, 2, 3]);
    });
    test('inserts at the tail', () {
      expect(insertedAt([1, 2], 3, 2), [1, 2, 3]);
    });
    test('clamps an out-of-range index to the tail', () {
      expect(insertedAt([1, 2], 3, 99), [1, 2, 3]);
    });
    test('clamps a negative index to the head', () {
      expect(insertedAt([2, 3], 1, -5), [1, 2, 3]);
    });
    test('does not mutate the input', () {
      final input = [1, 2];
      insertedAt(input, 3, 1);
      expect(input, [1, 2]);
    });
  });
}
