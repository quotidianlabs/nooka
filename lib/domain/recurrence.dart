/// Unit of a completion-relative recurrence interval. Stored as its index
/// (intEnum) in the database and in backups.
enum RecurrenceUnit { days, weeks, months }

/// The instant a recurring task returns, given when it was completed and the
/// interval. Days/weeks are exact Durations; months add calendar months with
/// end-of-month clamping (complete Jan 31 + 1 month -> Feb 28 / 29 leap year),
/// preserving the time of day.
DateTime nextDueDate(DateTime completedAt, int count, RecurrenceUnit unit) {
  switch (unit) {
    case RecurrenceUnit.days:
      return completedAt.add(Duration(days: count));
    case RecurrenceUnit.weeks:
      return completedAt.add(Duration(days: 7 * count));
    case RecurrenceUnit.months:
      final targetMonthStart = DateTime(
        completedAt.year,
        completedAt.month + count,
      );
      final lastDay = DateTime(
        targetMonthStart.year,
        targetMonthStart.month + 1,
        0,
      ).day;
      final day = completedAt.day < lastDay ? completedAt.day : lastDay;
      return DateTime(
        targetMonthStart.year,
        targetMonthStart.month,
        day,
        completedAt.hour,
        completedAt.minute,
        completedAt.second,
        completedAt.millisecond,
        completedAt.microsecond,
      );
  }
}

/// Whole days until [nextDueAt] as of [now], for the "Returns in N days"
/// label. Rounds a partial day up and clamps to 0, matching
/// `archive.daysRemaining`.
int daysUntilDue(DateTime nextDueAt, DateTime now) {
  final remaining =
      (nextDueAt.difference(now).inMilliseconds / Duration.millisecondsPerDay)
          .ceil();
  return remaining < 0 ? 0 : remaining;
}
