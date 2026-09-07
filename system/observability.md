# Observability

**Status: ADOPTED** — policy and requirements are normative; the
reference design is illustrative of one compliant implementation,
except the diagnostics lifecycle and the attempt record, which are
adopted. The team reviews the implemented system in operation. The
operational surface is ADOPTED.

## Purpose

How RAPID records and explains its operation without committing to a
large observability platform. Nothing here requires centralized log
search, distributed tracing, or a dashboard. Three levels: durable
policy, testable requirements derived from it, and a replaceable
reference design showing both can be satisfied simply — policy →
requirement → design element → test.

## Scope and model

In scope: pipeline jobs and their retries; long-running operator
services; AWS Batch execution; fleet hosts; operational metadata for
alert publication. Out of scope: alert payloads and science-quality
metrics (alert identifiers, schema versions, destinations, publication
times, and acknowledgements are in scope). Security and audit records
follow their own SMDC requirements; this policy does not weaken or
replace them.

Four observability products:

| Product | Purpose | Normal consumer |
|---------|---------------------------------------|------------|
| **Record** | Structured facts about identity, provenance, timing, outcome | Software and people |
| **Diagnostic** | Free text explaining what happened | People |
| **Metric** | Low-cardinality aggregate health or performance signal | Alarms and people |
| **Alarm** | Notification of a condition requiring a response | Named owner |

An **attempt** is one execution of a logical job. A retry creates
another attempt; it never overwrites the previous one. A runtime
**transport** is how data leaves a process; it is not necessarily the
authoritative retained store.

## Policy

**Machine facts are records.** Facts needed for control, provenance, or
later analysis are emitted as versioned structured records. Pipeline
correctness and state transitions never depend on diagnostic text.

**Every operation is attributable.** Every record carries the
identifiers applicable to its subject. Attempt records identify their
logical run, logical job, immutable attempt and, where applicable,
exposure, SCA, sky-tile, and relationship to alert publication.

**Silence is a state, not an answer.** Application self-report is
reconciled with independent scheduler state. A missing, late, or
contradictory record is detected and classified.

**Latency has defined boundaries.** SCA-to-alert latency is
recorded at named boundaries and decomposes into queue, startup,
execution, and publication intervals. Durations are data, not values
inferred from diagnostics.

**No dedicated observability platform by default.** RAPID reuses
runtime-native transports and stores it already operates. A new
searchable or indexed service requires a named question, an owner, a
cost and retention model, and a removal condition. Small bounded
mechanisms — a metric, an alarm, a short-retention safety stream — are
permitted only when they satisfy the same test.

**Channels follow their purpose.** Job diagnostics, service
diagnostics, host/OS forensics, records, and metrics have separate
retention and access rules. Host/OS evidence is moved off replaceable
hosts and is not used as a pipeline control interface.

**Retention is explicit.** Every retained product has an owner,
authoritative copy, retention period, and cost profile.
Successful-attempt diagnostics are short-lived; failed-attempt
diagnostics may live longer. Provenance remains readable for at least
the lifetime of the products it describes. Vendor retention defaults
are not accepted implicitly.

**Schemas evolve deliberately.** Record identifiers, fields, units,
timestamps, and compatibility rules form a versioned, tested contract.
Producers and consumers declare the schema versions they support.

**Sensitive content is prohibited.** Structured-record fields and
metric dimensions are allowlisted. Diagnostics may contain free text
from RAPID and external tools, but never credentials, tokens, complete
environment dumps, or science/alert payloads; known sensitive values
are redacted before emission.

**Alarms are owned or absent.** Every alarm has an owner, condition,
expected response, missing-data behavior, and response-hours
expectation. Informational signals are not alarms.

## Requirements

