# Error handling

Imperative mutations run as `HomeViewModel` intents that return a
`CommandOutcome` (`success` | `failure`): the VM's `_run` helper catches any
throw, logs it (`debugPrint`), and returns `failure` — the raw error never
crosses the seam. `_HomeScreenState._dispatch` awaits the intent and, on
`failure` (if still mounted), shows the localized `actionFailed` SnackBar — the
single place outcomes map to UI. The reactive `watchCategoriesWithTasks` stream
then re-renders the unchanged truth, so a failed write visibly reverts on its
own — no manual rollback. Follow-on side effects are gated on `success` inside
the intent (e.g. `addTask` only remembers its category when the write
succeeded), so a failed mutation never leaves a stale side effect. See
[home coordination](home-coordination.md).

Startup is resilient: `main` wraps the one-off archive purge in `try/catch` (a
DB failure logs and still reaches `runApp`), installs `FlutterError.onError`,
and runs the app inside `runZonedGuarded`, so an escaped async error is logged
rather than lost. The categories/tasks stream's error state renders a localized
message (`errorLoading`), never the raw exception.

Logging is `debugPrint` (no remote crash sink); that is the hook point if a
reporting backend is ever added.
