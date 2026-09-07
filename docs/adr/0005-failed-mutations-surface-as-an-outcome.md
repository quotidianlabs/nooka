# Failed mutations surface as an outcome

**Decision:** Every mutating intent on the home view model returns an outcome, success or
failure. The view model catches any throw, logs it, and returns failure; the raw error never
crosses the seam. The widget has one dispatch point that shows a single localized message on
failure. There is no error state on the view model and no retry or rollback.

A stateful error channel was the alternative: an error field on the view model that the widget
watches and renders. It was rejected as more machinery than the problem needs. An error here is
always the same thing to the user, a write that did not happen, and it is always handled the same
way, by telling them once. A state field would additionally need clearing, which introduces the
question of when an error stops being current and a way for a stale message to appear after an
unrelated action.

Rollback is unnecessary for a specific reason worth recording, because its absence looks like an
omission. The list renders from a reactive query over the database. A write that fails changes
nothing, so the stream re-emits the unchanged truth and the interface visibly returns to where it
was without anything being undone. Rollback would be re-implementing what the stream already does.

The rule that makes this correct is that follow-on effects are gated on success inside the
intent, never beside it. Adding a task remembers its category only if the write succeeded, so a
failure cannot leave a side effect behind pointing at something that was never created.

Startup takes the same posture: the one-off purge is wrapped so a database failure logs and still
reaches the app, and an escaped asynchronous error is logged rather than lost.

Logging is local only. There is no crash-reporting backend, and this is the single point where
one would attach.

**Revisit trigger:** a failure appears that the user could actually act on differently, so that
one message is no longer the right answer, or a reporting backend arrives and the failure path
needs to carry the error rather than swallow it.
