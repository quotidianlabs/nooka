/// Days an archived item is retained before automatic deletion.
const int archiveRetentionDays = 30;

/// Items archived at or before this instant are eligible for deletion.
DateTime archiveCutoff(DateTime now) =>
    now.subtract(const Duration(days: archiveRetentionDays));

/// Whether an item archived at [archivedAt] should be purged as of [now].
bool isExpired(DateTime archivedAt, DateTime now) =>
    !archivedAt.isAfter(archiveCutoff(now));

/// Whole days until an item archived at [archivedAt] is auto-removed, as of
/// [now]. Clamped to 0; never negative.
int daysRemaining(DateTime archivedAt, DateTime now) {
  final expiry = archivedAt.add(const Duration(days: archiveRetentionDays));
  final remaining = expiry.difference(now).inDays;
  return remaining < 0 ? 0 : remaining;
}
