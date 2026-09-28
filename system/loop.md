# The processing-date loop

**Status: DRAFT**

`rapidpipe loop run` runs regular operations from one scheduled trigger;
it is not a continuously running service. The
[specification](specification)'s Sequencing item 7 states the requirement.

## In plain terms

A spec names a schedule, a release and processing dates. The loop creates
one production run per date and walks it through admission, differencing,
loading, crossmatch, statistics, pruning and alerts, in order. Each
field's crossmatch uses the previous date's association set as its base,
so objects accumulate across dates as they do in `dev`'s date-by-date
operation. Once every unit completes, the run is promoted under the
spec's check policy. A refusal is recorded without failing the date, and
the loop moves to the next date. A separate table records one row per
schedule and date.

## The scheduler

The trigger is the `processing-date-loop` row in `rapid_systems`'
operations registry, `cloudformation/operations.tsv`. The registry is
the estate's single scheduling mechanism: it already drives `pin-sweep`
and other recurring fleet operations through an SSM Maintenance Window
and an Automation runbook per row. The loop row has trigger
`window:at(<UTC>)`, target `Name=rapid-admin`, runbook
`rapid-op-processing-date-loop-runbook`, concurrency 1, error cutoff 1,
owner `rapid-alerts`, freshness `P7D` and freshness actions `quiet`.
The runbook's shell step sets `executionTimeout` to 21600 seconds,
about two control dates at roughly 4.5 hours each, so SSM kills a stalled
run before it runs past the window.

One Maintenance Window firing runs the whole loop over every date the
spec names. The loop walks the dates. It has no EventBridge rule or
Batch driver job of its own: the registry's `event:` trigger class is
reactive only, never an orchestrator, and a separate driver would
duplicate the registry's scheduling of unattended fleet operations.

The proof row uses a one-shot `at()`, the registry's deploy-phase shape
that `postgres-swap` uses as an inert placeholder. After the proof, the
row keeps a far-future `at()` instead of a daily `cron()`. A daily
trigger over the control inputs would re-process the same image into
the trial database every day; there are no real deliveries yet to
advance against. The steady-state cadence will be set once they exist
(Not decided here, below).

## Venue

The operation runs as root under SSM on `rapid-admin`, from a checkout
of the release tag. Every registry row already runs on `rapid-admin`.
The workstation idle-stops fifteen minutes after its last session,
which would interrupt a loop polling Batch for hours.

`rapid-admin-instance-role` already holds `batch:SubmitJob`/`DescribeJobs`
on the `rapid-*` definitions and reads the rebuild database secret.
Input-set writes for its own runs are granted through a new parameter,
`LoopLauncherRoleNames`, rather than the [tool](tool) page's
`WorkstationSubmitterRoleNames`. The role already carries 22 of the 25
policies an instance role can hold, so the loop receives only
`ScratchSubmitter`, without the workstation role's fuller set.

Like every other registry row, the runbook embeds its operation script,
`op-processing-date-loop.sh`. The script reads the spec's S3 location
from the SSM parameter `/rapid/rebuild/loop/spec` and fetches it. It
clones `rapid` at the named tag into `/var/lib/rapid/loop/rapid-<tag>`
and refuses if `git describe --tags --exact-match` in that checkout
does not equal the tag. It then exports the launcher's environment
(the pooler, rebuild database, queue and job-definition names, no
secrets) and runs `rapidpipe.cli.main loop run --spec <loc>`, teeing
the log to `/var/log/rapid/processing-date-loop.log`. Ben's sentence
for it: the scheduled operation reads the loop spec named in one SSM
parameter, checks out the release the spec names, and runs the loop
over the spec's dates.

## Release binding

The spec names the release; the operation checks out that tag and each
date's run records it. The run's code and the image its units execute
therefore use the same tag, never a branch head. The release is the
first tag cut at a rebuild head carrying the loop's code and migration,
allocated by `next_tag` from the laptop using the
[releases](releases) page's recipe.

## The loop spec

The spec is a TOML document read from S3 or a local path:

```toml
[loop]
schedule = "processing-date-loop"
release = "rebuild-v0.3"
kind = "production"
owner = "loop/processing-date-loop"
lane = "loop"
check_policy = "rebuild-trial@1"
max_attempts = 3
inbox = "s3://<scratch-bucket>/rapidpipe-firstrun/ops4/inbox/"
difference_template = "control/20260923/inputs"
admit_settings = "control/20260923/settings/admit-socsim.toml"
difference_settings = "control/20260923/settings/difference-gain1-imgnoise.toml"
```

