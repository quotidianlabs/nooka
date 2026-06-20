# Audit: Whole-app hardening sweep — 2026-06-20

Spec: [hardening-audit-and-tests](../changes/2026-06-20.01-hardening-audit-and-tests/design.md).
Method: six parallel read-only agents, one per area (data, domain, UI/view-model,
controllers, i18n, cross-cutting), synthesized and deduped here. Severities are the
auditors'; the **Disposition** column is the recommended triage for review.

## Summary

19 findings: **5 high, 5 medium, 9 low**. They cluster in three places —
error handling (swallowed DB-write failures), the drag board (collapsed-drop and
stale-snapshot hazards), and the archive countdown (`daysRemaining` truncation,
independently flagged by three agents). **i18n is clean** (42 keys at parity,
Russian CLDR plurals correct), and transactions / cascade-delete / settings
round-trips were verified correct.

| # | Sev | Title | Disposition |
|---|-----|-------|-------------|
| H1 | high | DB write failures silently swallowed (fire-and-forget mutations) | Fix bundle A |
| H2 | high | Startup `purgeExpired()` failure aborts app launch | Fix bundle A |
| H3 | high | Dragging a task into a collapsed category hides it, no feedback | Fix bundle B |
| H4 | high | `_onItemReorder` trusts stale `cats` snapshot → RangeError / wrong task | Fix bundle B |
| H5 | high | Rapid double-tap on Add/Save creates duplicate task/category | Fix bundle B |
| M1 | med | `daysRemaining` truncation: shows "0 days" while task still survives | Fix bundle C |
| M2 | med | Stale `last_category` pref not cleared on category delete | Fix bundle C |
| M3 | med | Whitespace-only/overlong names: Save silently no-ops; no length cap | Fix bundle B |
| M4 | med | `last_category` persisted before `addTask` resolves | Fix bundle C |
| L1 | low | Reorder/move sortOrder has no DB tiebreaker → nondeterministic order | Fix bundle C |
| L2 | low | `reorderedIds` unguarded against out-of-range/empty | Defer (contract-safe) |
| L3 | low | `archivedAt!` unwraps rely on caller discipline, not types | Fix bundle B |
| L4 | low | Category edit = 3 un-batched writes (no transaction, 3 rebuilds) | Fix bundle C |
| L5 | low | Quick-add `_submit` calls `requestFocus` after await, no `mounted` | Fix bundle B |
| L6 | low | Stream-error state renders raw `'$e'` unlocalized | Fix bundle A |
| L7 | low | Retention is elapsed-24h, not calendar days (DST drift) | Defer (document) |
| L8 | low | `now` captured once per build → stale countdown across midnight | Defer |
| L9 | low | Startup `purgeExpired` return count discarded | Fix bundle A (trivial) |

