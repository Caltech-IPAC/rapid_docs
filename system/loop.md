# The loop

**Status: DRAFT**

`rapidpipe loop` carries a selection of a live run's data from the
source root to the Kafka topic. Each pass admits what is new, moves
every ready epoch one stage forward, and ends by publishing what became
official. It is one verb run under a timeout from a host, not a service
and not a scheduler of its own. The [foundation](foundation) page
states the records it reads and writes, and the
[intake](intake) page the stage it starts with.

This page replaces the processing-date loop of the retired run model,
with its operations-registry trigger, loop spec, per-date runs and
promotion. Where an older page still points at that loop's discovery,
classification or commands, this page governs.

## In plain terms

The loop looks at the run's source root and at the database, decides
what can run now, submits it to Batch without waiting, and goes to
sleep. Two minutes later it looks again. A filter and SCA with no PSF
gets a job that derives one, and its files wait for it; a file nobody
has taken in gets an intake job; a field with all its images taken in gets a
reference; an image with a reference gets a difference; and each
field's association and packets advance one epoch at a time, oldest
first. At the end of every pass, whatever packet sets became official
go to the topic. When a pass finds nothing new, nothing running and
nothing to submit, the selection is drained and the loop exits.

## Starting a night

Before the loop runs, a night needs four things: a run that names its
source root and reference bound, that run made live for its survey and
dataset, the dataset's Gaia catalog imported under it, and a job
definition revision whose image runs the run's revision. The commands
below run from the top of a checkout of `rebuild`, in the rapid conda
environment, against the team's database. The environment is the
commented block of the
[repository README](https://github.com/Caltech-IPAC/rapid/blob/rebuild/README.md)'s
Getting started section,
with `RAPIDPIPE_OUTPUTS_ROOT` an `s3://` prefix the Batch job role
writes. The example is HLWAS F146, pointing `001_0001`, SCA 8, with
passes 1 to 3 for the reference and pass 4's epoch differenced. Each
night uses a dataset name of its own.

1. **The environment and the names.**

   ```sh
   export PYTHONPATH=$PWD PY=<python3 of the rapid conda environment>
   rp() { $PY -m rapidpipe.cli.main "$@"; }
   D=<a dataset name of your own>                    # e.g. r00342-<initials>-<date>
   SOURCE_ROOT=s3://stpubdata/roman/nexus/soc_simulations/r00342/l2/
   BOUND=61591.4056                                  # the F146 bound, between its third and fourth passes
   GAIA_DIR=<the directory holding the Gaia DR3 Parquet file of the dataset>
   GAIA_FILE=gaia-dr3-hlwas-r00342-box.parquet
   REV=<the 40-character sha of the image the job definition runs>
   JOBDEF=rapid-rebuild:<n>                          # the revision the deploy hook printed for that image
   ```

   The job definition revision comes from `rapid_systems`: the release
   hook registers one per image (`docs/deploying-a-change.md` there).
   The run records a code revision, not a job definition, so the
   revision is the loop's argument.

2. **The run.** `run create` resolves the settings once, from the base,
   the dataset's overlay and the `--set` values, and prints the run's id.
   The source root and the bound are the two keys the base leaves
   absent, so they always come by `--set`. Other filters' bounds are in
   the runbook, part 9 step 2.

   ```sh
   RUN=$(rp run create --who "$USER" --why "<why this night>" --revision $REV \
     --overlay rapidpipe/settings/datasets/hlwas-r00342.toml \
     --set "intake.source_root=\"$SOURCE_ROOT\"" --set reference.selection.before_mjd=$BOUND \
     --survey HLWAS --dataset $D)
   rp run show $RUN | head -20
   ```

3. **Make it live.** A change group is a JSON list of items. This item
   opens the live binding of the survey and dataset for the run:

   ```sh
   echo '[{"open": {"survey": "HLWAS", "dataset": "'$D'", "run": '$RUN'}}]' > live-$D.json
   cat live-$D.json      # [{"open": {"survey": "HLWAS", "dataset": "r00342-...", "run": 91}}]
   rp official change --group live-$D.json --who "$USER" --why "run $RUN live for HLWAS $D"
   ```

   It prints the group's id. A dataset that already has a live run
   refuses the group (exit 1). To replace that run, the same item closes
   its binding as well: `{"close": <the old run's "live" from run show>,
   "open": {...}}`. `official undo <group>` reverses a group.

4. **Import Gaia.** The packet stage names exactly one official Gaia
   catalog of the dataset, so the import runs once per dataset, on this
   host:

   ```sh
   rp job local --run $RUN --stage import \
     --scope '{"source_dir": "'$GAIA_DIR'", "gaia": {"name": "gaia-'$D'", "version": "DR3", "path": "'$GAIA_FILE'"}}' \
     --expects '[{"product": "catalogs", "key": {"dataset": "'$D'", "name": "gaia-'$D'", "version": "DR3"}, "binding": null}]'
   ```

   It prints the job's result: `"published": true`, `"live": true`,
   `"refusal": null`.

5. **The loop**, under a timeout (which runs the module, since it cannot run the `rp` function), from this host:

   ```sh
   timeout 5400 $PY -m rapidpipe.cli.main loop --run $RUN --filters F146 --scas 8 --pointings 001_0001 --passes 1,2,3,4 \
     --job-definition $JOBDEF --interval 60
   echo "loop exit $?"
   ```

   It prints one JSON line a pass. Its first pass submits the PSF job,
   and later passes the intakes, the reference, the difference and the
   packet. The sample drained in 9 to 15 minutes (runs 86, 87, 90 and 97, 2026-10-24).

6. **Check the run.**

   ```sh
   scripts/check_run.sh --run $RUN
   ```

   The script prints one line, `Check run N: CLEAN validate 6/6 reader
   1/1 consumer M/M ...`, and exits 0. Any failure prints `FAIL`
   and exits non-zero.

**What the exit codes mean**, as on `rebuild` at `d4866eab`:

| Code | `loop` | `job local` |
|---|---|---|
| 0 | the selection drained with no failed or refused job (or one `--once` pass saw none) | the job published; under a run that is not live, the refusal is on stderr and on its row |
| 1 | it drained around failed jobs, or jobs published with their binding refused. Each is named on stderr and in the last pass's `failed`, and the rest of the selection drained around them. Read the row's `refusal` (`rp job show <id>`), fix the cause, rerun with `rp job submit --job <id> --job-definition $JOBDEF`, then start the loop again | the job published but its binding was refused under a live run |
| 64 | a usage error: the run does not exist, the selection cannot be parsed, its first pass found no file of the selection under the source root, or the dataset has no single official Gaia catalog when a packet job is due | the run or an input does not exist, or the arguments are wrong |
| 70 | an unexpected error, traceback on stderr | the stage failed: an exception, or a tool's nonzero exit (`ToolFailed`, with the tool's name, code and last 20 lines on the row) |
| 75 | a transient failure: the database was unavailable, or an AWS call was throttled or timed out. Start the loop again | the same; Batch repeats such a job on its own |

