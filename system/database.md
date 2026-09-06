# Database access

**Status: ADOPTED**

## Purpose

How RAPID's clients reach its PostgreSQL database: who connects,
through what, with which credentials; how elastic Batch fan-out is
concentrated onto few server connections; how the schema changes; and
how database-path failures stay observable. What the database holds —
workflow state, attempt records — is defined by the operations and
observability documents; this document owns the access path.

## Scope and model

In scope: the operational database (workflow and attempt state, image
and product registration, source catalogs), its connection architecture,
role and credential model, schema-change mechanism, the availability
and durability posture, and the pipeline-versus-user serving question.
Out of scope: schema content, sizing of storage volumes, and the
choice of database engine — PostgreSQL with the Q3C extension is part
of the structural family and is assumed.

| Term | Meaning |
|---|---|
| Pooler | A proxy that concentrates many client connections onto few database connections |
| Transaction pooling | A server connection is assigned to a client only for the duration of a transaction |
| Session pooling | A server connection is held for the client's whole session |
| SCRAM | SCRAM-SHA-256, the challenge–response password authentication used throughout |

## Access model

**Most Batch jobs hold no database connection at all.** Difference and
detection, reference construction and export are database-free by
design: they read their declared inputs, write their artifacts and one
sealed result manifest, and exit, with the controller accepting the
result. Association is the designed exception — it holds one
connection, uses set-based SQL, and runs under the database queue's
hard concurrency cap. Batch concurrency therefore never determines
database concurrency, which is what the pooler and the cap exist to
guarantee.

| Client class | Path | Credentials |
|---|---|---|
| Transform workers (difference, reference, export) | **No database path** | None — they hold no database credential |
| Controller | Pooler, transaction-pooled | Machine credential from the secrets store under its IAM role; SCRAM |
| Association jobs | Pooler, session-pooled lane under an explicit connection budget | Machine credential, as above |
| Publisher | Pooler, transaction-pooled; scoped to outbox and delivery state | Machine credential, as above |
| Bulk loads and long analytic jobs | Session-pooled or direct, with an explicit connection budget | Machine credential, as above |
| Operators (`rapidctl`) | Pooler; execute-only on the constrained procedures, no table writes | Personal login per operator; SCRAM |
| People (interactive SQL) | Direct, over the private-network access path | Personal login per user; SCRAM; no shared human accounts |
| Schema migrations and administration | Direct; the only path allowed DDL | Admin credential under the credential-custody rules |

Clients connect through **one stable endpoint** — a DNS alias, never
the instance address — so a standby can be added later without
touching a single client.

Rules:

- **SCRAM only.** No md5, no trust, no password authentication over
  cleartext. The host-based access configuration admits only the
  pooler, the private network's service hosts, and administrative
  access — never a personal machine or public address.
- **No IAM database authentication.** That is a managed-database
  feature; self-managed PostgreSQL authenticates with SCRAM. IAM
  governs who may read the credential, not the handshake itself.
- **Roles are tiered groups.** Three tiers — read, pipeline-write,
  administer — granted by group membership, never by direct object
  grants to individuals. Human accounts hold the read tier as the
  standing posture; write membership is granted per named need,
  scoped, recorded, and revocable. The pipeline writes only through
  its service identity, never through a personal account.
- **One credential store.** Machine credentials live in the secrets
  store and are fetched at connection time under an IAM role; personal
  logins are held by their users. No credential appears in an
  environment dump, a job definition, an image, or version control
  (composing with the observability policy's sensitive-content
  prohibition).
- **One connection path, parameterized SQL only.** Pipeline code
  connects through a single connection helper — credential fetch,
  connect timeout, per-component application_name, bounded connect
  retry, context-manager transactions, errors raised, never
  swallowed into flags or process exits from library code. All SQL
  is parameterized; dynamic identifiers go through the driver's
  identifier quoting. String-substituted SQL is prohibited.
  Each job type's database lane (transaction- or session-pooled) is
  part of its validated route in the compute design's payload
  contract, assigned by transaction shape: only long-transaction
  work (association, catalog bulk load, crossmatch) holds the
  budgeted session lane. Forked workers open their own connections.
- **New access goes through narrow typed repositories.** A repository
  returns named records and raises typed errors, with transaction
  ownership at the use case rather than inside the repository.
  Library code never terminates the process — it raises, and the
  caller decides. PostgreSQL is itself the work queue: ready rows are
  claimed with row locks and `FOR UPDATE SKIP LOCKED`, and there are
  no separate ready, retry or quarantine queue tables and no internal
  event stream.
- **The legacy access object is frozen.** It is a shrinking
  inventory, deleted when its last path retires. The pace is
  opportunistic rather than deadlined: the inventory shrinks as call
  sites are touched for other reasons, and compliance is judged on
  direction and mechanism — the typed repositories exist, new access
  goes through them, and the legacy object is frozen with typed
  raises — never on residual call-site count. A deadline here would
  buy churn in working code rather than correctness.

