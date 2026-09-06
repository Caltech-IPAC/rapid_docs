# Compute

**Status: ADOPTED**

The execution substrate for pipeline processing: AWS Batch on EC2. The
operations document owns what runs and when; this document owns the
queues, capacity, submission mechanics, and job-definition surface it
runs on.

Batch is scheduling and execution only. It is **evidence, never
workflow truth**: no Batch state, event or log line constitutes a
RAPID state transition by itself, and every observation of it is
reconciled into PostgreSQL. Batch job dependencies are never used to
express the RAPID processing graph.

## Queues

Three job queues express capacity and policy envelopes — never
pipeline stage names:

| Queue | Priority and capacity | Carries |
|---|---|---|
| `prompt` | Highest priority; warm reliable on-demand | Production D (difference and detect) |
| `database` | Small on-demand pool under a hard concurrency cap | Production A (associate and assess) |
| `bulk` | Scale-to-zero, with explicit on-demand escalation | R reference construction, reprocessing D and A, E release export |

The `prompt` split gives the latency-target class its own capacity.
The `database` queue exists because A-work is the only pipeline work
that holds a database connection: its hard concurrency cap — initially
one — is the mechanism by which **Batch concurrency never determines
database concurrency**, which is a correctness boundary rather than a
tuning choice. Without a queue-level cap nothing stops the scheduler
from co-scheduling connection-holders without bound. Priority is the
tiebreak where queues draw on common capacity: prompt latency wins.

Bulk workloads have no artificial concurrency ceiling — their total
compute work does not change with parallelism — so a single bulk queue
serves reference construction, reprocessing and export; a further
split is warranted only if operating experience shows contention that
priority ordering does not resolve. **[ADOPTED]**

## Compute environments

Each queue has its own dedicated compute-environment stack — capacity
isolation by architecture, not by scheduling policy — and each
on-demand environment carries its own MaxvCpus ceiling, so one class's
burst cannot silently consume the headroom another would scale into.
All scale to zero: capacity is elastic and there is no reserved pool.
The declared starting ratio is sized under the on-demand quota with
headroom for transient overlap, and smoke-run evidence replaces it.
Allocation strategy is best-fit-progressive: dense packing of the
dominant job shape first, broadening only on contention. **[ADOPTED]**

Instance selection is deliberately wide — six families at multiple
sizes, spread across all three availability zones — giving the
allocation strategy genuine width to pack densely at scale. The
memory-optimized families are included in the environments rather than
carved into a separate pool: a job whose footprint needs the headroom
gets it without a routing decision. **[ADOPTED]**

Spot compute environments exist at second consultation order, built
but disabled: zero cost while disabled, and enabling later is a state
flip rather than a deployment. When enabled they allocate
capacity-optimized — interruption-minimizing across the wide family
list — not price-first. The gate is smoke-run evidence that a reclaim
is retried automatically and cleanly through the attempt-record path
rather than surfacing as a false failure; the Spot quota request is
filed then, sized from observed demand. Bulk work adopts Spot first —
a reclaim there costs a retry, never a latency-target breach, and the
`prompt` queue's warm reliable on-demand posture is itself a stated
property of the target. **[ADOPTED]**

## Resource profiles and job definitions

Job definitions exist for **distinct IAM, resource, scratch and
timeout envelopes — not one per task**. A task is selected by the
worker subcommand and its manifest, not by having its own definition.

Four semantic resource profiles carry the sizing:

| Profile | Shape | Used by |
|---|---|---|
| Pixel standard | The dominant difference-imaging footprint | D |
| Pixel heavy | Elevated memory or scratch for outsized inputs | D escalation, R |
| Database bounded | Small footprint, holds one database connection | A |
| Export | Streaming-shaped, scratch-light | E |

Measurement determines the numeric CPU, memory and scratch behind each
profile; the profile names are the stable surface, the numbers are
evidence-set. One pinned application image supplies every worker
subcommand, so a science change never forces a new revision — and
therefore a new provenance record — onto unchanged work in another
profile. The image is pinned by digest; a tag is carried for human
readability only and can never change what a submitted job runs.
Jobs run under the service identity the security design assigns to
their function. **[ADOPTED]**

Scheduler-side automatic attempts are configured to **one**. RAPID
owns retry; Batch performs none on its behalf.

## Scratch

Per-job scratch is provided by the host root volume, sized for the
typical packing with headroom for AMI, container-layer and agent
overhead. Instance-store families are excluded — they would narrow the
instance list or fork a second scratch code path for a working-space
requirement that ordinary volume sizing meets. Reconsidered only if
smoke-run evidence shows the scratch I/O pattern IOPS-bound at the
baseline. A storage-quota check against the fleet's aggregate
root-volume footprint precedes full-scale concurrency. **[ADOPTED]**

## Submission

Submission is a durable record, not a side effect of dispatch.
`submission` is one sealed Batch API payload with its own lifecycle,
distinct from the attempt rows it carries. It records the manifest URI
and checksum, the child count, the pinned queue, job-definition and
image identities, the dispatcher lease and its state.

The protocol has three transactions and one API call between them:

1. **Claim and create.** One transaction claims compatible ready work,
   creates the attempts and the submission row, assigns dense array
   indices and marks the work active.
2. **Generate and seal.** The manifest is generated and uploaded from
   those frozen rows, then sealed in a second short transaction that
   pins its checksum.
3. **Call.** The Batch API call is made outside any transaction, with
   the submission row moving PREPARED → CALLING before it.
4. **Bind or resolve.** A clear response binds the row to the parent
   job identity (BOUND). An unclear one leaves it UNKNOWN, and
   reconciliation searches Batch for the submission before any
   resubmission, resolving it FOUND or LOST.

