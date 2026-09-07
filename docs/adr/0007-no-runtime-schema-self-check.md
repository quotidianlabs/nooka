# No runtime schema self-check

**Decision:** The app does not call Drift's `validateDatabaseSchema()` when opening the database.
Schema drift is caught in CI instead, by re-dumping the schema and regenerating the migration
helpers and failing if either differs from what is committed.

The runtime check compares the live database against the declared schema at startup, and it would
catch a migration bug on a real device where the CI gate only ever sees a freshly built one. It
was rejected on a dependency argument: `validateDatabaseSchema` is exported from `drift_dev`, the
code generator, not from the runtime package. Calling it from `lib/` puts the analyzer and build
stack into the application's runtime dependency graph, to answer once per launch a question CI
already answers before the code ships.

The two are not equivalent and the gap is worth naming rather than glossing. CI proves that the
committed schema artifacts match the declared tables and that each pinned version migrates to the
current schema with its data intact. What it cannot prove is that a migration behaves against a
real user's database, with whatever history that database has. The migration harness makes this a
much narrower gap here than it would otherwise be, since every version's migration is exercised
against its own pinned snapshot.

**Revisit trigger:** a schema mismatch actually reaches a device past CI, or Drift ships a
validation path that does not require the generator at runtime. The second is the cleaner
outcome and the one to watch for.
