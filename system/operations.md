# Operations

**Status: ADOPTED** — the controller, convergence, association and
alert-production sections are ADOPTED; paragraphs marked **[ADOPTED]**
carry forward where the target does not touch them.

## Purpose

How RAPID runs as an operated system: the lifecycle from launch to
routine operations, the controller that automates it, the failure and
problems paths, latency handling, and the roles and interfaces for
humans. The target is an automated, hands-off system in which people
select operating states, authorize releases, and triage grouped
problems — not one that requires per-item attendance.

This document composes with the observability policy: attempt records,
reconciliation classification, latency milestones, alarms, and retention
are defined there and are used here, not restated. No operational
mechanism in this document may depend on parsing diagnostic text.

## Terms

| Term | Meaning |
|----|----------------------------------------------------------|
| SOC | Roman Science Operations Center, RAPID's upstream data provider |
| L2 | Calibrated science-image product; RAPID's pipeline input |
| SCA | Sensor Chip Assembly, one of 18 detectors per exposure; the detector grain of a calibrated input |
| Work unit | RAPID's independent unit of processing: one immutable process specification applied to one canonical typed subject and input set |
| Controller | The pipeline's single automated operator: admission, ready work, submission, retry policy, reconciliation, result acceptance |
| CAR | Commissioning Activity Request: an early-mission observation providing real data before routine surveys |

## Operational lifecycle

| Phase | Character | Operating posture |
|---------|---------------------|------------------------------|
| Commissioning (~90 days after launch) | Data private; upstream SOC processing, calibration, and file formats expected to change; CARs provide early real data | Team-driven: exercise ingestion, processing, and scientific interpretation; support old and new SOC input versions concurrently for short, case-dependent transitions |
| Early Science and bootstrap | Mission-plan observations and public data begin; upstream may remain unsettled | Team-driven with growing automation; publish useful prototype products to brokers at the consumer's risk, with no stability or compatibility promises |
| Routine operations (first supported release onward) | Stable calibrated L2 basis, constructed references, trained classifiers, accumulated operating experience | Automated, hands-off; humans select operating states and handle escalations |

Routine operations cannot begin immediately after launch: they require
sufficiently stable calibrated L2 inputs, repeat coverage from which to
construct references, real data on which to train and validate
classifiers, and accumulated processing experience. The present estimate
for the first supported release is roughly six to nine months after
survey operations begin; this is a planning estimate, not a schedule.

The bootstrap/routine distinction is an explicit operating state, not an
emergent condition. In the bootstrap state, reference construction and
reprocessing run when instructed by an operator. In the routine state,
reference construction, validation, and activation are automatic once
eligibility criteria are met. Human control selects the operating state;
it does not approve individual references or reprocessing runs.

## The controller

The controller is the single automated operator of the pipeline. It
owns admission, deriving ready work, submission, retry policy,
reconciliation and result acceptance — and nothing else: it performs
no scientific computation and no external publication.

One controller instance runs under a supervisor with automatic
replacement, held safe across crash replacement by database leases;
instance count is a capacity dial, not an architectural property
(architecture.md gives the active-active framing in full). Controller
downtime delays acceptance and never causes recomputation or loss. The
controller is a supervised long-running service under the same
service-supervision requirement as reconciliation — clean
start/stop/restart, bounded local diagnostics — not a scheduled
script. **[ADOPTED]**

The publisher is a separate process under its own IAM and database
role, holding the broker credential alone. It runs as one instance and
may share the controller's host; the outbox absorbs its downtime by
design.

Pipeline work divides along two distinct axes. The five
**operational classes** — prompt processing, reference construction,
historical backfill, release reprocessing, test — are the declared,
normative set of kinds of work; the compute design's three **queue
classes** (prompt, database, bulk) are the routing discriminator, and
the mapping follows capacity and policy rather than stage names:
production difference and detection routes to the prompt queue;
production association routes to the database queue under its hard
concurrency cap; reference construction, backfill, reprocessing and
export route to bulk;
a test campaign declares its queue at campaign definition — bulk by
default, prompt only for an explicitly ruled latency rehearsal.
Backfill, release reprocessing, and test are declared ahead of
implementation — backfill belongs to the failure-path design as the
resume mechanism of the pending state, release reprocessing to the
release machinery, test to the mission-mock harness (§ Mission mock
and test campaigns) — and nothing may claim their names meanwhile.
Test is a workload class, not a data class: continuous-validation
injection runs as prompt-class work on validation-class data
(§ Continuous validation), never as test. The
post-DB science chain (catalog load, crossmatch, statistics,
pruning) targets bulk-queue job types under the payload contract;
until that lands it runs as controller subprocesses over an
environment interface, the environment policy's one named temporary
exception. Submission-ordering details internal to gathering are not
classes. **[ADOPTED]**

Gathering is a job-type-keyed registry: adding a job type is a
registry entry, not a branch in a class conditional. Every job type
declares its work-subject grain (exposure/SCA, date/SCA, date/field,
field, or release-unit), and dedup identity and logical-job identity
derive from that declared subject — never from the storage-path key.
The storage-path key (exposure/SCA) is retained only for
product-producing job types, because `product_prefix()` embeds it;
database-effect job types declare empty product sets and mint no
object keys, so identity and storage-path key are independent
concerns. **[ADOPTED]**

