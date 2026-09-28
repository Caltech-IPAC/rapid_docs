# Logging, monitoring and job timing

**Status: DRAFT**

An attempt's logs and database record show what failed and where time
went. Every `rapidpipe` log line has one shape and goes to stderr;
stdout carries only command data. Stages also publish a log file beside
their outputs, keeping the attempt's log independently of CloudWatch.
Batch timestamps separate queue time, execution and orchestration.
None of this needs an agent, a daemon or a metrics service.

The [stage contract](stage-contract) and the [tool](tool) page state the
invocation and exit-code rules.

## The line

```
2026-09-26T20:44:27.004Z INFO run=<run-id> attempt=<attempt-id> stage=finalize unit=e20260821001234/SCA07 rapidpipe.stages.finalize finalize: 01J8Y6QZ3MF1NA1E0000000D1F -> 01J8Y6QZ3M00000000000MASK1 (diffimage_masked.fits), 4 catalogs
```

Each line gives UTC time with milliseconds, then the level, followed
by `key=value` identity fields in fixed order (`run`, `attempt`,
`stage`, `unit`), the logger name and the message. A missing value
prints `-`: a CLI command outside an attempt logs
`run=- attempt=- stage=- unit=-`. The default level is INFO for a stage
and WARNING for the CLI; `RAPIDPIPE_LOG_LEVEL` overrides either.

A stage's last line carries its exit code and timing (below). Start and
exit messages still repeat `stage= run= unit= attempt=` from before the
prefix carried them. Removing that repetition is a cleanup for the next
release: a search for `stage=X exit=` matches the prefix either way.

A wrapped tool's output (SExtractor, SWarp, awaicgen) is captured and
logged after it returns. Prefixed lines name the command, its return
code and what it printed. Only direct library writes to stderr, such as
Photutils or Astropy warnings, pass through unprefixed.

The console handler writes to stderr. Nothing in the pipeline reads
logs from stdout. `run local` now separates its one stdout data line
from the stage's logs, which used to share that stream. Batch's log
driver captures both streams, so the CloudWatch record is unchanged.

## The record, with and without CloudWatch

Three records hold everything about an attempt without CloudWatch:

- **The console stream**: stderr of the process that ran the stage, the
  job's container on Batch or the terminal of `run local`.
- **The per-stage log file**: the same lines at `log/<stage>.log`
  under the attempt's output location, published even if the attempt
  fails. A failed upload logs a warning without changing the exit code.
  The file and its S3 copy include the final line (exit code, manifest,
  timing). A `--dry-run` writes no file. Like `exec/<attempt>.json`,
  the log is not a manifest member.
- **The database**: `attempts` (started, ended, exit code, disposition,
  output, inputs and settings locations, scheduler job id) and
  `execution_records` (source revision, image digest, release, schema
  version, settings hash, resolved settings, scheduler metadata).

Batch's log driver also sends the console stream to the CloudWatch log
group named by the job definition. The rebuild's definitions use
`/rapid/batch/rapid-queue-prompt`, with one stream per job under the
prefix `rebuild` or `rebuild-production`. The group keeps 14 days; the
per-stage file and database retain the attempt's record for the run's
lifetime. Nothing is shipped elsewhere, and the pipeline does not
depend on CloudWatch.

## Monitoring with `rapidpipe` alone

| Question | Command |
|---|---|
| What is running, what failed, in one run | `run status <run>` (`--watch` to follow), `run show <run>` |
| How long each job queued, ran and waited to be noticed | `run timings <run> [--stage S] [--json]` |
| What a processing date did | `loop show <schedule>` |
| Which checks a run's candidates passed | `check show <run>` |
| Which release is deployed where | `release list`, `release show <tag>` |
| What an attempt logged | the per-stage file at `<attempt output>/log/<stage>.log`, or its CloudWatch stream |

Other questions need a read-only database query through the team's
existing `rapid_read` login.

## Where a job's time goes

The pipeline sees four timestamps in a Batch job's life: attempt
allocation (`attempts.started`) and Batch's job creation, start and
stop. When `reconcile` records the result, it stores Batch's three
timestamps in the attempt's execution record as
`scheduler_metadata.batch`, alongside the job's attempt count, status
reason, log stream and queue.

| Measure | Derived as | What it tells you |
|---|---|---|
| Submission latency | Batch created minus attempt allocated | The tool's own overhead before Batch knows the job; derivable by query, not printed by `run timings` |
| Queue time | Batch started minus Batch created | Waiting for capacity, including instance start-up |
| Execution time | Batch stopped minus Batch started | The container's run, the thing the 30-minute target is about |
| Reconcile lag | attempt ended minus Batch stopped | How long until `run start` or the loop noticed; mostly the poll interval |

