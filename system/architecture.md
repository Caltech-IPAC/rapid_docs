# Architecture

**Status: ADOPTED**

## Purpose

The shape of the system: how processing flows, what executes it, where
data rests, and what boundaries separate the parts. This document is
the orienting view — a reader who has not read the domain documents
should finish it knowing how an observation becomes a published alert,
and which document owns each mechanism it passed through.

It states no rule of its own. Every mechanism named here is owned by a
domain document — compute, storage, database, observability,
operations, security, interfaces, releases, code standards,
repositories — and this document defers to them wherever detail is
wanted. Where the two disagree, the domain document is correct. Domain
documents carry their own status; a mechanism drawn from a DRAFT
document is the current target, not a ratified fact.

## What the system is

RAPID is a **modular monolith with distributed execution**. One
installable application supplies the controller, the Batch worker
commands, the publisher, the operator CLI and the database
migrations. These are deployment roles, not independent
architectures: the same code, the same typed definitions, and the same
schema contract, started under different commands and different
identities.

The deployment runs at its smallest correct setting. Every capacity,
redundancy and tooling choice below is a **deployment-scale dial, not
a model change**: one controller rather than an active-active pair,
one PostgreSQL primary rather than a replicated cluster, scheduled
reconciliation rather than an event bus, one association lane rather
than many. The architecture is whole at this scale, and each deferred
capability carries a recorded non-preclusion mechanism and an adoption
trigger.

## Organizing principles

The system shape derives from six principles, each normative. They do
the structural work that the rest of this document only arranges.

1. **One durable truth.** PostgreSQL is the sole authority for
   accepted inputs and products, provenance, logical work, attempt
   history and publication state. Batch observations and object-store
   contents are *evidence*, reconciled into that truth; neither ever
   constitutes a state transition by itself.
2. **Exactly-once acceptance, not exactly-once execution.** Duplicate
   submissions, duplicate events, worker loss and controller crashes
   are assumed. Correctness comes from deterministic identity,
   immutable inputs, publication fencing and database uniqueness —
   never from a belief that anything ran exactly once. Duplicate
   computation wastes resources; it cannot corrupt accepted state.
3. **Logical work is distinct from execution.** The identity chain is
   `work_unit → attempt → submission → batch_execution`, and each
   level answers exactly one question: what must be true, what RAPID
   authorized, what was sent, and what physically ran.
4. **Products are distinct from artifacts.** A product is a
   scientifically meaningful result with deterministic identity — a
   digest of process specification, canonical subject, ordered inputs
   and role. An artifact is a physical encoding of one. Paths, Batch
   identifiers and array indices are never scientific identity.
5. **No distributed transactions.** Objects upload first; one short
   PostgreSQL transaction arbitrates acceptance. No transaction spans
   computation, upload, job submission or network publication.
6. **Reconciliation proves; events would only accelerate.** Periodic
   reconciliation against Batch and object storage is mandatory and
   sufficient for convergence. Loss of any acceleration path changes
   latency and nothing else.

Two further rules shape what the reader will not find here. The
**structural family is fixed** — AWS Batch and PostgreSQL with Q3C are
the skeleton, and no event-driven rearchitecture is in scope — and
**familiar workflows** are preferred, so the design favors mechanisms
a scientific programmer can reason about and debug over cloud-native
patterns that demand a new mental model.

## Explicit exclusions

Normative, and stated here because their absence is a design choice
rather than an omission: no internal Kafka or message bus, no Step
Functions or second workflow authority, no per-stage service or
function, no general workflow engine, no mutable latest-result row,
and no hidden Batch retry lifecycle.

## System shape

| Component | Authoritative for | Owning document |
|---|---|---|
| PostgreSQL with Q3C | Scientific catalog, provenance, logical work, attempts, publication state | Database, catalog, data model |
| Object storage | Immutable artifact bytes, manifests, result envelopes | Storage |
| AWS Batch | Scheduling and running containers — evidence, never workflow truth | Compute |
| Controller | Admission, deriving ready work, submission, retry policy, reconciliation, result acceptance | Operations |
| Worker | One bounded scientific computation | Compute |
| Publisher | Delivery of committed alert events | Interfaces, operations |