## Pooling design

Transaction pooling is the default client path. It fits the pipeline's
connection shape — many concurrent clients, each transacting briefly —
and its known restrictions are accepted and written down: no
session-scoped state through the pooled path (no `SET`-based session
configuration, session advisory locks, `LISTEN`, WITH HOLD cursors, or
cross-transaction temporary tables). Driver-level prepared statements
are supported through the pooler's prepared-statement tracking and are
permitted. Code that needs session semantics uses the session-pooled or
direct path, with a stated reason.

The database host is an r8a.4xlarge — 16 vCPU, 128 GiB,
memory-optimized, non-burstable, x86-64-v3 — an empirical choice
revisitable on utilization evidence; clones run the same type by the
fidelity rule. The connection arithmetic below keys off its 16 cores.

Sizing is arithmetic from the workload envelope, restated whenever the
envelope changes; these are starting values to be confirmed against
measured rehearsal load, not tuning folklore:

| Quantity | Derivation | Value |
|---|---|---|
| Useful active server connections | ~2 × database cores (16), working set cached | ~32 |
| Transaction-pool server connections | at the knee, with headroom | 30–50 |
| Server `max_connections` | pools + bulk budget + services + admin + monitoring | 150–200, set explicitly |
| Peak concurrent clients | ~1,000 Batch jobs + services + people | ~1,100 |
| Pooler client ceiling | ≥ 2 × peak | ≥ 2,000 |
| Expected in-transaction clients | ~1,000 jobs × ~1% database duty cycle | ~10 |

The multiplexing ratio (~20:1 at full fan-out) holds because a job's
database time is seconds inside a runtime of tens of minutes. Routine
pool saturation is a workload-shape change to be understood, not a pool
size to be silently raised. The duty cycle is an estimate until the
rehearsal workload measures it.

Bulk work is the deliberate exception: catalog loads and multi-hour
crossmatching hold transactions far too long for a transaction pool and
would pin its connections. They run on their own session-pooled or
direct path with an explicit budget counted inside `max_connections`;
their concurrency with prompt processing is a scheduling matter for the
workload classes defined in the operations document.

The pooler is PgBouncer (ADOPTED): mature, single-purpose, actively
maintained, packaged, transaction pooling with prepared-statement
support, SCRAM pass-through, and an admin console exposing pool state
as queryable facts. It is single-threaded; if one core ever bounds
throughput, multiple instances share the listen port with kernel
load-balancing — also the rolling-restart mechanism. Credential
mediation is auth_query lookup in PostgreSQL itself — one credential
home, matching the single-source-of-truth rule — with the provisioned
userlist file documented in the pooler configuration as the one-line
fallback swap.

The pooler runs on the database host as a supervised system service:
co-location keeps one failure domain — no state where the pooler is up
and the database is not, or vice versa — and adds no hop or extra host.

## Reference data: the sky tessellation

The Roman sky tessellation (6,291,458 tiles at NSIDE 512) is
versioned reference content, not a place: its authority is the
output of a canonical, committed builder — repairs applied
programmatically, certified by a validation battery over every row
(bounds ordering, ring and adjacency invariants, boundary, RA-wrap,
and pole probes, and a regularity determination) — identified by
content digest. This database holds the authoritative installation:
immutable version-keyed rows loaded through the migration stream
like any schema change, certified before activation. The active
version is pinned by release content — a tessellation change can
change science products, so switching versions is a release change
— and every attempt records the version it used. A prior version is
retired only when no attempt references it.

Per-source hot-path lookups never become per-row network queries:
if certification proves the tessellation arithmetically regular,
tile identity is a closed-form vectorized computation from the
declination-bin structure with no I/O; otherwise lookups run
batched — one round trip per catalog — against the versioned table,
accepted on measured query-plan evidence at representative catalog
size and concurrency. Cone and polygon queries use Q3C. No
container-baked copy is an authoritative source.

## Schema management

The schema changes only through versioned migrations:

- One ordered migration stream in version control; applying it is the
  only DDL path. Manual DDL is prohibited outside the documented
  break-glass procedure, which ends with an audit event and
  reconciliation.
- Every applied migration is recorded in the database itself —
  identifier, checksum, application time — so the live schema version
  is a queryable fact and drift from the stream is detectable.
- Migrations are forward-only: a mistake is corrected by a new
  migration, never by editing an applied one. Application is idempotent
  and rehearsed against a restored copy before production.
- Extension creation and role/grant definitions are migrations like any
  other — the stream alone must bring an empty database to a servable
  state.
- Applications declare the schema versions they support and check at
  startup, composing with the observability policy's rule that schemas
  evolve deliberately as versioned contracts.
- The pipeline repository's legacy schema DDL (`database/schema/`) is
  retired and deleted; the migration stream is the sole DDL authority,
  its 006/007 baseline the audited re-derivation of that DDL.

## Integrity and durability

