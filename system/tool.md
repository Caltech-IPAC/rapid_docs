# The command-line tool

**Status: DRAFT**

The operations the team runs through `rapidpipe`, mapped from the
specification's Tools section onto its subcommands; the input-set
composer; the tool's own exit codes; personal submission from a
workstation; and where the tool runs. Written 2026-09-24 from
supervisor step 4's rulings (R1 through R9). The
[specification](specification)'s Tools section states the requirement;
this page records how the rebuild meets it.

## In plain terms

The team touches one command-line tool: `rapidpipe`, shipped in the
pipeline repository and already the image's entrypoint for a stage
invocation. Step 4 extends it rather than adding a second binary — a
`rapidctl` would contradict the specification's own sentence naming one
tool, and would split an entrypoint the container already carries (R1,
2026-09-24). Everything below is `rapidpipe`'s command surface; nothing
here is a separate program.

## Operations

The specification's Tools section names a small set of operations. Each
maps onto one or more subcommands, all existing arguments keeping their
names:

| Operation | Subcommand |
|---|---|
| Create a run | `run create` (`--seed <run>` copies a previous run's settings and input references; `--release <tag>` is the [releases](releases) page's) |
| Start a stage or the whole loop | `run start` |
| Rerun part of a run | `run start --stage <stage>` |
| Watch progress | `run status [--watch]`, `run show` |
| Cancel and restart from failure | `run cancel <attempt>`, then `run start` |
| List and compare runs | `run list`, `run compare <a> <b>` |
| Promote a candidate | `run promote`, `run rollback` |
| Delete scratch | `run delete`, `run expire`, `run pin` / `run unpin` |
| One unit by hand | `run submit`, `run reconcile`, `run local` |
| A stage directly | `stage run <name> …` (a synonym of `stage <name> …`, the frozen invocation form the container's entrypoint calls), `stage list`, `stage describe <name>` |
| Fixtures | `selftest --stage` |
| Releases | `release cut\|show\|list\|verify` ([releases](releases), supervisor step 5, 2026-09-24) |

`run start <run> --unit <u> [--stage <s>]` walks the run's selected
stages in order, or the one named stage: a complete unit is skipped, a
failed unit with retry allowance left gets a new attempt — this is what
"restart from failure" means for the loop as a whole, alongside
`run cancel` followed by `run start` for one attempt. Each stage's
inputs resolve in this order: an explicit `--inputs` on the command
line, then a `--template` composed through `run inputs` (below), then
the nearest preceding non-`register` stage's selected output (`register`
produces database rows, not files, so a stage that follows it reads
`difference`'s output instead). `--no-wait` submits the first runnable
stage and prints the command that continues the walk; otherwise `start`
polls reconcile until the unit is terminal, printing one line per
attempt (stage, unit, attempt, job, disposition, outputs).

`stage run <name> …` and `stage <name> …` take the one frozen invocation
form the [stage contract](stage-contract) page describes
(`--run --unit --attempt --inputs --outputs [--settings] [--dry-run]`);
the launcher's own submission uses that exact form, unchanged by this
step (R8, R2).

## Input sets

`run inputs <run> <stage> --unit <u> --from-stage <producer> --template <loc> [--dest <loc>]`
is the input-set composer the third supervisor step scripted, promoted
to a tool operation (R4). It reads the template's manifest, replaces or
adds the entry of the producer's output kind with that producer's
selected output, copies that member and the template's other members to
`<dest>` (default a path under the run's own outputs, by run, stage and
unit), writes the composed manifest there, prints the location, and
binds it to the unit when the unit already exists. It refuses to
overwrite a manifest already at `<dest>`.

This is the explicit, whole-input-set form of resolution: which
reference among several eligible ones a field should use is not decided
here (below).

## Exit codes

These are the tool's own reporting codes for `run start`, `run status`
and `run compare`; they are distinct from the five exit codes a stage
itself reports, which the [stage contract](stage-contract) page's Exit
codes table carries.

| Code | Meaning |
|---|---|
| 0 | Success: every requested unit reached complete (`start`), every unit is complete (`status`), or the two runs are identical (`compare`) |
| 1 | A stage or unit failed or was cancelled (`start`, `status`); the two runs differ (`compare`) |
| 2 | Still running: `status` without `--watch`, while a unit remains non-terminal |
| 64 | Usage: bad arguments, or the tool refused rather than acting — for example `run inputs` onto a destination that already carries a manifest |
| 75 | `run start --timeout` expired before a unit reached a terminal state |

## Personal submission from a workstation

A person can run the same commands from a workstation that the launcher
runs from a fleet host. The identities involved are documented in the
systems repository, but the shape reaches this page (R7): the
workstation's own submission role is set as one parameter of the
systems repository's scratch identities, rather than three hand edits
across the policies that name it, so a further per-owner workstation
role is one parameter value. Scratch jobs submitted this way still run
under the scratch job role, exactly as they do from the launcher; only
the submitting identity differs.

Cleanup — `run delete` and `run expire` — has its own principal,
separate from the general workstation role. When the environment
variable `RAPIDPIPE_CLEANUP_ROLE_ARN` is set, the tool assumes that role
for the deletion; when it is unset, the tool deletes under whatever
credentials are ambient, as it does today. During the transition, the
workstation role also carries the cleanup permission directly, so a
failure of the assumed path cannot strand a deletion; removing that
direct attachment is a recorded follow-up, not done by this step.

## Where it runs

The tool runs launcher-side: on a fleet host, under that host's instance
role, exactly where it runs today. Deployment-specific locations,
connection settings and credentials — for example `RAPID_PARAMETER_PATH`
and `RAPIDPIPE_CLEANUP_ROLE_ARN` — reach it through named environment
variables; the pipeline repository's README carries the full list. A
launcher-side change, including everything on this page, needs no image
rebuild and no job-definition deployment: the container's own
`stage <name>` invocation is unchanged, and the live job-definition
revisions this step touches are none (R8).

## Not decided here

- The field-level input resolver — which reference a field should use
  among several eligible ones — and the scheduler's own use of
  `run start` for a processing-date loop: both the seventh supervisor
  step's.
- `--only-failed` on `run start`: the sixth supervisor step's.
- The automatic check gate `run promote` consults: the sixth supervisor
  step's, and scientific content besides.
- Removal of the transitional direct cleanup attachment on the
  workstation role, once the assumed-role path is proven.
