# Runs, attempts and custody

**Status: DRAFT**

Runs, units of work, attempts, product instances, result sets and the
three custody states have database records and storage locations. This
page defines them, alongside the specification's Runs section, the
[stage contract](stage-contract) and the [products](products) page.

## In plain terms

A run records who started a pass over which inputs, with which code
and settings, and whether the outputs belong to a person or the
project. Each piece of work is a unit; each try is an attempt with its
own output folder. Every product a finished attempt makes, whether a
file or database rows, has an instance row. Its custody state says
whose it is and whether consumers see it.

Promotion changes those rows under one lock and records the changes
so they can be undone. Files never move. Scratch-run deletion is one
guarded operation; nothing else deletes run data.

## Tables

| Table | One row per | Key columns |
|---|---|---|
| `runs` | run | id, kind (`scratch`, `production`), owner login, created, state (`open`, `finished`, `deleting`, `deleted`), purpose, selected stages, code revision, image digest, release, schema version, settings overlay ref, input selection ref, lane, resource profile, database target, max attempts per unit, auto-promote flag, check-policy ref, seed run, expires at, pinned, deleted at |
| `units` | piece of work in a run | run, stage, unit kind, unit id, state (`pending`, `ready`, `running`, `complete`, `failed`, `cancelled`), selected attempt, cancel reason, seeded-from unit |
| `unit_inputs` | frozen input binding | unit, producer instance |
| `attempts` | execution of a unit | id, run, stage, unit, started, ended, exit code, disposition (null while queued or running; `succeeded`, `failed`, `transient`, `killed`, `lost`), output location, inputs location, settings location, execution record, scheduler job id |
| `execution_records` | attempt | attempt, source revision, working-copy patch, image digest, release, schema version, resolved settings, settings hash, scheduler metadata; contents stored, not referenced into the run prefix |
| `product_instances` | product an attempt made, file or result set | instance id, kind, provenance key, slot, identity (the latter two nullable, database-derived; [products](products) page), run, producing stage, producing attempt, registering attempt, custody (`scratch`, `candidate`, `current`), format version, primary location, manifest ref, published at, deletion state |
| `product_members` | file in a bundle | instance, role, path, bytes, sha256 |
| `result_sets` | one-to-one extension of an instance that is rows | instance, complete flag, row count |
| `promotions` | promotion action | id, who, when, reason, check-policy version, check result ids, request context |
| `promotion_changes` | affected slot, or provenance key for a legacy row, in a promotion | promotion, kind, provenance key, slot (nullable), before instance (nullable), after instance (nullable) |
| `checks` | verification result | instance, check name, version, required flag, outcome, when, detail |
| `dependencies` | provenance edge | consumer instance, producer instance |

The `dev` schema's product tables (`l2files`, `refimages`, `diffimages`,
`sources`, `merges`, `astroobjects`, `astroobjectsmeta` and their
companions) are kept with their names and columns. Each gains `run`,
`attempt` and `instance` (or `result_set`) columns, and where a
uniqueness constraint would block two runs holding the same logical
product it is widened to include the run or set. Nothing is renamed and
nothing is dropped.

## Runs

A run's kind and input selection are fixed at creation. Scratch runs
make scratch outputs; production runs make candidates. Production uses
the one production database, while scratch runs may name a trial
database. A run may bind another run's complete current result-set
instance as a frozen input. The dependency retains that instance, so
the binding stays valid after supersession. Scratch result sets are
usable only within their own run.

A run is eligible to finish once every unit is terminal. Finishing
requires an explicit `finish`; a finished run is never reopened.
Seeding copies configuration and permitted input selections without
authorising reuse of another run's scratch outputs. A run created by
the processing-date loop takes its owner from the spec and records the
spec's location as its `input_selection_ref`. A loop promotion records
`who = scheduler` (the [loop](loop) page).

### Recovery from a seed

`run create --seed <run> --only-failed` creates a recovery run. What it
copies depends on the seed's kind. For a production seed, it copies
the release (or code revision and image digest), settings and input
refs, lane, resource profile, database target, max attempts and
check-policy ref. It sets `purpose` to name the seed it recovers and
takes `selected_stages` from the seed's list, starting at the earliest
stage with a non-complete unit: `failed`, `cancelled`, or `running`
with a job-less or `lost` attempt.

