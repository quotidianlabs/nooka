# Error handling

Imperative mutations from the home screen run through
`_HomeScreenState._guard`: it awaits the action and, on any failure (if the
widget is still mounted), shows a localized `actionFailed` SnackBar and logs the
error. The reactive `watchCategoriesWithTasks` stream then re-renders the
unchanged truth, so a failed write visibly reverts on its own — no manual
rollback. `_guard` returns whether the action succeeded; a caller that persists
follow-on state (e.g. the remembered add-task category) gates that persistence
on success, so a failed mutation never leaves a stale side effect.

Startup is resilient: `main` wraps the one-off archive purge in `try/catch` (a
DB failure logs and still reaches `runApp`), installs `FlutterError.onError`,
and runs the app inside `runZonedGuarded`, so an escaped async error is logged
rather than lost. The categories/tasks stream's error state renders a localized
message (`errorLoading`), never the raw exception.

Logging is `debugPrint` (no remote crash sink); that is the hook point if a
reporting backend is ever added.
