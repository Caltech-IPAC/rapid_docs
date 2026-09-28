# Stage contract and package layout

**Status: DRAFT**

A stage implementation is accepted only if it meets this contract.
It expands the specification's "The stage contract" section, drawing on
the specification, the `dev` stage inventory and the `smdc` salvage.

## In plain terms

A stage is one program that takes one declared piece of work, reads the
inputs a manifest lists, does one job, and writes its outputs plus a
manifest saying what it wrote. The same program accepts a local
directory or an S3 location. Image-transform stages use the database
only to check that their run may read the supplied inputs; catalog
stages declare what they read and write. Each execution is an attempt
with its own output location, so a retry cannot overwrite a finished
one. The caller controls retries.

## The package

The repository builds one Python distribution, `rapid-pipeline`,
with import package `rapidpipe`. The word `rapid` alone means the
project. Development workstations use an editable installation;
release images install the distribution built from the recorded
source commit.

| Subpackage | Holds |
|---|---|
| `rapidpipe.products` | Product identifiers, kinds, manifest types, the storage layout beneath a run, and the pure sky-partition geometry `db` needs. |
| `rapidpipe.db` | Persistence: typed repositories, the connection module, the migrations applier. |
| `rapidpipe.science` | Algorithms the stages call: differencing, coaddition, photometry. Pure functions and wrappers around the C tools. |
| `rapidpipe.checks` | The check registry and the shipped policies. Running checks against a run's candidates, and automatic promotion, is `rapidpipe.runs`, not this package. |
| `rapidpipe.runs` | Runs, units of work, attempts, the three output states, promotion, and recording a run. |
| `rapidpipe.stages` | One module per stage, each directly runnable. |
| `rapidpipe.launch` | Turning a run into Batch jobs, enforcing dependencies, reading results back, and the run walk that carries a unit through its selected stages. |
| `rapidpipe.selftest` | Each stage's packaged fixture and the runner that drives it. |
| `rapidpipe.cli` | The command-line tool: parses the command line and prints, with no orchestration of its own. |

A unit test enforces the dependency order across every module,
including lazy and relative imports: a unit imports only units
strictly below it. From lowest to highest, the layers are the leaf
modules (`exitcodes`, `log`, `revision`, `seams`, with no
`rapidpipe` import), `products`, `db` and `science` (which do not
import each other), `checks`, `runs`, `stages`, `launch`,
`selftest`, then `cli`. `release` sits beside this stack: it
imports only the leaves and `db`, and only `cli` imports it. Stage
modules do not import other stage modules, `launch` or `cli`.

The sky-partition geometry comprises the HEALPix indexes and
tessellation fields in a registered image's row. It lives in
`products` so `db` can derive it without importing `science`.

Stage entrypoints live in `rapidpipe.stages`, reusable algorithms in
`rapidpipe.science`, and database access and migration code in
`rapidpipe.db`. Existing code is retained only where it implements
this contract. The container build pins C tool versions and build inputs.

## The stage contract

### Declaration

Every stage exports a declaration containing its name, unit of work,
settings schema, versioned input and output product kinds, database
reads and writes, and supported exit codes. Importing it performs no
I/O. Resources come from the Batch job definition, not the declaration.
Dependencies specify the required product kinds, their mapping to
upstream units, and the condition that makes each input set complete.
A field-wide stage waits for all its declared field inputs.

Stage names are a stable list: `admit`, `reference`, `difference`,
`finalize`, `register`, `load`, `maintain`, `crossmatch`,
`statistics`, `prune`, `alerts`, `export` (`maintain` has its
own page, [maintain](maintain)). Units of work are `exposure`,
`detector-image`, `field`, `processing-date` and `detector-date`
(`detector-date` is `maintain`'s unit; see
[maintain](maintain), "Unit").

### Database access

A declaration specifies one of four access levels. `none` never
connects, and the shared runner skips its read guard. `custody`
connects only for that guard, which judges the custody of every
registered instance named in the input manifest (see "Invocation");
it reads or writes nothing else. `read` and `read-write` also pass
through the guard. Every shipped stage reads an input manifest, so
none declares `none`.

The transform stages (`admit`, `reference`, `difference`,
`finalize`) declare `custody` and need a reachable database whenever
their input manifest names a registered instance. `register` records
file products from manifests; `load` loads source rows. `maintain`
clusters and analyzes a `sources` child table once per observation
date and detector, reading named source sets but writing none of its own.

`crossmatch`, `statistics` and `prune` read named, completed
database result sets and write new run-scoped sets; their manifests
identify both. The run records the catalog versions and epoch range
crossmatch used. Each downstream stage names its exact predecessor
result set, and statistics identify the association set they describe.

`alerts` and `export` also read named, completed database result
sets. `export` writes files only, with no database writes of its own.
No stage changes another run's results or the current selection.

### Invocation

Each stage exposes `main(argv)` and is directly runnable as
`python -m rapidpipe.stages.<name>`; `rapidpipe stage <name>` calls
the same entrypoint. One invocation form:

```
rapidpipe stage <name> --run <run-id> --unit <unit-id> --attempt <attempt-id> \
    --inputs <dir-or-s3-prefix> --outputs <dir-or-s3-prefix> \
    [--settings <toml>] [--dry-run]
```