| Requirement | Derives from | Acceptance condition |
|----|---------|-----------------------------------------------|
| Attempt record | records; attributability; observable failure | Every submitted attempt has a structured attempt record. A started attempt records its application result; a never-started attempt records its scheduler outcome. The schema defines required and absent fields for each lifecycle state. |
| No diagnostic control | records | No automated state transition, provenance update, or success decision parses diagnostic text. |
| Identity | attributability | Records carry run, work-unit, attempt, submission, scheduler, subject, and stage identifiers where applicable. |
| Outcome taxonomy | records | Scheduler state, process exit code, RAPID outcome, product disposition, and machine-readable error category are distinct fields, required only in lifecycle states where they exist. |
| Provenance | records; deliberate schemas | A product resolves to its inputs, checksums, source revision, container digest, job-definition revision, configuration digest, and reference/calibration identities. |
| Reconciliation | observable failure | On a stated cadence, every submitted attempt becomes terminal, missing, or contradictory; none remains silently indeterminate beyond a stated horizon. |
| Time semantics | latency boundaries; deliberate schemas | Timestamps are UTC RFC 3339 with offsets; event, ingestion, and recording time are distinct where needed; durations use monotonic clocks with explicit units and precision. |
| Milestones | latency boundaries | Named observation-to-alert boundaries are queryable per work unit and its subject. The four latency clocks — arrival to admission, admission to transform result, acceptance to outbox, outbox to broker acknowledgement — are measured separately, each authored by one source. |
| Authority | channel lifecycle; explicit retention | Each field class has one named authority; disagreement between stores is detectable rather than silently resolved. |
| Retention | explicit retention | Every retained stream has an explicit finite rule, except provenance, whose rule is tied to product lifetime. Success and failure diagnostics can expire independently. |
| Service supervision | channel lifecycle | Operator services have bounded local diagnostics and clean start, stop, restart, and termination behavior. |
| Safe content | sensitive-content prohibition | Fields and metric dimensions conform to allowlists; wrappers and entry points do not dump unrestricted environments; diagnostic controls and representative output pass checks for prohibited content. |
| Alarm contract | owned alarms | Every deployed alarm records its owner, response, missing-data treatment, response hours, and test method. |
| Query tests | cross-cutting | Tests answer: what happened to an attempt; which inputs/code/config produced an output; where SCA-to-alert time was spent; which expected records are missing; which alarms currently require action. |
| Cost bound | minimal platform | Telemetry volume, metric cardinality, retention, and standing-service cost are estimated before deployment and reviewed from actual usage. |

## The operational surface

**Status: ADOPTED**

PostgreSQL views are the primary operational surface, versioned
through the migration stream, answering: pipeline flow and oldest work
age, result-acceptance backlog, active and possibly-lost attempts,
quarantine, outbox health, reference coverage, and integrity probes
(provenance completeness, object-orphan candidates, partition and Q3C
index health). Every consumer — CLI, any rendering tier, automation —
reads the same views, so a number cannot disagree between surfaces.

A small low-cardinality metric set carries symptoms only:

| Symptom | Why it is a symptom |
|---|---|
| Backlog count and oldest age by task class | The single best indicator that work is not flowing |
| The four latency clocks | Locates delay in a specific interval rather than reporting a total |
| Connection-pool saturation | The correctness boundary between Batch and database concurrency |
| WAL-archive lag | Directly bounds committed-data loss exposure |
| Reconciliation discrepancies | Convergence is the only mechanism; its disagreement rate is its health |
| Missing objects and checksum failures | A database reference to a missing object is a critical integrity failure |
| Outbox age, retries and permanent failures | The only route to publication, so its stall is invisible elsewhere |

Every non-terminal work-unit state other than `blocked` — the
operator-wait state — carries a bound on dwell time,
measured from the append-only event log rather than any mutable
timestamp column, so that a state stamped without a transition cannot
silently under-report. Exceeding the bound surfaces the unit as an
operator-visible anomaly; it never transitions the unit — a bound
cannot distinguish "accepted and running slowly" from "request never
arrived", and those warrant different operator responses. A state that
waits on a deliberate operator act carries no bound: dwell there is not
evidence of a fault. Bounds are data, not migrations, so retuning is a
configuration update.

