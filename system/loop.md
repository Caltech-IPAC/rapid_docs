# The processing-date loop

**Status: DRAFT**

How regular operations run themselves: the registry row that triggers
the loop, the host it runs on, the spec it reads, the production run it
creates for each processing date, how a date's fields bind to the
previous date's catalog, promotion, and what each date leaves in the
database. Written 2026-09-24 from supervisor step 7's rulings (R1
through R10), with the stage chain, base-catalog rule, concurrency and
the IAM grant amended after a Codex plan review the same day. The
[specification](specification)'s Sequencing item 7 states the
requirement; this page records how the rebuild meets it.

## In plain terms

The loop turns a spec naming a schedule, a release and a list of
processing dates into one production run per date, walked through
admission, differencing, loading, crossmatch, statistics, pruning and
alerts, in order. Each field's crossmatch binds the previous date's
association set for that field as its base, so objects accumulate across
dates the way `dev`'s date-by-date operation does. A date's run is
promoted under the spec's check policy once every unit completes; a
refusal is recorded, not fatal, and the loop moves to the next date. One
row per schedule and date, in a table of its own, is the record. The loop
itself is `rapidpipe loop run`, started by one scheduled trigger, not a
service that runs continuously.

## The scheduler

The schedule trigger is a row, `processing-date-loop`, in `rapid_systems`'
operations registry, `cloudformation/operations.tsv`: the estate's one
scheduling mechanism, already driving `pin-sweep` and the other
recurring fleet operations through an SSM Maintenance Window and an
Automation runbook per row (ruling R1). The row's fields: trigger
`window:at(<UTC>)`, target `Name=rapid-admin`, runbook
`rapid-op-processing-date-loop-runbook`, concurrency 1, error cutoff 1,
owner `rapid-alerts`, freshness `P7D`, freshness actions `quiet`. The
runbook's shell step sets `executionTimeout` to 21600 seconds, about two
control dates at roughly 4.5 hours each, so SSM kills a stalled run
rather than letting it run past the window (supervisor step 7,
2026-09-24, after the Codex plan review).

The loop has no EventBridge rule and no Batch driver job of its own. The
registry's `event:` trigger class is reactive only, never an
orchestrator, so it is not the right shape for a recurring run; a
separate driver would duplicate the scheduling the registry already
does for every other unattended operation on the fleet. "One schedule
trigger" means that Maintenance Window firing once runs the whole loop
for every date the spec names: the loop itself walks the dates, not the
registry.

The proof row's trigger is a one-shot `at()`, the registry's own
deploy-phase shape (as `postgres-swap` uses it as an inert placeholder).
After the proof, the row keeps a far-future `at()` rather than moving to
a daily `cron()`: a daily trigger over the control inputs would
re-process the same image into the trial database every day, and there
are no real deliveries yet for it to advance against. The steady-state
cadence is set once real deliveries exist (below, Not decided here).

## Venue

The operation runs as root under SSM on `rapid-admin`, from a checkout
of the release tag (ruling R2). `rapid-admin` is where every registry
row already runs; `rapid-rusholme`, the workstation, idle-stops fifteen
minutes after its last session, and an unattended loop polling Batch
over hours would be stopped mid-run there. `rapid-admin-instance-role`
already holds `batch:SubmitJob`/`DescribeJobs` on the `rapid-*`
definitions and reads the rebuild database secret. For the input-set
write access its own runs need, it joins a new parameter,
`LoopLauncherRoleNames`, rather than [tool](tool) page's R7
`WorkstationSubmitterRoleNames`: the role already carries 22 of the 25
policies an instance role can hold, so the loop's grant is scoped to
`ScratchSubmitter` alone, not the workstation role's fuller set
(supervisor step 7, 2026-09-24, after the Codex plan review).

The operation script, `op-processing-date-loop.sh`, is embedded in the
runbook like every other registry row. It reads one SSM parameter,
`/rapid/rebuild/loop/spec`, whose value is the spec's S3 location;
fetches the spec; clones `rapid` at the tag the spec names into
`/var/lib/rapid/loop/rapid-<tag>`, refusing if the checkout's
`git describe --tags --exact-match` does not equal that tag; exports the
launcher's environment (the pooler, the rebuild database, the queue and
job-definition names, no secrets); and runs
`rapidpipe.cli.main loop run --spec <loc>`, its log tee'd to
`/var/log/rapid/processing-date-loop.log`. Ben's sentence for it: the
scheduled operation reads the loop spec named in one SSM parameter,
checks out the release the spec names, and runs the loop over the
spec's dates.

