# Backup and restore are replace-all

**Decision:** A backup is the whole database, and restoring one discards everything currently
stored rather than merging. This holds for the manual file export and import and for the Google
Drive backup alike. The data model carries no identifiers, timestamps or tombstones that a merge
would need.

Merge was rejected at both ends. Merging requires deciding what makes two rows "the same" across
devices, which needs stable identifiers the rows do not have; it needs per-row modification times
to decide which side wins; and it needs tombstones so a deletion on one device is not resurrected
by the other. Adding those turns a local-first list into a sync system, with the conflict
resolution and the migration that implies, in service of a feature nobody has asked for.

Replace-all is also honest about what this app is. Drive is a destination the user already owns,
in the same role as the file export: somewhere to put a copy. It is not a second source of truth,
and the app never reconciles two of them. That is why restoring shows a confirmation, and why the
backup format carries a version field, which stays the clean upgrade path if sync is ever built.

The cost is real and bounded: a user with the app on two devices cannot keep both current, and
restoring on either one overwrites whatever was there. Anyone in that position is served by
treating one device as primary.

Cloud backup is also manual only. Automatic backup on a lifecycle signal, throttled and opt-in,
was designed but not built, because an automatic upload of the whole database needs a story for
failure, for metered connections and for the user who did not realise it was on.

**Revisit trigger:** multi-device use becomes a real request rather than an anticipated one. The
first move then is the sync-ready data model, not a merge on top of the current one, because a
merge without stable identifiers cannot be made correct afterwards.