Attempts carry no per-state dwell bound: the attempt record has no
transition log, so a clock-based bound cannot be evidenced the way the
work-unit bound is. Instead, a standing anomaly count flags product-producing
attempts whose outcome is success but whose product disposition is
none,
independent of age. A dwell bound for attempts is a future addition,
gated on a reconciler-closure timestamp or an attempt-level event log.

Identifiers belong in structured logs, never in metric dimensions.
Correlation identifiers propagate end to end — admission, work,
attempt, submission, Batch job, manifest, product, delivery — and that
propagation is the recorded non-preclusion mechanism for a tracing
platform, whose adoption trigger is demonstrated diagnostic need.
There is no tracing platform and no dashboard product at this scale.

Pages are reserved for service-level symptoms: database unavailable,
WAL archiving stalled, controller deadman, prompt-age breach, stalled
acceptance, outbox age, reference gap, missing accepted objects, and
failed recovery exercises. **Expected individual Batch failures never
page** — they are the design's assumed case, absorbed by the retry
taxonomy, and paging on them would train the response away.

## Reference design (illustrative, not policy)

```text
controller --> work unit + attempt + submission (PostgreSQL) --> AWS Batch
                    |                                              |
                    |                                              +- runtime diagnostics
                    |                                              +- stage records
                    |                                              +- result manifest + provenance
                    |                                                         |
reconciliation <----+------------ scheduler API                     durable object records
    |                                                                         |
    +-- closes or flags attempts; detects disagreement ----------------------+
```

Authorities:

| Concern | Authority |
|---------------------------------|---------------------------|
| Logical processing intent and current operational state | PostgreSQL |
| Scheduler/container execution state | AWS Batch |
| Terminal application result, provenance, reconciliation classification | Immutable terminal per-attempt S3 record |
| Human diagnosis | Retention-classified diagnostic artifact or safety stream |
| Aggregate health | Small, low-cardinality metric set, when justified |

The stores do not independently author the same fact. PostgreSQL holds
the evolving attempt lifecycle; AWS Batch remains authoritative for
scheduler state. Reconciliation records disagreement instead of
choosing whichever value arrived last.

Attempt lifecycle — the PostgreSQL record evolves by state, and fields
unavailable in a state are absent, never fabricated or sentinel-valued:

| Lifecycle state | Required content |
|-----------|-------------------------------------------------|
| Submitted | Schema, run/job/attempt and scheduler identifiers; submission time; the submission-time execution binding (job-definition revision, image digest, release identity, manifest checksum, retry-policy version), copied from the logical job at row creation — the retry-policy version alone copies from the active retry-policy document |
| Started | Submitted fields plus start time, runtime/code/configuration identity (configuration digest bound in the same transition that marks the start) |
| Application-closed | Started fields plus application outcome, product disposition, stages, application-intended exit, and terminal-record reference; scheduler-observed facts not yet known |
| Terminal after start | Application-closed fields plus reconciler-recorded scheduler end state and scheduler-observed exit; agreement or contradiction classified, never silently resolved |
| Terminal without start | Submitted fields plus scheduler end state, reason, and end time; application-only fields absent |
| Missing or contradictory | Attempt identity, reconciliation classification, observation sources, detection time |

The process exit is two columns with one writer each —
application-intended (written at application close) and
scheduler-observed (written by the reconciler) — the same
disagreement-preserving shape as the timestamp pairs. Attempt rows
are acquired through one atomic claim-or-create resolver keyed by
scheduler job identity and attempt index (application-observed and
scheduler-observed indexes in separate single-writer columns under
partial uniqueness constraints), so a scheduler retry, a
reconciler-discovered retry, and a late-starting runtime always
resolve to one row per attempt.

The application writes the immutable S3 result and provenance record
(sequence 0) at its terminal step; the reconciler closes every
attempt with a closure record — sequence-keyed above the
application's, a complete canonical snapshot folding the validated
predecessor plus classification and scheduler-observed facts — so
the highest-sequence record alone is always the full, reconciled
terminal account. Where no usable sequence 0 exists (never started,
died before writing, or present but failing key/checksum
validation), the reconciler writes a marked reconciler-first record
from the row, the stream, and scheduler state, citing any rejected
predecessor. Registration and other consumers act only on
reconciler-closed attempts and reprocess on supersession. A terminal
S3 record is never mutated; a
correction appends an explicitly superseding record. Started-attempt
provenance includes source SHA, container digest, job-definition
revision, configuration digest, input and reference/calibration
identities, output identities and checksums, and named milestone and
stage timestamps/durations.