## The loop spec

The spec is a TOML document, read from S3 or a local path (ruling R3):

```toml
[loop]
schedule = "processing-date-loop"
release = "rebuild-v0.3"
kind = "production"
owner = "loop/processing-date-loop"
lane = "loop"
check_policy = "rebuild-trial@1"
max_attempts = 3
inbox = "s3://roman-rapid-scratch/rapidpipe-firstrun/ops4/inbox/"
difference_template = "control/20260923/inputs"
admit_settings = "control/20260923/settings/admit-socsim.toml"
difference_settings = "control/20260923/settings/difference-gain1-imgnoise.toml"
```

A spec needs `inbox` or `[[dates]]`, or `loop run` refuses it
(`LoopSpecError`, exit 64). The `[[dates]]` form, one entry per
processing date and one `[[dates.detector_images]]` per delivery
carrying its own `admit_settings`, `difference_template` and
`difference_settings`, stays exactly as before, for proofs and backfills
named by `loop run --date D`.

This is `ops4-stream`, the spec at
`s3://roman-rapid-scratch/rapidpipe-firstrun/ops4/loop/ops4-stream.toml`
(supervisor step 4, 2026-09-26), release the tag this step cuts, policy
`rebuild-trial@1`. A later batch's crossmatch binds the earlier batch's
association set for its field, the same way a later date's does (Base
catalog, below).

`loop run` processes, in spec order, every date whose `loop_dates` row is
absent or `open`, when the spec lists dates explicitly; an inbox spec's
discovery and batch order are below (Discovery and batches). Concurrency,
retries and exit codes are further down (Concurrency and recovery).

## Discovery and batches

A spec that names `inbox` turns each firing into a discovery pass over
that location, ahead of anything the spec lists under `[[dates]]`
(supervisor step 4, 2026-09-26).

### Inbox layout