This is `ops4-stream`, at
`s3://<scratch-bucket>/rapidpipe-firstrun/ops4/loop/ops4-stream.toml`,
release the newly cut tag, policy `rebuild-trial@1`.

A spec needs `inbox` or `[[dates]]`; otherwise `loop run` refuses it
with `LoopSpecError`, exit 64. The explicit `[[dates]]` form remains
available for proofs and backfills selected by `loop run --date D`:
one entry per processing date, with one `[[dates.detector_images]]` per
delivery carrying its own `admit_settings`, `difference_template` and
`difference_settings`.

For explicit dates, `loop run` processes every date whose `loop_dates`
row is absent or `open`, in spec order. Inbox discovery and batch order
are described under Discovery and batches; retries and exit codes are
under Concurrency and recovery. A later batch's crossmatch binds the
earlier batch's association set for its field, just as a later date's
does (Base catalog, below).

## Discovery and batches

With `inbox` set, each firing discovers deliveries at that location
before processing anything listed under `[[dates]]`.

### Inbox layout

Deliveries land at `<inbox>/<YYYY-MM-DD>/<delivery-name>/manifest.json`.
The date directory states the processing date. The mission's interface
for that is undefined ([operations](operations), "What this page assumes
about the mission"), and the socsim fixture has only one exposure, so
its FITS observation date cannot separate proof dates. Stating the date
in the staging layout is the stream's smallest assumption.
`<delivery-name>` is the `<stem>-scaNN` prefix `admit` already reads;
its manifest gives the detector unit id. Inbox keys that do not match
`^<inbox>/(\d{4}-\d{2}-\d{2})/([^/]+)/manifest\.json$` are ignored and
counted in the firing's log line.

Discovered manifests carry no stage inputs. Instead, `[loop]` supplies
stream-level inputs for every discovered delivery: `difference_template`
is required when `inbox` is set; `admit_settings` and
`difference_settings` are optional. One template for all deliveries is
a proof-scale assumption. Resolving a reference per field for a real
stream remains open on the [operations](operations) page.

### What a firing does

Under the schedule's advisory lock, `loop run` on an inbox spec:

1. Resumes the schedule's `open` and reopenable `failed` rows in
   `(processing_date, batch)` order, reading deliveries from
   `loop_deliveries` rather than the spec. A non-reopenable `failed`
   row stops it.
2. Discovers new manifests (Classification, below) and creates every
   new batch, oldest processing date first, freezing membership as
   each batch is created.
3. Processes the new batches in that order.

If nothing is resumed or discovered, the firing prints `schedule
<s>: nothing to discover` and exits 0 without writing a row, run or
object. `--date D` selects only `[[dates]]` entries. A spec with
`[[dates]]` and no `inbox` keeps its existing behaviour: it bypasses
discovery because a person has named the deliveries.

### Classification

Discovery lists the inbox and keeps manifest keys not yet recorded in
`loop_deliveries` for the schedule. A recorded location is never read
again, whatever its state. In key order, each new manifest is read and
classified against the schedule's admission history: rows already
`batched` plus whatever this firing has classified before it. The
delivered image's identity is `(exposure, detector,
version)`; a checksum is the primary file's `sha256`.

| Manifest | Outcome |
|---|---|
| Not a delivery manifest, or missing a key field or checksum | Quarantined, reason `malformed` |
| Same exposure, detector, version and checksum as a batched delivery | Refused, reason `identical re-delivery` |
| Same exposure, detector and version as a batched delivery, different checksum | Quarantined, reason `checksum conflict` |
| Same exposure and detector, a newer version, while an earlier version is batched | Deferred, reason `corrected delivery awaits a correction run` |
| None of the above | Batched |

Refused, quarantined and deferred manifests create no batch or run.
Each classification still creates one `loop_deliveries` row, which
`loop show` prints after the schedule's batch rows. For an inbox spec,
`loop plan` performs and prints the same classification without writing.

### One transaction per batch

Discovery commits in two stages under the same lock. First, it inserts
and commits all refused, quarantined and deferred manifests in one
transaction, before any batch exists. Even a firing with nothing
admissible leaves a full record.

Then, for each new date, oldest first, the loop creates a run and inserts
its `loop_dates` row and `batched` `loop_deliveries` rows. The date row
is `open`; its batch number is one past the date's highest existing
batch, or 1 if none exists. The loop commits before moving to the next
date, freezing the batch's membership. A manifest arriving afterward
waits for the next firing. Processing begins only after all of the
firing's batches have committed.

A crash after a batch commits leaves its `loop_dates` row `open`; the
next firing resumes it from the database against the same run. A crash
before commit leaves nothing behind, so the next firing rediscovers
the unrecorded manifests.

## Per date

Each processing date becomes one production run through the CLI's
`run create --release` path. Owner and lane come from the spec. Purpose
is `"processing date <D> (schedule <S>)"`, `input_selection_ref` is the
spec's location, `check_policy_ref` is its policy, and
`max_attempts_per_unit` is its attempt limit. `selected_stages` holds
the loop's chain: admit, register, difference, finalize, register, load,
maintain, crossmatch, statistics, prune, alerts. The chain has two
`register` steps, not three: `finalize`'s contract never registers the
raw difference instance, and promotion refuses two candidates for the
same kind and logical key.

For each detector image, the tool's stages run in order:
admit(delivery) → register → difference (input set composed from the
template) → finalize → register(finalize's output) → load(finalize's
output). Next comes `maintain`, with a `detector-date` unit id of
`<yyyymmdd>/SCA<nn>` derived from the load attempt's child-table name.
For each distinct `field` in that table, the chain continues:
crossmatch (input set containing the load manifest's source set and
the base association set, below) → statistics (crossmatch's output) →
prune (crossmatch's output).

After each field's prune, the loop reads the selected prune attempt's
manifest. It must name exactly one pruned set whose base is the
association set that date's crossmatch produced for the field;
otherwise the date fails. Each detector image's alerts input set names
the source set, followed, for each field it touches, by the association
set, its statistics set and that pruned set, in that order (the
[alerts](alerts) page's `pruned-set` binding). The date record gains
`pruned_sets {field: instance}` (Records, below). Submission and polling
use `submit_unit` and `reconcile`, as `run start` does for one unit at
a time.

## Base catalog

A field's base catalog comes from the newest earlier `loop_dates` row
in the same schedule that is `complete` and has an association set for
that field. Rows are ordered by `(processing_date, batch)`; the bound
instance is the association set produced by the selected crossmatch
attempt for the field's unit in that row's run. If no earlier complete
row has one, the field has no base, as on a schedule's first date or
for a field first seen on a later date. A later batch of the same date
extends the earlier batch's association sets.

The search skips failed and open dates and steps back to the most
recent complete row, so a date's failure does not stall base-catalog
binding for later dates. Promotion is not required: association sets
bind by instance, independently of current custody. `prune`'s not-best
exclusion keeps an inferior instance out of the chain a later date
reads. Each field's record stores `base_promoted`, whether the date
supplying its base had been promoted at bind time.

Field discovery and base selection both obey the [products](products)
page's cross-run reading rule. Field discovery reads a source set only
after the rule passes; an unreadable own source set fails the date.
A candidate base that fails the rule (another run's scratch set, or
one from an unselected attempt) is skipped. The search continues to
the next earlier complete row, just as it steps past failed or open
dates. Each skip is recorded in `bases_skipped`: per field, the run,
processing date, instance and reason skipped.

Crossmatch and alerts input-set manifests are written under
`<scratch root>/runs/<run>/inputs/<stage>/<unit>/`, the layout used by
the [tool](tool) page's composer. This implements the loop's own
field-level input selection. The tool page's question of which
reference to use among several eligible ones remains open (below).

A schedule's first date has no base. If field association sets for that
sky are already current, the [runs](runs) page's association-set
ancestor rule refuses scheduler promotion until a chain switch to the
earlier sets exists: the before instance must be reachable from the
new set through `base`. A proof or new stream over the same sky
therefore continues the existing schedule with a new inbox prefix and
new exposures, rather than starting a new schedule name.

## Promotion

When every unit in a date's run is complete, the loop resolves the
check policy from the spec, then the run, then the default. It checks
the run's candidates and records each result as `scheduler`.
`promote_run` is called only for a team-approved policy with
`auto_promote` true, the same gate used by `run start` ([checks](checks),
"Automatic promotion"). No shipped policy permits this.

Every scheduled date so far has used `rebuild-trial@1`, which leaves
the run a candidate and records
`promotion = candidate; promotion is a person's (policy <ref>)` in
`loop_dates`. A refusal under a policy that permits automatic promotion
is recorded as `refused: <reason>` without failing the date.
`finish_run` follows either way, and the date exits 0 regardless of
which text was recorded.

