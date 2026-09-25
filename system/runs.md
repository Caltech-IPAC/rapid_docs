# Runs, attempts and custody

**Status: DRAFT**

Companion to the specification's Runs section, the [stage contract](stage-contract)
and the [products](products) page: how runs, units of work, attempts, product
instances, result sets and the three custody states are held in the database
and laid out in storage. Written 2026-09-21, revised on a Codex review and on
the lead's schema ruling; direction approved by the lead.
## In plain terms

A run is a row that says who started a pass over which inputs with
which code and settings, and whether its outputs are a person's or the
project's. Each piece of work in the run is a unit; each try at a unit
is an attempt with its own output folder. Every product a finished
attempt made, file or database rows, is an instance row. Three states
on the instance row say whose it is and whether consumers see it.
Promotion changes those rows under one lock and writes down what it
changed, so it can be undone. Files never move; only rows change.
Deleting a scratch run is one guarded operation, and nothing else
deletes run data.

## Tables

| Table | One row per | Key columns |
|---|---|---|
| `runs` | run | id, kind (`scratch`, `production`), owner login, created, state (`open`, `finished`, `deleting`, `deleted`), purpose, selected stages, code revision, image digest, release, schema version, settings overlay ref, input selection ref, lane, resource profile, database target, max attempts per unit, auto-promote flag, check-policy ref, seed run, expires at, pinned, deleted at |
| `units` | piece of work in a run | run, stage, unit kind, unit id, state (`pending`, `ready`, `running`, `complete`, `failed`, `cancelled`), selected attempt, cancel reason |
| `unit_inputs` | frozen input binding | unit, producer instance |
| `attempts` | execution of a unit | id, run, stage, unit, started, ended, exit code, disposition (null while queued or running; `succeeded`, `failed`, `transient`, `killed`, `lost`), output location, execution record, scheduler job id |
| `execution_records` | attempt | attempt, source revision, working-copy patch, image digest, release, schema version, resolved settings, settings hash, scheduler metadata; contents stored, not referenced into the run prefix |
| `product_instances` | product an attempt made, file or result set | instance id, kind, logical key, run, producing stage, producing attempt, registering attempt, custody (`scratch`, `candidate`, `current`), format version, primary location, manifest ref, published at, deletion state |
| `product_members` | file in a bundle | instance, role, path, bytes, sha256 |
| `result_sets` | one-to-one extension of an instance that is rows | instance, complete flag, row count |
| `promotions` | promotion action | id, who, when, reason, check-policy version, check result ids, request context |
| `promotion_changes` | affected logical key in a promotion | promotion, kind, logical key, before instance (nullable), after instance (nullable) |
| `checks` | verification result | instance, check name, version, required flag, outcome, when, detail |
| `dependencies` | provenance edge | consumer instance, producer instance |

The `dev` schema's product tables (`l2files`, `refimages`, `diffimages`,
`sources`, `merges`, `astroobjects`, `astroobjectsmeta` and their
companions) are kept with their names and columns. Each gains `run`,
`attempt` and `instance` (or `result_set`) columns, and where a
uniqueness constraint would block two runs holding the same logical
product it is widened to include the run or set. Nothing is renamed and
nothing is dropped (lead, 2026-09-21: changing confuses the team;
`smdc` deleted too much).

## Rules

**Runs.** A run's kind is fixed at creation and decides the custody of
everything it makes: a scratch run makes scratch, a production run makes
candidates. A run freezes its input selection at creation. A run may
bind a complete current result-set instance from another run as a
frozen input; that binding stays valid if the instance is later
superseded, because the dependency retains it. Scratch result sets are
usable only within their own run. Production runs use the one
production database; scratch runs may name a trial database. A run
becomes eligible to finish once every unit is terminal, but finishing
is an explicit `finish` and not automatic; a finished run is never
reopened (supervisor step 3, 2026-09-24). Seeding a new run copies
configuration and permitted input selections; it does not authorise
reuse of another run's scratch outputs.

Scratch runs receive a default `expires_at` of fourteen days after
creation. `pinned` holds a run past that date. An expiry sweep deletes
unpinned scratch runs past their `expires_at`, through the same
operation as `run delete`. The sweep runs as an explicitly authorised
actor, not the run's owner; under the run lock it re-checks the run's
kind, pin and expiry and refuses the delete if any no longer holds
(supervisor step 3, 2026-09-24). The sweep's warning mechanics are not
decided here.

