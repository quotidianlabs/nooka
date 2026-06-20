/// Days an archived item is retained before automatic deletion.
const int archiveRetentionDays = 30;

/// Items archived at or before this instant are eligible for deletion.
DateTime archiveCutoff(DateTime now) =>
    now.subtract(const Duration(days: archiveRetentionDays));

/// Whether an item archived at [archivedAt] should be purged as of [now].
bool isExpired(DateTime archivedAt, DateTime now) =>
    !archivedAt.isAfter(archiveCutoff(now));

/// Whole days until an item archived at [archivedAt] is auto-removed, as of
/// [now]. Rounds a partial day up, so a not-yet-expired item always reports
/// at least 1; only an expired item reports 0. Clamped to 0; never negative.
int daysRemaining(DateTime archivedAt, DateTime now) {
  final expiry = archivedAt.add(const Duration(days: archiveRetentionDays));
  final remaining =
      (expiry.difference(now).inMilliseconds / Duration.millisecondsPerDay)
          .ceil();
  return remaining < 0 ? 0 : remaining;
}
