# Stage contract and package layout

**Status: DRAFT**

Detail beneath the specification's "The stage contract" section, written
2026-09-21 from the specification, the `dev` stage inventory and the `smdc`
salvage, revised on a Codex review and approved in direction by the lead.
A stage implementation is accepted only if it meets this contract.
## In plain terms

A stage is one program that takes one declared piece of work, reads the
inputs a manifest lists, does one job, and writes its outputs plus a
manifest saying what it wrote. The same program accepts a local
directory or an S3 location. Stages that transform images never touch
the database; stages that build the catalog say what they read and
write. Every execution is an attempt with its own output location, so
a retry can never overwrite a finished one. The caller decides about
retries, never the stage.

## The package

The repository builds one Python distribution, `rapid-pipeline`, whose import package is `rapidpipe`. The word `rapid` alone keeps meaning the project. Development
workstations use an editable installation; release images install the
distribution built from the recorded source commit. The package has
these subpackages:

| Subpackage | Holds |
|---|---|
| `rapidpipe.stages` | One module per stage, each directly runnable. |
| `rapidpipe.products` | Product identifiers, kinds, manifest types, the storage layout beneath a run. |
| `rapidpipe.db` | Persistence: typed repositories, the connection module, the migrations applier. |
| `rapidpipe.runs` | Runs, units of work, attempts, the three output states, promotion. |
| `rapidpipe.launch` | Turning a run into Batch jobs, enforcing dependencies, reading results back. |
| `rapidpipe.cli` | The command-line tool. |
| `rapidpipe.science` | Algorithms the stages call: differencing, coaddition, photometry. Pure functions and wrappers around the C tools. |

Dependency direction is fixed. Stage modules do not import other stage
modules. `rapidpipe.products` defines identifiers and manifest types without
importing `runs`, `db` or stages. `rapidpipe.db` provides persistence
without importing `runs` or stages. `rapidpipe.runs` composes products and
persistence. `rapidpipe.science` does not import stages, launch or CLI.
Stages do not import launch or CLI.

Stage entrypoints live in `rapidpipe.stages`, reusable algorithms in
`rapidpipe.science`, and database access and migration code in `rapidpipe.db`.
Existing code is retained only where it implements this contract. C tool
versions and build inputs are pinned by the container build.

## The stage contract

### Declaration

Every stage exports a declaration containing its name, unit of work,
argument and settings schemas, versioned input and output product kinds,
database reads and writes, resource defaults, and supported exit codes.
Importing the declaration performs no I/O. Dependencies specify the
required product kinds, their mapping to upstream units, and the
condition that makes each input set complete.

Stage names are a stable list: `admit`, `reference`, `difference`,
`finalize`, `register`, `load`, `maintain`, `crossmatch`, `statistics`,
`prune`, `alerts`, `photometry`, `export` (`maintain` added by the
supervisor step 1, 2026-09-24: the stage was created by the lead's
ruling of 2026-09-23, described on the [load](load) page, but this list
was not amended until the port landed). Units of work are `exposure`,
`detector-image`, `field`, `processing-date` and `detector-date`
(`detector-date` added the same day, for `maintain`'s unit -- see
[maintain](maintain), "Unit").

Transform stages (`reference`, `difference`, `finalize`, `photometry`)
declare no database access. `register` records file products from
manifests; `load` loads source rows; `maintain` clusters and analyzes a
`sources` child table, once per observation date and detector, reading
named source sets but writing none of its own. `crossmatch`, `statistics`
and `prune` read named, completed database result sets and write new
run-scoped result sets; their manifests identify those input and output
sets. `alerts` and `export` both read named, completed database result
sets; `export` writes files only, with no database writes of its own
(supervisor step 8, ruling R9, 2026-09-24). No stage changes another run's results or the current selection.

The run records the catalog versions and epoch range crossmatch used.
Each downstream stage names its exact predecessor result set. A
field-wide stage waits for all its declared field inputs. Statistics
identify the association set they describe.

### Invocation

Each stage exposes `main(argv)` and is directly runnable as
`python -m rapidpipe.stages.<name>`; `rapidpipe stage <name>` calls that same
entrypoint. One invocation form:

```
rapidpipe stage <name> --run <run-id> --unit <unit-id> --attempt <attempt-id> \
    --inputs <dir-or-s3-prefix> --outputs <dir-or-s3-prefix> \
    [--settings <toml>] [--dry-run]
```