Reconciliation: the controller polls, comparing PostgreSQL intent, AWS
Batch state, and expected object records. Scheduled reconciliation is
mandatory and sufficient for convergence — it is the only convergence
mechanism, not a fallback for one. Any event path added later is
acceleration only, changing latency and nothing else, and every
notification handler must be idempotent under duplication and
reordering.

### Diagnostics lifecycle (adopted)

Diagnostics use a bounded CloudWatch safety stream over durable S3
artifacts. Two facts drove the choice. First, operations increasingly
delegates diagnosis to automated agents, whose native interface is an
API query against a live stream — evidence that sits in local files
until an export run is invisible to them, and invisible to anyone
while a job is still running. Second, abrupt loss (out-of-memory kill,
Spot reclaim, host death) destroys exactly the final local evidence
that explains the death; a stream receives it within seconds. The
scheduler already streams container output by default, so the safety
stream is configuration, not machinery. The durable record remains
fetch-and-grep S3 artifacts: the stream adds a live window, it takes
nothing away.

Every terminal attempt ends with exactly one compressed per-attempt
diagnostics bundle in S3 (one `tar.gz` per attempt: stdout, stderr,
stage logs, tool outputs), in an internal bucket named per the
security document's identifier rules, keyed by run/job/attempt on a
classification-neutral key; the retention class (success or
failure) is a reconciler-stamped object tag applied at
classification, and the lifecycle rules act on tags — so a
superseding reclassification retags rather than strands the bundle.
Retagging is a canonical full-tag-set rewrite preserving the other
adopted tags and moves only toward the longer-retention class. A cleanly exiting attempt uploads its own bundle at its
terminal step, then writes the terminal record citing the bundle's
checksum. For an attempt that never wrote one — abrupt loss, or never
started — the reconciler builds the bundle from the attempt's
CloudWatch stream at classification time and marks it reconstructed.
Either way the bundle exists before the attempt is closed, whichever
way it died.

| Stream | Runtime transport | Retained copy | Moves to S3 | Tiering | Expires |
|---|---|---|---|---|---|
| Job stdout/stderr | CloudWatch, group per queue | none — safety net only | never; source for reconstructed bundles | — | 14 days |
| Attempt bundle, success | local files | S3 bundle | at terminal step, by the job | none | 90 days |
| Attempt bundle, failure | local files or stream | S3 bundle | at terminal step, or by the reconciler at classification | Standard-IA at 30 days; Glacier Instant Retrieval at 90 days; Deep Archive at 1 year | never — retained as a record |
| Service/controller | CloudWatch, short-retention groups | the stream itself | no | — | 30 days |
| Host/OS forensics | CloudWatch agent, off-host | the stream itself | no | — | 30 days |
| Records and provenance | direct write | immutable S3 objects (+ live state in PostgreSQL) | at event | Standard only | ≥ lifetime of the products described |

Tiering rationale: while a diagnostic can still be needed
interactively, it stays in tiers with immediate retrieval — Standard,
then Standard-IA, then Glacier **Instant Retrieval** (roughly a third
of Standard-IA's storage price). Diagnostics from a stale release are
no longer diagnostics: nobody debugs against superseded code. They
change purpose to records — custody follows purpose — and move to
Glacier **Deep Archive**, retained indefinitely at negligible cost; a
twelve-hour retrieval is acceptable for something expected to be
retrieved never, whose value is that it exists. The one-year transition
is the calendar proxy for release staleness; if release cadence makes
the proxy poor, the release cycle's supersession step may instead
transition the superseded release's bundles directly (diagnostics
carry their producing release as an object tag). Success diagnostics
expire from Standard without
tiering: transition requests cost per object, and S3 lifecycle skips
objects under 128 KB by default — many success bundles are that
small, so expiry is the only economical action. Records and
provenance never leave Standard: their readability requirement
outlives any tiering saving on their negligible volume. All periods
above are adopted defaults, set in lifecycle configuration and
reviewed against actual volume and spend per the cost-bound
requirement; changing one is a configuration change, not a design
change.

