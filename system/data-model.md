# Data model

**Status: DRAFT**

## Purpose

RAPID's data model defines the entities that the pipeline stores,
their relationships and the processes that write them. This page maps
the model and states the invariants shared across its layers.
The domain documents listed in the entity map provide the schemas,
state machines and key grammars. They may strengthen an invariant
stated here, but must not contradict it.

## Entity map

| Layer | Entities | Writers | Owning document |
|---|---|---|---|
| Identity | `l2files`, `refimages`, `diffimages`, `psfs`: one row per registered image product version, `vbest` as the promotion pointer, attempt-identity columns for idempotent registration (the registration outcome field; see catalog.md) | Registration, through stored functions only | Catalog (promotion, key schema); Database (integrity) |
| Auxiliary metadata | `diffimmeta`, `refimcatalogs` (mainline-written, alongside registration); `l2filemeta`, `exposures` (mainline-read; written by ingest and simulation registration); `filters`, `scas`, `pipelines`, `swversions` (static reference and FK targets, loaded by migration/seed) | Named per table above | Database (integrity) |
| Records | Attempt records, stage records, milestones, closure records: the append-only account of every unit of work | Each record class has exactly one author | Observability |
| Workflow | Work units, attempts, submissions, Batch executions, runs, typed subjects, task and process specifications: the identity chain, what should run, and the history of every transition | Exclusive per transition class: admission creates, the controller submits and accepts, reconciliation closes, constrained procedures override | Architecture (identity chain); Compute (submission protocol); Operations (workflow schema, draft) |
| Delivery | Alert events, the transactional outbox, deliveries and delivery attempts: committed alert effects and their transmission history | Alert production writes outbox rows in the alert-effect confirmation transaction; the publisher writes delivery state only | Operations (alert production); Interfaces (packets) |
| Science catalog | `sources`, `merges`, `astroobjects`, `astroobjectsmeta` and their per-field/per-date children; row currency derived from image currency | The post-DB chain's bulk-queue job types | Operations (post-DB science chain); Database (integrity and durability) |
| Object store | Immutable products and records under the key grammar; terminal records double as promotion manifests; product roles bind contract names to concrete products in release content | Per-container single-writer mapping | Storage (key schema, writer mapping); Catalog (promotion) |
| Problems and audit | Problem occurrences (immutable) and grouped problems, the audit history, vocabulary reference tables | Reconciler files; operators group and resolve; audit rows written by the mutation functions in the mutating transaction | Operations (problems path, operator surface) |
| Reference data | Sky tessellation, injection truth catalogs, retry policy, workflow definitions: versioned content loaded from reviewed files through the migration stream or audited mutation | The load path named per item; never edited in place | Database (tessellation); Operations |
| Derivation | SQL views over all of the above: the one query surface for every derived quantity | The migration stream | Operations (operator surface) |

Attempts reference their work unit, submissions reference the attempts
they carry, and observed Batch executions reference their attempt.
Science-catalog rows reference the difference image that produced them.
Every derived artifact inherits its release identity, data class and
provenance from its inputs. The campaign-to-unit relationship is recorded
through a foreign key.

An **association set** is an immutable grouping of association work.
Live prompt processing and each reprocessing run have separate sets;
later work never mutates a set once it has been written. Accepted
associations and the ordering watermark that gates them are scoped to
`(association_set, lane)`. This lets reprocessing cover historical
observations without changing the live set. The [operations design](operations)
defines the ordering and watermark mechanics.

A **submission** records one sealed AWS Batch API payload: the manifest
URI and checksum, child count, pinned queue, job-definition and image
identities, dispatcher lease, and state. The submission call cannot be
part of a database transaction. The submission therefore has a durable
lifecycle (PREPARED, CALLING, BOUND, UNKNOWN, FOUND, LOST) that outlives
the call. If the response is ambiguous, RAPID searches for the submitted
job rather than submitting it again.

An observed Batch execution records what physically ran; it does not
determine the workflow state. Several executions may exceptionally
reference one attempt, but only the execution authorized by the executor
fence can have its results accepted.

A typed subject is an immutable record containing a subject kind,
canonical key and validated document, unique on kind and key. This envelope lets the
workflow layer identify a subject without interpreting its scientific
content. Scientific tables remain normalized and typed; the envelope
does not replace them with a general attribute store.

## Run

A **run** has its own row with a `run_id`, an owner bound to the login
that created it, and a kind fixed at creation: scratch or production
([glossary](glossary)). The owner cannot be supplied as free text.
The run also records its database target, configuration overlay and
image digest. These are part of the provenance of every attempt and
registered product, alongside the attempt's release identity.

A scratch run may use a trial database, configuration or image instead
of those used in production. Products made with a configuration or image
outside the release are structurally ineligible for promotion
([security design](security)). Publishing that work requires a new
production run under the release.

