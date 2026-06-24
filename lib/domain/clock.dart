/// A source of the current time. The seam that lets the data layer stamp
/// archive-lifecycle time deterministically: production uses [SystemClock],
/// tests inject a [FixedClock].
abstract class Clock {
  const Clock();

  /// The current instant.
  DateTime now();
}

/// The production clock — the real wall clock.
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// A clock frozen at a single instant, for deterministic tests.
class FixedClock extends Clock {
  const FixedClock(this._instant);
  final DateTime _instant;

  @override
  DateTime now() => _instant;
}
