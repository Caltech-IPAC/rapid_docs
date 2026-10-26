# Stage contract and package layout

**Status: current**

A stage implementation is accepted only if it meets this contract. The
[foundation](foundation) page states the records a stage works within:
runs, jobs, recorded inputs, official bindings and the publisher.

## In plain terms

A stage is one Python function. It is given a job: the run's settings,
the inputs chosen for the job at launch, and a folder whose path names
the job and the attempt. It reads only what the job names, computes in
memory, writes its files and a manifest that says which of them are
catalog rows, and returns. It never writes a catalog row and never
decides what is official. The runner around it then calls the
publisher, which loads the declared rows in one transaction. A retry is
a new attempt of the same job in a new folder, and a job that is
already published is never run again.

## The package

The repository builds one Python distribution, `rapid-pipeline`, with
import package `rapidpipe`. The word `rapid` alone means the project.

| Subpackage | Holds |
|---|---|
| `rapidpipe.products` | Product identifiers, the manifest types, the storage layout, and the pure sky-partition geometry (HEALPix indexes and tessellation fields). |
| `rapidpipe.db` | One connection from the `PG*` environment, a secret or a parameter tree. |
| `rapidpipe.science` | Algorithms the stages call: differencing, coaddition, limiting magnitude, the in-memory matcher, sufficient sums, alert records, cutouts, forced photometry. Pure functions and wrappers around the C tools. |
| `rapidpipe.foundation` | The operations over `database/schema.sql`: runs and jobs, `change` and `undo`, `publish`, the stage contract (`JobContext`, `run_job`), and reading and writing `file://` and `s3://` prefixes. |
| `rapidpipe.stages` | One module per stage. |
| `rapidpipe.launch` | Submitting a recorded job to Batch. |
| `rapidpipe.cli` | The command-line tool: parses the command line and prints, with no orchestration of its own. |

A unit test enforces the dependency order across every module,
including lazy and relative imports: a unit imports only units strictly
below it. From lowest to highest: the leaf modules (`exitcodes` and
`log`, with no `rapidpipe` import), `products`, then
`db`, `science` and `foundation` (which do not import one another),
`stages`, `launch`, then `cli`. The `reference` and `difference` unit
tests' fake toolkits are under the repository's `tests/support/`. A stage module never imports
another stage module.

## The stage contract

### A stage is `run(job)`

A stage is `rapidpipe/stages/<name>.py` with one function,
`run(job: JobContext) -> None`. The stage named `import` lives in
`import_products.py`, since `import` is a Python keyword. The stages on
this contract are `intake`, `psf`, `import`, `reference`, `difference`
and `packet`; the [foundation](foundation) page describes each. A stage
that needs a C tool (awaicgen, SExtractor, SWarp, ZOGY, SFFT) gets it
from a `toolkit()` function in its module, which its unit tests
replace with fakes.

`JobContext` carries:

- `job`, `run`, `stage`, `scope`, `survey`, `dataset`: the job's
  identity and the scope it was launched with;
- `settings`: the run's whole settings body, from which the stage reads
  its own table;
- `inputs`: the job's recorded `job_inputs` rows (`kind`, `product`,
  `key`, `source_job`, `binding`), the authority for what the stage
  reads. An input is told apart from another of its product by its key
  alone: a `psfs` key carries its `kind`, `science` or `reference`, so
  `difference` names one of each and never reads a file to decide
  which is which;
- `attempt` and `prefix`: the attempt number and its URL,
  `<outputs root>/<run>/<stage>/<job>/<attempt>/`, and `path`, the local
  directory the stage writes into;
- `connect()`: a context manager yielding a database connection for
  short reads, closed on exit.

A stage reads the rows and files its inputs name, in short
transactions, and never the official views: what is current is decided
by whoever launched the job. It computes in memory, writes its files
under `path`, and writes the manifest with
`job.write_manifest([(table, file), ...], **fields)` last. It returns
without publishing.

### Settings

A stage's settings are its table in the run's settings body, for
example `[reference]` in `rapidpipe/settings/foundation-thin.toml`. The
body is stored whole on the run when the run is created, so there is no
overlay and no resolution at run time; a retune is a new run.
Algorithm parameters belong in settings, with `dev`'s values where
`dev` hard-codes them. Data locations and credentials do not: a source
directory is a job's scope, and the outputs root is the environment's
`RAPIDPIPE_OUTPUTS_ROOT`.

### The manifest

`manifest.json` under the attempt's prefix declares the files the
publisher loads:

```json
{"outputs": [{"table": "objects", "path": "objects.parquet", "checksum": "sha256:<64 hex>"}]}
```

`table` is one of the product tables, `path` is relative to the
prefix, and `checksum` is the file's SHA-256. Each Parquet file holds
the table's columns without `job`, which the publisher sets; columns
the file leaves out take their defaults. Any further fields a stage
passes (counts, timings, provenance) are kept with the manifest on the
job row. Files the manifest does not declare are the stage's own
products, reached through the URL a declared row records.