At that stage and every later one, each non-complete seed unit becomes
a new `pending` unit carrying `units.seeded_from_unit` and a copy of
its frozen `unit_inputs`. Each copied binding names the same producer
instance, protected by the existing deletion fence like any frozen
input of unfinished work. `run start` skips stages the seed completed
and goes straight to the seeded units.

A scratch seed's recovery run recreates every unit from the first
stage. It carries over only that stage's inputs and settings; later
stages must regenerate their inputs within the new run, as in a fresh
run. Recovery refuses with exit 64 if the seed has no non-complete
unit or is deleting or deleted. `--only-failed` without `--seed` is a
usage error.

### Expiry

Scratch runs receive a default `expires_at` of fourteen days after
creation. `pinned` holds a run past that date. The expiry sweep deletes
unpinned scratch runs past their `expires_at` through the same
operation as `run delete`. It acts under explicit authorisation,
rather than as the run's owner. Under the run lock, it re-checks kind,
pin and expiry and refuses deletion if any condition no longer holds.
The warning mechanics are not decided here.

## Units

A unit is pending until its declared input set is complete and its
upstream attempts are selected. It then becomes ready, and running
when an attempt is allocated. Selecting a successful completed attempt
makes it complete. A retryable failure returns it to ready while
attempts remain; otherwise it becomes failed. Cancellation or a
permanently failed required dependency cancels an unstarted unit with
a recorded reason. Complete, failed and cancelled are terminal. Unit
state is stored, not derived. Inputs are bound in `unit_inputs` before
execution and retained for retries.

`register`'s unit id is `<producing stage>/<producing unit id>`, for
example `admit/e20260821001234/SCA07` or
`difference/e20260821001234/SCA07`, derived from the manifest
`register` reads. One `register` unit follows every producer, with no
occurrence counter, and is runnable singly for one producer at a time.
Rows written under an earlier unit-id form stay unchanged.

A unit created by `run create --seed <run> --only-failed` carries
`units.seeded_from_unit`, identifying the seed unit it re-runs. It
enters the same state machine as an ordinary new `pending` unit.

## Input binding and composition

A stage declares its input set by product kind and role. The launcher
resolves each entry from this run's own instance of that kind for the
unit first, then from the run's frozen input selection. It uses
`dev`'s selection rules: the current reference by field and filter,
and the current PSFs by filter and detector. It never resolves an entry
from an unrelated run unless the selection explicitly names that
instance.

The binding is written to `unit_inputs` before execution, and the
stage's input manifest is generated from it. Hand-composed manifests
are a test path; production runs assemble inputs through the launcher.

### Submission

Before any submission write (`run submit`, `run start`, `run local`),
the launcher reads `manifest.json` at the local or `s3://` `--inputs`
location. It collects every output entry's `instance` and every
`inputs.result_sets` entry. It excludes `inputs.products`, which
names what the upstream attempt read rather than this unit's inputs.
It then creates the unit, binds the registered product instances
through `bind_unit_inputs`, commits both together and allocates the
attempt.

Unregistered names, such as a delivery manifest or dev-era template
entry, bind nothing and are logged rather than refused. An absent,
invalid or unreadable manifest refuses submission before any write:
exit 75 for a network error, exit 65 otherwise. Binding is idempotent
per (unit, instance): a retry and a seeded `--only-failed` re-run both
re-read the manifest and bind nothing new.

Binding takes each producer instance's run row for share and refuses
with exit 65 if that run is deleting or deleted, as
`register_manifest` does. An uncommitted binding therefore holds the
producer's run against deletion. The fence also covers `run inputs`
and the loop's binding. These bindings are the deletion guard's basis.

### Composition