Under continuous arrival the accumulator is the live submission
mechanism: ready work flows into it and batches are cut by size or
age. A batch is homogeneous in its validated route — one job type,
one queue, one definition per array submission. Cadence values are
operational configuration in the parameter tree (adopted defaults:
500 units, 60 s). The design bounds them: batch age — time since
the oldest waiting unit entered the accumulator — is capped by the
allocation this document makes from the latency budget (60 s within
the one-hour working target), and batch size by the array-child
ceiling. The smoke run's drip phase and its exit analysis supply the
cut-full versus cut-stale counts and measured arrival rate that
replace the defaults; retuning is a parameter edit. **[ADOPTED]**

Capacity is elastic through AWS Batch; there is no reserved compute
pool. If one is introduced later, its idle capacity is shareable across
workload classes rather than stranded in one. Reference and backfill
workloads are not given artificial concurrency ceilings to reduce cost:
their total compute work, and therefore cost, does not change materially
with parallelism.

### Admission

Admission is controller and catalog work, never a Batch job. It
validates external identity and checksum, establishes artifact
custody, registers the input product, pins release, configuration and
reference products, and creates difference work once its references
exist.

The admission source must be **durable and replayable** — the
controller admits by polling it, and a source that cannot replay
requires a durable buffer in front of admission. Admission is
idempotent: a repeated observation returns its existing admission.
"The database is down" must never mean "an observation was lost."

### Workflow state

The RAPID database is the durable source of truth for workflow state.
Controller state and AWS Batch job or queue state are transient
execution views, reconstructible and reconcilable from the database,
never independent authorities.

The identity chain is four distinct records — work unit, attempt,
submission, Batch execution — each answering one question, per the
architecture and compute designs. A work unit closes only from an
accepted result or explicit retry-policy exhaustion, never from an
intermediate physical failure. Work claiming is atomic and exclusive:
row locks plus a unique active-attempt constraint, with at most one
active attempt per work unit and no select-then-insert race.

### Result acceptance

Result acceptance is a bounded controller loop, not a Batch job and
not a scientific checkpoint. One short transaction verifies the
current work, attempt and fenced executor, registers products,
artifacts and provenance, marks logical success, and materializes
downstream work. Repeating it after a lost response is idempotent, and
cancellation, quarantine, retry and acceptance all take the same
work-unit lock in the same order.

Batch success means a durable result exists; **logical success waits
for acceptance**. Objects upload first and one short transaction
arbitrates the winner — no transaction spans computation, upload,
submission or publication.

| Property | Rule |
|-----|-------------------------------------------------------|
| Transitions | Idempotent; the database keeps an append-only event history plus a queryable current-state summary per tracked unit |
| Tracked units | Release or specialist scope, reference builds, backfill and reprocessing batches, SCAs, processing stages, and individual candidates — nested with explicit parent–child links |
| Retries | Every retry creates a new attempt record with its own immutable identity, never an update to a prior attempt (per the observability policy); attempts record inputs, software and configuration, resources, timestamps, outcome, and log identity |
| Logs | The database stores a structured attempt summary plus a durable log reference and checksum, not the log payload; logs are separate artifacts with their own retention and security policy |
| Retry policy | Versioned policy document mapping (error category × operational class) to a disposition — retry with a stated budget, or park-until-change; versions change independently of scientific releases; every attempt records the policy version that governed it **[ADOPTED]** |
| Workflow definitions | Versioned independently of scientific releases; in-flight units finish under the definition they started with unless an explicit, audited migration is ordered |

### Reconciliation

**Scheduled reconciliation is the only convergence mechanism.** The
controller polls Batch state, sweeps for uploaded result manifests and
re-derives ready work on a short interval — tens of seconds, not
minutes, because that interval is part of the prompt latency budget
and is set from it. There are no event rules, no queues and no redrive
tooling.

This is a baseline rather than a sacrifice: the design already
requires that loss of any event path change latency and nothing else,
so an acceleration path may be added later without changing a result.
Every notification handler, if one is ever introduced, is idempotent
under duplication and reordering. Reconciliation against Batch and
object storage is mandatory and sufficient for convergence.

The controller reconciles authoritative database state with AWS
Batch execution state and expected artifacts. It repairs safe
discrepancies automatically; automatic repair is limited to idempotent
operations such as safe resubmission and workflow-state reconstruction,
and can never promote, replace, or delete a scientific product.
Discrepancies that cannot be resolved safely become structured records
in the problems path.

An ambiguous submission is a reconciliation case, not a resubmission
case: reconciliation searches Batch for the sealed submission before
any resubmission, and the attempt fence makes a duplicate physical
execution harmless.

