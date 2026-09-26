# Logging, monitoring and job timing

**Status: DRAFT**

What a `rapidpipe` log line looks like and where it goes, what the
record of a run is with and without CloudWatch, what the team can ask of
that record with `rapidpipe` alone, how a Batch job's time is split into
queue, execution and orchestration, how to profile a stage, and a
baseline of today's job durations against a 30-minute target. Written
2026-09-26 by the rebuild direction pass (Lanes C and D) for the team
member who has to find out why a run is slow or what a failed attempt
did. The [stage contract](stage-contract) and the [tool](tool) page
state the invocation and exit-code rules this page builds on.

## In plain terms

Every `rapidpipe` log line has one shape and goes to stderr, so a
command's stdout carries only its data. A stage writes the same lines to
a log file that is published beside its outputs, so the attempt's own
record keeps its log whether or not CloudWatch has it. The database
already records every attempt, its outcome and its execution record; to
those it now adds Batch's own timestamps for each job, which is enough to
say how long a job queued, how long it ran, and how long the tool took to
notice. Nothing here needs an agent, a daemon or a metrics service.

## The line

```
2026-09-26T20:44:27.004Z INFO run=01M3FQCJ7P4EYMZCV2Q9N6KE2F attempt=01M3FQCJ7P4EYMZCV2Q9N6KE2G stage=finalize unit=e20260821001234/SCA07 rapidpipe.stages.finalize finalize: 01J8Y6QZ3MF1NA1E0000000D1F -> 01M3FQCJZH926NEY4XQ91988NQ (diffimage_masked.fits), 4 catalogs
```

(from the `finalize` selftest under release rebuild-v0.8, job definition
`rapid-rebuild:24`, 2026-09-26)

UTC time with milliseconds, level, then `key=value` identity fields in a
fixed order (`run`, `attempt`, `stage`, `unit`), then the logger name
and the message. A field with no value prints `-`: a CLI command outside
any attempt logs `run=- attempt=- stage=- unit=-`. A stage's last line
carries its exit code and its timing (below). The start and exit
messages still repeat `stage= run= unit= attempt=` inside the message,
from before the prefix carried them; dropping the repetition is a small
cleanup for the next release, since a search for `stage=X exit=` matches
the prefix either way. The level is INFO for a
stage and WARNING for the CLI by default; `RAPIDPIPE_LOG_LEVEL` overrides
either.

A wrapped tool's own output (SExtractor, SWarp, awaicgen) is captured
and logged after it returns, as prefixed lines naming the command, its
return code and what it printed. Only what a library writes straight to
stderr, a warning from Photutils or Astropy for example, passes through
unprefixed.

The console handler moved from stdout to stderr on 2026-09-26 (the
direction pass). Nothing in the pipeline read log lines from stdout; `run
local`, which printed its one data line on the same stdout as the
stage's log lines, now keeps the two apart. Batch's log driver captures
both streams, so the CloudWatch record is unchanged.

## The record, with and without CloudWatch

Without CloudWatch, three things hold everything about an attempt:

- **The console stream**: stderr of the process that ran the stage, the
  job's container on Batch or the terminal of `run local`.
- **The per-stage log file**: the same lines, at `log/<stage>.log`
  under the attempt's output location, published with the attempt,
  including when it fails (a failed upload logs a warning and never
  changes the exit code). For outputs in S3 the file is closed and
  uploaded before the stage's final success line is written, so that one
  line (exit code, manifest, timing) is in the console stream and not in
  the S3 copy; the same timing is in the execution record. A `--dry-run`
  writes no file. It is not a manifest member, in the same way
  `exec/<attempt>.json` is not.
- **The database**: `attempts` (started, ended, exit code, disposition,
  output, inputs and settings locations, scheduler job id) and
  `execution_records` (source revision, image digest, release, schema
  version, settings hash, resolved settings, scheduler metadata).

With CloudWatch, the console stream also arrives in the log group the
job definition names (for the rebuild's job definitions,
`/rapid/batch/rapid-queue-prompt`, one stream per job under the prefix
`rebuild` or `rebuild-production`), through Batch's own log driver.
That group keeps 14 days; the per-stage file and the database keep an
attempt's record for the run's lifetime. Nothing is shipped anywhere
else, and nothing the pipeline does depends on CloudWatch being there.

## Monitoring with `rapidpipe` alone

| Question | Command |
|---|---|
| What is running, what failed, in one run | `run status <run>` (`--watch` to follow), `run show <run>` |
| How long each job queued, ran and waited to be noticed | `run timings <run> [--stage S] [--json]` |
| What a processing date did | `loop show <schedule>` |
| Which checks a run's candidates passed | `check show <run>` |
| Which release is deployed where | `release list`, `release show <tag>` |
| What an attempt logged | the per-stage file at `<attempt output>/log/<stage>.log`, or its CloudWatch stream |

