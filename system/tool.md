# The command-line tool

**Status: current**

`rapidpipe` is the team's single command-line tool, shipped in the
pipeline repository and the image's entrypoint. This page lists the
commands it has on the `rebuild` branch, as `rapidpipe --help` and each
command's `--help` print them; the [foundation](foundation) page's "The
verbs" section says what each does to runs, jobs and bindings, and the
[loop](loop) page covers `loop`. A command not on this page does not
exist. An earlier version of this page described the run model the
foundation replaced (`run start`, `run status`, `run list`, `run promote`,
`check run`, `release cut`, `loop run`, `loop plan` and others); it stays
in this repository's history.

## Commands

| Command | Does |
|---|---|
| `run create --who --why --revision [--settings FILE] [--overlay FILE] [--set TABLE.key=VALUE ...] --survey --dataset` | Records a run with its body resolved from the three layers and prints its id |
| `run show <id>` | Prints one run, its live binding and its jobs as JSON |
| `job show <id>` | Prints one job, its recorded inputs and its bindings as JSON |
| `job local --run --stage --scope JSON [--inputs JSON] [--expects JSON]` | Records a job, runs its stage in this process under `RAPIDPIPE_OUTPUTS_ROOT`, publishes it and prints the result |
| `job submit --job-definition D [--job N \| --run --stage --scope JSON [--inputs JSON] [--expects JSON]] [--job-queue Q]` | Records a job (or, with `--job`, takes an existing one's next attempt) and submits one Batch job running `job run --job <id>`; prints the job and Batch job ids |
| `job run --job N` | Runs an existing job's next attempt in this process and publishes it; a published job stops before touching a file |
| `job wait --job N [N ...] [--timeout S] [--interval S]` | Blocks until every named job is published or failed and prints the states |
| `official change --group FILE --who --why` | Applies one change group (a JSON list of items, each with `close` and/or `open`) in one transaction and prints its id |
| `official undo <group-id> --who --why` | Applies the inverse of a change group and prints the new group's id |
| `publish --run N [--settings FILE]` | Produces every official packet set of the run not yet stamped to the Kafka topic, stamping each once acknowledged; prints the counts |
| `loop --run --filters --scas --pointings [--passes] [--expids] --job-definition D [--job-queue Q] [--max-intake N] [--interval S] [--once]` | Admits what is new under the run's `[intake] source_root` for the selection and submits every ready job one stage forward on Batch, one summary line per pass, until a pass finds nothing new, pending or to submit ([loop](loop)) |
| `outage-probe --window DATE --until TIME [--scenario N] [--interval S] [--hold S] [--stall S]` | Meets the database maintenance bracket with one probe scenario (0 fresh login, 1 idle connection, 2 transaction in flight; default the Batch array index) until `--until`, one JSON line per step, and writes its timeline under `RAPIDPIPE_OUTPUTS_ROOT/outage-probe/<window>/<index>-<scenario>/<attempt>/`; temporary, for the windows of 2026-10-29 and 2026-11-05, deleted with outage-probe-read (rapid PR 510) |

The stages the loop submits (`psf`, `intake`, `reference`, `difference`,
`packet`) and `import`, which a person runs by hand before the loop, are
reached through `job local`, `job submit` and `job run`. The older
contract's `stage` and `selftest` commands were retired on 2026-10-25
(rapid PR 464).

## What the tool does not have

There is no command that lists runs or jobs, watches a run or cancels a
job. To look: `run show`, `job show`, the loop's per-pass line, the
pipeline repository's `scripts/check_run.sh` and `scripts/inspect_run.py`,
and the named queries in `database/queries.sql`. To cancel a Batch job:
`aws batch terminate-job`.

## Exit codes

Every `rapidpipe` process uses `rapidpipe/exitcodes.py` (`ExitCode`);
the [stage contract](stage-contract) page lists what `job run` returns.

| Code | Meaning |
|---|---|
| 0 | Success; also a job published under a run that is not live, the refusal on its row and on standard error |
| 1 | A refused change group or a job published with its binding refused; `job wait` when a job failed; `loop`, `--once` included, when a job of the run failed or was published with its binding refused |
| 2 | `job wait`'s `--timeout` passed first |
| 64 | Usage: every argparse parse failure (help exits 0), a missing run, job or group (the foundation's `NotFound`, no other lookup error), an unreadable file, `RAPIDPIPE_OUTPUTS_ROOT` unset, a database configuration error, and `loop` when its first pass finds no stem of the selection under the source root |
| 65 | A declared input rejected by the stage reading it: difference, reference or import (`CommandExit: <reason>` on the row) |
| 69 | Reserved; nothing in this build returns it |
| 70 | An unexpected error, logged with its traceback: a stage's own `KeyError` or `IndexError`, a missing dependency, a failed product write; a failed external tool (`ToolFailed`) |
| 75 | A transient failure: the database unavailable or failing mid-query, a storage or AWS call throttled, timed out or unreachable; Batch retries it |

A failed job's row records the same code its process exits with.

## Where it runs

On a fleet host or a workstation, with the image's environment or a
checkout on `PYTHONPATH`. It reads:

- `RAPIDPIPE_OUTPUTS_ROOT`: the `file://` or `s3://` root every job's
  prefix is under (`job local`, `job run`, `job submit`, `loop`);
- `RAPIDPIPE_BATCH_JOB_QUEUE`: the Batch job queue when `--job-queue` is
  not given; the job definition is always `--job-definition`;
- `RAPIDPIPE_BATCH_JOB_NAME_PREFIX`: the Batch job name's prefix
  (default `rapid`);
- the database: the `PG*` variables when set, else `RAPID_DB_SECRET_ID`
  for the credential, else the SSM parameter tree `RAPID_PARAMETER_PATH`
  names (`rapidpipe/db/connection.py`);
- `RAPIDPIPE_LOG_LEVEL`, which overrides the log level.

The systems repository's `docs/workstation-submission.md` covers
submitting from a workstation.