The stage times three execution phases and reports them on its last
line and in its execution record's `timing`: `fetch_s` (copying
inputs and settings from storage), `body_s` (the stage's own work) and
`publish_s` (writing outputs back), with `elapsed_s` the total. The log
line shows whether science or storage made a job slow.
`fetch_s` and `body_s` also go into the execution record's `timing`,
which `reconcile` copies into `scheduler_metadata.stage` for a
successful attempt, so `run timings` prints them; `publish_s` happens
after the record is written and is on the log line only.

No new column was needed. Attempts predating Batch timestamp recording
lack those timestamps and print `-`.

The control-image profiling run below exposed a defect: `run timings`
printed a negative `reconcile_lag_s` (about minus 330 seconds for `difference`).
This means `attempts.ended` is stamped before Batch's stop time.
PostgreSQL's `now()` returns the recording transaction's start time;
reconcile opens that transaction before waiting on Batch and reading
the execution record. Recording `clock_timestamp()` instead is the
likely fix. Until then, reconcile lag is unreliable.

## Profiling a stage

Profiling is refused on a production run, exit 64: profiles are for
development, and production attempt outputs live in the products bucket.
`--profile` on `run submit`, `run start` or `run local` runs the stage's
body under Python's `cProfile` and writes `profile/<stage>.pstats` and
`profile/<stage>.txt` (the forty most expensive functions by cumulative
time) beside the attempt's outputs. On Batch it reaches the container as
`RAPIDPIPE_PROFILE=1` in the job's environment; a stage invoked by hand
honours the same variable. Time spent inside a wrapped C tool (SExtractor,
SWarp, awaicgen) appears as the one Python call that ran it.

## Today's baseline

AWS Batch's records cover 260 rebuild jobs, including 208 real stage
invocations, all on `rapid-queue-prompt` with job definitions at 1 vCPU
and 15 GiB. The table gives execution minutes for real invocations
against a 30-minute target:

| Stage | Jobs | Median | 90th percentile | Longest | Over 30 minutes |
|---|---|---|---|---|---|
| `difference` | 19 | 58.4 | 59.4 | 59.6 | 14 |
| `alerts` | 4 | 25.5 | 25.9 | 26.1 | 0 |
| `reference` | 1 | 0.7 | 0.7 | 0.7 | 0 |
| `finalize` | 5 | 0.5 | 0.5 | 0.5 | 0 |
| `load` | 11 | 0.5 | 0.5 | 0.7 | 0 |
| `admit` | 29 | 0.1 | 0.1 | 0.1 | 0 |
| `crossmatch` | 35 | 0.1 | 0.6 | 1.3 | 0 |
| `register` | 43 | 0.0 | 0.5 | 0.6 | 0 |
| `maintain` | 5 | 0.0 | 0.1 | 0.1 | 0 |
| `statistics` | 35 | 0.0 | 0.1 | 0.1 | 0 |
| `prune` | 21 | 0.0 | 0.0 | 0.0 | 0 |

Median queue times ranged from 0.1 to 1.8 minutes per stage. The maximum
was 4.5 minutes, when the compute environment had to start an instance.
Five `difference` jobs ran in 7 to 20 minutes; whether inputs or
settings set them apart is not established here. The per-job rows and
job ids behind the table are kept separately.

`difference` alone exceeds the target, typically taking about twice as
long. Under exact-reproduction settings, the control image's stage body
took 4918 seconds in `cProfile`. Photutils PSF-fit catalogs took 4662
seconds, 95% of that time, in six calls: positive and negative on each
of the ZOGY, naive and SFFT differences. The naive and SFFT branches
together took about 3160 seconds. With the shipped settings, neither
branch's catalogs are registered or loaded; only ZOGY's are. The ten
million unseeded samples per clipped-statistics call do not appear among
the forty most expensive functions.

Skipping unused catalogs, assigning more than one vCPU, or doing both
remains a proposal for the team. This page makes no such change.

## Proposed, not built

CloudWatch's embedded metric format could turn the final line's timing
into per-stage duration metrics without an agent. CloudWatch Logs would
parse the same stderr line written as one JSON object. This is proposed
only and would add a second line shape.

The systems repository's shell scripts currently log in three shapes:
`lib.sh`'s timestamped stdout lines, thirteen copies of `fail()` in the
operations scripts, and the release hooks' `<script>: message` on
stderr. The proposed format matches `rapidpipe`'s:
`<UTC> <script> <LEVEL> key=value
message` on stderr through one formatter. Each script would keep its
failure handling and stdout data. The migration markers and pins hook's
JSON, which callers parse from stdout, would stay unchanged.

CloudWatch's fourteen-day retention is shorter than a run's life. The
per-stage file now covers the gap, so no retention change is proposed.

## Not decided here

- Whether per-stage duration metrics are wanted at all, and by whom.
- A resource profile per stage: `difference` might want more than one
  vCPU once a profile shows where its time goes.
