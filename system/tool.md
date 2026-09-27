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
invocation. Step 4 extends it rather than adding a second binary: a
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
| Create a run | `run create` (`--seed <run>` records lineage only: it inherits no settings and no input references from the seeding run, unless paired with `--only-failed`, which makes it a recovery run over the seed's non-complete units instead (the [runs](runs) page has the mechanics); `--release <tag>` is the [releases](releases) page's; `--auto-promote --check-policy P` is refused unless P permits automatic promotion (the [checks](checks) page has the gate); supervisor step 6, 2026-09-24) |
| Start a stage or the whole loop | `run start` |
| Rerun part of a run | `run start --stage <stage>` |
| Watch progress | `run status [--watch]`, `run show`, `run timings [--stage S] [--json]` (queue, execution and orchestration time per attempt; the [observability](observability) page, direction pass, 2026-09-26) |
| Cancel and restart from failure | `run cancel <attempt>`, then `run start` |
| List and compare runs | `run list`, `run compare <a> <b>` (each `instance` line now carries the slot column beside the provenance key; supervisor step 5a, 2026-09-26) |
| Promote a candidate | `run promote --check-policy P` (defaults to the run's own `check_policy_ref`, then `rebuild-trial@1`); `run promote-plan <run>` prints the run's slot groupings as a frozen plan, without promoting; `run promote <run> --plan <file>` applies that plan, refusing (exit 64) if the current selection or the run's candidates have moved since, or if the file is not a non-empty JSON list of `{kind, slot, before, after}` entries (JSON `null` included); `run rollback` ([checks](checks) page has the gate; supervisor step 6, 2026-09-24; the plan commands, supervisor step 5a, 2026-09-26, amendment 2) |
| Delete scratch | `run delete`, `run expire`, `run pin` / `run unpin` |
| One unit by hand | `run submit`, `run reconcile` (`--resolve-jobless [--older-than SECONDS]` records a job-less attempt `lost` (the [runs](runs) page has the mechanics); supervisor step 6, 2026-09-24), `run local` |
| Verify a candidate | `check list`, `check run <run> [--policy P] [--instance I] [--check NAME@V]`, `check show <run>` ([checks](checks), supervisor step 6, 2026-09-24) |
| A stage directly | `stage run <name> …` (a synonym of `stage <name> …`, the frozen invocation form the container's entrypoint calls), `stage list`, `stage describe <name>` |
| Fixtures | `selftest --stage` |
| Releases | `release cut\|show\|list\|verify` ([releases](releases), supervisor step 5, 2026-09-24) |
| The processing-date loop | `loop run\|plan\|show` ([loop](loop), supervisor step 7, 2026-09-24) |

`run start <run> --unit <u> [--stage <s>]` walks the run's selected
stages in order, or the one named stage: a complete unit is skipped; a
unit already terminal `failed` or `cancelled` is not re-attempted:
`start` prints its state and exits 1, and recovering it is the sixth
supervisor step's `--seed`/`--only-failed`, not this step's; a unit with
an attempt still running is attached to and polled, never resubmitted;
and a unit reconcile returns to `ready` after a transient result (exit
75, or a lost job) gets another attempt within its allowance. `run
cancel` followed by `run start` is how a person restarts one attempt by
hand. A run created with `--release <tag>` submits to that release's
recorded job-definition revisions rather than whatever a job definition
currently pins, and its outputs are promotable without the
unreleased-image exception ([releases](releases) page). Each stage's
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
`<dest>`, admits and binds the unit through `bind_input_set` before
writing the composed manifest there last, and prints the location. It
refuses to overwrite a manifest already at `<dest>`.

An input set is a staged working copy, not a product, so `<dest>`
defaults to, and `--dest` is refused outside,
`<scratch root>/runs/<run>/inputs/<stage>/<unit>/`, the scratch outputs
root, for every run kind, since the launcher host has no write access to
the products bucket. Before copying, the composer checks the run's
admission fence: a run that is finished, deleting or already deleted
admits no new input set. `run delete` removes a run's inputs prefix
along with its attempt outputs.

Every submission now binds its input set, not only one composed by this
command. Before any write, `run submit`, `run start` and `run local`
all read `manifest.json` at `--inputs`, whether it came from `run
inputs`, a producing stage's own completion manifest, or a hand-composed
one; collect every output entry's instance and every
`inputs.result_sets` entry (not `inputs.products`, which name what the
*upstream* attempt read, not this unit's own binding); create the unit;
bind the collected names that are registered product instances through
`bind_unit_inputs`; commit both together; and only then allocate the
attempt. A name that is not a registered instance (a delivery manifest,
a dev-era template entry) binds nothing and is logged, not refused. A
manifest that is absent, invalid or unreadable for a non-network reason
refuses the submission before anything is written, exit 65; a network
error is exit 75 instead. Binding is idempotent per (unit, instance), so
a retry or a seeded `--only-failed` re-run binds nothing new. This is
what makes a unit a live consumer of its declared inputs from
submission, not only once it has produced an output of its own to
depend on ([runs](runs) page, "Units", "Deletion"; supervisor step 9,
ruling R4, 2026-09-25).

This is the explicit, whole-input-set form of resolution: which
reference among several eligible ones a field should use is not decided
here (below).

## Exit codes

One vocabulary covers every `rapidpipe` process, in the module
`rapidpipe/exitcodes.py` (`ExitCode`). The [stage contract](stage-contract)
page's Exit codes table carries the six of these a stage itself reports
(0, 64, 65, 69, 70, 75); a stage never exits 1 or 2. The table below is
the full eight, with which command family returns each one folded into
the third column.

| Code | Meaning | Returned by |
|---|---|---|
| 0 | Success: the command did what was asked | every family |
| 1 | A negative outcome: a stage or unit failed or was cancelled, two runs differ, a check failed, or a release refused (a check or a hook failed, a resume did not match, verify found a mismatch) | `run start`, `run status`, `run compare`, `run show`, `run submit` (a release whose recorded job-definition revision is refused, not `ACTIVE`); `run inputs` (an input's size mismatch); `loop run`; `check run`; `release cut\|show\|list\|verify` |
| 2 | Still running: a unit remains non-terminal | `run status` |
| 64 | Usage, configuration or an unmet precondition: bad arguments, including every argparse parse failure from every command family (help still exits 0), invalid settings, a refused destination, a dirty tree, a tag that exists, missing hooks, a release whose record is not `complete`, or a stale promotion plan (`run promote --plan`) | every family; `release cut\|show\|list\|verify`, `run create` included |
| 65 | A declared input absent, corrupt or incompatible once its storage was reached (a stage's own invocation); `run submit`, `run start` or `run local`'s own input-manifest read failed for a non-network reason, the manifest absent, not JSON, or failing validation; or a deleting or deleted producer met while `run inputs` or the loop binds an input set. Nothing is written (supervisor step 9, ruling R4, 2026-09-25; supervisor step 2, 2026-09-26) | a stage's own invocation; `run submit`, `run start`, `run local`; `run inputs` (a deleting or deleted producer at bind time); `loop run` (the same, met while the loop composes an input set; a refusal at submission still fails the date with exit 1, as before) |
| 69 | Declared but not implemented in this build | a stage's own invocation (`stage run <name>`, the form Batch runs) |
| 70 | An unclassified error; stop and investigate | every family: an unexpected error escaping a command is logged with its traceback and exits 70 (supervisor step 1, 2026-09-26); and a stage's own invocation |
| 75 | `run start --timeout` expired before a unit reached a terminal state, or the tool hit a transient database or AWS failure, including a network-shaped error reading the input manifest: any of these is retryable | `run start`, `run submit`, `run local`; every family for a transient database failure (`release cut\|show\|list\|verify`, `run create`, `check` included); `loop run`'s lock or timeout |

`selftest` reads its own subset: 0 when every check passes, 1 when a
check fails or the stage under test exited 0 where the fixture expected
a non-zero code, 64 when the work directory already exists, and
otherwise the stage's own unexpected code.

Three invariants follow from finishing the unification (supervisor
step 1, 2026-09-26). A parse failure exits 64 from every family: every
`rapidpipe` parser, nested subparsers included, is
`rapidpipe.exitcodes.ArgumentParser`, whose usage error exits 64
directly, and help still exits 0. The stage runner keeps its older
translation of a parse failure to 64 for `stage run <name>` as a
safeguard. Because of that, 2 now means only "still running", never
"could not parse". And `release` spells its own usage and precondition
refusals 64, the same as every other family, not 2.

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

Cleanup (`run delete` and `run expire`) has its own principal,
separate from the general workstation role. When the environment
variable `RAPIDPIPE_CLEANUP_ROLE_ARN` is set, the tool assumes that role
for the deletion; when it is unset, the tool deletes under whatever
credentials are ambient, as it does today. During the transition, the
workstation role also carries the cleanup permission directly, so a
failure of the assumed path cannot strand a deletion; removing that
direct attachment is a recorded follow-up, not done by this step.

`run cancel` needs `batch:TerminateJob` on whichever identity issues
it. The workstation instance role (`rapid-rusholme-instance-role`) does
not carry that permission yet, so a cancel issued from a workstation
fails `AccessDenied` until the systems repository grants it; the
launcher's own fleet-host role is unaffected (supervisor step 6
finding, 2026-09-24).

## Where it runs

The tool runs launcher-side: on a fleet host, under that host's instance
role, exactly where it runs today. Deployment-specific locations,
connection settings and credentials reach it through named environment
variables, for example `RAPIDPIPE_BATCH_JOB_QUEUE`,
`RAPIDPIPE_BATCH_JOB_DEFINITION_SCRATCH` and `_PRODUCTION`,
`RAPIDPIPE_OUTPUTS_ROOT_SCRATCH` and `_PRODUCTION`,
`RAPIDPIPE_SCRATCH_BUCKET`, `RAPIDPIPE_CLEANUP_ROLE_ARN`, and the
database connection variables (`PG*`, `RAPID_DB_SECRET_ID`): the
pipeline repository's README, "Running on Batch", carries the full
list. A launcher-side change, including everything on this page, needs no image
rebuild and no job-definition deployment: the container's own
`stage <name>` invocation is unchanged, and the live job-definition
revisions this step touches are none (R8).

## Not decided here

- The field-level input resolver (which reference a field should use
  among several eligible ones): still open, and not resolved by the
  seventh supervisor step's own field-level binding either (the
  [loop](loop) page, supervisor step 7, 2026-09-24).
- The automatic check gate `run promote` consults is on the
  [checks](checks) page; the lead-approved policy content behind it is
  scientific and stays undecided there (supervisor step 6, 2026-09-24).
- Removal of the transitional direct cleanup attachment on the
  workstation role, once the assumed-role path is proven.
- Granting the workstation instance role `batch:TerminateJob`, so
  `run cancel` from a workstation stops needing an operator's own
  elevated credentials.