A delivery lands at `<inbox>/<YYYY-MM-DD>/<delivery-name>/manifest.json`.
The date directory is the delivery's processing date: the mission's own
interface for that is not yet defined ([operations](operations), "What
this page assumes about the mission"), the socsim fixture is one exposure
so its FITS observation date cannot separate proof dates, and a staging
layout that states the date outright is the smallest assumption the
stream can make. `<delivery-name>` is the prefix `admit` already reads,
`<stem>-scaNN`, and its manifest gives the detector unit id. A key under
the inbox that does not match
`^<inbox>/(\d{4}-\d{2}-\d{2})/([^/]+)/manifest\.json$` is ignored and
counted in the firing's log line.

Because a discovered manifest carries no stage inputs of its own,
`[loop]` also takes stream-level ones applied to every delivery it
finds: `difference_template`, required whenever `inbox` is set, and the
optional `admit_settings` and `difference_settings`. One template for
every delivery is a proof-scale assumption; a real stream resolves a
reference per field, which stays open ([operations](operations) page).

### What a firing does

Under the schedule's advisory lock, `loop run` on an inbox spec, in
order:

1. Resumes the schedule's `open` rows and its reopenable `failed` rows,
   in `(processing_date, batch)` order, reading their deliveries from
   `loop_deliveries` rather than the spec; a non-reopenable `failed` row
   still stops it, as today.
2. Discovers new manifests (Classification, below) and creates every new
   batch, oldest processing date first, freezing each batch's membership
   as it is created.
3. Processes the new batches in that order.

A firing that resumes nothing and discovers nothing prints `schedule
<s>: nothing to discover` and exits 0, having written no row, no run and
no object. `--date D` still selects `[[dates]]` entries only; a spec that
sets `[[dates]]` and no `inbox` behaves exactly as it does today,
bypassing discovery because a person has already named its deliveries.

### Classification

Discovery lists the inbox and keeps every manifest key not yet recorded
in `loop_deliveries` for the schedule; once a location is recorded, it is
never read again, whatever its state. Each kept manifest is read and
classified against the schedule's admission history, the rows already
`batched` plus whatever this same firing has classified ahead of it, in
key order. Identity is the delivered image's `(exposure, detector,
version)`; a checksum is the primary file's `sha256`.

| Manifest | Outcome |
|---|---|
| Not a delivery manifest, or missing a key field or checksum | Quarantined, reason `malformed` |
| Same exposure, detector, version and checksum as a batched delivery | Refused, reason `identical re-delivery` |
| Same exposure, detector and version as a batched delivery, different checksum | Quarantined, reason `checksum conflict` |
| Same exposure and detector, a newer version, while an earlier version is batched | Deferred, reason `corrected delivery awaits a correction run` |
| None of the above | Batched |

A refused, quarantined or deferred manifest creates no batch and no run;
each classification is still one `loop_deliveries` row, so `loop show`
prints it after the schedule's batch rows. `loop plan` on an inbox spec
runs the same classification and prints it without writing anything.

### One transaction per batch

Discovery commits in two stages. First, under the same lock, every
refused, quarantined and deferred manifest from this firing is inserted
and committed in one transaction, before any batch exists, so a firing
that finds nothing admissible still leaves a full record. Then, for each
new date in turn, oldest first: the loop creates the date's run, inserts
its `loop_dates` row (`open`, one past the date's highest existing batch,
or 1 if it has none) and the batch's `batched` `loop_deliveries` rows,
and commits before moving to the next date. A batch's membership is
frozen at that commit; a manifest that reaches the inbox afterward waits
for the next firing. Processing starts only once every batch of the
firing has committed.

A crash after a batch's commit leaves its `loop_dates` row `open`, and
the next firing resumes it from the database, against the same run, as
above. A crash before the commit leaves nothing behind: the manifests it
would have covered are still unrecorded, and the next firing discovers
them again.

## Per date

Each processing date becomes one production run, created through the
CLI's `run create --release` path: owner and lane from the spec, purpose
`"processing date <D> (schedule <S>)"`, `input_selection_ref` the spec's
location, `check_policy_ref` the spec's policy, `max_attempts_per_unit`
the spec's, and `selected_stages` the loop's own chain: admit, register,
difference, finalize, register, load, maintain, crossmatch, statistics,
prune, alerts: one `register` fewer than first ruled, since the landed
`finalize` contract never registers the raw difference instance, and
promoting two candidates for the same kind and logical key is refused
(ruling R4, amended, supervisor step 7, 2026-09-24, after the Codex plan
review).

Per detector image, the chain runs as the tool's own stages do:
admit(delivery) → register → difference (input set composed from the
template) → finalize → register(finalize's output) → load(finalize's
output). Then `maintain`, whose `detector-date` unit id,
`<yyyymmdd>/SCA<nn>`, the loop derives from the load attempt's own
child-table name. Then, per distinct
`field` read from that table: crossmatch (input set the load manifest's
source set plus the base association set, below) → statistics
(crossmatch's output) → prune (crossmatch's output). After a field's
prune, the loop reads the selected prune attempt's manifest: exactly
one pruned set, whose base must be the association set the same date's
crossmatch produced for the field, else the date fails. Each detector
image's alerts input set names, per field it touches, the association
set, its statistics set and that pruned set, in that order after the
source set (the [alerts](alerts) page's `pruned-set` binding, ruling
R5), the recipe `compose-alerts-inputs.py` already scripts. The date
record gains `pruned_sets {field: instance}` (see Records, below).
Submission and polling go through `submit_unit` and `reconcile`, as
`run start` uses them for one unit at a time.

## Base catalog

A field's base catalog is the association-set instance its crossmatch
produced in the newest earlier `loop_dates` row of the same schedule,
ordered by `(processing_date, batch)`, that is `complete` and has an
association set for that field (that row's run's selected attempt for
the field's unit), or none, if no earlier complete row has one, on a
schedule's first date or a field new to a later one. A later batch of the
same processing date counts as later in this order, so it extends the
earlier batch's association sets rather than starting the field over
(supervisor step 4, 2026-09-26). A failed or still-open date has no
association set to offer, so the search steps back past it to the most
recent complete one: one date's failure does not stall base-catalog
binding for the dates that follow it. The base date need not itself be
promoted:
association sets bind by instance, not by current custody, so an
unpromoted complete date is still an eligible base, and `prune`'s own
not-best exclusion, not promotion, is what keeps an inferior instance
out of the chain a later date reads. Each field's entry in the date's
record notes `base_promoted`: whether the date that supplied its base
had itself been promoted at bind time (ruling R5, amended, supervisor
step 7, 2026-09-24, after the Codex plan review). Input-set manifests
for crossmatch and alerts are written under
`<scratch root>/runs/<run>/inputs/<stage>/<unit>/`, the same layout the
[tool](tool) page's composer uses. This is the loop's own instance of the
field-level input selection the tool page leaves open; which reference a
field should use among several eligible ones is still not decided
(below).

Field discovery and base selection both go through the [products](products)
page's cross-run reading rule, not around it. Field discovery reads a
source set only after that rule passes; an unreadable own source set
fails the date. A candidate base association set that fails the rule --
another run's scratch set, or one from an unselected attempt -- is
skipped, and the search continues to the next earlier complete row of
the schedule, the same stepping-back the paragraph above already does
for a failed or open date; each skip is recorded in the date's record as
`bases_skipped` (per field, the run, processing date, instance and
reason skipped) (supervisor step 9, ruling R2, 2026-09-25).

A schedule's first date has no base, so over a sky whose field
association sets are already current its scheduler promotion is refused
by the [runs](runs) page's association-set ancestor rule (the before
instance must be reached from the new set through `base`) until a chain
switch to the earlier sets exists; a proof or a new stream over the same
sky therefore continues the existing schedule, a new inbox prefix and
new exposures, rather than starting a new schedule name (supervisor
step 7, 2026-09-27; step 7's proof continued `ops4-stream`).

## Promotion

Once every unit of a date's run is complete, the loop promotes it under
the spec's check policy: `promote_run(conn, run_id, who="scheduler",
reason="processing date <D>", check_policy=…)`, once step 6's check gate
has landed, or today's released-image-only `promote_run` with the gap
recorded on the date's row (ruling R6). A refusal, a failed or missing
required check, is a science outcome, not an operation failure: the
`loop_dates` row records `promotion = refused: <reason>`, the run is
finished, and the loop moves to the next date regardless, since the next
date's crossmatch binds this date's association set by instance whether
or not it was promoted. `finish_run` follows promotion or refusal either
way, and the date exits 0.

## Concurrency and recovery

`loop run` takes one PostgreSQL advisory lock scoped to the spec's
schedule for its whole run; a second launcher for the same schedule (a
stray retry, an overlapping Maintenance Window) exits 75 without
touching any date, rather than racing the first (supervisor step 7,
2026-09-24, after the Codex plan review).

Within the lock, dates are processed in spec order. A `complete` row is
skipped, and an `open` row is resumed as described above (The loop
spec): complete units skipped, running attempts attached, ready units
re-attempted. A `failed` row is also skipped by default. `loop run --retry-failed`
recovers a failed date whose run has a failed or cancelled unit by
seeding a replacement run, the `run create --seed <run> --only-failed`
recovery the [runs](runs) page describes: the row is repointed to the
new run, the old run's id is kept in `record.previous_runs`, and the
date is walked again against the new run, which re-runs only the
seed's non-complete units. Only a
failed date with no failed or cancelled unit resumes the same run,
the reopen described below (direction pass, 2026-09-26, correcting
this paragraph's earlier "resumes the same run rather than creating a
new one", which the code, `rapidpipe/launch/loop.py` `retry_date`, has
not done since the seeded path landed). A date's move
to `complete` and its run's `finish_run` commit in one transaction, so a
crash between the two cannot leave a `loop_dates` row claiming
completion for a run that never finished, or a finished run with no row
to show for it (supervisor step 7, 2026-09-24, after the Codex plan
review).

`reconcile` marks an attempt `lost` the same way it always does when its
Batch job is gone. From there the unit's own retry-safe recovery
applies, the [stage contract](stage-contract) page's rule that a retry
recovers a completed-but-unconfirmed write rather than duplicating it,
or discards an incomplete one and tries again within the run's attempt
allowance; a unit with no attempts left fails, and that fails the date
(supervisor step 7, 2026-09-24, after the Codex plan review).

A date whose input set cannot be read -- an absent or invalid manifest,
or a producer run that is deleting or deleted -- fails with that reason,
and can fail before any unit exists, when nothing has run yet to give
`--retry-failed` a failed or cancelled unit to seed. A later `loop run`
reopens such a failed row -- one whose run has no failed or cancelled
unit -- and resumes it with the same run: the row returns to `open`,
its failure moves to `record.previous_failures`, and the reopen's time
is appended to `record.reopened` (`loop plan` shows this as
`action=reopen`). A row with a failed unit still takes `--retry-failed`'s
seeded path instead, and a finished run's row is never reopened, since a
finished run takes no new units (supervisor step 9, ruling R2,
2026-09-25).

`loop run` exits 0 when every date it processed reached `complete`, 1 on
the first date that fails with no later date started, 64 on bad
arguments or a refused spec, a parse failure included (supervisor step
1, 2026-09-26), and 75 on a timeout or a lock already held. The full
vocabulary is on the [tool](tool) page.

## Records

Each schedule, date and batch is one row of `loop_dates`, its primary key
`(schedule, processing_date, batch)` since migration
`20260926-01-loop-batches.sql` added `batch` (a date's first batch is 1,
each later one for the same date the next integer) and `kind` (`batch`
or `switch`, the [operations](operations) page's chain switch); every row
the migration found kept batch 1 and kind `batch` (supervisor step 4,
2026-09-26). The table itself dates to migration
`20260924-11-loop-dates.sql`: schedule, processing date, run, state
(`open`, `complete`, `failed`), started and ended timestamps, the
promotion id, and a `record` JSON column, granted to
`rapid_rebuild_pipeline` under the same guard as the rebuild's other
grants (ruling R7). `record` carries the spec's location and release,
each unit's selected attempt and job id, the field list, the base sets
each field bound and, per field, `base_promoted` (above, Base catalog),
`bases_skipped` (per field, the bases the reading rule refused before an
eligible one was found, ruling R2), `pruned_sets` (per field, the
pruned-set instance that field's `prune` wrote and alerts read, ruling
R5), the alert container's instance and location, and the promotion id
or refusal reason. An inbox spec's batches add `record.batch` and
`record.deliveries`, the batch's `loop_deliveries` locations.

Each manifest discovery classifies is one row of `loop_deliveries` (same
migration), keyed on `(schedule, location)` so a manifest is never read
twice: schedule, location, processing date, exposure, detector, version,
checksum, the delivery instance and unit it produced, its state
(`batched`, `refused`, `quarantined` or `deferred`), the reason for a
state other than `batched`, its batch and when it was discovered, with an
index on `(schedule, exposure, detector, version)` for the classification
lookup. `loop show <schedule>` prints the schedule's `loop_dates` rows,
then its `loop_deliveries` rows.

## Release binding

The spec names the release; the operation checks that tag out before
running, and each date's run records it, so a run's code and the image
its units execute are the same tag the spec named, never a branch head
(ruling R9). The release is the first tag cut at a rebuild head that
carries the loop's own code and migration, allocated by `next_tag` from
the laptop, by the [releases](releases) page's own recipe.

## Commands

| Command | Does |
|---|---|
| `loop run --spec <loc> [--date D]… [--retry-failed] [--dry-run] [--interval N] [--timeout N]` | Runs every date in the spec whose `loop_dates` row is absent or `open`, in spec order, under the schedule's advisory lock; `--date` restricts to named dates; `--retry-failed` also recovers `failed` dates, through a seeded replacement run when the date has a failed or cancelled unit |
| `loop plan --spec <loc>` | Prints what `run` would do: the dates it would process and the runs it would create, without creating them; given an inbox spec, it discovers and classifies without writing any row |
| `loop show <schedule>` | Prints the schedule's `loop_dates` rows, then its `loop_deliveries` rows |

## Not decided here

- The mission's own inbox layout and manifest fields, once the interface
  is defined; the layout above is a proof-scale assumption.
- A per-field difference template or reference selection: the stream
  applies one template to every delivery today.
- Parallel dates: today's loop runs dates one after another.
- Lanes or resource profiles dedicated to the loop, beyond the one the
  spec names.
- The steady-state cadence, once real deliveries exist to advance
  against.
- Publishing the alerts a date's run produces.