Service health is progress on actionable work. The actionable set at
a poll is the attempts past their applicable horizon — the grace
horizon after terminal observation, the submission horizon for
never-resolved children — which reconciliation should therefore
classify. The reconciler is unhealthy after five consecutive polls in
which the actionable set was non-empty and nothing was classified; a
poll whose actionable set is empty is healthy silence, whatever
volume is merely resting inside its horizons. This is a
service-health check consumed by the supervisor — the response is
exit and supervised restart — not an alarm; an alarm contract on
restart frequency requires operating evidence of need. A health check
must be quiet under nominal operation — its trigger rate is part of
its correctness. The operative constants (horizons, poll interval,
consecutive-poll threshold) are operational configuration, enumerated
with the implementation. **[ADOPTED]**

The log-group identity of an attempt is derived from its recorded
execution binding: the job definition binds to exactly one queue and
each queue to one log group (compute design), so the group is
derivable and no separately configured log-group name exists to
drift. **[ADOPTED]**

### Post-DB science chain

The post-DB science chain — catalog load, crossmatch, statistics,
and the currency and dedup sweeps — comprises six bulk-queue job
types under the payload contract. The two sweeps beyond the
currently invoked set (source currency, merge dedup) are part of the
operational chain: they maintain integrity properties the schema
does not enforce, and an unmaintained invariant is a defect under
the cross-cutting rules. **[ADOPTED]**

Work units are enumerated at submission: the gathering queries that
discover ready work run in the submission layer, and each manifest
names its declared inputs — catalog load per processing date and
SCA, crossmatch per processing date and field, statistics and the
sweeps per field. Crossmatch readiness is durable state, not operator
sequencing: its gathering predicate checks recorded catalog-load
completion facts directly (the same fact class the alert gathering
predicate reads), never an ordering convention among gatherer
invocations. A job type never discovers its work by catalog
introspection at runtime; every unit is individually retryable and
individually reconcilable in attempt records. **[ADOPTED]**

These job types produce database state, not stored products: each
declares an empty product set, its terminal record is a pure
disposition record that promotes nothing, and its effect — rows
written, rows removed — is recorded in the attempt record's own
fields. **[ADOPTED]**

Row currency in the source and merge family is a derived property: a
row is current while the image it derives from holds best status,
and the currency sweeps remove rows whose image has been demoted.
Between a demotion and the next sweep, superseded rows are present
by design; consumers of these tables read currency through the
image, not the row. **[ADOPTED]**

Registration failure is item-scoped at the operator layer: a pass
that makes progress while recording failures continues, the exit
distinguishes partial from total failure, and a malformed record is
reconciler triage, not a stop condition. **[ADOPTED]**

Job-type configuration is release content: the science and
instrument constants a job type reads live in the versioned
configuration homes the code-standards policy names, and the legacy
master configuration file retires reader-by-reader as each reader
converts. **[ADOPTED]**

### Association

Association runs on the database queue under a hard concurrency cap,
initially **one**. The cap is a dial — its adoption trigger is
measured association throughput exceeding one lane per set — but the
ordering mechanism it sits beside is not, and must not be dropped as
unnecessary at one lane.

At one association job at a time the neighbor-locking machinery is
vacuously satisfied, while the temporal ordering it protects is not:
serial execution does not by itself prevent a later observation's
association from running ahead of an earlier one still in retry.
Ordering therefore keeps its full mechanism from day one. Association
work is claimed in canonical `(observation_time, detection_id)` order
behind a persistent watermark per `(association_set, lane)` — initially
one lane per association set — advanced in the same transaction as the
accepted associations. At this scale that is one row per set and one
ordered claim; concurrent lanes later multiply watermark rows, not the
model.

Ordering is scoped within an association set. Reprocessing sets carry
their own watermarks over historical times and never regress the live
one, and reprocessing association always writes an isolated
`association_set` and never mutates the live prompt set — correctness,
not scale, and therefore in force at any cap. The schema keeps what
makes lanes possible later: every detection has one deterministic home
partition, and association output is scoped to an immutable
association set.

An association job holds one database connection through the
session-mode pooler lane and uses set-based SQL. Affected cell locks
or revisions are acquired in canonical order, and one short final
transaction revalidates them, writes the immutable associations,
assessments and alert products, and succeeds the work unit.

### Alert production

Alert production is a prompt-queue job type under the payload
contract, fed by gathering over registration outcomes: the gathering
query enumerates attempts whose registration committed with the
unit's difference image promoted to current, past the alert
watermark and with the unit's catalog load complete, and units flow
through the accumulator like all prompt work. The manifest names the
attempt identity and the promoted difference-image identity as
declared inputs. The in-process registration seam is not a trigger:
publication never runs inside the registration transaction's process
or identity. **[ADOPTED]**

**External publication happens only through the transactional outbox
and the publisher role.** No Batch job performs an external side
effect: an alert-production job writes outbox rows, and the publisher
alone contacts the broker. That single route is what makes emission
auditable and replayable.

Outbox rows commit atomically **within the alert-effect confirmation
transaction**, which is itself gated on prior result acceptance. They
do not commit in the acceptance transaction, because alert content
does not exist at acceptance time — alert production is a downstream
stage. The binding invariants are unchanged by that placement: no
alert effect is durable outside that transaction, the outbox is the
only route to publication, and repeating the transaction is idempotent.
Emission confirmation and
the alert-published milestone commit together, so a crash cannot
confirm an emission without the milestone recording it.