**Units.** A unit is pending until its declared input set is complete
and its upstream attempts are selected. It then becomes ready, and
running when an attempt is allocated. Selection of a successful
completed attempt makes it complete. A retryable failure returns it to
ready while attempts remain; otherwise it becomes failed. Cancellation,
or a permanently failed required dependency, makes an unstarted unit
cancelled with a recorded reason. Complete, failed and cancelled are
terminal. Unit state is stored, not derived. Inputs are bound in
`unit_inputs` before execution and retained for retries. `register`'s
own unit id is `<producing stage>/<producing unit id>` (for example
`admit/e20260821001234/SCA07`, `difference/e20260821001234/SCA07`),
derived from the manifest `register` reads: one `register` unit follows
every producer, with no occurrence counter, and it is runnable singly
for one producer at a time (lead, 2026-09-23). This applies from the
next run; rows a run wrote before it stay as they are.

**Input-set composition.** A stage declares its input set by product
kind and role. The launcher resolves each entry from this run's own
instance of that kind for the unit first; failing that, from the run's
frozen input selection, using `dev`'s selection rules (the current
reference by field and filter, the current PSFs by filter and
detector). It never resolves an entry from an unrelated run unless the
input selection names that instance explicitly. The resolved binding is
written to `unit_inputs` before execution, and the manifest a stage
reads is generated from that binding; a hand-composed manifest is a
test path, not how a production run assembles its inputs (lead,
2026-09-23).

**Attempts.** Each try is an attempt with a fresh id and an exclusive
output location; an attempt has no disposition while queued or running.
Success requires a valid completion manifest and complete declared
outputs; exit zero alone is not success. Selection locks the unit row
and atomically sets its selected attempt and complete state; the
selected attempt belongs to that unit and the selection never changes.
Late results cannot reopen a terminal unit or replace its selected
attempt. The run records the maximum attempts per unit, counting the
first attempt and all Batch retries; only code 75 and explicitly
approved infrastructure failures are retried; an exhausted allowance
fails the unit. `lost` means the scheduler lost the job: unresolved
execution, treated as a possible writer until resolved.

**Instances.** `register` preserves the instance ids and the producing
run, stage and attempt recorded in the manifest, and records the
registering attempt separately. Replaying an identical manifest is a
no-op; conflicting content for an existing instance id is an error.
Database-writing stages create their own attempt-scoped result-set
instances and record completion, including empty completion. After an
uncertain commit the same attempt recovers its recorded results rather
than inserting duplicates. Published identity, content metadata and
provenance are immutable; custody and deletion metadata change only
through promotion and deletion. A dev-registered product enters the run
model by an import run: `reference-import` for a reference `dev`
registered, `psf-import` for a PSF `dev` registered, each a production
run whose one unit registers that product with a run, an attempt and an
instance of its own, so the imported instance is a candidate in project
custody and a production run that depends on it can be promoted
(supervisor step 3, 2026-09-24, amending the lead's 2026-09-23 wording:
`dev`'s registered products are the project's, and a scratch import
would refuse every production promotion that depends on it). It can be
named as a frozen input like any other instance. The two
`reference-import` runs registered in `rapid_rebuild` before this
ruling were re-kinded to production by hand on 2026-09-24 and their
instances made candidates (supervisor step 3, 2026-09-24).

**Custody.** Scratch never leaves scratch. Candidate becomes current by
promotion; current becomes candidate again when superseded. At most one
current instance exists per kind and logical key, enforced by a partial
unique index where custody is current. The current selection is a view
over the instance table and includes file products and result sets
alike. A consumer resolves a related selection from one database
snapshot.

**Promotion eligibility.** Automatic and manual promotion require
completed, selected outputs, a recorded image digest identifying a
released artifact, and passing results for every required check in the
applicable lead-approved check-policy version. Missing or failed
required checks refuse promotion. Every provenance dependency must
identify a complete, retained instance in project custody; a dependency
need not be current. The replacement's kind and logical key must equal
the requested pair, it must be retained, and a result set must be
complete. Validation against a released image digest is now
implemented, closing the trial exception recorded here for step 3: every
deliverable's selected producing attempt must have an execution record
whose image digest is a complete release's digest, or the promotion is
refused unless the operator passes the explicit unreleased exception
(the [releases](releases) page has the record and the check; supervisor
step 5, 2026-09-24). Validation against the check-policy version above
is unaffected by this and remains as stated. Automatic promotion stays
disabled
until the lead approves its policy; reprocessing is a production run
with auto-promote off.

