# Retention counts elapsed 24-hour periods

**Decision:** An archived task is kept for thirty elapsed 24-hour periods measured from the
instant it was completed, not for thirty local calendar days. The countdown shown to the user
rounds any partial day up.

Calendar-day retention is the alternative, and it is what a user would describe if asked. It was
rejected because it means normalising two instants to local dates before comparing them, which
drags the local time zone into the purge decision and therefore makes the purge dependent on
where the device currently is. Elapsed time is a subtraction, is independent of zone, and is
correct without any date handling at all.

The visible consequence is that a daylight-saving transition shifts the boundary by about an
hour. Against a thirty-day window that is not something a user can perceive, which is the whole
reason the simpler rule is acceptable here. It would not be acceptable for a short window, and it
is not the rule used anywhere a calendar day is the actual unit.

Rounding the countdown up is a separate, deliberate choice that keeps the label honest under this
scheme: a task with any time left reads at least one day, so zero means expired rather than
"expiring at some point today". The label is recomputed when the app returns to the foreground so
it cannot go stale across a midnight the user slept through.

**Revisit trigger:** the retention window shrinks to where an hour matters, or retention becomes
user-configurable and someone sets it to a small number of days. Either makes the calendar-day
rule worth its complexity.