```text
Admission source ──> controller x1 ────> AWS Batch workers
Scheduled tick ───> reconciliation           │
                        │                    v
                        v              object storage
                 PostgreSQL/Q3C x1           │
                        │            result manifests
                 transactional outbox        │
                        v                    │
                  publisher x1 <── acceptance transactions
                        │
                        v
                external alert broker
```

The controller is one supervised instance with automatic replacement;
database leases make crash replacement safe. Controller downtime
delays acceptance — it never causes recomputation or loss. The
publisher is a separate process under a separate IAM and database
role, holding the broker credentials alone, running as one instance
and permitted to share the controller's host. The outbox absorbs
publisher downtime by design. Neither is an active-active pair: the
row-claim and lease machinery that would make active-active safe is
already in the model, so running one instance of each is purely a
capacity setting.

## Processing graph

```text
Calibrated detector image
          │
          v
 Admission                     controller transaction; references pinned
          │
          v
 D: difference and detect      database-free Batch transform
          │                    immutable result manifest
          v
 Controller result acceptance  products, artifacts, detections
          │                    one A unit per occupied coarse sky partition
          v
 A: associate, assess, build alerts   database-capped Batch
          │                    associations, alert products, outbox rows
          v
 Publisher                     external alert broker

Historical accepted images ──> R: reference build ──> immutable reference sets
Reprocessing run ──────────> same D/A graph on bulk capacity ──> E: release export
```

**Admission** validates external identity and checksum, establishes
artifact custody, registers the input product, pins release,
configuration and reference products, and creates D work once its
references exist. It is controller and catalog work, never a Batch
job.

**D — difference and detect** takes one calibrated detector image
against a pinned reference set. Its internal stages — input
verification, reference assembly and warp, mask and variance
propagation, normalization, PSF matching and optimal subtraction,
difference and significance construction, detection, deblending and
measurement, quality classification, stamp extraction, output
validation — are one Batch job rather than several, because they share
pixels, scratch, resource profile and retry fate. D holds no database
connection: it uploads artifacts and one sealed, checksummed result
manifest and exits.

**Result acceptance** is a bounded controller loop, not a Batch job
and not a scientific checkpoint. It verifies the fenced executor,
registers products, artifacts and provenance, streams detections,
verifies counts and constraints, succeeds the D work unit and
materializes A work.

**A — associate and assess** takes an accepted detection product over
a deterministic coarse sky partition. It performs set-based Q3C
candidate joins, immutable history retrieval, association hypotheses,
feature and eligibility calculation, and packet validation. The coarse
cell bounds work and write ownership; Q3C makes the exact angular
decision. A runs under a hard concurrency cap, initially one.

**Publication** happens only through the transactional outbox and the
publisher role. No Batch job performs an external side effect.

**R — reference construction** builds immutable reference sets from
historical accepted images on bulk capacity; activation is a
controller decision after QA. Workers never discover a mutable latest
reference, and missing coverage blocks D without consuming attempts.
**E — release export** emits immutable checksummed shards of a frozen
release, finalized into one release manifest after all required shards
and QA are accepted. **Reprocessing** supplies new process identity
and an immutable selection, reuses the same D/A graph on bulk
capacity, and neither mutates live history nor emits live alerts
without explicit promotion.

## Identity and state

Four distinct records carry the chain, each answering one question.

| Record | Answers | Key properties |
|---|---|---|
| Work unit | What must be true | One immutable process specification applied to one canonical subject and input set; deterministic work key |
| Attempt | What RAPID authorized | Monotonic attempt number; at most one active per work unit; every retry is a new attempt |
| Submission | What was sent | One sealed Batch API payload pinning manifest checksum and exact queue, job-definition and image identities |
| Batch execution | What physically ran | Observed scheduler identity, state, times and exit facts — evidence only; several may exceptionally refer to one attempt, and only the fenced executor (the single execution the transaction verifies as authorized to have its result registered or promoted; defined in catalog.md) can be accepted |

Batch automatic attempts are configured to one; every retry is a new
RAPID attempt under RAPID's own retry taxonomy. Work claiming is
atomic and exclusive — row locks plus a unique active-attempt
constraint, with no select-then-insert race. A work unit closes only
from an accepted result or explicit retry-policy exhaustion, never
from an intermediate physical failure.

Subjects are **typed** and validated at creation by task-specific
canonicalizers — exposure-detector, date-detector, date-field, field
and release unit. There are no sentinel exposure or detector carriers,
no identifiers smuggled through numeric columns, and no parallel
untyped fact carriers alongside typed state.