**Promotion.** The default deliverable list is every candidate instance
the run produced through its unit's selected attempt, one per kind and
logical key; intermediate revisions and unselected attempts are
excluded, and two candidates for the same key refuse the promotion,
since a promotion needs exactly one replacement instance per kind and
logical key (supervisor step 3, 2026-09-24). Piecemeal promotion names
an explicit subset of that list and passes the same validation. A
change may also name no replacement, unselecting a key: the replaced
instance returns to candidate, and the promotion record's after-instance
for that key is null (supervisor step 3, 2026-09-24). Promotion
replaces only identical kind-and-logical-key selections; different
settings or upstream instances produce additional current products
rather than supersede earlier ones. A reprocessing with changed
settings therefore sits beside the old result as a new instance, per
the products page's keys, rather than superseding it. Only a
production run's outputs can be promoted; scratch never leaves scratch.
On rows a run wrote, `vbest` is a current-membership flag: 1 while the
instance is current, 0 otherwise. Rows `dev` wrote, with `run` null,
including those an import run links through `instance`, keep `dev`'s
own flag. A mapped kind whose instance has no row refuses the
promotion (lead, 2026-09-22; restated by the supervisor, step 3,
2026-09-24). All promotions
take one transaction-scoped advisory lock; after acquiring it the
transaction checks every expected previous selection, including
expected absence, against the actual selection and refuses the whole
request on any mismatch, then validates dependencies, updates custody
and records the action. Each promotion records a before and after
instance for every affected key, either nullable. Reversal is itself a
promotion, carrying the inverse mapping and
`request_context.rollback_of`, and is refused if the recorded
after-selection is no longer current (supervisor step 3, 2026-09-24).

**Deletion.** `run delete` is allowed on a scratch run by its owner,
finished or not: a finished run admits no new unit, attempt or input
binding, but that alone does not block its deletion (supervisor step 3,
2026-09-24). It first locks the run, verifies the owner, refuses if any
attempt is queued, running or unresolved, if any frozen input binding
of unfinished work or any provenance dependency of a retained output
outside the run points into it, or if a row in `refimimages`,
`refimcatalogs`, `refimmeta` or `xsources` references one of the run's
rows (those tables are not in the cleanup set below, so such a
reference refuses the whole delete rather than leaving an orphan;
supervisor step 3, 2026-09-24), and marks the run deleting, in one
transaction. Attempt allocation, input binding and result acceptance
use the same run fence and refuse a deleting or deleted run.

Before touching storage, every attempt's output location must lie in
the scratch bucket under `runs/<run-id>/`; otherwise the whole delete
is refused. Cleanup then removes the run's object versions; a storage
delete that reports a per-object error leaves the run deleting and
touches no row, so a retry resumes at storage. Once storage cleanup is
clean, one transaction removes the science rows, marks the run's
instance rows deleted (`deletion_state`) and marks the run deleted
(supervisor step 3, 2026-09-24). The science-row cleanup set is
`l2files`, `l2filemeta`, `refimages`, `diffimages`, `diffimmeta`,
`psfs` and `sources` (the parent delete reaches the children), each
where the `run` column equals the run being deleted; `l2files` and
`l2filemeta` join the set because a scratch run's admitted rows are
its own, and the fence already refuses when another run binds them
(supervisor step 3, 2026-09-24). Rows with `run` NULL, which is
everything `dev` wrote, are never touched (lead, 2026-09-23). Failure
before the final transaction leaves the run deleting, and re-running
cleanup on a deleting run resumes it from wherever it stopped
(supervisor step 3, 2026-09-24). Custody stays separate from deletion
state. Run, unit, attempt and instance rows remain as tombstones with
their provenance. Scratch expiry calls the same operation after the
run's expiry date, with a warning first and a pin to hold a run.

## Storage layout