One primitive backs `run inputs`, `run start`'s `compose_inputs` and
the loop's maintain, crossmatch and alerts composers:
`rapidpipe.runs.binding.bind_input_set(conn, storage, *, run_id, stage,
unit_kind, unit_id, dest, compose, reuse_existing=True)`. Submission-time
binding (`run submit`, `run start`, `run local`, through
`bind_registered_inputs`) remains a separate path, sharing only the id
rule with the primitive.

The primitive first checks whether `manifest.json` exists at `dest`.
`run inputs` refuses reuse with exit 64; `run start` and the loop reuse
it. Next, `add_unit` admits the unit through the run fence. This is the
first write-side check, before copying anything, reading template or
producer manifests, or parsing an existing manifest. A finished,
deleting or deleted run is therefore refused with exit 64 before its
inputs are inspected.

The composer reads the existing manifest or calls its `compose`
callable to copy inputs and build one. The `manifest_instances` rule
collects every output entry's `instance` plus every
`inputs.result_sets` entry. The composer binds registered instances
through `bind_registered_inputs`, commits, then writes the manifest to
storage only if it did not already exist. Reuse commits an idempotent
re-bind of the existing manifest's ids to the consuming unit without
rewriting the manifest. A stored manifest therefore means its bindings
were committed. If the write fails after commit, the next call finds
no manifest and composes again.

Both `compose_inputs` and the loop's composer call this primitive; a
test fails if either binds or writes a manifest independently. Thus
`run inputs` binds a template's `inputs.result_sets` and output
entries, and exits 65 if a producer is deleting or deleted at binding.

## Attempts and retries

Each try has a fresh attempt id and an exclusive output location. An
attempt has no disposition while queued or running. Success requires
a valid completion manifest and complete declared outputs; exit zero
alone is insufficient. Selection locks the unit row and atomically
sets its selected attempt and complete state. The selected attempt
belongs to that unit and never changes. Late results cannot reopen a
terminal unit or replace its selection.

The run records a maximum attempts per unit, counting the first try
and every retry. The launcher retries; a Batch job runs its container
once. An attempt ending `transient` returns the unit to ready for
submission as a new attempt. Once one of a unit's attempts is lost to
a Spot reclaim, in the run or in a run it was seeded from, every
further attempt of that unit is submitted to the reclaim queue
(`RAPIDPIPE_BATCH_RECLAIM_QUEUE`) when that is set and differs from
the job queue; otherwise it goes to the job queue like any other
retry. Only code 75 and the approved
infrastructure failures listed in the [stage contract](stage-contract),
"Exit codes", are recorded `transient`. Exhausting the allowance fails
the unit. `lost` means the scheduler lost the job: unresolved
execution, treated as a possible writer until resolved.

`submit_unit` records the resolved input-set and settings locations on
`attempts.inputs_location` and `attempts.settings_location`, alongside
the frozen bindings in `unit_inputs`.

### Job-less attempts

`run reconcile --resolve-jobless [--older-than
SECONDS]`, default 600 seconds, first looks for a scheduler job under
the attempt's deterministic job name. Exactly one match repairs the
attempt by recording the job id; an ambiguous match is left alone.
Once past that age, an attempt with no disposition, scheduler job or
repair is locked and recorded as `lost`, with a null exit code and a
reconcile note explaining why. Its unit returns to `ready` if attempts
remain under the allowance, or `failed` otherwise. This resolves
job-less running attempts instead of leaving them open indefinitely.

### Reusing result sets

A database-writing stage's `done_check` decides whether to reuse a
complete result set or write a new one. It checks the producing
attempt's disposition as well as completeness. Reuse requires a
complete, retained set in this run with the same kind and provenance
key, produced either by the calling attempt or by an attempt whose
disposition is `succeeded`.

A set left by an attempt that committed rows and then failed, or by
another attempt still without a disposition, is not reused. The retry
writes a new set under its own instance. The orphaned rows remain the
run's own until deletion, but are unreachable because their producer
is never the selected attempt.

`load`'s, `crossmatch`'s, `statistics`' and `prune`'s `done_check`
all use this rule through `db/sources.find_complete_source_set` and
`db/objects.find_complete_result_set`. Both join `attempts` for the
producing attempt's disposition; the per-stage pages record each
`done_check`'s key.