### Attempt record (adopted)

The attempt record is the authoritative, queryable account of every
processing attempt, realized as three live-state tables plus the
immutable S3 terminal record above.

- **Attempts**: one row per attempt, updated in place as it advances
  through the lifecycle states. A retry — from the scheduler or the
  controller — is a new row with its own immutable attempt identity,
  never an update to a prior attempt. Array-submitted children are
  independent attempt rows, created at submission time before the
  scheduler assigns child identifiers; a child whose identifier never
  resolves is thereby a detectable reconciliation case rather than a
  silent gap.
- **Outcome is a five-field taxonomy**, never one collapsed status:
  scheduler state, process exit code, application outcome, product
  disposition, and a machine-readable error category drawn from an
  allowlist versioned with the schema. Scheduler-success with
  application-failure is a representable, expected combination — no
  automated decision parses diagnostic text to discover it.
- **Stage records** are span-shaped and append-only: one row per stage
  execution, written once at completion, carrying a wall-clock start
  for correlation and a monotonic-clock duration that is authoritative
  for elapsed time. Stage names come from a versioned,
  pipeline-owned vocabulary; stages are flat within an attempt.
- **Milestones** record named SCA-to-alert boundaries independently of
  any attempt, queryable per exposure, SCA, or sky tile; the producing
  attempt is carried for traceability, not as the join key, because a
  processing unit may reach a milestone through more than one attempt.
  The wired milestone writers are the chain's ends: `l2_available`
  carries the authoritative source-availability timestamp, and
  `alert_published` commits with emission confirmation. Intermediate
  boundaries are not separately wired milestones — they are derived
  from attempt and stage records. Until the upstream ingest interface
  delivers a SOC-supplied availability timestamp, the recorded
  availability fact is the input registration row's creation time —
  an upper bound on availability, correct for the simulated
  substrate where registration is creation; the SOC timestamp
  replaces it when the real ingest interface lands, with no schema
  change to the milestone itself.
- **Interval decomposition**: SCA-to-alert latency decomposes into
  submission, queue, startup, execution, and publication intervals,
  each authored by exactly one source (application timestamps,
  scheduler timestamps, stage aggregates, milestone timestamps) and
  assembled by joining the records — no per-interval bespoke
  convention. No timestamp column ever has two writers for the same
  row: the application authors creation, submission, and start;
  scheduler-observed times land in their own reconciler-written
  columns beside them; the end time is written by whichever party
  closes the attempt — the job at clean exit, the reconciler at
  classification. Disagreement between application and scheduler
  pairs beyond a stated tolerance is flagged by reconciliation, never
  overwritten or silently resolved. The full decomposition is defined
  for a job's first scheduler attempt; a scheduler-level retry's
  queue interval is bounded only by the prior attempt's stop and its
  own start — a stated limitation of the scheduler's per-attempt
  evidence.
- Fields a lifecycle state has not reached are absent — never
  sentinel-valued — in the database rows and the terminal record
  alike, and every required-or-absent cell of the lifecycle matrix is
  backed by a schema constraint.

The submission-time execution binding includes the retry-policy
version that governs the attempt — authored at submission by the
submitter, required from the Submitted state onward; the
policy-version field copies from the active retry-policy document,
the binding's other fields from the logical job. Queue identity is
not a separate field: it is derivable from the recorded job
definition, which binds to exactly one queue.

The record schema is versioned; producers and consumers declare the
versions they support. The tables ship as a versioned migration in
the infrastructure repository's migration stream. Open parameter: the
timestamp-disagreement tolerance.

Diagnostics never drive pipeline control. A full
OpenTelemetry/Prometheus/Grafana-class platform remains outside the
reference design unless tracing or interactive fleet-wide analysis
demonstrates the adopted design insufficient.