### Running a job

`rapidpipe.foundation.run_job` runs one attempt of one job, and every
way of running a stage goes through it:

- `rapidpipe job local --run <id> --stage <name> --scope JSON
  [--inputs JSON] [--expects JSON]` records the job
  and runs it in this process;
- `rapidpipe job run --job <id>` runs an existing job's next attempt;
- `rapidpipe job submit ... --job-definition <name:revision>` records
  the job and submits one Batch job to the queue in
  `RAPIDPIPE_BATCH_JOB_QUEUE`, whose command, after the image's
  `rapidpipe` entrypoint, is `job run --job <id>`; with `--job <id>` it
  submits an existing job's next attempt. The id Batch returns is
  written on the job row, replacing any earlier one, and the
  submission asks for the stage's memory from the run's
  `[batch.memory_mib]` table.

`run_job` reads the job and stops at once, touching no file, if it is
already published. Otherwise it claims the next attempt, marks the job
`running` with its start time and, from `RAPID_IMAGE_DIGEST`, the image
digest the job definition pins (none from a checkout) and beside it the
instance type from the instance's metadata service (none when it does
not answer), closes its
connection, and calls the stage's `run(job)`. An attempt's start
clears the row's `refusal`, so a reason the loop's reconcile wrote does
not outlive the next attempt. Under an `s3://` outputs root the stage
writes into a local working directory, which `put` uploads to the
attempt's prefix, manifest last, before publication, and which is
removed once the upload returns.
Then it calls `publish`, records the end time and exit code, and
returns the publisher's result with `peak_rss_kib`: the peak resident
memory of the Python process and of its largest finished child. Batch
runs one attempt at a time; two concurrent attempts of one job are not
supported on `s3://`. The [foundation](foundation) page states how the
prefix functions behave and how a commit gets its image and job
definition.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | The job was published, or was already published; or it was published and its automatic binding was refused only because its run is not live, the refusal on its row and on standard error |
| 1 | The job was published, but its automatic binding was refused for another reason, such as an expected binding no longer open; its rows are an unbound candidate |
| 64 | Usage: bad arguments, no outputs root, a stage with no `run(job)`, a run or input that does not exist (the foundation's `NotFound`), or a database configuration that cannot be read |
| 65 | A declared input the stage rejects (`CommandExit(65, reason)`): difference's, reference's and import's input checks |
| 70 | The stage or the publication raised, a tool's nonzero exit (`ToolFailed`), a stage's own lookup error, a missing dependency or a failed product write included, with the traceback; the job is marked `failed` |
| 75 | A temporary dependency failure: the database unavailable or failing mid-query after the connection's own retries, or a storage or AWS call (the parameter store's included) throttled, timed out, unreachable or answered with HTTP 503 |

A failed job's row records the code the process exits with, and its
`refusal` is `<Class>: <message>`, at most 500 characters; the
traceback is in the job's log.

On Batch, exit 75 and nothing else is retried: the job definition
allows three attempts, and any other exit code, or a failure with no
exit code, ends the job. A bad parameter tree is 64 and is not retried.
Off Batch nothing retries by itself. Every retry, whether Batch's, a
`job run` on the same job or a resubmission, lands in a new attempt,
and one that finds the job published stops at once. The
[foundation](foundation) page states the rule and why.

## The older contract, retired

`admit` and `finalize` ran on an older contract, `rapidpipe stage <name>
--run --unit --attempt --inputs --outputs`, through a shared runner,
with per-stage settings files and a packaged fixture under `rapidpipe
selftest`; they wrote files and a manifest and published nothing, and
the loop ran neither. They, the runner, the `stage` and `selftest`
commands and the fixture were retired on 2026-10-25 (rapid PR 464); git keeps
them. `run(job)` is the one contract.

`reference` and `difference` were ported to `run(job)`, and the port set the
pattern: the module's settings file becomes the stage's table in the
run's body, its old entry point, selftest module and fixtures are
deleted rather than kept beside the new one, and the science modules
keep their `# ported-from:` pins on `dev`.

## What this replaces

This contract replaces the run model's stage invocation: the
`--run/--unit/--attempt` arguments, the execution record, custody
checks before a stage reads, `register` writing rows from manifests,
and stages writing catalog rows themselves. The run model's database
stages (`register`, `load`, `maintain`, `crossmatch`, `statistics`,
`prune`, `alerts`, `export`) were retired with its schema; `intake`,
`psf`, `import` and `packet` replace the ones the thin chain needs, and
the association runs in the `difference` job.

## Not decided here

- Whether a post-processing stage (database ids in headers, the header
  stamp `finalize` wrote) returns: the [migration](migration) page's
  question for the team.
- The C tool packaging beneath `rapidpipe.science`.
