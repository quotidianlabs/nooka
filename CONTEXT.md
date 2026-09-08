# Nooka

A local-first to-do list for iOS and Android, in English and Russian. Categories and tasks live
in a SQLite database on the device, with an optional manual backup to the user's own Google
Drive. There is no account, no server and no sync.

## Language

A term is listed only when there is a synonym to reject, or a meaning subtle enough that code
and docs must agree on it. General programming vocabulary does not belong here.

**Nooka**:
The product. The thing it tracks is a **task**.
_Avoid_: to-do item, for the thing itself. "To-do list" is fine for the product category, which
is what the app is and how it is described. The persistence types are named `TodoDao` and
`TodoRepository`, which predates this vocabulary and is not a reason to reintroduce the word.

**Task**:
One item of work, belonging to exactly one category. Its state is not stored: it is derived
from two nullable columns, so there is no status field to read or to keep consistent.

**Active**:
A task with neither an archived instant nor a next-due instant. It appears in the main list in
its own slot.

**Dormant**:
A recurring task that has been completed and is waiting to come back, carrying the instant it
returns. It is not archived and it keeps its slot in the active order, so it reappears exactly
where it was rather than at the end.

**Archived**:
A completed non-recurring task, carrying the instant it was completed. It leaves the active
list, is shown in the Archive, and is purged once retention expires.

**Complete**:
Finish a task. A non-recurring one becomes archived; a recurring one becomes dormant. Either
way the row survives.

**Delete**:
Remove a task outright. It is not completion and it never reaches the Archive, whatever the
task's state. The row is gone, and only the undo action can bring it back.

**Recurrence**:
A count and a unit, always written and cleared together, saying how long after completion a
task returns. It is a property of the task, not of a particular completion, and it is measured
from the moment of completion rather than from the previous due instant, so completing late
never accumulates a backlog.

**Category**:
A named, coloured, optionally emoji-marked group of tasks, and the unit of ordering and
collapse in the list. Deleting one takes its tasks with it.

**Sort order**:
A task's explicit integer position within its category. Positions are renumbered as a whole
when the user reorders or moves something; a delete or a completion instead leaves the number
unused, holding the slot open so an undo or a return lands where it was. A gap is therefore
normal and is not corruption.

**Retention**:
How long an archived task is kept before it is purged, counted in elapsed 24-hour periods from
the moment of completion rather than in calendar days. Dormant tasks are never subject to it.

**Backup**:
A single JSON document holding every category and task, written either to a file the user
keeps or to their own Google Drive. Restoring one is replace-all: it discards the current
contents entirely rather than merging.

**Clock**:
The injected source of the instants that decide a task's lifecycle, so archive and recurrence
behaviour is deterministic in a test. Times used only for display are not read from it.

**Command outcome**:
What every mutating intent returns instead of throwing: it succeeded, or it failed. A failure
is reported to the user once, in one place, and the underlying error never crosses out of the
view model.