Emission is once per logical unit per release. The emission watermark
initializes at trigger deployment: promotions predating the deployed
trigger never emit retroactively — emission is live-flow from the
watermark forward. A pin-suppressed registration promotes nothing and
emits nothing; a later pin release that promotes is the unit's first
promotion and emits then. Whether a new release's reprocessing
re-emits is the release machinery's ruling, deliberately not assumed
here, and reprocessing output publishes only under a separately
authorized delivery policy.

Delivery carries a deterministic idempotency key per alert and
destination. An ambiguous broker acknowledgement is answered by
**resending the identical packet with the identical alert
identifier** — never by constructing a new one. Emitted alerts are
immutable: a correction is a new linked event, never an edit or a
re-issue. The stream contract is at-least-once, so consumers
deduplicate on alert identity and producer idempotence is a
duplicate-rate reduction rather than a correctness dependency.
**[ADOPTED]**

Candidate scope is assembly and serialization only: producer
construction, topic resolution, authorization, send, and flush are
chip-level failures, never candidate-scoped — publication runs outside
the per-candidate catch. Recording follows the database-effect
job-type shape: empty declared product set, pure disposition record,
alert-specific effect counts — candidates considered, alerts
published, candidates dropped by reason, emissions suppressed.
Candidate-level failures (assembly, serialization) drop only the
affected candidate, recorded as per-candidate dispositions; the
attempt fails only on chip-level failure, and delivery failure raises
loudly. The archive witness for the internal phase is the existing
stream sink; the archived-representation choice belongs to the
interfaces design. **[ADOPTED]**

Alert provenance and measurement: the packet's pipeline-version
field carries the release identity from the attempt's execution
binding. Forced photometry ships null in the internal phase per the
stub rule and is mandatory before the public phase opens. The
internal phase measures real packet size and per-chip alert counts;
the sizing model and the archive-representation ruling consume the
measurements. **[ADOPTED]**

## Failure-path design

Processing is not binary. Difference-image creation, catalog creation,
alert construction, publication, and archival each have distinct
recorded outcomes. Failure handling is scoped to the smallest affected
unit:

| Scope | Behavior |
|----|--------------------------------------------------------|
| Invalid input SCA | Quarantined at validation without blocking unrelated SCAs; recorded internally and reported to the SOC outside the public alert stream; an unchanged invalid object is not re-retried — a new SOC version makes the logical SCA eligible again |
| SCA-level success boundary | Difference-image construction and source extraction (provisionally extending through deterministic cuts and real–bogus classification) form one atomic success unit; aggregate health statistics are evaluated before promotion, and a seriously anomalous SCA is set aside rather than processed by relaxing thresholds; unrelated SCAs continue |
| Individual candidate | Forced-photometry, cutout, and alert-assembly failures occur after the SCA boundary and drop only the affected candidate; other candidates from the same SCA publish normally |

Retries are failure-aware and governed by the versioned retry policy.
Policy version 1 is deliberately conservative: every
application-failure category is park-until-change — no automatic
retry; the unit waits until a relevant input, configuration, software,
or operational condition changes, and is never tombstoned — while
scheduler-visible failures carry the condition-gated scheduler retry
rows, the sole automatic-retry surface under version 1. Bounded
automatic retries for likely transient application failures remain
the target this policy converges toward: a retry budget is added as a
new policy version justified by an observed failure distribution,
never speculatively. A candidate dropped from the live path remains
eligible for archival processing; a recovered result enters the
archive but never creates a retroactive live alert. **[ADOPTED]**

Pending is likewise a state, not a failure. An incoming SCA advances
through every stage whose prerequisites are available; if no applicable
release reference exists, it stops at that boundary with its completed
state retained. When reference construction — a separate asynchronous
process — activates a reference, the affected observations resume
through backfill. Backfill preferably completes before new data are
processed under a release for that scope; the acceptable wait is hours,
not days, and if exceeded, prompt processing begins first, with each
alert recording that the backfill is incomplete.

Each SCA run is independent: the pipeline does not delay alerts to
synchronize overlapping observations, delayed inputs, or other
asynchronous processing.

## Problems path

The problems path handles many simultaneous or repeated problems with
scalable recording, grouping, review, and follow-up. It is distinct from
real-time alarms: an individual failed SCA does not emit an alarm.

- Every affected SCA receives a structured problem record linked to a
  grouped problem. Failures correlated across observations, time
  periods, surveys, or pipeline components are grouped at the
  appropriate scope, not one record per SCA per issue.
- A grouped problem carries at least category, severity, affected scope,
  first and last occurrence, occurrence count, current status, owner,
  and resolution history.
- Individual occurrences are immutable and traceable even when their
  grouping or category later changes. Initial grouping uses versioned
  automatic rules; operators may merge, split, or reclassify groups
  without modifying occurrence records.
- The problems database is broader than the human work tracker. Only
  selected grouped problems become issue-tracker items — automatically,
  by severity, scope, persistence, and recurrence, or by manual
  promotion. Groups do not become tickets mechanically.