Uniqueness is declared, not swept. Key uniqueness in the source and
merge family is enforced by constraints: (aid, sid) unique on the
merges prototype and on every per-field table, aid unique on
astroobjects likewise. Per-field tables are created carrying the
prototype's indexes — a clone path that silently drops them is a
defect. Bulk loads land through a staging table and an upsert so a
rerun cannot produce duplicate rows; the load rate of that shape is
measured at implementation. With prevention in place, the dedup
sweep is a should-find-nothing integrity check, not a maintenance
dependency. **[ADOPTED]**

Every table holding science or workflow rows is LOGGED, per-field
children included: unlogged tables lose their contents on crash
recovery and are not replicated. Trading durability for load speed
is an argued-for regression requiring measurements, never a default.
**[ADOPTED]**

All four identity tables carry attempt-identity columns and
find-before-mint guards per the established additive template; a
writer threads attempt identity from the point an operational writer
exists. **[ADOPTED]**

## Pipeline and user serving

One instance serves both pipeline and people at current scale, and the
sizing above assumes it. Community-scale precedent says the loads
eventually diverge: at thousand-client scale elsewhere, shared database
services — not pipeline algorithms — dominated processing losses, and
the mature pattern separates the pipeline-written store from the
user-query store because their access patterns conflict.

The design therefore keeps the two separable without deciding a split:
workflow/attempt state (small, hot, pipeline-critical) and science
catalogs (large, bulk-loaded, user-queried) stay in distinct databases
or schemas with no cross-dependency that would force them to share an
instance forever. A future split — a replica, a serving copy, or export
to file-based catalogs — then moves data, not application code. No read
replica exists by default: a replica is a new failure mode (staleness,
lag, reset procedures) and is added only against a measured need, with
its lag observable and alarmed.

## Availability and durability

One PostgreSQL primary runs on EC2 from an immutable AMI in a single
availability zone. Q3C requires self-managed PostgreSQL, so a managed
database service stays excluded until one supports the exact required
Q3C version and upgrade path.

**No standbys, no failover runbook, no failover exercises.** Database
loss is a restore event, not a correctness event, and that follows
from the pipeline's own first principle — failure delays work, it does
not create another truth. While the database is unavailable, workers
finish and park their manifests, admission buffers at its durable
source, and acceptance and publication pause. Nothing diverges,
because none of those paths can commit an effect without the database
arbitrating it.

Durability is continuous: scheduled base backups plus continuous WAL
archiving to a versioned backup bucket, so committed-data loss
exposure is the archive lag — minutes rather than hours. One
interaction is recorded rather than assumed: a WAL availability valve
that drops WAL past a queue cap to protect volume space would widen
that exposure beyond the archive lag during a sustained archiver
outage; that interaction is an open item.

A scheduled monthly restore drill restores into an isolated
environment and verifies schema, constraints, representative Q3C
queries and sampled artifact checksums, with dispatch and publication
forcibly disabled. An untested restore path is not a recovery
capability.

The stable client endpoint, the immutable AMI and continuous WAL
archiving together are the whole non-preclusion mechanism for a hot
standby: none of the three has to change to add one. The deferred
capability's adoption trigger is a stated availability requirement
with a recovery-time objective shorter than restore time — and
automatic failover only after fencing and partition exercises prove no
split brain. Reopening the question needs that trigger, not a
preference.

## Failure behavior

Composes with the observability policy: silence is a state, not an
answer.

| Condition | Behavior |
|---|---|
| Pooler down | Clients fail to connect; each failure lands in the attempt record or service diagnostic; reconciliation classifies affected attempts; a service-health alarm fires. Supervised restart; never silent |
| Pool saturated | Clients queue for a bounded wait, then error — never an unbounded hang; queue depth and wait time are metrics |
| Database down | Same visibility path; the pooler's health reflects the database's, one failure domain |
| Credential fetch fails | The job fails before connecting and records that outcome distinctly from a database failure |
| Connection storm (mass retry) | The pooler is the throttle: the database sees at most the pool size; excess clients queue or error visibly |
| Pooler restart/upgrade | Rolling, via shared-port instances or wait-for-clients shutdown; in-flight transactions complete |

Pool state (active/waiting clients, server connections, wait times) is
queryable from the pooler's admin interface and feeds the small metric
set the observability policy permits. The pooler is an operator service
under that policy's service-supervision requirement: bounded local
diagnostics, clean start/stop/restart.

## Open design points

- Measured pool sizes: the arithmetic above gives starting values; the
  full-scale rehearsal supplies the duty cycle and peak concurrency
  that confirm or replace them.
- The bulk-path budget: how many direct/session connections bulk loads
  and crossmatching may hold, and whether they get their own pool.
- The trigger for physically splitting pipeline and user serving, and
  which form (replica, serving copy, file-based export) the split takes.
- Whether operator dashboards read through the pooler or directly;
  affects the pool budget and the access-path table.