A candidate date still supplies the next date's base by instance; the
next date's field entry `base_promoted` (Base catalog, above) records `false`.
A person promotes candidates with `rapidpipe run promote`, in date
order. The [runs](runs) page's ancestor rule refuses promotion of a
later date's association set while the earlier date's run it depends
on remains a candidate.

## Concurrency and recovery

`loop run` holds one PostgreSQL advisory lock for the spec's schedule
throughout its run. A second launcher for the same schedule, such as
a stray retry or overlapping Maintenance Window, exits 75 without
touching any date.

Within the lock, dates are processed in spec order. A `complete` row is
skipped; an `open` row is resumed (The loop spec, above), skipping
complete units, attaching to running attempts and re-attempting ready
units. A `failed` row is skipped by default.

For a failed date whose run has a failed or cancelled unit,
`loop run --retry-failed` seeds a replacement run using the [runs](runs)
page's `run create --seed <run> --only-failed` recovery. The date row
points to the new run and retains the old id in `record.previous_runs`.
The loop walks the date again, re-running only the seed's non-complete
units. Only a failed date with no failed or cancelled unit resumes the
same run, through the reopen described below.

`reconcile` marks an attempt `lost` when its Batch job is gone. The
unit then follows the [stage contract](stage-contract) page's retry-safe
recovery: recover a completed-but-unconfirmed write without duplicating
it, or discard an incomplete write and try again within the run's
attempt allowance. A unit with no attempts left fails, failing the date.