- Operational alarms are reserved for aggregate conditions requiring
  near-term attention; each alarm links to the relevant grouped problems
  and workflow units rather than duplicating them.
- A grouped problem may resolve automatically after its trigger stays
  absent for a defined quiet period; recurrence reopens the existing
  history rather than creating a new record.
- Problem occurrences, grouping changes, and resolution history are
  retained for the full mission, beyond the lifetime of the associated
  scientific products.
- Detailed problem records are internal. Public processing metadata
  exposes selected status and reason summaries only.

## Latency and late processing

RAPID has no formal public latency requirement. The operational
objective is to avoid adding substantial delay after an input becomes
available from the SOC.

| Element | Design |
|-----|-------------------------------------------------------|
| Measurement grain | One L2 SCA — the subject of one difference work unit; the 18 SCAs of an exposure are processed independently, with no wait for the full exposure |
| Clock start | The SOC makes one L2 SCA available in a form RAPID could process |
| Clock end | Processing complete and the alert published; queueing and retries count |
| Working target | One hour for ~95% of ordinary observations, excluding the Galactic plane — a development target, not a guarantee |
| Distribution | Strongly source-density dependent, with a long asymmetric tail; Galactic-plane observations take longer |
| Measurement | Stage-level as well as end-to-end, at the named boundaries defined in the observability policy |
| Live cutoff | A late result enters the live stream only while useful and not confusing — provisionally one day after L2 availability; later results go to the database and archive only |

**Starting per-hop allocations**, over the full
availability→publication clock, reconciling to the one-hour working
target — starting allocations to be replaced by mission-mock
measurement (§ Mission mock and test campaigns), not tuning folklore:

| Hop | Allocation (min) |
|---|---|
| Availability / ingest | 2 |
| Science gather + accumulate | 2 |
| Queue + start | 5 |
| Science execution | 35 |
| Reconciler closure | 2 |
| Registration | 1 |
| Catalog load | 6 |
| Alert gather + accumulate | 2 |
| Publication job | 5 |
| **Total** | **60** |

Dense-field (Galactic plane) execution falls outside this target, per
the smoke-run exit ruling on measurement context.

The live stream never publishes failure messages or gap notifications:
it represents the best set of alerts producible at that time. Missing
results are documented through archival and operational metadata.

## Release promotion in operation

Release composition, identity, and validation policy are a separate
domain; this section covers only their operational execution.

A supported release goes live only on explicit human authorization. The
working mechanism is a version-controlled approval commit in the
pipeline repository that changes a machine-readable release manifest
pinning the complete execution chain — code, references, calibration
baseline, configuration, models, schemas, runtime artifact, and
infrastructure configuration. CI blocks the approval commit unless the
manifest is complete and validation has passed against exactly that
manifest. Passing validation is necessary evidence for authorization; it
never triggers promotion by itself. Permission to merge the approval
commit is the release-authorization control; there is no separate formal
release-authority role.

Merging the approval commit triggers production promotion automatically
— no separate operator deployment action. Promotion stops safely if the
manifest's pinned infrastructure artifact has not passed the separate
deployment-compliance process. During migration overlap the established
and new releases run concurrently (subject to the overlap-vs-pointer
fork marked in the release document — neither topology is normative
until the release-topology redesign lands), and RAPID automatically compares them
on the same incoming SCAs (processing failures, latency, detection and
alert populations, scientific-quality metrics).

Rollback is automatic against health criteria — deployment, operational,
and scientific-quality — that are defined and versioned before
promotion. A rolled-back bundle is never edited or reactivated; the
correction is a new immutable bundle with fresh validation and a new
approval commit, and the failed bundle stays in the audit history.
Retirement of the established release is also automatic, at the planned
overlap end date recorded in the new release's manifest, provided the
new release still satisfies its health criteria; operators may extend
the overlap through an ordinary version-controlled configuration commit.
Emergency hotfixes follow the same path with an explicitly reduced,
documented validation scope; omitted validation runs after deployment.

Every release exposes its lifecycle state — at minimum validating,
approved, live-parallel, primary, retired-hot, archive-only — with
planned and actual transition timestamps in machine-readable metadata.

## Roles and interfaces

The operational surface serves three populations: automated
operations (the service identities), the development team, and agents
operating on the team's behalf. All three read through the same query
surfaces over the authoritative records, and all three perform
operational control mutations — scoped retry, requeue, quarantine,
problem resolution, operating-state changes — through the single
documented mutation path, with break-glass remaining the sole
documented exception. A service identity's own function — writing
attempt records, closure records, and products under its directly
granted role — is not a control mutation and does not pass through
the API. No population has an undocumented side channel. Agents are
first-class consumers: operational state is machine-queryable by
design, the repositories' agent conventions files are their
documentation surface, and an agent acts under the authorization of
the person or service that dispatched it while remaining attributable
as the acting agent in the audit trail — delegated authorization and
audit attribution are distinct properties and both are required.
**[ADOPTED]**