Two buckets separate personal and project custody: `s3://roman-rapid-scratch/rapidpipe`
for scratch runs, `s3://roman-rapid-products/rapidpipe` for production
runs. The launcher chooses the root from the run's kind at submission.
A scratch run reads `RAPIDPIPE_OUTPUTS_ROOT_SCRATCH`, falling back to
`RAPIDPIPE_OUTPUTS_ROOT` when it is unset. A production run requires
`RAPIDPIPE_OUTPUTS_ROOT_PRODUCTION`; it never falls back to the
unsuffixed variable, which is the scratch fallback only (supervisor
step 3, 2026-09-24). Runs written under `rapidpipe-firstrun/` before
2026-09-24 stay where they were written; their attempt rows carry that
location rather than moving to the new root (supervisor step 3,
2026-09-24). Candidate and current objects share the project bucket and
never move at promotion. Ordinary execution roles cannot delete
completed objects; only the cleanup role deletes, and only through
`run delete`. Within either bucket:

```
runs/<run-id>/<stage>/<unit-id>/<attempt-id>/manifest.json
runs/<run-id>/<stage>/<unit-id>/<attempt-id>/<member paths from the manifest>
```

Admitted inputs and reference images live under the same scheme in the
project bucket, in the run that admitted or built them. Consumers read
current products through the selection, never by guessing paths. Alert
containers follow the same scheme; the outbox row carries the
container's location and each alert's block locator, the offset and
size of the Avro block holding its record plus the record's position
within that block and within the container, since Avro compresses
records per block and a single record has no byte range of its own
(supervisor step 2, 2026-09-24; the [alerts](alerts) page has
the outbox's full column list).

Each kind runs under its own Batch job definition. Scratch runs use
`rapid-rebuild`, whose job role can write only the scratch bucket;
production runs use `rapid-rebuild-production`, whose job role can
write `rapidpipe/*` of the products bucket and never delete, and also
reads the scratch bucket's `rapidpipe*` prefixes, where staged inputs,
settings overlays and input-set manifests live today (supervisor step
3, 2026-09-24). A scratch run reads `RAPIDPIPE_BATCH_JOB_DEFINITION_SCRATCH`,
falling back to `RAPIDPIPE_BATCH_JOB_DEFINITION` when it is unset. A
production run requires `RAPIDPIPE_BATCH_JOB_DEFINITION_PRODUCTION`; it
never falls back to the unsuffixed variable (supervisor step 3,
2026-09-24).

Deletion runs under different credentials than execution. `run delete`
runs launcher-side, under the caller's own credentials, not a Batch
job's. On rapid-rusholme, the instance role holds `rapid-scratch-cleanup`,
which can delete object versions under the scratch bucket's
`rapidpipe*/runs/*` prefix and nothing else; the deletion code itself
refuses to touch any object outside the scratch bucket. A dedicated
cleanup principal for workstation submission is a later step
(supervisor step 3, 2026-09-24).

## Identifiers

Runs, attempts and product instances receive globally unique,
time-ordered identifiers (ULID) before execution or manifest
publication, allocated by whoever creates the row, so the local runner
and the Batch wrapper need no database to allocate; registration
preserves them. Date-and-sequence names such as `r-20260921-007` are
display labels only. Unit identity is unique within a run and stage and
uses the product vocabulary's unit identifiers.

## Schema

The run-model tables above land as one migration beside the baseline.
The additive columns and widened keys on the `dev` product tables land
one kind at a time, difference image first, each with the stage that
writes it. Ruled by the lead 2026-09-21: the `dev` schema coexists and is
kept as far as possible; the rebuild adds, it does not rename or drop.

## Trial database

A scratch run's `database target` may name a trial database instead of
the one production database. A trial database lives on the production
PostgreSQL instance, beside `rapid`, created with rapid's own schema:
it is not a separate server or a clone. rapid's own migration applier
(`database/apply-migrations.sh`, `database/migrations/`, files named
`YYYYMMDD-NN-name.sql`) builds and updates it, run inside the pipeline
container image; the applier records each applied file's sha256 and an
applied migration is never edited. Clients reach a trial database
through the pooler: pgbouncer routes any database name to the one
PostgreSQL port (a wildcard `[databases]` entry), so adding a trial
database needs no pooler config change. The pipeline authenticates as a
per-tier service login (for example `rapid_rebuild_pipeline`) holding
SELECT/INSERT/UPDATE/DELETE on the trial database's tables, granted by
guarded migrations in rapid's own stream (they no-op where the role
does not exist, so CI still applies the stream from empty); people read
it through `rapid_read`. That role's identity — its NOLOGIN cluster
role, its secret and its SSM tree — is provisioned separately, by the
system repo's own migration stream, since the role itself is
cluster-wide and rapid's stream owns only the trial database's tables.
A job definition's `RAPID_PARAMETER_PATH` selects the tier: it points
at an SSM tree `/rapid/<tier>/db/*` (name, host, port, secret id) that
resolves the trial database's name, host and port, with the service
login's password in Secrets Manager under
`rapid/db/service/<tier>-pipeline`. Each tier runs under its own Batch
job definition, revision-pinned to an image digest. Practised
2026-09-22/23: trial database `rapid_rebuild`, service login
`rapid_rebuild_pipeline`, tree `/rapid/rebuild`, job definition
`rapid-rebuild`. A run created under a release submits to the revision
that release's record deployed for the run's kind, not whatever
revision the job definition currently pins (the [releases](releases)
page has the mechanism; supervisor step 5, 2026-09-24).

