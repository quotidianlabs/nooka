import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/domain/recurrence.dart';

void main() {
  group('nextDueDate', () {
    test('days adds exact duration', () {
      expect(
        nextDueDate(DateTime(2026, 7, 4, 9), 3, RecurrenceUnit.days),
        DateTime(2026, 7, 7, 9),
      );
    });
    test('weeks adds 7 days per count', () {
      expect(
        nextDueDate(DateTime(2026, 7, 4, 9), 2, RecurrenceUnit.weeks),
        DateTime(2026, 7, 18, 9),
      );
    });
    test('months adds calendar months, preserving time of day', () {
      expect(
        nextDueDate(DateTime(2026, 1, 15, 8, 30), 1, RecurrenceUnit.months),
        DateTime(2026, 2, 15, 8, 30),
      );
    });
    test('months clamps to end of a shorter target month', () {
      expect(
        nextDueDate(DateTime(2026, 1, 31, 8), 1, RecurrenceUnit.months),
        DateTime(2026, 2, 28, 8),
      );
    });
    test('months clamps to Feb 29 in a leap year', () {
      expect(
        nextDueDate(DateTime(2028, 1, 31, 8), 1, RecurrenceUnit.months),
        DateTime(2028, 2, 29, 8),
      );
    });
  });

  group('daysUntilDue', () {
    final now = DateTime(2026, 7, 4, 12);
    test('rounds a partial day up', () {
      expect(daysUntilDue(now.add(const Duration(days: 2, hours: 1)), now), 3);
    });
    test('exactly now is 0', () {
      expect(daysUntilDue(now, now), 0);
    });
    test('never negative', () {
      expect(daysUntilDue(now.subtract(const Duration(days: 5)), now), 0);
    });
  });
}
