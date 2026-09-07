# The repository is the data test-seam

**Decision:** `TodoRepository` is retained as the data-layer port rather than deleted as a thin
delegation, and it is given real depth by owning an injected `Clock` as the source of
lifecycle instants. `createdAt` is deliberately left outside that: the DAO stamps it directly.

An architecture review flagged the repository as a one-to-one pass-through to a deep DAO, and
flagged the current instant being minted independently on both sides of the seam. The options
were to delete the repository and let the view model depend on the DAO, to keep it as-is and
document it, or to keep it and give it something to do.

Deleting it loses no behaviour, since the DAO stays deep, but it loses a seam that four test
doubles subclass in order to inject failures the view model must handle. Two adapters make a
seam real; there are four. Without it, testing the error paths means subclassing a generated
Drift accessor, and there is no way to make a real in-memory database throw on one specific
method, so the failure-handling paths would lose clean coverage. The port earns its keep on
substitutability rather than on behaviour.

Giving it the `Clock` resolves the determinism problem at the same time and gives the production
adapter genuine implementation: archive and recurrence instants now come from one injected
source and are controllable in a test through the repository's own interface.

`package:clock` was rejected for this. Its ambient, zone-scoped clock is at odds with a codebase
that injects its collaborators explicitly, and mixing the two styles makes it unclear which
mechanism a given test is relying on.

`createdAt` stays with the DAO because it is never sorted by and never displayed. Routing it
through the `Clock` would churn roughly eighty seed call sites across the test suite for a value
nothing asserts, and would still leave a fallback instant inside the DAO.

**Revisit trigger:** reconsider deleting the repository if the error-injection doubles disappear,
or if it ends up carrying nothing beyond delegation and the clock. Route `createdAt` through the
`Clock` if it ever becomes load-bearing, meaning sorted by or shown to the user.