## Instances and custody

`register` preserves the instance ids and producing run, stage and
attempt from the manifest, recording the registering attempt
separately. Replaying an identical manifest is a no-op; conflicting
content for an existing instance id is an error. Database-writing
stages create their own attempt-scoped result-set instances and record
completion, including empty completion. After an uncertain commit, the
same attempt recovers its recorded results instead of inserting
duplicates.

Published identity, content metadata and provenance are immutable.
Custody and deletion metadata change only through promotion and
deletion. Scratch never leaves scratch. Promotion makes a candidate
current; supersession returns it to candidate.

A product registered by `dev` enters the run model through an import
run: `reference-import` for a reference, `psf-import` for a PSF. Each
is a production run whose one unit registers the product with its own
run, attempt and instance. The instance is a candidate in project
custody and can be named as a frozen input. Production runs that
depend on it can therefore be promoted: `dev`'s registered products
belong to the project, while a scratch import would refuse every
dependent production promotion.

Two partial unique indexes govern current selection. One allows at
most one current instance per kind and provenance key across all
current rows. The other allows at most one per kind and slot wherever
the fill has resolved a slot ([products](products) page). Current
selection is a view over the instance table, covering file products
and result sets alike. A consumer resolves a related selection from
one database snapshot.

## Promotion

### Eligibility

Automatic and manual promotion require completed, selected outputs,
a recorded image digest identifying a released artifact, and passing
results for every required check under the resolved check-policy
version. Policy resolution uses an explicit `--check-policy`, then the
run's `check_policy_ref`, then the default `rebuild-trial@1`. There is
no unchecked exception: every deliverable of a kind the policy covers
passes the gate ([checks](checks) page). Missing or failed required
checks refuse promotion with exit 1.

Every provenance dependency, followed to its roots through the whole
chain, must be `current`, `superseded`, or an after-instance of the
same promotion request that passes validation in its own right.
Anything else refuses promotion with exit 1, naming the ancestor and
its state ([checks](checks) page has the states and walk). `run show`
ends its listing with a `state:` block, one line per candidate or
current instance in those states, after `units:`, `attempts:` and any
`promotions:` ([checks](checks) page has the format).

The replacement's kind and slot must match the requested selector.
It must be retained, and a result set must be complete
([products](products) page has the identity). Every deliverable's
selected producing attempt must have an execution record whose image
digest belongs to a complete release. Otherwise promotion is refused
unless the operator passes the explicit unreleased exception
(the [releases](releases) page has the record and check). Automatic
promotion stays disabled until the team approves its policy.
Reprocessing is a production run with auto-promote off.

### Selecting replacements

`promote_run` first fills the run's rows through
`product_identity_fill()` ([products](products) page). A candidate
registered before its slot resolved is therefore not refused for that
alone. The default deliverable list contains every candidate the run
produced through its unit's selected attempt, grouped by (kind, slot).
It excludes intermediate revisions and unselected attempts.

A candidate whose slot or identity remains null is refused by name:
a slot never exists without its identity ([products](products) page).
Two candidates sharing a slot are refused because each (kind, slot)
needs exactly one replacement. Piecemeal promotion names an explicit
subset of the list and passes the same validation.

A change may withdraw a slot by naming no replacement. The replaced
instance returns to candidate, and the promotion record's after-instance
is null. Expected-before for a slot is its current instance, or none.
A current instance with a null slot is invisible to slot promotion:
it can be neither replaced nor withdrawn until an operator resolves it
by hand.

A replacement supersedes its predecessor whenever they share (kind,
slot), regardless of differing settings or upstream instances.
Reprocessing with changed settings therefore replaces old difference
images in their slots instead of adding instances beside them.

### Frozen plans

`run promote-plan <run>` reads the run's slot groupings under the lock
and prints them without writing anything. Later,
`run promote <run> --plan <file>` applies that file under a fresh lock.
It refuses with exit 1, naming the first slot whose actual current
instance or candidate no longer matches the plan, and writes nothing
([tool](tool) page has the commands).