Operators work through a unified internal, authenticated query and
dashboard surface over the authoritative workflow and problems database,
with drill-through to logs, AWS Batch jobs, and produced artifacts —
never by reconstructing state across separate consoles. Public
processing summaries are delivered separately, through catalog metadata
and the public operational-metadata export, without exposing the
operational system.

| Rule | Design |
|-----|-------------------------------------------------------|
| Actions | Scoped retry, requeue, quarantine, and problem resolution |
| Audit | Every operator action lands in the append-only audit history with actor, time, target scope, and reason |
| Authorization | Read access is broadly available to the team; state-changing actions require role-based authorization |
| Bulk safety | Bulk state-changing actions provide a dry-run preview of affected units, products, and estimated work |
| One mutation path | Dashboard, CLI, and automation share one documented mutation path — one authorization, validation, and audit path |
| Break-glass | Direct mutation of workflow tables is prohibited except through a documented break-glass procedure, followed by an explicit audit event and reconciliation restoring a complete authoritative history |

Humans decide, rather than the system: the operating state (bootstrap
versus routine), release authorization and overlap extension, promotion
of grouped problems to tracked work, validation waivers for individual
regression metrics (explicit in the approval record, with rationale and
scope; integrity, provenance, manifest-consistency, and public-schema
gates are non-waivable), and specialist-geometry exceptions — when
arriving observations no longer match a configured specialist reference
geometry, the pipeline raises an internal operational issue and
continues with the current valid default where it can; it never silently
redesigns the geometry.

## Operator surface

`rapidctl` is the operator interface, executing over a dedicated
constrained database role. Operators connect **directly** under that
role: there is no administrative adapter service and no custom
operations web application. Dropping the adapter tier removes a
network hop, not any part of the mutation contract below. Its adoption
trigger, should it return, is operators without a direct database
network path, or team growth.

The full mutation contract applies to every mutation: actor, reason,
idempotency key, expected current state, dry-run output and explicit
confirmation, with the append-only operator-action ledger recording
target, before and after state, and correlation identifier. Routine
operation never requires handwritten state-changing SQL.

The surface as a whole is the query views, the mutation path, and the
operator documentation. It serves the three populations of § Roles
and interfaces through one query surface and one mutation path.

**The primary operational surface is the database views.** Pipeline
flow and oldest work age, acceptance backlog, active and possibly-lost
attempts, quarantine, outbox health, reference coverage and integrity
probes are answered by views in the workflow database, versioned
through the migration stream. The adopted target defers a dashboard
product, with correlation identifiers propagating end to end as the
non-preclusion mechanism and demonstrated diagnostic need as the
adoption trigger; the question-region layout below is the design a
rendering tier would realize, and whether one is deployed is an open
fork, not settled here.

**The dashboard answers questions, not metrics.** A derivation layer
sits between raw telemetry and display, converting measurements into
operationally meaningful quantities; every gauge normalizes to 0–1 —
position in the range empty → full against a configured limit, never
an observed maximum, and the panel names its denominator. The layout
is a fixed set of question regions read as the operational story
(numbering append-only; display order 0, 8, 9, then 1–7):
**[ADOPTED]**

| # | Question | Content |
|---|---|---|
| 0 | What is the system running? | Identity strip: operating state, release identity, image revision per queue, schema head, CI status, dashboard freshness — labels and binary lights only; cross-authority mismatch renders as a warning state |
| 8 | What is in flight? | Per-class in-flight strip: jobs and concurrency share per operational class; one native 0–1 progress row per active campaign with failure fraction and drain ETA; test-traffic presence; empty campaign rows disappear |
| 9 | Are we recovering what we inject? | Recovery efficiency from continuous validation: recovery fraction by substrate, efficiency curve with 50%-completeness depth against baseline, efficiency trend, measurement freshness — the one region measuring scientific performance |
| 1 | Are we receiving data? | Input staleness, generation and SCA completeness, validation pass — placeholder pending upstream-interface answers; denominators label themselves when self-referential fallbacks are in use |
| 2 | Are alerts going out? | Publication fraction, dropped-candidate fraction, flow-through paired with region 1, live-window misses, archive-sink lag, promotion completeness — built from database and publication records, never by consuming the stream |
| 3 | How long does processing take? | Target attainment (prompt class), latency pressure on fixed target-normalized axes with an explicit overflow bin, single-writer interval decomposition, Galactic-plane population displayed beside never merged |
| 4 | Is anything silent? | Indeterminate attempts, detected silence, unresolved children, stalled generations, watcher liveness — the liveness panel gates the region: target-zero panels render stale the moment the reconciler misses cadence; recorded pending is excluded |
| 5 | Is there a pattern of errors? | Fractions never counts, split by versioned category and job type; trend vs trailing baseline; retry pressure; quarantine fraction by gate; top-cluster share; unclassified is a plotted category whose growth signals taxonomy drift |
| 6 | How loaded are the resources? | Queue utilization with time-at-ceiling, bulk backlog vs bound, pooler lanes vs budgets, DB host, stream capacity, named hosts vs elastic fleet — elastic-empty is healthy idle; named-host absence is the alarm shape |
| 7 | Does a human need to act? | An ordered queue, not a gauge: alarms with owner and age vs response expectation, data-starved alarms displayed never hidden, problems awaiting triage, the humans-decide queue, unreconciled break-glass (hard target zero) |

