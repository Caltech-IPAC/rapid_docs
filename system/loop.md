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

[[dates]]
processing_date = "2027-10-01"

[[dates.detector_images]]
delivery = "control/20260923/delivery/r0034001002001001001-sca01"
admit_settings = "control/20260923/settings/admit-socsim.toml"
difference_template = "control/step3/P1/inputs"
difference_settings = "control/20260923/settings/difference-gain1-imgnoise.toml"

[[dates]]
processing_date = "2027-10-02"

[[dates.detector_images]]
delivery = "control/20260923/delivery/r0034001002001001001-sca01"
admit_settings = "control/20260923/settings/admit-socsim.toml"
difference_template = "control/step3/P1/inputs"
difference_settings = "control/20260923/settings/difference-gain1-imgnoise.toml"
```

This is `control-loop`, the spec ruling R8 names for the two dates on
the control inputs: `s3://roman-rapid-scratch/rapidpipe-firstrun/control/loop/control-loop.toml`,
release the tag ruling R9 cuts, policy step 6's `rebuild-trial@1` once
landed. The second date's crossmatch binds the first date's association
set for its field; the evidence is the second date's statistics rows and
its crossmatch row counts.

`loop run` processes, in spec order, every date whose `loop_dates` row is
absent or `open`; concurrency, retries and exit codes are below
(Concurrency and recovery).

## Per date

Each processing date becomes one production run, created through the
CLI's `run create --release` path: owner and lane from the spec, purpose
`"processing date <D> (schedule <S>)"`, `input_selection_ref` the spec's
location, `check_policy_ref` the spec's policy, `max_attempts_per_unit`
the spec's, and `selected_stages` the loop's own chain: admit, register,
difference, finalize, register, load, maintain, crossmatch, statistics,
prune, alerts — one `register` fewer than first ruled, since the landed
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
(crossmatch's output) → prune (crossmatch's output). Then alerts per
detector image, its input set the finalized difference image plus the
template's reference catalog plus the source set, the field association
sets and the field statistics sets, the recipe `compose-alerts-inputs.py`
already scripts. Submission and polling go through `submit_unit` and
`reconcile`, as `run start` uses them for one unit at a time.

## Base catalog

A field's base catalog is the association-set instance its crossmatch
produced in the most recent earlier `loop_dates` row of the same
schedule that is `complete` and has an association set for that field —
that row's run's selected attempt for the field's unit — or none, if no
earlier complete row has one, on a schedule's first date or a field new
to a later one. A failed or still-open date has no association set to
offer, so the search steps back past it to the most recent complete
one: one date's failure does not stall base-catalog binding for the
dates that follow it. The base date need not itself be promoted:
association sets bind by instance, not by current custody, so an
unpromoted complete date is still an eligible base, and `prune`'s own
not-best exclusion, not promotion, is what keeps an inferior instance
out of the chain a later date reads. Each field's entry in the date's
record notes `base_promoted` — whether the date that supplied its base
had itself been promoted at bind time (ruling R5, amended, supervisor
step 7, 2026-09-24, after the Codex plan review). Input-set manifests
for crossmatch and alerts are written under
`<scratch root>/runs/<run>/inputs/<stage>/<unit>/`, the same layout the
[tool](tool) page's composer uses. This is the loop's own instance of the
field-level input selection the tool page leaves open; which reference a
field should use among several eligible ones is still not decided
(below).

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
schedule for its whole run; a second launcher for the same schedule — a
stray retry, an overlapping Maintenance Window — exits 75 without
touching any date, rather than racing the first (supervisor step 7,
2026-09-24, after the Codex plan review).

Within the lock, dates are processed in spec order. A `complete` row is
skipped, and an `open` row is resumed as described above (The loop
spec): complete units skipped, running attempts attached, ready units
re-attempted. A `failed` row is also skipped by default; `loop run
--retry-failed` reopens it to `open` and resumes the same run rather
than creating a new one, walking its units the same way. A date's move
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

`loop run` exits 0 when every date it processed reached `complete`, 1 on
the first date that fails with no later date started, and 75 on a
timeout or a lock already held.

## Records

Each schedule and date is one row of `loop_dates` (migration
`20260924-11-loop-dates.sql`): schedule, processing date, run, state
(`open`, `complete`, `failed`), started and ended timestamps, the
promotion id, and a `record` JSON column, granted to
`rapid_rebuild_pipeline` under the same guard as the rebuild's other
grants (ruling R7). `record` carries the spec's location and release,
each unit's selected attempt and job id, the field list, the base sets
each field bound and, per field, `base_promoted` (above, Base catalog),
the alert container's instance and location, and the promotion id or
refusal reason. `loop show <schedule>` prints these rows.

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
| `loop run --spec <loc> [--date D]… [--retry-failed] [--dry-run] [--interval N] [--timeout N]` | Runs every date in the spec whose `loop_dates` row is absent or `open`, in spec order, under the schedule's advisory lock; `--date` restricts to named dates; `--retry-failed` also reopens and resumes `failed` dates |
| `loop plan --spec <loc>` | Prints what `run` would do: the dates it would process and the runs it would create, without creating them |
| `loop show <schedule>` | Prints the schedule's `loop_dates` rows |

## Not decided here

- Real deliveries per date, drawn from the archive rather than a spec's
  fixed list.
- Parallel dates: today's loop runs dates one after another.
- Lanes or resource profiles dedicated to the loop, beyond the one the
  spec names.
- The steady-state cadence, once real deliveries exist to advance
  against.
- Publishing the alerts a date's run produces.