Anything beyond these is a read-only query on the database, through the
`rapid_read` login the team already has.

## Where a job's time goes

A Batch job's life has four timestamps the pipeline can see: when the
tool allocated the attempt (`attempts.started`), and when Batch created,
started and stopped the job. `reconcile` records Batch's three in the
attempt's execution record as `scheduler_metadata.batch` when it
records the result, together with the job's attempt count, status
reason, log stream and queue. From those:

| Measure | Derived as | What it tells you |
|---|---|---|
| Submission latency | Batch created minus attempt allocated | The tool's own overhead before Batch knows the job; derivable by query, not printed by `run timings` |
| Queue time | Batch started minus Batch created | Waiting for capacity, including instance start-up |
| Execution time | Batch stopped minus Batch started | The container's run, the thing the 30-minute target is about |
| Reconcile lag | attempt ended minus Batch stopped | How long until `run start` or the loop noticed; mostly the poll interval |

Inside execution, the stage itself times three phases and prints them on
its last line and in its execution record's `timing`: `fetch_s` (copying
inputs and settings from storage), `body_s` (the stage's own work) and
`publish_s` (writing outputs back), with `elapsed_s` the total. So a slow
job answers "was it the science or the storage" from its own log line.
`fetch_s` and `body_s` also go into the execution record's `timing`,
which `reconcile` copies into `scheduler_metadata.stage` for a
successful attempt, so `run timings` prints them; `publish_s` happens
after the record is written and is on the log line only.

None of this needed a new column. Attempts recorded before 2026-09-26
have no Batch timestamps and print `-`.

## Profiling a stage

`--profile` on `run submit`, `run start` or `run local` runs the stage's
body under Python's `cProfile` and writes `profile/<stage>.pstats` and
`profile/<stage>.txt` (the forty most expensive functions by cumulative
time) beside the attempt's outputs. On Batch it reaches the container as
`RAPIDPIPE_PROFILE=1` in the job's environment; a stage invoked by hand
honours the same variable. It is refused on a production run, exit 64:
profiles are for development, and a production attempt's outputs live in
the products bucket. Time spent inside a wrapped C tool (SExtractor,
SWarp, awaicgen) appears as the one Python call that ran it.

## Today's baseline

From the jobs AWS Batch still held on 2026-09-26: 260 rebuild jobs
between 2026-09-23 and 2026-09-25, 208 of them real stage invocations,
all on `rapid-queue-prompt`, every job definition at 1 vCPU and 15 GiB.
Minutes of execution, real invocations only:

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

Queue time was a median of 0.1 to 1.8 minutes per stage, and at most 4.5
minutes, when the compute environment had to start an instance. Five
`difference` jobs in the sample ran in 7 to 20 minutes; what set them
apart (inputs or settings) is not established here, and the per-job rows
behind this table, with job ids, are kept with the direction pass's
records.

`difference` is the one stage over the target, at about twice it in the
typical case. Its log shows where to look first, without
profiling: the Photutils PSF-fit catalogs, run on four images (ZOGY
positive and negative, naive positive and negative), take most of the
hour, and the job has one vCPU. The science-correctness review of
2026-09-12 also found ten million unseeded normal samples drawn in every
clipped-statistics call, which `difference` makes several times. Which
of these dominates is what the first profiled run on the control image
will say; nothing is changed until it has.

## Proposed, not built

- **Metrics.** CloudWatch's embedded metric format would turn the final
  line's timing into metrics without an agent: the same stderr line,
  written as one JSON object, is parsed by CloudWatch Logs into
  per-stage duration metrics. Proposed only; it would add a second line
  shape.
- **The operations scripts' lines.** The shell scripts in the systems
  repository log in three shapes today (`lib.sh`'s timestamped lines on
  stdout, thirteen copies of a `fail()` function in the operations
  scripts, the release hooks' `<script>: message` on stderr). Proposed:
  the same shape as `rapidpipe`'s, `<UTC> <script> <LEVEL> key=value
  message` on stderr, through one formatter, with each script keeping its
  own failure handling and its stdout data. The migration markers and
  the pins hook's JSON, which callers parse from stdout, stay as they
  are. The direction review of 2026-09-26 (in the log) has the detail and
  the cost.
- **CloudWatch retention.** Fourteen days is shorter than a run's life;
  the per-stage file now covers the gap, so no change is proposed.

## Not decided here

- Whether per-stage duration metrics are wanted at all, and by whom.
- A resource profile per stage: `difference` might want more than one
  vCPU once a profile shows where its time goes.
