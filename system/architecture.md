# Architecture

**Status: DRAFT**

## Purpose

This document follows an observation from admission to published
alert. It describes the processing flow, execution roles, data stores,
and boundaries between them, with pointers to the detailed designs.

The domain documents define every mechanism described here; this page
adds no requirements. They cover compute, storage, database,
observability, operations, security, interfaces, releases, code
standards, and repositories. Where a domain document and this page
disagree, the domain document takes precedence. Each carries its own
status: a mechanism from a DRAFT document remains a proposed target.

## What the system is

RAPID is a **modular monolith with distributed execution**. One
installable application supplies the controller, the Batch worker
commands, the publisher, the operator CLI and the database
migrations. Each role starts under its own command and identity,
sharing the application code, typed definitions, and schema contract.

The initial deployment uses one controller, one PostgreSQL primary,
scheduled reconciliation, and one association lane. These choices set
capacity, redundancy, and tooling without changing the data model or
its correctness requirements. The [deferred capabilities](#deferred-capabilities)
table records how the design supports each later addition and what
would justify adopting it.

## Organizing principles

Six normative principles determine the system's structure.

1. **One durable truth.** PostgreSQL is the sole authority for
   accepted inputs and products, provenance, logical work, attempt
   history and publication state. Batch observations and object-store
   contents are evidence, reconciled into that truth; neither ever
   constitutes a state transition by itself.
2. **Exactly-once acceptance, not exactly-once execution.** Duplicate
   submissions, duplicate events, worker loss and controller crashes
   are assumed. Correctness comes from deterministic identity,
   immutable inputs, publication fencing and database uniqueness,
   never from a belief that anything ran exactly once. Duplicate
   computation wastes resources; it cannot corrupt accepted state.
3. **Logical work is distinct from execution.** The identity chain is
   `work_unit → attempt → submission → batch_execution`, and each
   level answers exactly one question: what must be true, what RAPID
   authorized, what was sent, and what physically ran.
4. **Products are distinct from artifacts.** A product is a
   scientifically meaningful result with deterministic identity: a
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

The design retains AWS Batch and PostgreSQL with Q3C; an event-driven
rearchitecture is out of scope. It favors familiar workflows that a
scientific programmer can reason about and debug over cloud-native
patterns that require a new mental model.

## Explicit exclusions

The design explicitly excludes internal Kafka or another message bus,
Step Functions or a second workflow authority, per-stage services or
functions, a general workflow engine, mutable latest-result rows, and
a hidden Batch retry lifecycle. These exclusions are normative.

## Deferred capabilities

These capabilities are deferred at the initial deployment scale.
Each row identifies the existing design support and the condition for
adoption. Where a capability depends on another row, that prerequisite
is implemented first.

| Capability | Kept reachable by | Adoption trigger |
|---|---|---|
| Hot standby, then operator-gated failover | Continuous WAL archiving, a stable client endpoint, an immutable database AMI | A stated availability requirement with an RTO shorter than restore time |
| Automatic failover | Builds on hot standby | Fencing and partition exercises proving no split brain |
| Active-active controller and publisher | Row claims, leases and advisory locks are already concurrency-safe | A throughput or zero-gap-deployment requirement |
| Administrative adapter service in front of `rapidctl` | The CLI already speaks only constrained procedures | Operators without a direct database network path, or team growth |
| Association lanes | The full ordering mechanism (canonical order, persistent watermark) runs from day one | Measured association throughput exceeding one lane per set |
| EventBridge/SQS acceleration | Reconciliation-first design already provides convergence; events would only change latency | A prompt-latency requirement the reconciliation interval cannot meet |
| Regional DR with RTO/RPO targets | Bucket versioning and backup replication are extendable to a second region | A mission requirement naming regional loss |
| S3 Object Lock on backups and releases | Immutability is already enforced by policy | A compliance or tamper-resistance requirement |
| A read tier or analytic replicas | WAL archiving supports a replica without schema change | Analytic load measurably degrading the primary |
| A tracing platform | Correlation identifiers already propagate end to end | Demonstrated diagnostic need |

## System shape

| Component | Authoritative for | Owning document |
|---|---|---|
| PostgreSQL with Q3C | Scientific catalog, provenance, logical work, attempts, publication state | Database, catalog, data model |
| Object storage | Immutable artifact bytes, manifests, result envelopes | Storage |
| AWS Batch | Scheduling and running containers: evidence, never workflow truth | Compute |
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
delays acceptance; it never causes recomputation or loss. The
publisher is a separate process under a separate IAM and database
role, holding the broker credentials alone, running as one instance
and permitted to share the controller's host. The outbox absorbs
publisher downtime. Both run as single instances. The existing
row-claim and lease mechanisms also support safe active-active
operation if that capability is adopted.

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

**D**, difference and detect, takes one calibrated detector image
against a pinned reference set. Its internal stages (input
verification, reference assembly and warp, mask and variance
propagation, normalization, PSF matching and optimal subtraction,
difference and significance construction, detection, deblending and
measurement, quality classification, stamp extraction, output
validation) are one Batch job rather than several, because they share
pixels, scratch, resource profile and retry fate. D holds no database
connection: it uploads artifacts and one sealed, checksummed result
manifest and exits.

**Result acceptance** is a bounded controller loop, not a Batch job
and not a scientific checkpoint. It verifies the fenced executor,
registers products, artifacts and provenance, streams detections,
verifies counts and constraints, marks the D work unit successful,
and creates A work.

**A**, associate and assess, takes an accepted detection product over
a deterministic coarse sky partition. It performs set-based Q3C
candidate joins, immutable history retrieval, association hypotheses,
feature and eligibility calculation, and packet validation. The coarse
cell bounds work and write ownership; Q3C makes the exact angular
decision. A runs under a hard concurrency cap, initially one.

**Publication** happens only through the transactional outbox and the
publisher role. No Batch job performs an external side effect.

**R**, reference construction, builds immutable reference sets from
historical accepted images on bulk capacity; activation is a
controller decision after QA. Workers never discover a mutable latest
reference, and missing coverage blocks D without consuming attempts.
**E**, release export, emits immutable checksummed shards of a frozen
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
| Batch execution | What physically ran | Observed scheduler identity, state, times and exit facts: evidence only; several may exceptionally refer to one attempt, and only the fenced executor (the single execution the transaction verifies as authorized to have its result registered or promoted; defined in catalog.md) can be accepted |

Batch automatic attempts are configured to one; every retry is a new
RAPID attempt under RAPID's own retry taxonomy. Work claiming is
atomic and exclusive: row locks plus a unique active-attempt
constraint, with no select-then-insert race. A work unit closes only
from an accepted result or explicit retry-policy exhaustion, never
from an intermediate physical failure.

Subjects are **typed** and validated at creation by task-specific
canonicalizers (exposure-detector, date-detector, date-field, field
and release unit). Each subject uses its own typed representation;
sentinel exposure or detector values, identifiers stored in unrelated
numeric columns, and parallel untyped representations are prohibited.

No transaction spans job submission. An ambiguous submission resolves
through the durable submission-row protocol (PREPARED → CALLING →
BOUND or UNKNOWN → FOUND or LOST), and the API call is never repeated
for a submission row; reconciliation searches before any resubmission.
Duplicate physical executions stay harmless through the attempt fence.

## Data stores

| Store | Holds | Authority for |
|---|---|---|
| PostgreSQL with Q3C | Scientific catalog, provenance, work units, attempts, submissions, Batch observations, alert events and outbox | Logical truth: work, provenance and publication state |
| Object storage | Staged inputs, reference sets, products, result manifests, diagnostics bundles, release exports, backups | Immutable artifact bytes and result envelopes |
| AWS Batch | Job and queue execution state | Scheduler state: evidence, reconciled into the database |
| Managed streaming | The live alert stream | The external delivery surface, distinct from the archive |

The database carries three application schemas: `science` (scientific
entities, products, artifacts, provenance, detections, associations),
`workflow` (specifications, runs, work units, attempts, submissions,
Batch observations) and `delivery` (alert events, the transactional
outbox, delivery history). PostgreSQL is itself the work queue: ready
rows are claimed with row locks and `FOR UPDATE SKIP LOCKED`, and
there are no separate ready, retry or quarantine queue tables and no
internal event stream. Q3C has a narrow boundary (indexed cone
searches, neighborhood queries and set-based candidate joins) while
scientific code performs WCS and pixel transformations, exact
geometry, differencing and probabilistic association.

One PostgreSQL primary runs in a single availability zone with no
standbys and no failover procedure. Database loss requires a restore;
the correctness guarantees remain in force during recovery. The
[database design](database.md) defines availability, pooling,
per-role connection budgets, the client endpoint, and preparations for
later failover support.

Storage is classified by mutability, custody, retention, audience,
and writer. Containers separate policies that require container-level
enforcement; prefixes separate policies that can be enforced within a
container. Policies enforce immutability through conditional creates
and denial of both ordinary and version-specific deletes. Object
deletion follows a recorded plan and uses the two-pass inventory
anti-join, with a safety horizon longer than the retry, quarantine,
and point-in-time-recovery windows.

## Execution substrate

Three queues express capacity and policy, never stage names:

| Queue | Capacity | Work |
|---|---|---|
| `prompt` | Warm reliable on-demand, highest priority | Production D |
| `database` | Small on-demand pool with a hard concurrency cap | Production A |
| `bulk` | Scale-to-zero, with explicit escalation | R, reprocessing D and A, E |

Job definitions exist for distinct IAM, resource, scratch and timeout
envelopes, not one per task; semantic resource profiles (pixel
standard, pixel heavy, database bounded, export) carry the numeric
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
re-derives ready work on a short interval, tens of seconds, part of
the prompt latency budget. There are no EventBridge rules, no SQS
queues and no redrive tooling.

The controller polls a durable, replayable source of incoming
observations. Admission is idempotent: a repeated observation returns
its existing admission. A source that cannot replay requires a durable
buffer before admission, so a database outage does not lose observations.

Association uses its full ordering mechanism from the initial
deployment, even with a single lane, where neighbor locking has no
effect. Work is claimed in canonical
`(observation_time, detection_id)` order behind a persistent watermark
per `(association_set, lane)`, advanced in the same transaction as the
accepted associations. Ordering is scoped within an association set;
reprocessing sets carry their own watermarks over historical times and
never regress the live one. Reprocessing association always writes an
isolated `association_set` and never mutates the live prompt set,
regardless of deployment scale.

## Boundaries

| Boundary | Rule |
|---|---|
| Upstream input | RAPID processes from source-controlled storage without creating a durable copy of the original object. Input identity is logical observation identity plus immutable version or checksum evidence; a filename is neither an identity nor an idempotency key |
| Worker | Transform workers read their exact inputs and write only their own attempt prefix. They hold no database connection, cannot submit jobs, and cannot publish |
| Publication | External publication happens only through the transactional outbox and the publisher role. Deliveries carry deterministic idempotency keys; an ambiguous acknowledgement is answered by resending the identical packet with the identical alert identifier. Emitted alerts are immutable; corrections are new linked events |
| Network | No public ingress. Private subnets, VPC endpoints, KMS encryption and Secrets Manager; interactive access is session-brokered, not network-exposed |
| Identity | Distinct IAM and database roles for controller, database-free transform, association, export, publisher, migration, operator and backup. No automated path uses a personal credential and no person operates under a service identity |
| Credentials | No long-lived static keys. Machine secrets live in the secrets store, are fetched at use under the caller's role, and rotate through overlapping versions without redeployment |
| Operator mutation | Every mutation goes through constrained procedures under the full mutation contract and the append-only operator-action ledger. Routine operation never requires handwritten state-changing SQL |
| Public surface | Public identifiers carry science semantics only and never embed account numbers, principal names, internal hostnames or personal paths. No storage name is an interface: discovery and retrieval are catalog-mediated |

## Operator surface

Operators use `rapidctl`, connecting through the pooler under a
dedicated database role. That role can execute constrained procedures
but has no table-level write grants. There is no administrative adapter
service or custom web application.

Every mutation requires an actor, reason, idempotency key, expected
current state, dry-run output, and explicit confirmation. The
append-only operator-action ledger records the target, before and
after state, and correlation identifier.

## Observability

PostgreSQL operational views are the primary surface: pipeline flow
and oldest work age, acceptance backlog, active and possibly-lost
attempts, quarantine, outbox health, reference coverage and integrity
probes. A small set of low-cardinality CloudWatch metrics records
backlog age by task class, the four latency clocks (arrival to admission,
admission to transform result, acceptance to outbox, outbox to broker
acknowledgement), pool saturation, WAL-archive lag, reconciliation
discrepancies, and missing-object and checksum failures.

Identifiers belong in structured logs rather than metric labels, and
correlation identifiers propagate end to end, through admission,
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
Rollback changes the active release for future admissions only; it
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
manifest it started with, and a retry replays the same manifest;
consuming a newer generation is new work. A product produced under a
science-affecting override is barred from promotion.

## Latency accounting

Latency decomposes into four separately measured clocks (arrival to
admission, admission to transform result, acceptance to outbox, and
outbox to broker acknowledgement), each authored by exactly one source
and assembled by joining records. Named milestones are recorded
independently of any attempt and stay queryable per observation,
detector or sky partition, because a work unit may reach a milestone
through more than one attempt. The working target is one hour for
about 95% of ordinary observations excluding the Galactic plane, and a
late result enters the live stream only while it remains useful:
provisionally one day after availability, after which later
completions go to the database and archive only. Both are development
targets, not guarantees.

## Operating states

An explicitly selected operating state determines the system's
behavior in each mission phase.

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

Recovery uses deterministic replay from PostgreSQL and immutable
objects, without introducing another source of workflow truth. Quarantine
records a work disposition and its reason without moving work to a
separate queue or bucket. A failure gathering or handling one enabled
work stream leaves independent ready work streams running. Health and
consecutive failures are tracked per work stream; only shared faults
cause process-level failure.

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