No transaction spans job submission. An ambiguous submission resolves
through the durable submission-row protocol — PREPARED → CALLING →
BOUND or UNKNOWN → FOUND or LOST — and the API call is never repeated
for a submission row; reconciliation searches before any resubmission.
Duplicate physical executions stay harmless through the attempt fence.

## Data stores

| Store | Holds | Authority for |
|---|---|---|
| PostgreSQL with Q3C | Scientific catalog, provenance, work units, attempts, submissions, Batch observations, alert events and outbox | Logical truth: work, provenance and publication state |
| Object storage | Staged inputs, reference sets, products, result manifests, diagnostics bundles, release exports, backups | Immutable artifact bytes and result envelopes |
| AWS Batch | Job and queue execution state | Scheduler state — evidence, reconciled into the database |
| Managed streaming | The live alert stream | The external delivery surface, distinct from the archive |

The database carries three application schemas — `science` (scientific
entities, products, artifacts, provenance, detections, associations),
`workflow` (specifications, runs, work units, attempts, submissions,
Batch observations) and `delivery` (alert events, the transactional
outbox, delivery history). PostgreSQL is itself the work queue: ready
rows are claimed with row locks and `FOR UPDATE SKIP LOCKED`, and
there are no separate ready, retry or quarantine queue tables and no
internal event stream. Q3C has a narrow boundary — indexed cone
searches, neighborhood queries and set-based candidate joins — while
scientific code performs WCS and pixel transformations, exact
geometry, differencing and probabilistic association.

One PostgreSQL primary runs in a single availability zone with no
standbys and no failover procedure: at this scale, database loss is a
restore event, not a correctness event. database.md owns the
availability posture and connection arithmetic — pooling, per-role
budgets, and the endpoint and failover-readiness detail.

Storage is classified on five axes — mutability, custody, retention,
audience and writer — and the container set derives from that
classification: a container exists per enforceable policy point, and
differences a prefix can enforce are carried as prefixes rather than
splits. Immutability is enforced rather than promised, through
policy-enforced conditional creates and denial of both ordinary and
version-specific deletes. Object deletion happens only through the
two-pass inventory anti-join with a safety horizon exceeding the
retry, quarantine and point-in-time-recovery windows, against a
recorded plan.

## Execution substrate

Three queues express capacity and policy, never stage names:

| Queue | Capacity | Work |
|---|---|---|
| `prompt` | Warm reliable on-demand, highest priority | Production D |
| `database` | Small on-demand pool with a hard concurrency cap | Production A |
| `bulk` | Scale-to-zero, with explicit escalation | R, reprocessing D and A, E |

Job definitions exist for distinct IAM, resource, scratch and timeout
envelopes, not one per task; semantic resource profiles — pixel
standard, pixel heavy, database bounded, export — carry the numeric
CPU, memory and scratch sizing that measurement determines. One pinned
application image supplies the worker subcommands.

Arrays compress homogeneous submissions only: every child in an array
shares task, process, image, queue, resource, retry and security
identity, and an array index is never scientific identity. Prompt work
takes only a short coalescing window and submits singly when
necessary. A failed child becomes a new attempt; successful siblings
are never repeated. Batch job dependencies are not used to express the
RAPID graph.

Retry is layered and the layers are distinct. The scheduler retries
nothing on RAPID's behalf. RAPID's taxonomy maps cause to disposition:
infrastructure or capacity loss retries with backoff; a temporary
storage failure retries locally, then as a new attempt; a database
serialization or deadlock failure in A retries the transaction, then
as a new attempt; resource exhaustion escalates once or repartitions
explicitly; corrupt input rejects and blocks dependants; a missing
reference **blocks without consuming an attempt**; a deterministic
algorithm or configuration defect fails and blocks that process
specification; a scientifically valid empty result is a **successful
empty product**; and Batch success without a valid result manifest is
a protocol failure taking a new attempt.

## Convergence

Scheduled reconciliation is the only convergence mechanism. The
controller polls Batch state, sweeps for uploaded result manifests and
re-derives ready work on a short interval — tens of seconds, part of
the prompt latency budget. There are no EventBridge rules, no SQS
queues and no redrive tooling.