## The selection

```
rapidpipe loop --run <id> --filters F146 --scas 8 --pointings all \
    [--passes 1,2,3] --job-definition <name:revision> [--job-queue <queue>] \
    [--max-intake 100] [--interval 120] [--once]
```

The selection is three arguments and an optional fourth: filters, SCAs,
pointings, either `all` or a list of `VVV_EEEE`, a visit and an
exposure, and the survey's passes, applied to the listed files and the
L2 rows alike. A GBTDS pointing is the visit modulo six, so it does not
bound that survey's epochs; a sample there is a source root of chosen
files ([datasets](datasets)). Under an OpenUniverse run
(`[intake] reader = "openuniverse"`) a pointing is the observing
sequence's row, which is the intake's `expid`; the loop lists each
selected filter's prefix in the simulation's legacy spelling
(`--filters F158` lists `H158/`), and `--passes` is refused. Under a
RimTimSim run (`[intake] reader = "rimtimsim"`) the loop lists the
source root's flat prefix of `_lite.fits.gz` files, a pointing is the
file's exposure number, the intake's `expid`, and there are no passes.
A selection admits only its own reader's stems. A pointing is
the same (visit, exposure) pair in every pass of a filter; the
observation number is not part of it, since it can change between
passes of one filter. The selection is the operator's instruction for
this invocation and is recorded in every pass's summary. It is not part
of the run's recipe: widening it changes nothing in the run's settings,
and the same run can be drained one pointing, one SCA or one footprint
at a time.