The plan file must contain a non-empty JSON list of
`{kind, slot, before, after}` entries. A JSON `null`, an empty list or
any other shape exits 64 before the file is read as a plan or anything
is written.

### Applying changes

A change into an `association-set` slot with a non-null expected-before
is refused unless that instance is an ancestor of the after-instance,
following the provenance key's `base` field. This prevents a live
batch from replacing a reprocessing campaign's chain head with its
own older chain. Rollback's recorded inverse is the sole exception:
it undoes a change that already passed this rule.

Ordinary slot replacement cannot substitute for the chain switch
operations.md describes, the promotion that moves a whole stream
between catalog chains. That switch is not built, and nothing writes
`loop_dates.kind = 'switch'`.

Only production outputs can be promoted; scratch never leaves
scratch. On rows a run wrote, `vbest` is 1 while the instance is
current and 0 otherwise. Rows `dev` wrote with `run` null keep
`dev`'s flag, including rows an import run links through `instance`.
A mapped kind whose instance has no row refuses promotion.

Every promotion takes one transaction-scoped advisory lock. Under it,
the transaction checks all expected previous selections, including
expected absence, against the actual selection. Any mismatch refuses
the whole request. It then validates dependencies, updates custody and
records the action. Each affected slot has a before and after instance,
either nullable; `promotion_changes` stores the slot alongside the
provenance key.

### Rollback

Rollback inverts the exact recorded change by slot: the recorded
after-instance becomes the expected before, and the recorded
before-instance, possibly null, becomes the new after. A change
recorded before slot identity, with no slot, is refused as not
reversible ({ref}`legacy compatibility ruling
<decision-legacy-compatibility>`); every promotion `rapid_rebuild` has
made was recorded after slot identity, so this refusal is reachable
only against a disposable database.

Reversal is itself a promotion, carrying the inverse mapping and
`request_context.rollback_of`. It is refused if the recorded
after-selection is no longer current. `promote()` accepts only a slot
selector; anywhere else, a selector naming an instance whose own slot
is null is refused.

## Deletion

### Guarding the run

An owner may `run delete` a scratch run whether or not it is finished.
A finished run admits no new unit, attempt or input binding, but can
still be deleted. In one transaction, deletion locks the run, verifies
the owner, checks for blockers and marks the run deleting.

Deletion is refused if:

- An attempt is queued, running or unresolved, meaning it has no
  disposition.
- A frozen input binding of unfinished work or a provenance dependency
  of a retained output outside the run points into it.
- A row in `xsources` references one of the run's rows. That table is
  outside the cleanup set, so deletion would leave an orphan.
- A row in `refimimages`, `refimcatalogs` or `refimmeta` belonging
  to another run's reference points to one of this run's rows. Its own
  reference's satellite rows are removed during cleanup.

`lost` is a recorded resolution of uncertainty. Reconcile writes it
only after the scheduler no longer returns the job, or after
`run reconcile --resolve-jobless` finds no job under the attempt's
name. A `lost` attempt therefore does not by itself block deletion.
Attempt allocation, input binding and result acceptance use the same
run fence and refuse a deleting or deleted run.

The guard counts only live consumers outside the run. A `unit_inputs`
binding counts only when its unit's run is not `deleted`; a
`dependencies` edge counts only when the consumer instance's
`deletion_state` is not `deleted`. Tombstones are never removed.
A consumer run still `deleting` blocks deletion of its producer's run
until the consumer finishes deleting. `run delete` refuses with exit 64.

Bindings recorded through `bind_unit_inputs` before an attempt starts
make the unit a live consumer immediately. The deletion guard sees it
before it produces any output, which makes submission-time binding
safe.

### Storage and row cleanup

Before storage is touched, every attempt's output location must lie in
the scratch bucket under `runs/<run-id>/`; otherwise the whole delete
is refused. Cleanup removes the run's object versions first. A
per-object storage deletion error leaves the run deleting and touches
no row; a retry resumes at storage.

