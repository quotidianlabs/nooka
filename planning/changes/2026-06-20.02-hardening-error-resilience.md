---
summary: Bundle A of the hardening sweep — stop swallowing DB-write failures, keep startup alive when the purge throws, log lost async rejections, and localize the stream-error screen.
---

# Design: Error resilience — guarded mutations + survivable startup

## Summary

The first fix bundle of the whole-app hardening initiative
([audit](../../audits/2026-06-20-whole-app-hardening.md), parent spec
[hardening-audit-and-tests](../2026-06-20.01-hardening-audit-and-tests/design.md)).
It closes the error-handling cluster: imperative DB mutations in the home
screen are fire-and-forget — a throwing Drift write surfaces nothing to the
user and nothing to the logs (H1); the startup `purgeExpired()` sits on the
critical launch path with no guard, so a first-query failure aborts `runApp`
and shows a blank app (H2); the stream-error branch renders the raw exception
unlocalized (L6); and the startup purge's `Future<int>` result is discarded
(L9). This bundle introduces one shared `_guard` helper that every awaited
mutation routes through, two new ARB keys (`errorLoading`, `actionFailed`), a
guarded + logged startup, and a global async-error handler. Bundles B and C
reuse `_guard` for their own edited and new mutations.

## Motivation

Audit findings, in severity order:

- **H1 (high) — DB write failures silently swallowed.** Mutations in
  `home_screen.dart` are fired without `await` or `catch`
  (`home_screen.dart:99,145,164,262,299,306`). A throwing Drift write (locked
  DB, constraint, closed connection) becomes an unhandled async error: no user
  feedback, no rollback signal. The `state.when(error:)` branch at
  `home_screen.dart:114` only catches the *watch stream's* build error, never
  these imperative writes.
- **H2 (high) — Startup `purgeExpired()` aborts launch.** `main.dart:20` awaits
  the purge before `runApp` with no `try/catch`. A first-query failure (corrupt
  file, failed `beforeOpen` PRAGMA, migration error) unwinds `main`, `runApp`
  is never reached, and the user gets a blank app with no UI and no error
  surface. Cleanup must never block boot.
- **L6 (low) — Unlocalized stream error.** `home_screen.dart:114`
  `error: (e, _) => Center(child: Text('$e'))` shows the raw exception
  regardless of locale.
- **L9 (low) — Startup purge count discarded.** `main.dart:20` ignores the
  `Future<int>` the purge returns, so there's no signal that cleanup ran.

## Non-goals

- No view-model-level error state / side-channel. The simplest correct surface
  is a `_guard`-wrapped `SnackBar` at the call site; a stateful error channel
  is more machinery than these fixes need.
- No retry / rollback logic — `_guard` reports the failure and lets the watch
  stream re-render the unchanged truth; it does not attempt to re-drive the
  mutation.
- `_onItemReorder` (the drag callback) is deliberately **not** touched here —
  Bundle B owns that method (H3/H4) and will route its awaited mutation through
  this bundle's `_guard`.
- No crash-reporting backend; the global handler logs via `debugPrint`, not a
  remote sink.

## Design

### 1. Startup resilience — H2 / L9

`main.dart` wraps the purge in `try/catch`, captures and logs the returned
count, and always proceeds to `runApp`. The purge stays before `runApp` (it is
cheap and the result is already awaited today) but can no longer abort boot.

```dart
try {
  final purged = await container.read(todoRepositoryProvider).purgeExpired();
  debugPrint('Startup purge removed $purged expired item(s).');
} catch (e, st) {
  debugPrint('Startup purge failed (continuing): $e\n$st');
}
```

`debugPrint` requires `import 'package:flutter/foundation.dart';` (or it is
already transitively available via `material.dart`, which `main.dart` imports —
the plan verifies and adds the import only if `flutter analyze` complains).

### 2. Global async-error handler — H1 (cross-cutting half)

So that any rejection that escapes a `_guard` (or any future un-guarded path)
is logged rather than lost, `main` installs `FlutterError.onError` and wraps
`runApp` in `runZonedGuarded`:

```dart
FlutterError.onError = (details) {
  FlutterError.presentError(details);
  debugPrint('FlutterError: ${details.exceptionAsString()}');
};

runZonedGuarded(
  () => runApp(
    UncontrolledProviderScope(container: container, child: const NookaApp()),
  ),
  (error, stack) => debugPrint('Uncaught zone error: $error\n$stack'),
);
```