`--inputs` names a local directory or S3 prefix containing
`manifest.json`; the stage reads only the immutable inputs that manifest
lists. `--outputs` names the attempt's exclusive output location. Every
execution receives a unique attempt ID and an exclusive output location:
the local runner allocates local attempt IDs, the Batch wrapper
allocates one per Batch attempt, and the launcher selects at most one
completed attempt per run, stage and unit. Deployment supplies
account-specific locations and connection settings through the
environment; explicit input and output locations may appear on the
command line. Credentials never appear in arguments or committed
settings.

`--dry-run` validates arguments, settings and the input manifest, then
prints the planned inputs and outputs without executing science code or
writing files or database rows. Exit 0 means validation passed; no
completion manifest is written.

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
files. The execution record, kept by `rapidpipe.runs`, retains the source
revision, working-copy changes if any, image digest when applicable,
database schema version, and the resolved settings. Input provenance
identifies exact reference versions and their constituent exposures.

Each product kind defines the registration metadata its manifest entry
must carry. `register` validates that metadata and writes product rows
without reading product contents. It stays independently runnable;
whether it shares a Batch job with a transform changes nothing about
attempt identity, completion or retry safety.

### Exit codes

| Code | Meaning | Caller's action |
|---|---|---|
| 0 | Success, manifest published | none |
| 64 | Usage: bad arguments, invalid settings, missing environment | fail, no retry |
| 65 | Declared input absent, corrupt or incompatible after its storage was reached | fail, no retry |
| 69 | Declared, not implemented in this build | fail, no retry |
| 70 | Unclassified stage error; stop for investigation | fail, no retry |
| 75 | Recognised temporary dependency failure; repeating the same work may succeed | retry within the limit |

Code 69 is `sysexits`' `EX_UNAVAILABLE`, chosen over 64 (which would
misreport a correct invocation as a usage error) and 70 (which calls
for investigation): a stub stage that validates its arguments and
settings and then declines to run is neither of those things.
`disposition_for` maps it to `failed`. `photometry` and `export` are
declared stages that exit 69 for every invocation past validation in
this build (supervisor step 8, ruling R9, 2026-09-24; see
[photometry](photometry) and [export](export)).

The entrypoint maps argument errors to 64 and unhandled exceptions to
70. Forced termination is reported by the launcher, not the stage.
Batch retries code 75 and explicitly selected infrastructure failures,
with a final catch-all rule that exits; Batch matches at most five such
rules and its attempt limit counts the first attempt. The launcher also
records terminations without a stage exit code and unexpected codes.

### Settings

Each stage ships default settings and a settings schema under
`settings/<name>.toml`. `--settings` supplies an overlay: tables merge
recursively, supplied scalar and array values replace defaults. Unknown
keys and invalid values fail with code 64. Before execution the runner
retains the resolved settings and their canonical hash. Algorithm
parameters, including random seeds where used, belong in settings;
deployment locations and credentials do not.

## Local execution

Each stage fixture under `tests/fixtures/<name>/` includes minimal input
files, settings, required database seed data, and expected products
with documented comparison tolerances, shipped as package data at under
1 MB. `make stage-<name>` prepares an isolated fixture, runs the stage
without account credentials, and checks its products and manifest;
provenance fields are validated for shape, not compared with fixed IDs
or paths. `make db` starts a local PostgreSQL with Q3C and applies the
migrations; fixture setup loads the seed data. CI uses the same
commands. The same fixture also runs through `rapidpipe selftest
--stage <name>` on Batch, as an ordinary job against the deployed image
and digest, replacing the docker run on rapid-admin that served until it existed; the submitted job's
execution record is the evidence that it ran, distinct from the
real-tool fixture gate below (lead, 2026-09-23). Each rebuilt science
stage also has an IMSS comparison on fixed inputs, with differences and
tolerances approved by the lead before operational use.

## What this replaces

The per-stage scripts on `dev` (`awsBatchSubmitJobs_*`, the launcher and
register scripts, the operator loop) and the `smdc` branch's single
dispatching entrypoint with manifest-driven job types. The launcher
enforces dependencies and controls retries. `rapidpipe.runs` owns attempt
allocation and the execution record. Stages execute the supplied attempt
and report its outputs.

## Not decided here

- Each remaining kind's registration metadata; the vocabulary and the
  difference-image example are on the [products](products) page.
- Whether delivered statistics describe associations before or after
  pruning. A science decision for the lead.
- The exact Batch infrastructure-failure patterns to retry.
- The C tool packaging beneath `rapidpipe.science`.