The run's kind determines which deletion rules apply. Production rows
and objects retain the restrictions of published custody. Permitted
deletion paths cover garbage collection for allowlisted classes,
tiered decay for diagnostics, and disposal of products once the
Mikulski Archive for Space Telescopes (MAST) holds the durable copy.
The scratch deletion path does not apply to production work.

For a scratch run, `run delete` ([operations design](operations)) deletes
objects from owned custody and marks their product and artifact rows as
deleted, retaining each key and checksum. Attempt rows, terminal records
and the run row remain permanently. The surviving provenance records
how the outputs were produced, even after their bytes have been deleted.

A product's identity is shared across every run that realizes it;
deletion is scoped to one run's realization, not to the product. When
two runs each hold a realization of the same product, deleting one
run's realization tombstones only that realization's row (and, where
owned exclusively by the deleted run, its bytes); the other run's
realization rows, its own current pointer, its bindings and its
provenance are untouched, and the shared product row itself is never
tombstoned while any realization of it survives. Shared identity is
consequently never itself a reachability dependency: a companion run
merely sharing a product's identity does not, on its own, block the
other run's deletion — only a recorded physical or provenance dependency
does (below).

## Invariants

1. **History is append-only; state is a derived summary.** Events,
   records, and audit rows are immutable; any "current state" column
   is a queryable summary updated in the same transaction as its
   event row, and any stored summary must be reconstructible from
   the history. A scratch run's deletion does not touch this
   invariant: it deletes product and artifact bytes and marks their
   rows deleted, an action on the object-store and product layers,
   never on the append-only event, attempt or record history, which
   stays exactly as permanent for a scratch run as for a production
   one (§ Run).
2. **One writer per fact.** Every table, record class, and store
   prefix has a named writer; two writers for one fact is a design
   defect. Interval and milestone data are assembled by joining
   single-writer records: nothing re-times, re-counts, or
   re-derives another writer's fact.
3. **Derivable is never stored.** Campaign progress, row currency,
   log-group identity, dashboard quantities: anything computable
   from authoritative records is a view, not a column, so it cannot
   disagree with its inputs.
4. **Currency is a relationship, not a state.** Supersession is a
   set-once pointer; "current best" is `vbest` under the single-best
   partial unique indexes; science-family row currency derives from
   image currency and is maintained by sweeps. Terminal history
   stays readable forever; only pointers move.
5. **Identity over flags.** Facts that must never be mis-set ride
   identity fixed at creation and propagate by provenance: attempt
   identity, data class (substrate × injection: science is exactly
   real ∧ pristine), release content, key-grammar components. A
   mixed derivation takes the most restrictive class of any input.
6. **Idempotence by identity.** Replayed work finds-before-minting
   on its identity (attempt id, record sequence); objects are
   create-once; migrations are forward-only and recorded in the
   database they change.
7. **Enumerations are versioned data, not schema.** Error
   categories, problem vocabulary, retry policy, workflow
   definitions: reference content extended or versioned through an
   audited path, with every consumer recording the version that
   governed it. Adding a vocabulary entry is an operator action, not
   a migration.
8. **Constraints declare invariants; sweeps verify them.**
   Uniqueness and referential rules the model relies on are declared
   on prototypes and their clones alike; loads take shapes that
   cannot violate them; a dedup or currency sweep that finds work is
   evidence of a defect upstream, and prevention beats cleanup.
9. **Everything is LOGGED; schema changes only through the
   migration stream.** Durability is the default; trading it for
   speed is an argued-for regression with measurements.
10. **Gates are grant facts where possible.** The one-mutation-path
    rule and the science gate are enforced by grants (execute-only
    functions, prefix-scoped roles), so violation is impossible
    rather than detected.
11. **Every fact has one home; a needed duplicate cites it.** This
    document cites; it does not restate. Where a schema detail here
    and a domain document disagree, the domain document is wrong or
    this map is stale: either is a defect to fix, never an
    ambiguity to interpret.

## Iteration surfaces

The workflow layer and data-class partition remain draft designs in
the [operations document](operations); this map follows changes made
there. The public-catalog design determines what consumers can see of
an alert event and remains deferred. This map covers the internal
outbox and delivery-state entities. Problem categories are extended
within the adopted taxonomy as operating experience identifies them.

The model is organized in three application schemas, `science`,
`workflow` and `delivery`, and the layers above map onto them:
identity, auxiliary metadata and science catalog to `science`;
workflow and its records to `workflow`; alert events, outbox and
delivery history to `delivery`.

The legacy set `jobs`, `refimmeta`, `refimimages`, `fields`,
`socprocs`, `alertnames`, `archiveversions` is dropped from the
schema by migration and carries no entry above.