`WidgetsFlutterBinding.ensureInitialized()` stays at the top of `main`, outside
the zone, per Flutter's guidance (the binding must be initialized in the root
zone).

### 3. Localized strings — shared interface

Two keys are added to **both** `app_en.arb` (template) and `app_ru.arb`. Neither
takes placeholders, so no plural forms.

| key | en | ru |
|-----|-----|-----|
| `errorLoading` | `Something went wrong` | `Что-то пошло не так` |
| `actionFailed` | `Couldn’t complete that. Try again.` | `Не удалось выполнить действие. Попробуйте ещё раз.` |

`flutter gen-l10n` (run on build) regenerates
`lib/l10n/app_localizations*.dart`; the generated files are committed.

### 4. Localized stream-error widget — L6

`home_screen.dart:114` changes from the raw `Text('$e')` to the localized key:

```dart
error: (e, _) => Center(child: Text(AppLocalizations.of(context).errorLoading)),
```

### 5. The `_guard` helper + guarded call sites — H1 (UI half)

A private helper on `_HomeScreenState` is **the shared interface this bundle
defines**; Bundles B and C route their own edited/new awaited mutations through
it verbatim:

```dart
Future<void> _guard(Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).actionFailed)),
    );
  }
}
```

It awaits the action, and on any throw — if still mounted — shows an
`actionFailed` `SnackBar`. The watch stream re-renders the unchanged data, so a
failed mutation visually reverts on its own.

This bundle converts the **existing non-drag fire-and-forget** mutation call
sites in `home_screen.dart` to route through `_guard`:

- the `purgeExpired` on switching to the Archive tab (`:99`);
- `toggleCollapsed` in the archive `CategorySection` (`:145`);
- `reorderCategories` in `onListReorder` (`:164`);
- `restoreTask` / `completeTask` invoked from the undo toast actions
  (`:299`, `:306`) — wrapped where the `onUndo` callback is built;
- (the `toggleCollapsed` inside `_onExpandToggle` at `:262` is on the active
  board path and is likewise wrapped).

`_onItemReorder` (`:249`, `:252`) is **excluded** — Bundle B owns it.

The already-`await`ed command bodies (`_complete`, `_restore`, `_addTask`,
`_clearArchive`, `_addCategory`, `_categoryMenu`, `_taskMenu`) keep their
structure; this bundle wraps the bare imperative calls and the toast-action
callbacks. Bundles B and C extend `_guard` coverage to the mutations they edit.

## Testing

- **Unit / data:** unchanged — no DAO or domain code moves.
- **Widget (new):** a `TodoRepository` subclass whose mutation throws is
  injected via `todoRepositoryProvider.overrideWithValue(...)`; the test drives
  a guarded action (e.g. switching to Archive → guarded `purgeExpired`, or
  tapping a collapse toggle) and asserts the `actionFailed` SnackBar text
  appears and the app does not crash. A second widget test forces the watch
  stream into an error state (a repo whose `watchCategoriesWithTasks` returns a
  `Stream.error`) and asserts `errorLoading` renders instead of a raw
  exception.
- **Startup (covered by reasoning + smoke):** the `main.dart` guard is verified
  by a focused smoke check (`flutter run` once) plus `flutter analyze`; the
  `try/catch` is straight-line and low-risk, so no harness test is added for
  the boot path.
- `just test` green and `just lint` clean gate every task.

## Risk

- **Over-guarding hides a real bug** (low × low) — `_guard` swallows the
  exception type after showing the SnackBar; the global handler's `debugPrint`
  preserves the stack in logs, so nothing is lost silently.
- **`debugPrint` import missing** (low × low) — caught immediately by
  `flutter analyze`; the plan adds `package:flutter/foundation.dart` if needed.
- **`runZonedGuarded` + binding ordering** (low × med) — initializing the
  binding inside the zone is a known Flutter footgun; the design keeps
  `ensureInitialized()` in the root zone, before the guarded `runApp`.
- **Widget-test repo override drift** (low × low) — overriding
  `todoRepositoryProvider` with a throwing subclass is coupled to the concrete
  `TodoRepository` surface; if a method signature changes, the fake fails to
  compile loudly rather than silently passing.
