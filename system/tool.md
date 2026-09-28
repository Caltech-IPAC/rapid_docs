# The command-line tool

**Status: DRAFT**

The operations the team runs through `rapidpipe`, mapped from the
specification's Tools section onto its subcommands; the input-set
composer; the tool's own exit codes; personal submission from a
workstation; and where the tool runs. The
[specification](specification)'s Tools section states the requirement;
this page records how the rebuild meets it.

## In plain terms

The team touches one command-line tool: `rapidpipe`, shipped in the
pipeline repository and already the image's entrypoint for a stage
invocation. There is no second binary: a `rapidctl` would contradict the
specification's own sentence naming one tool, and would split an
entrypoint the container already carries. Everything below is `rapidpipe`'s command surface; nothing
here is a separate program.

## Operations

The specification's Tools section names a small set of operations. Each
maps onto one or more subcommands, all existing arguments keeping their
names:

| Operation | Subcommand |
|---|---|
| Create a run | `run create` (`--seed <run>` records lineage only: it inherits no settings and no input references from the seeding run, unless paired with `--only-failed`, which makes it a recovery run over the seed's non-complete units instead (the [runs](runs) page has the mechanics); `--release <tag>` is the [releases](releases) page's; `--auto-promote --check-policy P` is refused unless P permits automatic promotion (the [checks](checks) page has the gate)) |
| Start a stage or the whole loop | `run start` |
| Rerun part of a run | `run start --stage <stage>` |
| Watch progress | `run status [--watch]`, `run show` (a `state:` block at the end, after `units:`, `attempts:` and any `promotions:`; the [checks](checks) page has the states), `run timings [--stage S] [--json]` (queue, execution and orchestration time per attempt; the [observability](observability) page) |
| Cancel and restart from failure | `run cancel <attempt>`, then `run start` |
| List and compare runs | `run list`, `run compare <a> <b>` (each `instance` line carries the slot column beside the provenance key) |
| Promote a candidate | `run promote --check-policy P` (defaults to the run's own `check_policy_ref`, then `rebuild-trial@1`); `run promote-plan <run>` prints the run's slot groupings as a frozen plan, without promoting; `run promote <run> --plan <file>` applies that plan, refusing (exit 1) if the current selection or the run's candidates have moved since, or refusing (exit 64) if the file is not a non-empty JSON list of `{kind, slot, before, after}` entries (JSON `null` included); `run rollback` ([checks](checks) page has the gate) |
| Delete scratch | `run delete`, `run expire`, `run pin` / `run unpin` |
| One unit by hand | `run submit`, `run reconcile` (`--resolve-jobless [--older-than SECONDS]` records a job-less attempt `lost`; the [runs](runs) page has the mechanics), `run local` |
| Verify a candidate | `check list`, `check run`, `check show` (the check commands below; the [checks](checks) page) |
| A stage directly | `stage run <name> …` (a synonym of `stage <name> …`, the frozen invocation form the container's entrypoint calls), `stage list`, `stage describe <name>` |
| Fixtures | `selftest --stage <name>`, one of `reference`, `difference`, `finalize`, `load`, `maintain`, `crossmatch`, `alerts`, `statistics`, `prune`, `export`; `admit` and `register` have no fixture |
| Releases | `release cut\|show\|list\|verify` (the release commands below; the [releases](releases) page) |
| The processing-date loop | `loop run\|plan\|show` (the loop commands below; the [loop](loop) page) |

The check, release and loop commands take these arguments:

| Command | Does |
|---|---|
| `check list` | Prints the registered checks and the shipped policies |
| `check run <run> [--policy P] [--instance I] [--check NAME@V] [--param k=v]…` | Runs every applicable policy check over the run's candidate instances from their selected attempts, or over the one named instance or check, records a row for each, and prints one line per result: instance, kind, logical key, check, version, required flag, outcome, summary; exits 0 if every result passed and 1 if any failed |
| `check show <run> [--instance I]` | Prints the run's recorded check results, newest first: `id=<check row id> at=<happened_at> instance=<id> kind=<kind> key=<compact json> check=<name>@<v> required=<true\|false> outcome=<passed\|failed> <summary>` |
| `release cut\|show\|list\|verify` | Also runnable as `python -m rapidpipe.release`. `cut` takes `--tag`, `--ref`, `--hooks-dir`, `--skip HOOK`, `--resume TAG` and `--dry-run`; `show` prints one release's record; `list` prints every recorded release; `verify` checks a recorded release against its live state |
| `loop run --spec <loc> [--date D]… [--retry-failed] [--dry-run] [--interval N] [--timeout N]` | Runs every date in the spec whose `loop_dates` row is absent or `open`, in spec order, under the schedule's advisory lock; `--date` restricts it to the named dates; `--retry-failed` also recovers `failed` dates, through a seeded replacement run when the date has a failed or cancelled unit |
| `loop plan --spec <loc>` | Prints what `loop run` would do: the dates it would process and the runs it would create, without creating them; given an inbox spec, it discovers and classifies without writing any row |
| `loop show <schedule>` | Prints the schedule's `loop_dates` rows, then its `loop_deliveries` rows |

The check commands run launcher-side, on a workstation or the launcher
host, reaching the database through the instance role; none of them
touches the pipeline image.

`run start <run> --unit <u> [--stage <s>]` walks the run's selected
stages in order, or the one named stage: a complete unit is skipped; a
unit already terminal `failed` or `cancelled` is not re-attempted:
`start` prints its state and exits 1, and recovering it is
`run create --seed <run> --only-failed`; a unit with
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
the launcher's own submission uses that exact form.

## Input sets

`run inputs <run> <stage> --unit <u> --from-stage <producer> --template <loc> [--dest <loc>]`
is the input-set composer. It reads the template's manifest, replaces or
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

Every submission binds its input set, not only one composed by this
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
depend on ([runs](runs) page, "Units", "Deletion").

This is the explicit, whole-input-set form of resolution: which
reference among several eligible ones a field should use is not decided
here (below).

## Exit codes

One vocabulary covers every `rapidpipe` process, in the module
`rapidpipe/exitcodes.py` (`ExitCode`). The [stage contract](stage-contract)
page's Exit codes table carries the six of these a stage itself reports
(0, 64, 65, 69, 70, 75), 69 reserved: no stage in this build returns it.
A stage never exits 1 or 2. The table below is
the full eight, with which command family returns each one folded into
the third column.

| Code | Meaning | Returned by |
|---|---|---|
| 0 | Success: the command did what was asked | every family |
| 1 | A negative outcome: a stage or unit failed or was cancelled, two runs differ, a check failed, a release refused (a check or a hook failed, a resume did not match, verify found a mismatch), or a promotion is refused: an ineligible after-instance or ancestor, an unapproved check policy or a missing or failed required check, a stale plan, or a check policy that does not permit what `run create --auto-promote` asked of it | `run start`, `run status`, `run compare`, `run show`, `run submit` (a release whose recorded job-definition revision is refused, not `ACTIVE`); `run inputs` (an input's size mismatch); `loop run`; `check run`; `release cut\|show\|list\|verify`; `run promote`, `run promote-plan`, `run rollback`; `run create` (an `--auto-promote` refusal) |
| 2 | Still running: a unit remains non-terminal | `run status` |
| 64 | Usage, configuration or an unmet precondition: bad arguments, including every argparse parse failure from every command family (help still exits 0), invalid settings, a refused destination, a dirty tree, a tag that exists, missing hooks, a release whose record is not `complete`, an unknown run (except `run show`, which exits 1), instance, promotion id or check policy, a malformed or empty promotion plan or selector (`run promote --plan` reads the plan file before connecting; a stale plan under the lock is exit 1, above), or the stage guard finding no database configured to check named inputs (a database it cannot reach instead exits 75, below) | every family; `release cut\|show\|list\|verify`, `run create` included; `run promote`, `run promote-plan`, `run rollback`; a stage's own invocation |
| 65 | A declared input absent, corrupt or incompatible once its storage was reached (a stage's own invocation); `run submit`, `run start` or `run local`'s own input-manifest read failed for a non-network reason, the manifest absent, not JSON, or failing validation; a deleting or deleted producer met while `run inputs` or the loop binds an input set; or the stage guard refusing a manifest entry that names another run's scratch or unselected product, file or result set, on any path into `run_stage`. Nothing is written | a stage's own invocation; `run submit`, `run start`, `run local`; `run inputs` (a deleting or deleted producer at bind time); `loop run` (the same, met while the loop composes an input set; a refusal at submission fails the date with exit 1) |
| 69 | Reserved: declared in the vocabulary, but no stage or command in this build returns it | none |
| 70 | An unclassified error; stop and investigate | every family: an unexpected error escaping a command is logged with its traceback and exits 70; and a stage's own invocation |
| 75 | `run start --timeout` expired before a unit reached a terminal state, or the tool hit a transient database or AWS failure, including a network-shaped error reading the input manifest or the stage guard's own database connection failure once it needs to read named inputs: any of these is retryable | a stage's own invocation; `run start`, `run submit`, `run local`; every family for a transient database failure (`release cut\|show\|list\|verify`, `run create`, `check` included); `loop run`'s lock or timeout |

`selftest` reads its own subset: 0 when every check passes, 1 when a
check fails or the stage under test exited 0 where the fixture expected
a non-zero code, 64 when the work directory already exists, and
otherwise the stage's own unexpected code.

Three invariants hold across the vocabulary. A parse failure exits 64 from every family: every
`rapidpipe` parser, nested subparsers included, is
`rapidpipe.exitcodes.ArgumentParser`, whose usage error exits 64
directly, and help still exits 0; the stage runner also translates a
parse failure to 64 for `stage run <name>`, as a safeguard. So 2 means
only "still running", never "could not parse". And `release` spells its
own usage and precondition refusals 64, the same as every other family.

## Personal submission from a workstation

A person can run the same commands from a workstation that the launcher
runs from a fleet host. The identities involved are documented in the
systems repository, but the shape reaches this page: the
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
credentials are ambient. During the transition, the workstation role
also carries the cleanup permission directly, so a failure of the
assumed path cannot strand a deletion; removing that direct attachment
is open (below).

`run cancel` needs `batch:TerminateJob` on whichever identity issues
it. The workstation's instance role does not carry that permission, so
a cancel issued from a workstation fails `AccessDenied` until the
systems repository grants it; the launcher's own fleet-host role is
unaffected.

## Where it runs

The tool runs launcher-side: on a fleet host, under that host's instance
role. Deployment-specific locations,
connection settings and credentials reach it through named environment
variables, for example `RAPIDPIPE_BATCH_JOB_QUEUE`,
`RAPIDPIPE_BATCH_JOB_DEFINITION_SCRATCH` and `_PRODUCTION`,
`RAPIDPIPE_OUTPUTS_ROOT_SCRATCH` and `_PRODUCTION`,
`RAPIDPIPE_SCRATCH_BUCKET`, `RAPIDPIPE_CLEANUP_ROLE_ARN`, and the
database connection variables (`PG*`, `RAPID_DB_SECRET_ID`): the
pipeline repository's README, "Running on Batch", carries the full
list. A launcher-side change, including everything on this page, needs no image
rebuild and no job-definition deployment, since the container's own
`stage <name>` invocation does not change.

## Not decided here

- The field-level input resolver (which reference a field should use
  among several eligible ones): still open, and not resolved by the
  [loop](loop) page's own field-level binding either.
- The automatic check gate `run promote` consults is on the
  [checks](checks) page; the team-approved policy content behind it is
  scientific and stays undecided there.
- Removal of the transitional direct cleanup attachment on the
  workstation role, once the assumed-role path is proven.
- Granting the workstation instance role `batch:TerminateJob`, so
  `run cancel` from a workstation stops needing an operator's own
  elevated credentials.