Test-coverage gaps (from the spec's test pass) are listed in §Test gaps.

---

## High

### H1 — DB write failures silently swallowed
- **Location:** `lib/ui/home/home_view_model.dart:19-51`; call sites `home_screen.dart:99,145,164,249,252,262,299,306`
- **Issue:** Every mutation returns a `Future`, but the UI fires most without `await`
  and with no error handler. A throwing Drift/SQLite write (locked DB, constraint,
  closed connection) becomes an unhandled async error with no user feedback and no
  rollback. The `state.when(error:)` branch at `home_screen.dart:114` only catches
  the *watch stream's* build error, never imperative writes.
- **Repro:** Drag-reorder while the DB is transiently locked → `reorderTasks`
  transaction throws → call at `home_screen.dart:249` has no `await`/`catch` → drag
  visually snaps back with zero explanation; error only in console.
- **Fix:** Have view-model commands catch and expose failures (error SnackBar via a
  side-channel state), `await` the fire-and-forget calls inside `try/catch`, and add
  a global zone / `FlutterError.onError` handler so rejections aren't lost.

### H2 — Startup `purgeExpired()` failure aborts app launch
- **Location:** `lib/main.dart:20` (verified: awaited before `runApp`, no `try/catch`)
- **Issue:** A best-effort housekeeping call sits on the critical launch path. If the
  first DB query throws (corrupt file, failed `beforeOpen` PRAGMA, migration error),
  the exception unwinds `main`, `runApp` is never reached, and the user gets a blank
  app with no UI and no error surface.
- **Fix:** Wrap the purge in `try/catch` (log and continue), or move it after
  `runApp` as fire-and-forget with error logging. Cleanup must never block boot.

### H3 — Dragging a task into a collapsed category hides it, no feedback
- **Location:** `home_screen.dart:203-205, 251-256`; `todo_dao.dart:152-166` (verified
  collapsed renders `children: const []` with a `contentsWhenEmpty` drop slot)
- **Issue:** A collapsed category shows no items but still exposes a drop target.
  `_onItemReorder` computes `insertedAt(to.activeTasks, movedId, newItemIndex)`
  against the **full DB list** while the rendered list is empty, so `newItemIndex`
  is 0 → the task is inserted at the front (jumping ahead of existing hidden tasks)
  and then vanishes because the category is collapsed. No toast, no confirmation.
- **Repro:** Category B (3 tasks) is collapsed. Drag task T from A onto B's header.
  T leaves A, lands at top of B, and disappears from view — user can't tell where.
- **Fix:** Auto-expand the destination after a cross-category drop
  (`toggleCollapsed(to.category.id, false)`), or disallow dropping into a collapsed
  list. Auto-expand is simplest and correct.

### H4 — `_onItemReorder` trusts a stale `cats` snapshot
- **Location:** `home_screen.dart:237-258` (verified: indexes `cats[...]` and
  `from.activeTasks[oldItemIndex]` from the build-time list)
- **Issue:** `cats` is captured at build. If the watch stream emits during a drag
  (concurrent mutation, purge, restore), the drop callback still indexes the stale
  list. `from.activeTasks[oldItemIndex]` / `to.activeTasks` can be out of range
  (RangeError) or reference the wrong task, corrupting sortOrder or moving the wrong
  task. Likelihood is low (requires an emission mid-drag) but the failure is a crash.
- **Fix:** Re-read current state via `ref.read(homeViewModelProvider).value` inside
  `_onItemReorder`, bounds-check indices, and no-op if stale.

### H5 — Rapid double-tap creates duplicate task/category
- **Location:** `task_dialog.dart:150-156`; `category_dialog.dart:121-133`;
  `home_screen.dart:336-345`
- **Issue:** Quick-add `_submit` is `async`, awaits `onAdd`, then clears the field
  *after* the await. The Add button is never disabled in-flight, so two fast taps
  both read the same non-empty text and both call `onAdd` → two identical tasks.
- **Repro:** Type "Milk", double-tap Add quickly → two "Milk" tasks.
- **Fix:** Add an in-flight `_busy` guard, clear the field synchronously *before*
  awaiting `onAdd`, and disable the button while busy.

## Medium

### M1 — `daysRemaining` truncation (flagged by 3 agents)
- **Location:** `lib/domain/archive.dart:14-18`; consumed `task_row_content.dart:51`
- **Issue:** `expiry.difference(now).inDays` truncates toward zero, but `purgeExpired`
  only deletes at `archivedAt <= now-30d`. So for the final ~24h of retention the UI
  shows "auto-removes in 0 days" while the task is *not yet* purgeable — the countdown
  contradicts the engine.
- **Repro:** `archivedAt = now - 29d12h` → not expired (12h of life left) but
  `daysRemaining` returns 0 → label reads "0 days" for a surviving task.
- **Fix:** Ceil the partial day: `(expiry.difference(now).inMilliseconds /
  Duration.millisecondsPerDay).ceil()`, clamped `>= 0`. A not-expired item then always
  reports ≥ 1; only an expired item reports 0.

### M2 — Stale `last_category` pref not cleared on delete
- **Location:** `home_screen.dart:33,309-327,401`; `settings_repository.dart:30-32`
- **Issue:** Deleting a category leaves its id in `_lastCategoryId` and the
  `last_category` pref. `_addTask` guards the dropdown default
  (`ids.contains(_lastCategoryId)` → falls back to `cats.first`), so it's not
  user-visible today, but the stale id lingers and would mis-target if an id were
  ever reused.
- **Fix:** On delete, if `cwt.category.id == _lastCategoryId`, clear the field and
  add a `clearLastCategoryId()` to `SettingsRepository`. Confirm Categories uses
  AUTOINCREMENT (no rowid reuse) to bound the risk.

### M3 — Whitespace-only/overlong names silently no-op; no length cap
- **Location:** `task_dialog.dart:92-95,150-156`; `category_dialog.dart:123-131`
- **Issue:** Submit handlers `trim()` and `return` on empty — correct (no blank
  tasks) — but the Save button stays visually enabled, so tapping it with a
  whitespace-only name does nothing with no feedback (reads as a broken button).
  No max length: a very long name is accepted and overflows `TaskRowContent`'s title
  (no `maxLines`/`overflow`).
- **Fix:** Drive button `onPressed` from a controller listener (enable only when
  `text.trim().isNotEmpty`); add `LengthLimitingTextInputFormatter`; give the title
  `maxLines: 2, overflow: TextOverflow.ellipsis`.

### M4 — `last_category` persisted before `addTask` resolves
- **Location:** `home_screen.dart:319-325`
- **Issue:** `_lastCategoryId = categoryId` and `writeLastCategoryId(...)` run before
  `await _vm.addTask(...)`. If the add throws (and its error is swallowed per H1), the
  default is persisted to a category that never accepted the task.
- **Fix:** Write `lastCategoryId` only after `addTask` succeeds; wrap in `try/catch`.

## Low

- **L1 — No DB ordering tiebreaker.** `watchCategoriesWithTasks` orders by
  `categories.sortOrder` then `tasks.sortOrder` with no secondary key
  (`todo_dao.dart:202-205`). Any duplicate sortOrder (reachable via the stale-set
  reorder hazard) orders nondeterministically and the list "jumps." Fix: append
  `OrderingTerm(tasks.id)` / `categories.id` as a total-order tiebreaker.
- **L2 — `reorderedIds` unguarded** (`reorder.dart:6-11`): `removeAt`/`insert` throw
  `RangeError` on out-of-range/empty input. Currently contract-safe (only the
  framework calls it). Disposition: defer; add an `assert` documenting the precondition.
- **L3 — `archivedAt!` unwraps** (`task_row_content.dart:50-51`,
  `category_with_tasks.dart:20`): a separate `archived` bool, not the type, gates the
  force-unwrap. Safe today; a future caller passing `archived: true` for an active
  task NPEs. Fix: derive `archived` from `task.archivedAt != null` inside the row.
- **L4 — Category edit = 3 un-batched writes** (`home_screen.dart:383-387`): rename +
  color + emoji are three awaited calls (no transaction → partial-failure
  inconsistency, three rebuilds/flickers). Fix: one `updateCategory(...)` DAO method.
- **L5 — `_submit` requestFocus after await, no `mounted`** (`task_dialog.dart:150-156`):
  dismissing the dialog mid-await can `requestFocus` on a disposed node. Fix: add
  `if (!mounted) return;` after the await.
- **L6 — Unlocalized stream error** (`home_screen.dart:114`): `error: (e,_) =>
  Text('$e')` shows the raw exception regardless of locale. Fix: add `errorLoading`
  ARB key (en/ru) and render it. (i18n data itself is correct — string never enters it.)
- **L7 — Elapsed-24h vs calendar-day retention** (`archive.dart:5-18`): `Duration(days:30)`
  + `inDays` count elapsed time, not local calendar days; a DST transition nudges the
  boundary by an hour. Low impact for a 30-day window. Disposition: defer; document the
  intended semantics (resolving M1 with `ceil` also reduces the user-visible mismatch).
- **L8 — Stale `now` across midnight** (`home_screen.dart:58`): `now` captured once per
  build; the archive countdown doesn't refresh until the next rebuild. Cosmetic,
  self-corrects on interaction. Disposition: defer (optionally recompute on resume).
- **L9 — Startup purge count discarded** (`main.dart:20`): `Future<int>` result
  ignored; no signal on cleanup. Trivial — fold into H2's fix (log the count).

---

## Test gaps (feed the test pass)

From the data-layer agent, plus the spec's coverage targets:
- `restoreTask` re-append: asserts `archivedAt` cleared but **not** the restored
  `sortOrder` — re-append behavior is untested (`todo_dao_test.dart:97-113`).
- Purge boundary: test uses 40d/5d only — never **exactly 30 days** nor a 29d-23h case,
  so the M1 mismatch would not be caught (`todo_dao_test.dart:115-134`).
- `moveTaskToCategoryAt` source-gap asserted by relative order only, not sortOrder
  values — a renumber regression would pass silently.
- Zero coverage: drag-board widgets (`category_section`, `task_row_content`,
  `category_header_content`), `task_dialog`, `confirm_delete_dialog`,
  `locale_controller`, `theme_controller`.
- No end-to-end integration test for add → complete → archive → purge → restore.

## Checked & OK (verified clean)

- **i18n:** 42 keys at exact parity en↔ru; placeholders consistent; all four pluralized
  keys (`clearArchiveBody`, `deleteCategoryBody`, `autoRemovesIn`, `openItemsCount`)
  carry correct Russian CLDR one/few/many/other; dates via `DateFormat.yMMMd(locale)`.
- **Cascade delete:** `Tasks.categoryId onDelete: cascade` (`database.dart:21`) +
  `PRAGMA foreign_keys = ON` (`database.dart:45`); active and archived tasks both cascade.
- **Transactions:** `reorderCategories` / `reorderTasks` / `moveTaskToCategoryAt`
  wrap multi-row renumbering in `transaction(...)` — no partial-write commits.
- **Settings round-trip:** locale/theme tokens write `value.storage` and read back via
  `firstWhere(... orElse: system)`; unknown/renamed tokens fall back to `system`
  gracefully; sensible defaults before first save.
- **DB lifecycle:** `appDatabaseProvider` is keepAlive with `ref.onDispose(db.close)`.
- **`restoreTask` append:** excluded from `_nextTaskOrder`'s active query while still
  archived, so it gets `max(active)+1` — no collision.
- **DateTime storage:** default Drift unix-epoch storage; `archivedAt` written/compared
  as the same absolute instant everywhere — no local-vs-UTC mismatch (only the `inDays`
  truncation of M1/L7).

## Recommended next steps

1. **Triage** these with the user — confirm severities and the bundle grouping below.
2. Spawn fix bundles (sized at triage):
   - **Bundle A — error resilience:** H1, H2, L6, L9. Touches `main.dart`,
     `home_view_model.dart`, `home_screen.dart`, new ARB key. Likely Full lane.
   - **Bundle B — drag board & dialogs:** H3, H4, H5, M3, L3, L5. Full lane.
   - **Bundle C — archive countdown & ordering polish:** M1, M2, M4, L1, L4. Mixed;
     M1 + L1 are small and high-value.
   - **Defer:** L2, L7, L8 (documented in `planning/deferred.md` if kept).
3. The **test pass** lands regression guards for every confirmed fix plus the
   coverage gaps in §Test gaps.