That places the durability requirement on the admission source, which
is where it belongs: the source of incoming observations must be
durable and replayable, and the controller admits by polling it.
Admission is idempotent, so a repeated observation returns its
existing admission, and a source that cannot replay requires a durable
buffer in front of admission. "The database is down" must never mean
"an observation was lost."

Association keeps its full ordering mechanism from day one even though
one lane makes neighbor locking vacuous. Work is claimed in canonical
`(observation_time, detection_id)` order behind a persistent watermark
per `(association_set, lane)`, advanced in the same transaction as the
accepted associations. Ordering is scoped within an association set;
reprocessing sets carry their own watermarks over historical times and
never regress the live one. Reprocessing association always writes an
isolated `association_set` and never mutates the live prompt set —
correctness, not scale.

## Boundaries

| Boundary | Rule |
|---|---|
| Upstream input | RAPID processes from source-controlled storage without creating a durable copy of the original object. Input identity is logical observation identity plus immutable version or checksum evidence — a filename is neither an identity nor an idempotency key |
| Worker | Transform workers read their exact inputs and write only their own attempt prefix. They hold no database connection, cannot submit jobs, and cannot publish |
| Publication | External publication happens only through the transactional outbox and the publisher role. Deliveries carry deterministic idempotency keys; an ambiguous acknowledgement is answered by resending the identical packet with the identical alert identifier. Emitted alerts are immutable — corrections are new linked events |
| Network | No public ingress. Private subnets, VPC endpoints, KMS encryption and Secrets Manager; interactive access is session-brokered, not network-exposed |
| Identity | Distinct IAM and database roles for controller, database-free transform, association, export, publisher, migration, operator and backup. No automated path uses a personal credential and no person operates under a service identity |
| Credentials | No long-lived static keys. Machine secrets live in the secrets store, are fetched at use under the caller's role, and rotate through overlapping versions without redeployment |
| Operator mutation | Every mutation goes through constrained procedures under the full mutation contract and the append-only operator-action ledger. Routine operation never requires handwritten state-changing SQL |
| Public surface | Public identifiers carry science semantics only and never embed account numbers, principal names, internal hostnames or personal paths. No storage name is an interface: discovery and retrieval are catalog-mediated |

## Operator surface

`rapidctl` is the interface, executing over a dedicated constrained
database role that holds only procedure execution — no table-level
write grants. There is no administrative adapter service and no custom
web application: the known operators connect directly under the
constrained role. Dropping the adapter tier removes a network hop, not
any part of the mutation contract, which applies in full — every
mutation requires actor, reason, idempotency key, expected current
state, dry-run output and explicit confirmation, and the append-only
operator-action ledger records target, before and after state, and
correlation identifier.

## Observability

PostgreSQL operational views are the primary surface: pipeline flow
and oldest work age, acceptance backlog, active and possibly-lost
attempts, quarantine, outbox health, reference coverage and integrity
probes. A small low-cardinality CloudWatch symptom set carries backlog
age by task class, the four latency clocks (arrival to admission,
admission to transform result, acceptance to outbox, outbox to broker
acknowledgement), pool saturation, WAL-archive lag, reconciliation
discrepancies, and missing-object and checksum failures.

Identifiers belong in structured logs rather than metric labels, and
correlation identifiers propagate end to end — through admission,
work, attempt, Batch job, manifest, product and delivery. There is no
tracing platform and no dashboard product. Pages are reserved for
service-level symptoms: database unavailability, stalled WAL
archiving, controller deadman, prompt-age breach, stalled acceptance,
outbox age, reference gap and missing accepted objects. Expected
individual Batch failures never page.

## Releases and deployment

Release discipline is independent of scale and applies in full. Every
release manifest pins source revision, image digests, the schema
migration set, PostgreSQL, Q3C and AMI versions, Batch job-definition
revisions, task specifications and scientific configuration.

Promotion is: build, scan and sign once; test against real PostgreSQL
with Q3C and representative detector data; apply backward-compatible
expand migrations; register immutable job definitions; deploy; run a
nonpublishing production canary through transform, acceptance and
association; atomically activate the release for new admissions; drain
work pinned to the previous release; and apply contract migrations
only after the rollback window closes.