**Mixture rules.** Operational class is a mandatory split dimension —
pooled aggregates across classes do not exist; regions 1–3 are the
prompt story, campaign-shaped classes live in region 8, and every
class feeds regions 4, 5, and 7. Test traffic is a declared class,
excluded from every default view, flagged in region 0 and shown in
region 8 — never invisible. Fractions never pool across data classes
either (§ Continuous validation). **[ADOPTED]**

**Two pages, split by story.** Page 1 — System: regions 0, 8, 9, 4,
5, 6, 7; always open, self-sufficient for triage, its good state
legible in seconds. Page 2 — Prompt processing: regions 1–3 in full
plus prompt-filtered cuts of silence and errors. Campaign detail
pages are later same-shaped additions that never touch page 1.
**[ADOPTED]**

**Realization.** The derivation layer is SQL views in the workflow
database, versioned through the migration stream; dashboard, CLI,
and agents read the same views, so a number can never disagree
between surfaces. Grafana renders them through the standing
read-only posture (database views plus the cloud-provider datasource
for region 6 quantities whose authority is cloud-side) — a display
over existing stores, not a new indexed platform; its removal
condition is "the views answer the questions without it." The
minimum surface displays; it does not mutate — mutations run through
`rapidctl` with any rendering tier linking worklist context;
embedding mutation actions into panels waits for operating
history. **[ADOPTED]**

**The mutation path is the database, not a service.** Mutations are
database procedures (callers hold execute on the procedures, never
write on the tables), called directly through `rapidctl`; the audit
history is a table written by the same functions in the same
transaction. Table grants make the functions the only write path, so
one-path is a checkable grant fact; dry-run is a function parameter,
default on, with execute the explicit flag. Authorization is the
triple (actor, action class, target scope); action classes group
into three documented tiers — read (whole team, standing), operate
(scoped retry, requeue, quarantine, problem resolution), decide (one
class per humans-decide item). The grant posture starts wide open —
every team member holds every class; narrowing is evidence-triggered
and is a grant-map change, never an API change. Service callers are
enumerated, not tiered: an automated caller holds exactly the
classes its versioned policy document authorizes, and the policy
citation is part of the authorization. Agents inherit their
dispatcher's grants; audit records dispatcher as authorization and
agent as actor, both required. Guidance is by friction and
visibility, not denial: dry-run first, a mandatory unvalidated
reason on every mutation, immediate attribution on the dashboard,
and advisory scale warnings that never refuse. **[ADOPTED]**

**Break-glass.** For the mutation path's own failure modes only —
never a faster path. Open loudly: assume the elevated role (assumed, never
resident; the assumption audits) and declare a reason — a
break-glass session is dashboard-visible from its first second.
Touch narrowly, transactionally where possible. Close explicitly
with an audit event recording reason, tables touched, and changes —
closing without it is not closing. Reconcile to done: the region 7
row clears only when the closing event and a passing reconciliation
both exist. No two-person requirement, ever — visibility is the
control. The walked-through runbook lives in the operator docs.
**[ADOPTED]**

**Problems-taxonomy scaffold.** The taxonomy content grows from
operating evidence; the scaffold lands first. Seed vocabulary:
four categories (upstream data, infrastructure, science quality,
other), two working severities (attention, urgent; info for
auto-resolved history). The vocabulary is data, not schema —
reference tables extended through an audited mutation function, with
the audit history satisfying the versioning requirement. Grouping
rule v1 is one rule: (category, error category, job type) within a
rolling window; operators merge, split, and reclassify as the escape
valve. Promotion to tracked work is manual-only until hand-promotion
volume shows what thresholds should be; one default quiet-period
constant for auto-resolve. **[ADOPTED]**

### Workflow schema

Adopted as v1 by the integration review: work_units, unit_events,
campaigns, and workflow_definitions land as the intent layer, with a
nullable attempts FK required on new operational attempts; writers are
exclusive per transition class; the campaign-scoped derivation view is
the one query surface. Scoped retry's effect is the unit-level
failed→ready compare-and-swap transition. Everything else this
section touches is adopted elsewhere and consumed, not restated.

Two state machines only. A **work unit** — (job type, declared input
scope, operational class, definition version) — has six states:
blocked (always with a machine-readable reason; park-until-change
folds in here), ready, submitted, complete, failed, quarantined.
Failed → ready and quarantined → ready pass only through the audited
mutation path. Supersession is a set-once pointer, not a state; a
partial unique index enforces one non-superseded unit per (job type,
input scope). Writers are exclusive per transition class:
admission creates, the controller submits, accepts results and
applies retry dispositions, reconciliation closes, and the mutation
path does operator overrides. A **campaign** — one row per finite-class run,
test campaigns the same shape under the test class — runs defined →
active ⇄ paused → complete | abandoned; progress is never stored,
always derived from its units. Candidates get write-once disposition
records, no state machine; batches have no table — manifest plus the
attempt record's batch identity are membership, statistics are
derivation-layer aggregation. Intent schema: work_units, unit_events
(append-only, same transaction as every transition), campaigns,
workflow_definitions (reference table loaded from a reviewed file in
the pipeline repository through the audited mutation function, tied
by checksum); attempts gain one FK to their work unit. In-flight
units finish under the definition version they started with;
explicit migration is a bulk-warned mutation-API action with an
event row per unit.