After clean storage removal, one transaction removes the science rows,
marks the instance rows deleted (`deletion_state`) and marks the run
deleted. The science-row cleanup set is `l2files`, `l2filemeta`,
`refimages`, `diffimages`, `diffimmeta`, `psfs` and `sources`
(the parent delete reaches the children), each where `run` equals the
run being deleted. `l2files` and `l2filemeta` are included because a
scratch run owns its admitted rows, and the fence already refuses
deletion when another run binds them.

`refimimages`, `refimcatalogs` and `refimmeta` have no `run` column:
they are reached through the `refimages` row's `rfid`. The same
transaction joins them through this run's `refimages` rows and deletes
them before those parent rows. Another run's reference is untouched;
the guard prevents deleting rows it references. Rows with `run` NULL,
everything `dev` wrote, are never touched.

Failure before the final transaction leaves the run deleting.
Re-running cleanup resumes where it stopped. Custody stays separate
from deletion state. Run, unit, attempt and instance rows remain as
tombstones with their provenance. Scratch expiry calls the same
operation after the expiry date, with a warning first and a pin to
hold a run.

## Storage layout

Two buckets separate personal and project custody:
`s3://<scratch-bucket>/rapidpipe` for scratch runs and
`s3://<products-bucket>/rapidpipe` for production runs. At submission,
the launcher chooses the root from the run's kind. Scratch reads
`RAPIDPIPE_OUTPUTS_ROOT_SCRATCH`, falling back to
`RAPIDPIPE_OUTPUTS_ROOT` when unset. Production requires
`RAPIDPIPE_OUTPUTS_ROOT_PRODUCTION` and never falls back to the
unsuffixed variable.

Runs written under `rapidpipe-firstrun/` stay there; their attempt
rows retain that location. Candidate and current objects share the
project bucket and never move at promotion. Ordinary execution roles
cannot delete completed objects. Only the cleanup role deletes, and
only through `run delete`. Within either bucket:

```
runs/<run-id>/<stage>/<unit-id>/<attempt-id>/manifest.json
runs/<run-id>/<stage>/<unit-id>/<attempt-id>/<member paths from the manifest>
```

Admitted inputs and reference images use this scheme in the project
bucket, in the run that admitted or built them. Consumers read current
products through the selection, never by guessing paths. Alert
containers use the same scheme. The outbox row holds the container's
location and each alert's block locator: the offset and size of its
Avro block, plus the record's position within the block and container.
Avro compresses records per block, so a single record has no byte range
of its own (the [alerts](alerts) page has the outbox's full column list).

### Execution and cleanup credentials

Each run kind has its own Batch job definition. Scratch uses
`rapid-rebuild`, whose job role writes only to the scratch bucket.
Production uses `rapid-rebuild-production`, whose job role can write
`rapidpipe/*` in the products bucket but never delete. It also reads
the scratch bucket's `rapidpipe*` prefixes, which hold staged inputs,
settings overlays and input-set manifests.

Scratch reads `RAPIDPIPE_BATCH_JOB_DEFINITION_SCRATCH`, falling back to
`RAPIDPIPE_BATCH_JOB_DEFINITION` when unset. Production requires
`RAPIDPIPE_BATCH_JOB_DEFINITION_PRODUCTION` and never falls back to the
unsuffixed variable.

`run delete` runs launcher-side under the caller's credentials, not a
Batch job's. On a workstation, the instance role holds
`rapid-scratch-cleanup`, which can delete object versions only under
the scratch bucket's `rapidpipe*/runs/*` prefix. The deletion code
refuses any object outside the scratch bucket. The [tool](tool) page
names the dedicated cleanup principal for workstation submission.

## Identifiers

Runs, attempts and product instances receive globally unique,
time-ordered identifiers (ULID) before execution or manifest
publication. Whoever creates the row allocates the id; the local
runner and launcher need no database for allocation, and registration
preserves it. Date-and-sequence names such as `r-20260921-007` are
display labels only. Unit identity is unique within a run and stage
and uses the product vocabulary's unit identifiers.

## Schema

The run-model tables land as one migration beside the baseline.
Additive columns and widened keys on the `dev` product tables land
one kind at a time, difference image first, with the stage that writes
each kind. The `dev` schema coexists and is kept as far as possible;
the rebuild adds without renaming or dropping.

## Trial database

A scratch run's `database target` may name a trial database instead of
the one production database. A trial database lives beside `rapid`
on the production PostgreSQL instance, built with rapid's own schema.
It is neither a separate server nor a clone.

rapid's migration applier (`database/apply-migrations.sh`,
`database/migrations/`, files named `YYYYMMDD-NN-name.sql`) builds
and updates it from inside the pipeline container image. The applier
records each file's sha256; an applied migration is never edited.
Clients connect through pgbouncer, whose wildcard `[databases]` entry
routes any database name to the one PostgreSQL port. Adding a trial
database therefore needs no pooler config change.