Work stays pinned to its release, so expand/contract compatibility
lets an old worker's result still be accepted during a deployment.
Rollback changes the active release for future admissions only — it
never edits completed products and never moves in-flight work onto
different code. Services and payloads preflight the application and
schema contract at startup, and task and process specifications load
through an idempotent audited deployment step that fails closed on a
missing or digest-mismatched definition.

## Promotion to community surfaces

Products reach the community view by promotion, never by enumeration.
An immutable manifest naming keys, sizes and checksums is written
create-once beside what it describes, after every object it names, and
promotion references that finalized manifest rather than a bare prefix
or a listing. The science current view advances by a catalog row flip
over immutable keys inside a database transaction; infrastructure
pointers advance by a single conditional write. A consumer pins the
manifest it started with, and a retry replays the same manifest —
consuming a newer generation is new work. A product produced under a
science-affecting override is barred from promotion.

## Latency accounting

Latency decomposes into four separately measured clocks — arrival to
admission, admission to transform result, acceptance to outbox, and
outbox to broker acknowledgement — each authored by exactly one source
and assembled by joining records. Named milestones are recorded
independently of any attempt and stay queryable per observation,
detector or sky partition, because a work unit may reach a milestone
through more than one attempt. The working target is one hour for
about 95% of ordinary observations excluding the Galactic plane, and a
late result enters the live stream only while it remains useful —
provisionally one day after availability, after which later
completions go to the database and archive only. Both are development
targets, not guarantees.

## Operating states

The system's posture changes with mission phase, and the change is an
explicit selected state rather than an emergent condition.

| Phase | Posture |
|---|---|
| Commissioning | Team-driven: exercise ingestion, processing and scientific interpretation while upstream processing and formats are still changing; support old and new input versions concurrently for short transitions |
| Early science and bootstrap | Team-driven with growing automation; reference construction and reprocessing run when instructed; prototype products published at the consumer's risk with no stability promises |
| Routine operations | Automated and hands-off: reference construction, validation and activation are automatic once eligibility criteria are met. People select operating states, authorize releases and triage grouped problems |

Human control selects the state; it does not approve individual
references or reprocessing runs. A supported release goes live only on
explicit human authorization that pins the complete execution chain,
and rollback runs against health criteria defined and versioned before
promotion.

## Failure behavior

| Failure | Behavior |
|---|---|
| Controller dies | The supervisor replaces it; expired database leases make claimed work reclaimable |
| PostgreSQL unavailable | Admission buffers, database-free transforms finish and park manifests, and acceptance, association and publication pause. Nothing diverges |
| Object storage unavailable | The attempt retries; no product is accepted without verified artifacts |
| Broker unavailable | The immutable outbox grows; scientific completion is unaffected |
| Batch execution lost or ambiguous | Reconciliation discovers the authoritative state; the attempt fence keeps duplicates harmless |
| Deterministic scientific failure | Quarantine with evidence, without consuming retries |
| Missing reference | Work blocks without consuming an attempt, and resumes when reference activation makes coverage available |
| Bad release | Deactivate it for new admissions, retain evidence, and reprocess under a new release |

Failure delays work; it does not create another truth. Recovery is
deterministic replay from PostgreSQL and immutable objects. Quarantine
is an explained work disposition, not another queue or bucket. A
failure gathering or handling one enabled work stream never prevents
progress of otherwise-independent ready work streams; health and
consecutive failures are tracked per work stream, and process-level
failure is reserved for shared faults.

## Where the detail lives

| Question | Document |
|---|---|
| Queues, capacity, submission and retry layering, job definitions, payload contract | Compute |
| Container set, classification, naming, immutability enforcement, promotion mechanics, assurance | Storage |
| Access model, pooling, availability and durability, schema management, integrity | Database |
| Records, diagnostics, metrics, alarms, attempt records, reconciliation, retention | Observability |
| Controller, admission, reconciliation, association, work streams, failure and problems paths, latency, operator surface | Operations |
| Reproducibility boundary, identifier exposure, service identities and access | Security |
| Source input, alert stream, product archive, forced photometry, cutouts, processing records, public metadata, release interface | Interfaces |
| Release composition, validation battery, supersession and archival | Releases |
| Catalog promotion, product roles, delivery records, restore acceptance | Catalog |
| Entity layers, writers, relationships, cross-cutting invariants | Data model |
| Style and lint authority, diagnostics style, test doubles, environment-variable policy | Code standards |
| Repository set, roles, visibility, content placement | Repositories |