## Continuous validation

Draft iteration base except where marked. Simulation and source
injection are permanent parts of the system — continuous validation
from the start, with injection into both real and simulated data —
and must never leak into science data.

Every input identity carries two values fixed at creation:
**substrate** (real | simulated) and **injection** (pristine |
injected). Science is exactly one cell: real ∧ pristine; the other
three are validation data. The pair is identity, not a flag: work
units, attempts, products, alerts, and catalog rows inherit their
data class from input identities through the provenance chain, and a
mixed derivation takes the most restrictive class of any input.
Injection never modifies — it creates a new immutable object under a
new identity citing its untouched parent and the versioned truth
catalog. The science gate is non-waivable and joins the existing
non-waivable list: promotion to community surfaces, mission-stream
publication, and science current-view flips require real ∧ pristine;
validation alerts flow to a separate internal stream, and the
mission stream is unreachable by construction for non-science
classes. Storage-side, data class rides the key grammar as a
mandatory component with prefix-scoped grants (storage design)
**[ADOPTED]**. The catalog partitions on data class inside the
database, with every science-facing view selecting the science
partition by construction; cross-partition queries are explicit —
default only in dashboard region 9, which is labeled as such. Truth
catalogs are versioned, provenance-recorded inputs.

## Mission mock and test campaigns

A mission mock is a test-class campaign driven by the deployed
controller:
defined as a campaign row, gathered and batched by the production
operator and accumulator, submitted through the guarded submission
seam under the campaign's declared route. No parallel operator and
no side-channel submitter exist; the bounded-width probe tool
remains a probe, never the mock. Zero-submission passes use the
structural rehearsal mode. **[ADOPTED]**

Mock inputs enter through the same validation/ingest writer as real
inputs: the harness's one new component transforms mission-schedule
rows into staged generations — exposure to per-SCA objects, wall
time to MJD, manifest written last — under simulated-substrate
identity fixed at creation. Nothing else writes input rows.
**[ADOPTED]**

Fidelity is four independent dials — scale, arrival cadence, sky
distribution, data realism. The v1 posture: one selected observing
day replayed at real arrival timestamps and real sky positions from
the mission schedule, full SCA fan-out, staged-simulation data
realism; longer spans by clock compression with the factor recorded
as a campaign property, never a hidden distortion. The mock's
purpose is the downstream — reference availability, database
contention, product volume, alert rates, and the dashboard's
in-flight and recovery readouts — the submission layer is
provisioned well past mission peak arrival. **[ADOPTED]**

Mock runs read the live parameter tree and never retune it.
Campaign-scoped parameter overrides are a future design taken up on
evidence, not built speculatively. **[ADOPTED]**

The run record is the campaign row plus its attempt records, read
through a campaign-scoped derivation view versioned in the migration
stream: per-campaign outcome, latency, and — where truth catalogs
apply — recovery quantities. Human-readable run reports are
generated from the view; narrative documents carry context, never
the record. **[ADOPTED]**

Test work needs no dedicated infrastructure: isolation is identity-
and IAM-shaped — data-class prefixes and grants on the shared stack
— not deployment-shaped. No test queue, no test bucket, no parallel
stack. **[ADOPTED]**

## Open design points

Deliberately unresolved, retained from the design source:

- The observable trigger for first-supported-release readiness; the
  six-to-nine-month estimate is provisional.
- The one-hour latency target and one-day live cutoff, to be replaced if
  operating experience supports better values.
- Galactic-plane latency treatment and any operational capacity targets.
- Cost behavior of Batch elasticity at full scale, and the
  storage-quota check before full concurrency; instance selection and
  capacity isolation are settled in the compute design.
- The exact backfill wait threshold within the hours-not-days bound.
- The stages, survey-specific health metrics, and anomaly thresholds
  defining the atomic SCA-level success boundary.
- The log-retention model (workflow schema, state machines, and
  definition versioning now carry a draft iteration base above;
  reconciliation rules are adopted).
- Whether autonomous operations agents warrant a dedicated
  service-identity-class account.
- Problems-taxonomy content beyond the seed vocabulary and grouping
  rule v1 — grown from operating evidence per the adopted scaffold;
  audit-retention implementation.
- Dashboard region 1's denominators and panel set — placeholder
  pending the upstream data-interface answers.
- The release governance process and the manifest's file format and
  required evidence links; the manifest is a probable design, not a
  finalized schema.
- The first supported release has no established stream to fall back to;
  its failed-promotion behavior is deliberately unresolved until actual
  readiness and operating conditions are understood.
- The fallback for missing or changed specialist observing plans, and
  confirmation of the observing-schedule interface, lead time, and
  stability.
