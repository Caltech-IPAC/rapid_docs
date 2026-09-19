# Data model

**Status: DRAFT**, this document is the map of RAPID's data model
and the owner of its cross-cutting invariants.
Per-entity detail (schemas, state machines, key grammars) lives in
the domain documents cited per layer; a domain document may
strengthen but never contradict an invariant stated here.

## Purpose

RAPID's data model was designed layer by layer, each in its own
domain document. This document makes the whole explicit: what
entities exist, how they relate, who writes them, and the invariants
that bind every layer. It exists so the model can be reasoned about,
and iterated, as one thing, and so a rule ruled once in one
context is not silently re-derived (or missed) in another.

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

Relationships that carry the model's weight: attempts reference their
work unit; submissions reference the attempts they carry; observed
Batch executions reference their attempt; science-catalog rows
reference their producing difference image; every derived artifact
inherits identity (release, data class, provenance) from its
inputs; campaign→unit is a plain foreign key.

**An association set is an immutable grouping of association work**:
the live prompt-processing set and each reprocessing run get their own
association set, and a set, once written, is never mutated by later
work. Association output, the accepted associations and the ordering
watermark that gates them, is scoped to `(association_set, lane)`,
never to the database as a whole; this is what lets reprocessing
proceed over historical time without touching the live set (Operations
owns the ordering and watermark mechanics).

**A submission is an entity with its own lifecycle.** It is one sealed
Batch API payload (manifest URI and checksum, child count, pinned
queue, job-definition and image identities, dispatcher lease, state)
and it exists precisely because the submission call is the one step
that cannot be made transactional. Its durable states (PREPARED,
CALLING, BOUND, UNKNOWN, FOUND, LOST) are what let an ambiguous
response be resolved by search rather than by resubmission, so the
record must outlive the call that created it. An observed Batch
execution is a separate entity again: evidence of what physically ran,
never workflow truth, and several may exceptionally reference one
attempt with only the fenced executor acceptable.

Typed subjects are entities, not columns: an immutable envelope of
subject kind, canonical key and validated document, unique on kind and
key. Scientific tables stay normalized and typed: the subject
envelope is a control-plane opacity, not a general attribute store.

## Run

A run is an entity, not a label on other rows: its own row, carrying
`run_id`, an owner bound to the login that created it (never supplied
as text), a kind fixed at creation (scratch or production,
[`glossary.md`](glossary)), a database target, a configuration overlay
and an image digest. The last three are recorded provenance for every
attempt the run carries, the same way an attempt already records the
release and image digest that ran it: a scratch run may name a database
target other than the one production database, and a configuration or
image that is not the release, and both travel with every product the
run's attempts register. Products of a run whose configuration or
image is not the release are structurally ineligible for promotion
([`security.md`](security)), because promotion means rerunning under
the release, not carrying a flag.

**Deletion is scoped to what a run's own kind allows.** A production
run's row and every row and object it produced keep the guarantees
published custody gives them today, unchanged by this design: no new
deletion path opens for them, and the existing ones, garbage collection
on allowlisted classes, diagnostics tiered decay, disposability once
MAST holds the durable copy, keep governing exactly as before. A
scratch run can end, through `run delete`
([`operations.md`](operations)): its product and artifact rows are
marked deleted, with their key and checksum retained, and the objects
they cite are deleted from owned custody. Attempt rows, terminal
records and the run row itself are never deleted; they are the run's
provenance and stay, permanent, under invariant 1 below, whether or not
the run that produced them still has any bytes to its name. What
survives a deletion can explain any result that ever cited the run;
what is gone is the bulk.

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

The workflow layer and the data-class partition are confirmed draft
iteration bases (operations document); their iteration happens
there, and this map follows. The delivery layer's public-catalog
surface (what a consumer sees of an alert event) remains deferred to
the public-catalog design; the outbox and delivery-state entities
above are the internal side of it. The problems-taxonomy content grows
from operating evidence under its adopted scaffold.

The model is organized in three application schemas, `science`,
`workflow` and `delivery`, and the layers above map onto them:
identity, auxiliary metadata and science catalog to `science`;
workflow and its records to `workflow`; alert events, outbox and
delivery history to `delivery`.

The legacy set `jobs`, `refimmeta`, `refimimages`, `fields`,
`socprocs`, `alertnames`, `archiveversions` is dropped from the
schema by migration and carries no entry above.