The pipeline authenticates as a per-tier service login, for example
`rapid_rebuild_pipeline`, with SELECT/INSERT/UPDATE/DELETE on the trial
database's tables. Guarded migrations in rapid's stream grant these
permissions; they no-op where the role does not exist, so CI can apply
the stream from empty. People read through `rapid_read`. That role's
identity (its NOLOGIN cluster role, secret and SSM tree) is provisioned
separately by the system repo's migration stream: the role is
cluster-wide, while rapid's stream owns only the trial database's tables.

A job definition's `RAPID_PARAMETER_PATH` selects the tier. It points
at the SSM tree `/rapid/<tier>/db/*` (name, host, port, secret id),
which resolves the trial database's name, host and port. The service
login's password is in Secrets Manager under
`rapid/db/service/<tier>-pipeline`. Each tier has its own Batch job
definition, revision-pinned to an image digest. The rebuild tier uses
database `rapid_rebuild`, service login `rapid_rebuild_pipeline`,
tree `/rapid/rebuild` and job definition `rapid-rebuild`.

A run created under a release submits to the revision that release's
record deployed for the run's kind, regardless of what revision the
job definition currently pins (the [releases](releases) page has the
mechanism).

## Python interface

`rapidpipe.runs`, in its `repository`, `cleanup` and `checking` modules,
`rapidpipe.launch.batch`, and `rapidpipe.checks.policy` are the
interface the command-line tool and the scheduler build on, as the
specification's Tools section names them.