## Python interface

`rapidpipe.runs`, in its `repository` and `cleanup` modules, and
`rapidpipe.launch.batch` are the interface the command-line tool and
the scheduler build on, as the specification's Tools section names them
(supervisor step 3, 2026-09-24).

| Function | Does |
|---|---|
| `create_run(conn, kind, owner, purpose, selected_stages, code_revision, image_digest, schema_version, settings_overlay_ref, input_selection_ref, lane, resource_profile, database_target, max_attempts_per_unit, auto_promote, check_policy_ref, seed_run=None, expires_at=None) -> run_id` | Inserts the run row and returns its id. |
| `submit_unit(conn, *, run_id, stage, unit_kind, unit_id, inputs_location, settings_location=None, outputs_root=None, job_definition=None, client=None) -> BatchSubmission` | Starts one unit on Batch; when not given, the outputs root and job definition are resolved from the run's kind, production failing closed if its configuration is missing rather than falling back to scratch's. |
| `reconcile(conn, run_id, ...)` | Records the attempts Batch has finished since the last call and selects among them. |
| `cancel(conn, *, attempt_id, reason)` | Terminates a queued or running attempt. |
| `promote(conn, who, reason, changes, check_policy_version=None, check_result_ids=(), request_context=None) -> promotion_id` | Runs one promotion from an explicit `changes` list of `(kind, logical_key, expected_before, after)`, either instance nullable. |
| `promote_run(conn, run_id, who, reason, *, kinds=None, check_policy_version=None) -> promotion_id` | Builds the run's default deliverable list, optionally narrowed to `kinds`, and calls `promote` with it. |
| `rollback_promotion(conn, promotion_id, who, reason) -> promotion_id` | Submits a past promotion's inverse mapping as a new promotion. |
| `finish_run(conn, run_id) -> None` | Marks a run finished; refuses unless every unit is terminal. |
| `mark_run_deleting(conn, run_id, requested_by, *, expiry=False) -> None` | The deletion fence: locks the run, runs the pre-deletion checks, and marks it deleting. `delete_run` calls it first; `expiry=True` marks the caller as the expiry sweep rather than the run's owner. |
| `delete_run(conn, run_id, requested_by, *, s3_client=None, scratch_bucket=None, expiry=False) -> DeletionReport` | Runs guarded deletion on a scratch run, committing internally rather than inside the caller's transaction; the report lists the objects, versions and per-table rows removed and the instances marked deleted. |
| `expire_runs(conn, *, now=None, s3_client=None) -> list[DeletionReport]` | Calls `delete_run` with `expiry=True` for every unpinned scratch run past its `expires_at`. |
| `pin_run(conn, run_id, pinned) -> None` | Sets or clears a run's `pinned` flag. |

The command-line tool's `run create`, `submit`, `reconcile`, `cancel`,
`promote`, `rollback`, `delete`, `finish`, `pin` and `unpin` are thin
wrappers over these (supervisor step 3, 2026-09-24). Its shape is on the
[tool](tool) page, which adds `run start`, `run status`, `run inputs`,
`run compare` and `run expire` over these same functions (supervisor
step 4, 2026-09-24).

## Not decided here

- The approved check policy that turns auto-promote on.
- The scratch expiry warning mechanics.