An unreadable input set fails the date with its reason: an absent or
invalid manifest, or a producer run that is deleting or deleted. This
can happen before any unit exists, leaving `--retry-failed` no failed
or cancelled unit to seed. A later `loop run` reopens a failed row
whose run has no failed or cancelled unit and resumes the same run.
The row returns to `open`, its failure moves to
`record.previous_failures`, and the reopen time is appended to
`record.reopened`; `loop plan` shows `action=reopen`. A failed unit
requires `--retry-failed`'s seeded path. A finished run's row is never
reopened because a finished run accepts no new units.

The date's move to `complete` and its run's `finish_run` commit in one
transaction. A crash cannot leave either a completed date row for an
unfinished run or a finished run without its completed row.

`loop run` exits 0 when every processed date reaches `complete`, 1 on
the first failed date without starting a later date, 64 for bad
arguments or a refused spec (including a parse failure), and 75 for a
timeout or held lock. The [tool](tool) page gives the full vocabulary.

## Records

`loop_dates` holds one row per schedule, date and batch, keyed on
`(schedule, processing_date, batch)`. Migration
`20260926-01-loop-batches.sql` added `batch` and `kind`: a date's first
batch is 1 and each later batch takes the next integer; `kind` is
`batch` or `switch` (the [operations](operations) page's chain switch).
Existing rows kept batch 1 and kind `batch`.

The table was introduced by `20260924-11-loop-dates.sql`, with schedule,
processing date, run, state (`open`, `complete`, `failed`), started and
ended timestamps, promotion id and a `record` JSON column. It is granted
to `rapid_rebuild_pipeline` under the same guard as the rebuild's other
grants.

`record` carries the spec's location and release, each unit's selected
attempt and job id, the field list and the base sets each field bound.
Per field it also carries `base_promoted` (Base catalog, above),
`bases_skipped` (bases the reading rule refused before finding an
eligible one) and `pruned_sets` (the pruned-set instance the field's
`prune` wrote and alerts read). It records the alert container's
instance and location, and the promotion id or refusal reason. Inbox
batches add `record.batch` and `record.deliveries`, the batch's
`loop_deliveries` locations.

`loop_deliveries` (same migration) holds one row per
classified manifest. Its key, `(schedule, location)`, prevents a second
read. Columns record schedule, location, processing date, exposure,
detector, version, checksum, the delivery instance and unit it produced,
state (`batched`, `refused`, `quarantined` or `deferred`), the reason
for any state other than `batched`, batch and discovery time. An index
on `(schedule, exposure, detector, version)` supports classification
lookup. `loop show <schedule>` prints the schedule's `loop_dates` rows,
then its `loop_deliveries` rows.

## Commands

The full command surface for `loop run`, `loop plan` and `loop show`,
including every flag, is on the [tool](tool) page.

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