`--inputs` names a local directory or S3 prefix containing
`manifest.json`; the stage reads only the immutable inputs it lists.
`--outputs` names the attempt's exclusive output location. Each
execution receives a unique attempt ID: the local runner allocates
local IDs, and the launcher allocates one per Batch job it submits.
A Batch job runs its container once, so a retry is a new submission
with a new attempt. The launcher selects at most one completed attempt
per run, stage and unit.

Deployment supplies account-specific locations and connection settings
through the environment; explicit input and output locations may
appear on the command line. Credentials never appear in arguments or
committed settings.

`--dry-run` validates arguments, settings and the input manifest,
then prints the planned inputs and outputs without executing science
code or writing files or database rows. Exit 0 means validation passed;
no completion manifest is written.

The shared runner, `run_stage` in `rapidpipe/stages/contract.py`,
returns on `--dry-run` before the stage's body runs. A stage that
needs kind-specific input validation before that return passes a
`validate_inputs` callable to
`run_stage(..., validate_inputs=<callable>)`. The runner calls it with
the built `StageContext` after generic validation and before the
`--dry-run` return, outside the body.

### Settings

Each stage ships default settings and a settings schema under
`settings/<name>.toml`. `--settings` supplies an overlay: tables merge
recursively, while supplied scalar and array values replace defaults.
Unknown keys and invalid values fail with code 64. Before execution,
the runner retains the resolved settings and their canonical hash.
Algorithm parameters, including random seeds where used, belong in
settings; deployment locations and credentials do not.

### The manifest

A stage publishes its manifest only after its outputs are complete.
Downstream stages use only the completed attempt the launcher selected.
Database writes are attempt-scoped and retry-safe: a retry after an
uncertain commit recovers completed results or discards incomplete ones
without duplicating them. Writing a manifest does not promote products
to current.

The manifest records its schema version; run, unit, stage and attempt
IDs; a reference to the execution record; references to the input
manifest and any database result sets read; and each output's identity,
kind, format version and location, with byte size and SHA-256 for
files. The execution record, kept by `rapidpipe.runs`, retains the
source revision, working-copy changes if any, image digest when
applicable, database schema version, and resolved settings. Input
provenance identifies exact reference versions and their constituent
exposures.

Each product kind defines the registration metadata its manifest entry
must carry. `register` validates that metadata and writes product rows
without reading product contents. It remains independently runnable;
sharing a Batch job with a transform changes nothing about attempt
identity, completion or retry safety.

### Exit codes

| Code | Meaning | Caller's action |
|---|---|---|
| 0 | Success, manifest published | none |
| 64 | Usage: bad arguments, invalid settings, missing environment | fail, no retry |
| 65 | Declared input absent, corrupt or incompatible after its storage was reached | fail, no retry |
| 69 | Declared, not implemented in this build | fail, no retry |
| 70 | Unclassified stage error; stop for investigation | fail, no retry |
| 75 | Recognised temporary dependency failure; repeating the same work may succeed | retry within the limit |

These six codes are the stage subset (`STAGE_EXIT_CODES` in
`rapidpipe/stages/contract.py`) of the vocabulary in
`rapidpipe/exitcodes.py`. The [tool](tool) page has the full table;
a stage never exits 1 or 2. The entrypoint maps argument errors to 64
and unhandled exceptions to 70.

Code 69 is `sysexits`' `EX_UNAVAILABLE`. A stub stage validates
arguments and settings, then declines to run: 64 would misreport a
correct invocation as a usage error, while 70 calls for investigation.
`disposition_for` maps 69 to `failed`. No stage in this build
returns it; it remains reserved for a future stage declared but not
yet implemented (see [decisions](decisions)).

The launcher reports forced termination. Batch does not retry:
the rebuild's job definitions carry one attempt. The launcher retries
as a fresh attempt, within the run's maximum attempts per unit, after
exit 75 or an approved infrastructure failure. These are jobs with no
container exit code whose status reason starts `Host EC2` (the host
was reclaimed) or whose container reason starts `Cannot` or
`DockerTimeoutError` (the container never started). It records other
terminations without a stage exit code, and unexpected codes, as not
retried.

## Local execution

Each stage fixture under `tests/fixtures/<name>/` includes minimal
input files, settings, required database seed data, and expected
products with documented comparison tolerances. It ships as package
data under 1 MB.

`make db` starts a local PostgreSQL with Q3C and applies the
migrations; fixture setup loads the seed data. `make stage-<name>`
prepares an isolated fixture, runs the stage without account
credentials, and checks its products and manifest. Provenance fields
are validated for shape, not compared with fixed IDs or paths. CI uses
the same commands.

The same fixture also runs through `rapidpipe selftest
--stage <name>`
on Batch as an ordinary job against the deployed image and digest.
The submitted job's execution record is evidence that it ran, distinct
from the real-tool fixture gate below. Each rebuilt science stage also
has an IMSS comparison on fixed inputs, with differences and tolerances
approved by the team before operational use.

## What this replaces

This contract replaces the per-stage scripts on `dev`
(`awsBatchSubmitJobs_*`, the launcher and register scripts, the
operator loop) and the `smdc` branch's single dispatching entrypoint
with manifest-driven job types.

The launcher enforces dependencies and controls retries.
`rapidpipe.runs` owns attempt allocation and the execution record.
Stages execute the supplied attempt and report its outputs.

## Not decided here

- Each remaining kind's registration metadata; the vocabulary and the
  difference-image example are on the [products](products) page.
- Whether delivered statistics describe associations before or after
  pruning. A science decision left to the team.
- The C tool packaging beneath `rapidpipe.science`.