The loop is for the live run of a survey and dataset. The run's
settings name its source root, and the run holds exactly one open Gaia
catalog binding, which every packet job names. The job definition is an
argument because the run records a code revision, not a job
definition. The loop changes no stage code, so it may run from a newer
checkout than the run's revision while the jobs run the run's image.

## One pass

A pass first asks Batch about the jobs it holds pending, then reads the
source root's listing and one snapshot of the run's tables, decides
every submission from them in a pure function, submits each through
`job submit`'s path without waiting, and publishes.

The listing covers only the selection. A source key's first seventeen
characters name one observation, and an observation is one filter, but
a filter's observation number can differ between passes. So the loop
reads one key of each observation in the source root, keeps the
observations whose filter the selection names, and lists only those in
full. Over the HLWAS simulation that is 23,398 keys instead of 272,160.

Its order:

1. **psf**: the pass's new files are grouped by filter and SCA, and a
   pair without both an official science and an official reference PSF
   gets one [psf](psf) job, named by the pair's first new file, unless a
   psf job of the run already serves it. That SCA's files are held from
   intake until both rows are official; they still count as new, so the
   pass is not drained while they wait. A selection needs no PSF
   imported: its first pass derives what is missing.
2. **intake**: one job per listed file the selection admits that no
   published intake of the dataset and no intake job of this run has
   taken, at most `--max-intake` per pass. Each names its filter's and
   SCA's science PSF. The first intake of an exposure expects the
   shared `exposures` key; the others leave it out.
3. **reference**: one job per field and filter that a selected L2 row
   has as its own field, with no official reference and none pending or
   failed, and only while no intake of the run is pending, so a
   reference coadds every epoch the drain admits rather than the first
   two to land. Its frames are the selected official rows of the
   filter, of any SCA, whose `overlapfields` list the field, at least
   `[reference.selection] min_frames` of them, as `dev` selects them
   ({ref}`ruling <decision-reference-by-field>`). The job's scope records
   the first SCA among the rows it serves.
   With a reference bound set, the rules change as described under
   [The reference bound](#the-reference-bound).
4. **difference**: one job per official L2 row whose field has an
   official reference and whose key has no official difference and no
   difference job of the run pending or failed. With a bound, only rows
   at or after it.
   The difference job associates its own sources with the field's
   objects as they stand ([difference](difference), Association).
5. **packet**: one job per official source set of the selection with
   no official packet set and no packet job of the run pending or
   failed, in any order. It names the reference, the run's Gaia
   catalog, the science PSF and the source set; the objects, their
   members, the forced window's images and the official packet sets'
   forced rows it reads as they stand when it runs, and records.
6. **Kafka**: the recovery sweep. A packet job sends its own set as its
   last act; the pass's `publish` takes only the official, unstamped
   sets whose jobs ended more than 300 s ago and the quality gate does
   not hold ([foundation](foundation), Publication to Kafka), on one
   connection and one producer, one set at a time. A set inside the
   window is reported as `sets_waiting` and keeps the pass from
   draining; a held set is reported in `held_sets` with its metric and
   value. `sets_late` counts the run's official sets stamped more than
   300 s after their job ended, sent by a sweep rather than by their own
   job, so a failing container send shows in every pass line after the
   window. An idle pass opens no producer.

A pass submits at most the run's `[batch] max_submissions_per_pass`
(1,000), in stage order, and reports the rest as `deferred`: the
breadth night's 3,456 intakes submitted at once throttled the parameter
store and 1,448 failed. With `--job-queue` the submissions go to that
queue; a run whose `[batch.spot]` names a Spot queue sends each stage's
backlog there under the four rules of
[Spot, a probe](foundation) and reports `queues` and `attempts`.

There are no field chains and no admission order
({ref}`ruling <decision-association-in-difference>`): every epoch with a
reference is differenced at once, and every official source set gets its
packet job at once, so the loop's only waits are the reference's frames
and the queue.

**Pending and failed.** A job is pending while it is `launched` or
`running`. A job whose container Batch ended without `job run`
recording it is resubmitted once, its Batch name ending `-rerun`, and
held pending; if the rerun's container dies too, the job is failed. A
failed job is reported and never resubmitted: its key counts as taken
until a person reruns it, with `job run --job <id>` on
the host or `job submit --job <id>` on Batch, and the loop then carries
on from it. `job submit --job` marks a failed row `launched` as it
records the new Batch id, so a loop restarted at once counts it
pending. A failed job holds only the work that depends on it: the loop
keeps passing until the rest of the selection drains around it. A
job whose Batch request itself raises (throttled, a queue that does not
exist) is marked `failed` with that error in its `refusal`, never left
`launched` with nothing on Batch, and the error ends the verb (75 when
it is transient).

**The reconcile.** Every job row records the Batch job id it was last
submitted as. At the start of each pass the loop describes the run's
unpublished Batch jobs, a hundred ids a call, and reads the answer two
ways. A Batch job that has ended while its row still says `launched` or
`running` is a container that ended without `job run` recording it: the
row is marked `failed`, with Batch's exit code and its status reason in
the row's `refusal`, and it gets its one rerun (Pending and failed,
above). A row
marked `failed` whose Batch job is still queued or running is Batch's
own retry of exit 75 in flight, and the pass holds it pending rather
than exiting. Once Batch has ended a job, the job's own record is the
authority; a local job, or one Batch no longer describes, is left
alone. The whole reconcile took 0.1 s a pass.

