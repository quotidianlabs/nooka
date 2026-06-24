import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/domain/clock.dart';

void main() {
  test('FixedClock.now returns its instant', () {
    final instant = DateTime(2026, 6, 24, 9, 30);
    expect(FixedClock(instant).now(), instant);
  });

  test('SystemClock.now returns roughly the current time', () {
    final before = DateTime.now();
    final now = const SystemClock().now();
    final after = DateTime.now();
    expect(now.isBefore(before), isFalse);
    expect(now.isAfter(after), isFalse);
  });
}
