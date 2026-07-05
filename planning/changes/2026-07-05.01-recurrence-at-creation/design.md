---
summary: Recurrence is now settable at creation — the quick-add dialog embeds the shared RepeatField (full-width rows, 48px targets, reset per add; same control replaces the edit dialog's cramped repeat row) and createTask carries the pair through VM → repository → DAO. No schema change.
---

# Design: Recurrence at creation

## Summary

Today a recurring task can only be made in two steps: quick-add it, then open
Edit and switch Repeat on. This change adds the Repeat control to the quick-add
dialog so recurrence is set at creation, extracts it into a shared widget used
by both dialogs, and redesigns its layout with full-width rows and 48px touch
targets (the current single-row stepper + segmented button is cramped and hard
to tap). The create path (`addTask` → `createTask` → DAO insert) gains optional
recurrence parameters mirroring `renameAndMove`. No schema change.

## Motivation

- The quick-add dialog (`showQuickAddDialog`) is the only creation path and has
  no recurrence controls; only the edit dialog (`showTaskDialog`) does. Creating
  a recurring task requires create-then-edit — two dialogs and a bottom-sheet
  hop for what should be one step.
- The existing repeat row crams two 24px icon-button steppers, the count, and a
  three-segment unit selector into one `Row` inside the dialog. The targets are
  well under Material's 48px minimum and are hard to hit.
- `createTask` (VM, repository, DAO) does not accept recurrence at all; only
  `renameAndMove` does, so the data layer itself forces the two-step flow.

## Non-goals

- No change to recurrence semantics (completion-relative dormancy, wake, purge)
  — see `planning/changes/2026-07-04.01-recurring-tasks/`.
- No schema or backup-format change; the nullable `recurrence_count` /
  `recurrence_unit` columns already exist.
- No preset chips or bottom-sheet picker (layouts B/C explored during
  brainstorming and rejected in favor of stacked full-width rows).
- No merging of the quick-add and edit dialogs; their flows (multi-add loop vs
  single result) stay separate.

## Design

### 1. Shared `RepeatField` widget

New file `lib/ui/widgets/repeat_field.dart`. A controlled component — the
parent owns the state; the widget renders it and reports changes:

```dart
class RepeatField extends StatelessWidget {
  const RepeatField({
    required this.repeat,
    required this.count,
    required this.unit,
    required this.onChanged, // void Function(bool repeat, int count, RecurrenceUnit unit)
  });
}
```

Layout (replaces the current cramped single row):

- `SwitchListTile` "Repeat" — unchanged, key `task-repeat-toggle`.
- When on, a full-width row: large **−** and **+** buttons (48px minimum
  touch target each) flanking the centered count — key `task-repeat-stepper`.
- Below it, a full-width `SegmentedButton<RecurrenceUnit>` (days / weeks /
  months) on its own row, at least 48px tall — key `task-repeat-unit`.
- Below that, the existing summary line (`recurrenceSummary`).

The three keys move verbatim from `_TaskDialog`, so existing widget tests keep
targeting the same controls. `−` disables at count 1, as today. No new l10n
strings — `repeatLabel`, the unit labels, and `recurrenceSummary` are reused.

### 2. Quick-add dialog gains recurrence

`_QuickAddDialog` adds `_repeat` / `_count` / `_unit` state (off / 1 / days)
and embeds `RepeatField` below the category dropdown. `onAdd` grows to:

```dart
Future<void> Function(String name, int categoryId,
    int? recurrenceCount, RecurrenceUnit? recurrenceUnit)
```

passing `(_count, _unit)` when Repeat is on and `(null, null)` when off.

**Reset per add:** the repeat state resets to off / 1 / days at the same point
the name field clears (synchronously, before the awaited `onAdd`). Rationale:
recurring tasks are the exception; a sticky toggle would silently make a whole
quick-add batch recurring. This intentionally mirrors the name field's existing
clear-before-await behavior, including on a failed add.

Category selection keeps its existing persistence (remembered default);
recurrence is deliberately not remembered.

### 3. Edit dialog uses the shared widget

`_TaskDialog` replaces its inline repeat section (SwitchListTile + stepper row
+ summary) with `RepeatField`, keeping its `_repeat`/`_count`/`_unit` state and
result-building logic unchanged. Same behavior, larger targets. The
`isEdit = initialName.isNotEmpty` heuristic stays as-is: quick-add remains the
only creation path, so `showTaskDialog` is still edit-only in practice.

### 4. Create path carries recurrence

Mirroring `renameAndMove`'s optional pair end to end:

- `HomeViewModel.addTask(int categoryId, String name, {int? recurrenceCount,
  RecurrenceUnit? recurrenceUnit})` — still remembers the category on success;
  a failed add persists nothing.
- `TodoRepository.createTask(...)` — pass-through.
- `TodoDao.createTask(...)` — inserts the two columns via the companion,
  absent when null.

Invariant: count and unit are both null or both non-null. The dialog guarantees
this the same way the edit path does (`_repeat ? _count : null` for both); the
create path adds no second validation scheme beyond what the recurrence
capability already enforces.

A task created recurring behaves identically to one edited into recurrence: a
normal active task until completed, then dormant per the existing
completion-relative logic. Completion, wake, archive, and backup code are
untouched. The reactive watch already propagates the new task to the UI.

## Error handling

Nothing new. `addTask` failures flow through the existing `_dispatch` →
`CommandOutcome` → error-toast path. The repeat controls reset alongside the
name-field clear (section 2), keeping the two fields symmetric on both success
and failure.

## Testing

TDD — failing tests first, per repo practice.

- **Widget, quick-add:** Repeat toggle reveals stepper + unit rows; add with
  Repeat on passes count/unit through `onAdd`; add with Repeat off passes
  nulls; after a successful add the controls reset to off / 1 / days.
- **Widget, edit dialog:** existing repeat tests keep passing against the
  shared keys; seeding an already-recurring task opens `RepeatField` on.
- **DAO/repository:** `createTask` with recurrence persists both columns;
  without recurrence leaves both null.
- **View model:** `addTask` forwards recurrence to the repository.
- Touch-target sizing is exercised implicitly by widget tests tapping the
  buttons; no pixel-measurement tests.

Gates: `just lint-ci`, `just test`, `just coverage`,
`just check-planning`.

## Documentation

Hand-edit in the implementing PR: `architecture/data-model.md` (create path now
accepts recurrence) and `architecture/home-coordination.md` (quick-add carries
recurrence, reset-per-add rule). Regenerate `*.g.dart` only if `@riverpod` /
Drift code shifts.

## Risk

- **Quick-add flow regression** (medium likelihood, medium impact): the
  clear-and-refocus multi-add loop is behaviorally subtle (`_busy` guard,
  synchronous clear, refocus after await). Mitigation: the reset hooks into the
  exact same point as the existing name clear; widget tests cover the
  multi-add sequence.
- **Edit-dialog visual regression** (low, low): `RepeatField` changes layout
  inside a fixed-width `AlertDialog`; full-width rows may need
  `IntrinsicWidth`/sizing care on small screens. Mitigation: manual check on a
  narrow device profile during implementation.
- **Signature churn** (low, low): `onAdd` and `addTask` callers are few and
  all in-repo; the analyzer catches any missed site.