**Drained.** A pass is drained when it found no new file, has nothing
pending and submitted nothing. The verb then exits 0. It exits 0 after
one pass with `--once`, 1 once the selection has drained around a
failed or refused job (or after a `--once` pass that saw one), naming each failed
job's stage and scope in the last pass's `failed` and on stderr, and
64 when the run's dataset has no single Gaia catalog or when its first
pass admits no file: a selection that matches nothing under the source
root (a mistyped root, filter or pass) is named on stderr with the
root, filters, SCAs, pointings and passes, not read as a drain. A later
pass that admits nothing new is the drain. Each pass prints
one JSON line: submitted and pending per stage, failed, held, new,
admitted, listed, packets and sets produced, the reconcile's counts,
drained, its time and the selection. The next pass starts `--interval`
seconds after the last one started, or at once if the pass ran longer.

## The reference bound

A run may set `[reference.selection] before_mjd`, a modified Julian
date. With it set, a field's reference is built only from the epochs
before the bound that overlap the field, and only for a field an epoch
at or after the bound has as its own. Only the epochs at or after it
are differenced, so no epoch is subtracted from a reference that holds it.
The bound is a date rather than a list of passes because a survey such
as GBTDS has no passes ({ref}`ruling <decision-reference-bound>`). Absent, every
epoch may build the reference and every epoch is differenced, as
before.

With the bound set, a reference job names only those official L2 rows
with `mjdobs` before it, and waits until the selection's intake has
drained: every listed file the selection admits is published and no
intake of the run is pending. No intake pending is not enough on its
own, because a pass admits at most `--max-intake` files and a field's
next epoch can still be listed and unadmitted. The rows before the
bound get no difference, association or packet; the field's chain
starts at the bound.

A field that, once the intake has drained, has fewer than `min_frames`
official rows before the bound that overlap it, none at all included, gets no
reference. The pass reports it under `held`, with the field and the
reason, on every pass. A held field does not keep the loop from
draining, and the verb exits 0: the gap is recorded, with no timeout.

## No chain (2026-10-24)

Until 2026-10-24 a field's object sets formed one chain, one `associate`
per epoch in `mjdobs` order, and its packet sets a second chain behind
it; an earlier epoch that arrived late was a rerun from that epoch. The
association now runs in the difference job against the objects of each
touched field as they stand
({ref}`by the source's field <decision-association-by-source-field>`), so data arriving out of order needs nothing: a late
epoch's memberships appear in the packets issued after it arrives and
never in those already sent
({ref}`ruling <decision-association-in-difference>`). Two SCAs on one
field still share one reference.