| Function | Does |
|---|---|
| `create_run(conn, kind, owner, purpose, selected_stages, code_revision, image_digest, schema_version, settings_overlay_ref, input_selection_ref, lane, resource_profile, database_target, max_attempts_per_unit, auto_promote, check_policy_ref, seed_run=None, expires_at=None) -> run_id` | Inserts the run row and returns its id; validates that `check_policy_ref` names a real policy and refuses `auto_promote` unless that policy permits it (`CheckPolicyRefused`). |
| `submit_unit(conn, *, run_id, stage, unit_kind, unit_id, inputs_location, settings_location=None, outputs_root=None, job_definition=None, client=None) -> BatchSubmission` | Binds the unit's inputs (`bind_unit_inputs`, below) before allocating the attempt, then starts it on Batch; when not given, the outputs root and job definition are resolved from the run's kind, production failing closed if its configuration is missing rather than falling back to scratch's; records the resolved `inputs_location`/`settings_location` on the attempt. |
| `bind_unit_inputs(conn, *, unit_id, manifest) -> list[str]`, in `rapidpipe.runs.repository` | Writes a `unit_inputs` row for every `instance` the manifest names, in `inputs.products` and `inputs.result_sets`, that is a registered product instance; a name that resolves to no instance binds nothing and is logged, not refused; called by `submit_unit` and `run local` before allocating the attempt. |
| `reconcile(conn, run_id, ...)` | Records the attempts Batch has finished since the last call and selects among them. |
| `cancel(conn, *, attempt_id, reason)` | Terminates a queued or running attempt. |
| `promote(conn, who, reason, changes, check_policy: Policy \| None = None, request_context=None, *, allow_unreleased=False) -> promotion_id` | Runs one promotion from an explicit `changes` list of `(kind, selector, expected_before, after)`, either instance nullable; `selector` is `{"slot": {...}}`. Validated under `check_policy` ([checks](checks) page). |
| `promote_run(conn, run_id, who, reason, *, kinds=None, check_policy: Policy \| str \| None = None, allow_unreleased=False, plan=None) -> promotion_id` | Fills the run's rows, builds its default deliverable list grouped by slot, optionally narrowed to `kinds`, and calls `promote` with it; given `plan` (the list `run promote-plan` printed), refuses under `StalePlan` if the actual current selection or the run's own candidates have moved since the plan was made. |
| `rollback_promotion(conn, promotion_id, who, reason) -> promotion_id` | Submits a past promotion's inverse mapping as a new promotion. |
| `finish_run(conn, run_id) -> None` | Marks a run finished; refuses unless every unit is terminal. |
| `mark_run_deleting(conn, run_id, requested_by, *, expiry=False) -> None` | The deletion fence: locks the run, runs the pre-deletion checks, and marks it deleting. `delete_run` calls it first; `expiry=True` marks the caller as the expiry sweep rather than the run's owner. |
| `delete_run(conn, run_id, requested_by, *, s3_client=None, scratch_bucket=None, expiry=False) -> DeletionReport` | Runs guarded deletion on a scratch run, committing internally rather than inside the caller's transaction; the report lists the objects, versions and per-table rows removed and the instances marked deleted. |
| `expire_runs(conn, *, now=None, s3_client=None) -> list[DeletionReport]` | Calls `delete_run` with `expiry=True` for every unpinned scratch run past its `expires_at`. |
| `pin_run(conn, run_id, pinned) -> None` | Sets or clears a run's `pinned` flag. |
| `resolve_run_policy(conn, run_id, explicit=None) -> Policy`, in `rapidpipe.runs.checking` | Resolves the policy `run promote` and `run start`'s auto-promote validate against: an explicit ref, then the run's `check_policy_ref`, then `rebuild-trial@1`. |
| `run_policy_checks(conn, run_id, policy, *, instance=None, check=None, param_overrides=None, who=None) -> list[RecordedCheck]`, in `rapidpipe.runs.checking` | Runs every applicable policy check over the run's candidate instances from their selected attempts, or one named instance or check, and records a `checks` row for each; `check run` builds on it. |
| `recorded_checks(conn, run_id, *, instance=None) -> list[RecordedCheck]`, in `rapidpipe.runs.checking` | Returns the run's recorded check results, newest first; `check show` prints them. |
| `maybe_auto_promote(conn, run_id, *, who="auto-promote") -> AutoPromoteOutcome`, in `rapidpipe.runs.checking` | Called at the end of a `run start` walk once every unit is complete; with the run's `auto_promote` flag true, resolves the policy, runs its checks over the run's candidates and calls `promote_run` on a pass; the outcome's status is `off`, `skipped`, `refused` or `promoted`. |
| `failed_rerun_plan(conn, seed_run) -> FailedRerunPlan`, in `rapidpipe.runs.repository` | Computes the recovery plan `run create --seed --only-failed` executes: the earliest non-complete position, the seed's stage list, and the non-complete units to seed, or, for a scratch seed, the first stage's units to recreate. |
| `seed_failed_units(conn, *, seed_run, new_run) -> list[str]`, in `rapidpipe.runs.repository` | Creates the new run's seeded units from a `FailedRerunPlan`, copying each seed unit's `unit_inputs` bindings, and returns the created unit ids. |
| `record_attempt_locations(conn, attempt_id, inputs_location, settings_location) -> None`, in `rapidpipe.runs.repository` | Records the input-set and settings locations `submit_unit` resolved for an attempt, on `attempts.inputs_location` and `attempts.settings_location`. |
| `resolve_jobless(conn, *, run_id, older_than_seconds, client=None) -> list[Reconciled]`, in `rapidpipe.launch.batch` | Implements `run reconcile --resolve-jobless`: for each job-less attempt, looks first for a scheduler job under its deterministic job name and repairs the attempt on exactly one match, otherwise records it `lost` once past the age threshold. |

The command-line tool's `run` and `check` subcommands are thin wrappers
over these; the [tool](tool) page has the command surface.

## Not decided here

- The scratch expiry warning mechanics.