**No transaction spans the submission call, and the call is never
repeated for a submission row.** That is what makes an ambiguous
response safe: a duplicate physical execution may exist, and the
attempt fence renders it harmless because only the fenced executor can
be accepted.

The manifest carries version, checksum and submission identity, and
per child the attempt, work, process and configuration identities. It
carries no credentials and no mutable state.

Arrays compress **homogeneous** submissions only: every child in an
array shares task, process, image, queue, resource, retry and security
identity. One call is one throttle unit regardless of array size,
which is what clears the scheduler's fixed submission rate ceiling at
full concurrency. Prompt work takes only a short coalescing window and
submits singly when necessary; bulk arrays begin in the hundreds
rather than at the service maximum.

An array index is a dense position within one submission and **never
scientific identity**. The child's work identity comes from the
manifest entry its index selects, and an attempt row exists for every
child before the scheduler assigns child identifiers — so a child that
never resolves an identifier is a detectable reconciliation case
rather than a silent gap. **[ADOPTED]**

## Retry

Retry layers are distinct, and the scheduler owns none of RAPID's.
Batch automatic attempts are one; every retry is a new RAPID attempt
with its own immutable identity, and the prior attempt's record
stands. Retry applies per child: one child's retry never resubmits its
siblings, and successful siblings are never repeated. **[ADOPTED]**

RAPID's taxonomy maps cause to disposition:

| Cause | Disposition |
|---|---|
| Infrastructure, capacity or service loss | Retry with backoff; production may escalate to on-demand |
| Temporary storage failure | Bounded local retry, then a new attempt |
| Database serialization or deadlock in A | Bounded transaction retry, then a new attempt |
| Resource exhaustion (memory, scratch, timeout) | One resource escalation, or explicit repartition |
| Corrupt input, checksum, WCS or schema | Reject and block dependants — no retry |
| Missing reference | **Blocked without consuming an attempt** |
| Deterministic algorithm or configuration defect | Fail and block that process specification |
| Scientifically valid empty result | **Successful empty product** |
| Batch success without a valid result manifest | Protocol failure; new attempt |

The versioned retry policy maps error category and operational class
to disposition; policy versions change independently of scientific
releases, and every attempt records the policy version that governed
it. **[ADOPTED]**

## Payload contract

One dispatching entrypoint serves every job definition; the worker
subcommand and the manifest select the task, so the commands differ
while the code path is one. At startup the runtime validates its full
route — manifest task identity, queue (from the scheduler's own
environment), resource profile and database lane — as a single tuple
and rejects any mismatch. No command override exists at submit time.
**[ADOPTED]**

Task and process specifications ship with the application release and
load through an idempotent, audited deployment step. Startup **fails
closed** on a missing or digest-mismatched definition: controller and
worker import the same installed definitions, and a digest mismatch is
a refusal, not a warning. One startup completeness check verifies that
every enabled work stream has one coherent specification, route and
job definition.

Transform workers hold **no database connection**. A D or R or E
worker reads its exact inputs, writes only its own attempt prefix,
uploads its artifacts and one sealed checksummed result manifest, and
exits. Batch success means a durable result exists; logical success
waits for controller acceptance. A workers are the exception by
design: they hold one connection, use set-based SQL, and run under the
`database` queue's hard cap.

Job configuration has three homes: **[ADOPTED]**

| Home | Carries | Property |
|---|---|---|
| Container environment | Per-invocation identity only — manifest location, submission identity, manifest checksum, and the scheduler's own job, attempt, array-index and queue values | Never configuration, never credentials, never anything science-affecting |
| Parameter tree | Operational configuration: container names, endpoints, mode toggles | Read at startup, persisted as a content-addressed snapshot, hashed into the attempt record's configuration digest |
| Release content | Anything that can alter a science product: tuning, reference-data versions | Versioned with the image; never in the mutable tree and never reachable from the environment |

The submission manifest is the sole carrier for a per-run override of
a science-affecting value. Override fields are enumerated in the
manifest schema, an override is recorded by construction because the
manifest and its checksum bind into the attempt record, and a product
produced under any science override is barred from promotion to a
community surface — enforcement of that bar is a stated criterion of
the promotion gate. **[ADOPTED]**

Every external command in the payload is checked: a nonzero exit or
missing binary raises, is classified against the versioned
error-category allowlist, and is recorded — no unchecked execution
path exists. A caught application failure records its outcome and
exits cleanly; scheduler-success with application-failure is the
recorded, expected combination, and a nonzero process exit is reserved
for conditions the job could not record. The retry surface is pinned:
job definitions carry condition-gated retries for scheduler-visible
reasons and a final no-retry catch-all, the submission layer never
passes a retry-strategy override, and an application failure with a
clean exit is never scheduler-retried. **[ADOPTED]**

Jobs run each attempt in a per-attempt working directory created by
the runtime; diagnostics follow the observability design, and tools
resolve against the image's controlled PATH set at build time. The
environment-variable policy of the code-standards design reaches
inside this contract: the software-root variable is fail-loud at every
payload read site, no code path defaults it, and the image-baked
job-definition revision is advisory only — provenance authority for
the executing revision is the submission record's pinned identities.
**[ADOPTED]**

## Logs and provenance

Each queue has one pre-created log group with a bounded retention
window, receiving the bounded safety stream via host-role delivery —
the observability design owns the policy; this substrate binds each
job definition's log configuration to its queue's group. Provenance —
the mapping from source revision through image digest, job-definition
revision and configuration digest to a product — is queryable through
the attempt and submission records; the compute substrate maintains no
separate registry. **[ADOPTED]**