## What it measured

On SMDC, 2026-10-22, over the HLWAS simulation's F146 data:

| Selection | Epochs | Passes | Loop start to drained | Jobs | Failed |
|---|---|---|---|---|---|
| one pointing, SCA 8 | 6 | 18 | 34.7 min | 25 | 0 |
| every pointing, SCA 8 | 312 | 15 | 42.8 min | 1,300 | 0 |
| one pointing, all 18 SCAs | 102 | 18 | 34.6 min | 424 | 0 |

- **An idle pass** took 29 to 35 seconds on the ramp, about 30 of them
  the listing of the whole source root, 272,160 keys in 273 pages.
  Listing only the selection's observations brought it to 3.8 to
  5.8 s; the listing itself is 95 requests and about 4 s.
- **Submission** takes 0.17 to 0.3 s a job, two short transactions and
  one Batch request; 200 intakes went out in 34 s.
- **A pass that publishes** about 52 packet sets took 251 to 274 s on
  the ramp, about 4.3 s a set and three connections a set, more than
  twice the interval. One connection and one flush per pass brings a
  publishing pass to two connections in all.
- **A chain's span is the pass interval times its depth**: a depth-6
  chain took 20 minutes for about 21 seconds of associate containers,
  and the same across 52 fields at once.

On SMDC, 2026-10-23, the six other filters of the same simulation, one
dataset and one loop each, all six at once:

| Selection | Epochs | Jobs | Loop start to drained |
|---|---|---|---|
| every pointing, SCA 8, six filters | 3,456 | 12,686, 1,448 of them intakes failed and re-planned | 3 h 21 min for all six, with three code fixes and their redeploys; one filter, interrupted once, 49 min |
| one pointing, all 18 SCAs, six filters | 1,088 more | 3,632 | 1 h 22 min, 9 min of it psf reruns |

- **A psf job** adds one queue wait before a pair's first intake: two
  passes, about four minutes, against an imported PSF.
- **A pass can submit thousands of jobs.** The six loops' second passes
  submitted 3,456 intakes in a minute, and 1,448 of them failed reading
  the database parameters from the parameter store, which throttled
  them; each job's read now backs off for minutes, with botocore's own
  retry setting, and none failed after. `--max-intake` is the lever on
  the burst.
- **Publishing at depth sets the pace.** About 30 packets a second per
  loop, one set at a time; a pass of 54 sets of about 205 packets took
  about six minutes, so a chain of 13 or 14 advanced one link each six
  minutes on 54 fields at once, and about two minutes on 17.
- **One failed job stops a loop**: it exits 1,
  a job published with its binding refused counting as failed, and every
  other SCA of that filter waits for the rerun. 72 psf jobs failing at
  once on the CRDS server stopped all six loops for nine minutes.

## Not decided here

- Where the loop runs on a schedule, and at what cadence, once real
  deliveries exist. Today a person starts it under a timeout on a host.
- A chain that advances faster than one link per pass, by passing again
  as soon as chain work ends or by running `associate` and `packet` in
  one Batch job. At GBTDS depth this is the loop's latency.
- An unbounded run's field with fewer than `min_frames` rows still
  waits without a `held` report; only a bounded run reports it.
- Where the bound goes in general. On the HLWAS simulation each
  filter's bound is the midpoint of its own third and fourth passes at
  the first pointing, a run setting per filter; a survey without passes
  needs another rule. Whether a reference disjoint from its epochs
  costs residuals by its depth or by its disjointness is open too
  ([foundation](foundation), Not decided here).
- Whether a failed job should stop only its own filter and SCA rather
  than the whole loop.
- A reconcile of a Batch job that Batch no longer describes is
  unit-tested only; it has not been seen live.
- The mission's own delivery layout and manifest, once the interface is
  defined; today the source root is a directory of SOC files.
- Lanes or resource profiles dedicated to the loop.
