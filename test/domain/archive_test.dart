import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/domain/archive.dart';

void main() {
  final now = DateTime(2026, 6, 17, 12);

  group('isExpired', () {
    test('archived exactly 30 days ago is expired', () {
      expect(isExpired(now.subtract(const Duration(days: 30)), now), isTrue);
    });
    test('archived 29 days ago is not expired', () {
      expect(isExpired(now.subtract(const Duration(days: 29)), now), isFalse);
    });
    test('archived just now is not expired', () {
      expect(isExpired(now, now), isFalse);
    });
  });

  group('daysRemaining', () {
    test('just archived has full retention remaining', () {
      expect(daysRemaining(now, now), archiveRetentionDays);
    });
    test('archived 10 days ago has 20 remaining', () {
      expect(daysRemaining(now.subtract(const Duration(days: 10)), now), 20);
    });
    test('never returns negative', () {
      expect(daysRemaining(now.subtract(const Duration(days: 99)), now), 0);
    });
  });
}
