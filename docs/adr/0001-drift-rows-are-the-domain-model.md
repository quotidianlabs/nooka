# Drift rows are the domain model

**Decision:** Drift's generated row classes are used directly as domain models, and the UI
renders them directly. There is no mapper layer and no projection type between a row and a
widget. The layer rule that actually holds, and that `test/architecture_test.dart` enforces, is
narrower than the usual formulation:

- `lib/domain/` depends on no Flutter- or Drift-ecosystem package.
- Its only `lib/data/` dependency is the generated database library.
- Nothing under `lib/domain/` or `lib/data/` depends on `lib/ui/`.
- Nothing under `lib/ui/` names a DAO, and the shared widgets in `lib/ui/widgets/` read no
  providers.

The alternative is a mapper layer: hand-written entities plus conversions at every boundary.
That buys a `domain/` with no knowledge of the persistence library, at the cost of a second
definition of every field and a class of bug where the two definitions drift apart. For an app
whose domain logic is a handful of pure functions over dates and integers, the mapper would be
most of the domain layer by volume and would exist to satisfy a diagram.

Two consequences are worth stating plainly, because both look like mistakes.

**The dependency arrow between `domain/` and `data/` points both ways.**
`lib/domain/models/category_with_tasks.dart` depends on the generated database library for its
row types, while `lib/data/services/database/tables.dart` depends on `lib/domain/recurrence.dart`
for the enum a column is stored as. That is a genuine cycle between the two directories. It is
tolerated rather than broken because the alternative is either the mapper above or moving the
recurrence enum into the table definitions, which would put a domain concept in the schema file
purely to satisfy an import graph.

**Widgets hold rows.** A widget that renders a task names the row type, so `lib/ui/` depends on
the generated database library in several places. The sibling repo `habbits` made the opposite
call for the same trade-off: it wraps rows in a projection and keeps `ui/` clear of the
database, at the cost of pushing the dependency into `domain/` instead. Neither app is wrong and
neither is drifting; they moved the same unavoidable dependency to different places. The rules
above are written to what is true here, which is why the sibling has one invariant this repo
does not.

A repository or a service is a different matter and is not covered by that last rule: the
Settings screen reaches the cloud-backup service directly, because the alternative is threading
a connect-and-authorize flow through a view model that has nothing else to do with it. The line
drawn here is about queries, not about every `lib/data/` type.

**Revisit trigger:** a second dependency from `lib/data/` appears in `lib/domain/`, or a widget
needs a value no column holds and starts computing it inline. Either makes a projection type
earn its keep, and at that point aligning with the sibling's shape is the cheaper move.
