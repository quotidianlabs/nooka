# A completed recurring task goes dormant

**Decision:** Completing a recurring task does not archive it and does not create a new row. The
same row goes dormant: it keeps its position, records the instant it should return, and comes
back to the active list in the slot it left. There is no per-occurrence history.

The obvious alternative is to treat each occurrence as its own item, archiving the completed one
and creating the next. That is what a task manager with a calendar does, and it buys a record of
every time the task was done. It was rejected because it multiplies rows without limit for a list
whose archive is deliberately shallow, and because it makes the task's identity ambiguous: edits,
recurrence changes and reordering would all have to decide whether they apply to this occurrence
or to the series.

The single-row model keeps identity simple. A recurring task is one thing that is sometimes
waiting, so editing it, moving it or turning off its repeat needs no notion of a series at all.
Keeping the slot open is what makes the return feel like the same task coming back rather than a
new one arriving at the bottom of the list.

Two consequences follow and are deliberate. Dormant tasks share the Archive view rather than
getting a surface of their own, listed ahead of archived ones with the time until they return,
because a separate "upcoming" screen is not worth a top-level destination for a dateless app.
And because a dormant task is not archived, retention never purges it and "clear archive" never
touches it: it leaves that view only by returning or by being deleted.

The corresponding undo also differs. Completing an archived task is undone by restoring it;
completing a recurring one is undone by waking it, since it was never archived.

**Revisit trigger:** a user needs to see how often a task was actually completed, or fixed
calendar recurrence arrives ("every Monday"). The first makes per-occurrence records real; the
second brings due dates, which is the larger change this model was chosen to avoid.
