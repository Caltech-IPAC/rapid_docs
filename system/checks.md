# Candidate checks

**Status: DRAFT**

A check examines one product instance in the database and records
whether it passes. A check policy names and versions a list of required
and advisory checks with their bounds. Promotion runs the required
checks and refuses if any is missing or failed. This page defines how
checks run without changing how promotion treats their results, meeting
the requirement in the [runs](runs) page's Promotion eligibility
paragraph and the [specification](specification)'s Promotion section.

Every promotion in the rebuild so far, including every demonstration on
this page and the [runs](runs) page, has used `rebuild-trial@1` for a
person's `run promote` by hand. Its trial approval permits manual
promotion. Automatic promotion is built and tested but stays off in
production: no shipped policy has the team's approval to permit it.

## What a check is

A check is a named, versioned Python function over one product
instance. It is registered in `rapidpipe/checks/`, keyed by
`name@version`, with a declaration such as
`@check("difference-image-statistics", "1")`. Its signature is
`(conn, instance_id, params: dict) -> CheckResult(outcome 'passed'|'failed', detail dict)`.
Versions are strings; a changed threshold or measurement requires a
new version. Both shipped checks read only the database; future checks
may read S3.

Running a check always records a `checks` row: instance, check name,
version, the policy's required flag, outcome, and a detail document
containing the measurements, bounds, params and reason for the outcome.
A check that raises records `failed` with the error in `detail`.
Policies can override a shipped check's bounds, so the promotion gate
counts only rows whose recorded params match the resolving policy's
params for that check.

## The two checks

`difference-image-statistics@1` runs over a `difference-image`
instance. It reads that instance's `diffimmeta` row through
`diffimages.instance` and passes when `scalefacref` falls within a
policy-supplied `[lo, hi]`, `dxrmsfin` and `dyrmsfin` are each at most
`rms_max`, `|dxmedianfin|` and `|dymedianfin|` are each at most
`median_max`, `nsexcatsources` falls within `[n_min, n_max]`, and, when
`source_counts` is present, the positive-to-negative SExtractor count
ratio falls within `[ratio_lo, ratio_hi]`. All bounds come from the
policy's `params` for that check.

`catalog-counts-vs-reference@1` runs over a `source-set` result-set
instance. It finds its reference by slot instead of walking dependencies
by hand. The slot names the candidate's exposure, detector and catalog
type ([products](products) page). The reference is another current
`source-set` instance in the same slot, from any differencer, or, when
`params` names a `reference_run`, that run's instance for the same slot.
A candidate or would-be reference without a slot is not a reference.
The runner fills every candidate's slot first, so a set lacks one only
when its producer is still unresolved. The check compares the candidate's
`result_sets.row_count` against the reference's and passes when
`|candidate − reference| / reference` is at most `params.tolerance`.
When no reference instance exists, the outcome follows
`params.missing_reference`, recorded in `detail`; policy
`rebuild-trial@1` sets that to pass.

## Check policies

A check policy is a named, versioned TOML file shipped in the package,
at `rapidpipe/checks/policies/<name>@<version>.toml`, loaded by the
same `name@version` key as a check. Its fields are `name`, `version`,
`approval` (`none`, `trial` or `team`), `approved_by` (nullable; who
granted the recorded approval level), `auto_promote` (boolean), and a
`[[checks]]` table per check listing its name, version, kind, required
flag and params. A policy is immutable once landed; changing any field
requires a new version.

Manual and automatic promotion refuse a policy whose `approval` is
`none`. A `trial`-approved policy can gate a person's promotion;
automatic promotion requires `team` and `auto_promote` true.

The rebuild ships one policy, `rebuild-trial@1`. It marks
`difference-image-statistics` required and `catalog-counts-vs-reference`
advisory, required false. Its bounds come from the control run's measured
values with generous margins:
`scalefacref` in `[1e-3, 1e5]`, `dxrmsfin` and `dyrmsfin` each at most
2.0 pixels, `|dxmedianfin|` and `|dymedianfin|` each at most 1.0 pixel,
`nsexcatsources` in `[1000, 1e6]`, and the SExtractor positive-to-negative
ratio in `[0.1, 10]`. It carries `approval: trial`, `approved_by`
recording who granted it, and `auto_promote` false. This trial approval
suffices to demonstrate the manual-promotion mechanism required by the
runs and specification pages; the team's own sign-off remains open.

`rebuild-strict@1` is a refusal test fixture using the same two checks
with bounds the control run cannot meet: `scalefacref` in
`[0.99, 1.01]`, the same two RMS measurements each at most 0.01 pixel,
and `nsexcatsources` at most 1000. It does not ship; naming it to a
command is an unknown policy.

There is no policy table in the database. The promotion row durably
records what ran through the policy's version string and the ids of the
check rows it relied on. The TOML file defines what that version meant.

## The check commands

`run_policy_checks`, the runner called by both `check run` and the
promotion gate, fills every candidate's slot before running any check.
Thus `catalog-counts-vs-reference` never sees a slot the fill could have
resolved. Checks run on the workstation and reach the database through
the instance role; they do not touch the pipeline image. The [tool](tool)
page gives the full command surface for `check list`, `check run` and
`check show`, including every flag, print format and exit code.

## The promotion gate

`promote()` takes an optional check policy. `promote_run` and `run
promote` resolve which one to validate against in this order: an
explicit `--check-policy`, then the run's own `check_policy_ref`, then
the default `rebuild-trial@1`. Promotion refuses an unapproved policy
(`approval: none`) before reading any check result.

For each after-instance, every check in the approved policy whose kind
matches the instance must have a latest `checks` row for its name,
version and policy params. Required checks must have outcome `passed`.
Ties in `happened_at` break by row id. The read locks the rows it relies
on; a check recorded after the read starts is not counted.

A missing or failed required check refuses the whole promotion, exit 1,
with a message naming the instance, check and outcome. A failed or
missing advisory check is recorded but does not refuse. The promotion
row records `check_policy_version` and `check_result_ids`, the rows it
relied on. A kind with no check in the policy passes trivially. There is
no unchecked-exception flag: a deliverable of a kind covered by the
policy always goes through this gate.

Acceptance means required checks pass, nothing more ({ref}`acceptance
ruling <decision-acceptance>`). There is no separate acceptance record:
the gate re-reads the latest result of every required check each time.
The `checks` row is the durable record of what let a candidate through;
no judgement is stored on the instance.

### Dependencies and rollback

Promotion walks every dependency to its roots.
`_refuse_unpromoted_ancestor` follows `dependencies` recursively for
each after-instance, with a cycle guard and no depth cap. It reads the
same instance states that `run show` prints ([runs](runs) page,
"Rules"). A `current` or `superseded` ancestor passes because its chain
was judged when it was promoted. The walk still continues past it, so a
`candidate` grandparent behind a current parent refuses promotion.

An ancestor included among the same request's after-instances also
passes the walk, but must independently meet the same eligibility rule
and check policy as every after-instance. Any ancestor that is neither
`current` nor `superseded` nor an after-instance in the request refuses
the whole promotion, exit 1. The message names the after-instance,
ancestor, kind and state: "after instance '01...' depends on '01...'
(difference-image, candidate: not current or superseded; promote it
first or in the same request); refusing", the hint appearing only for
a `candidate` ancestor. A refusal changes no selection or custody; the
transaction raises before anything is written.

Rollback skips the check-policy gate and the ancestor walk because it
restores a selection an earlier promotion admitted, the same treatment
the released-image check gives it. Each direct dependency of the
restored selection must still be complete, retained and in project
custody; only the walk past those direct dependencies is skipped.

### Accepted defect

The gate's read of the latest check rows takes its lock `FOR SHARE`; a
failed check row committed after that read is not seen by the
promotion it should have refused. The dependency walk reads no check
rows: an ancestor's state is custody, completeness and selection. This
is an accepted defect, not fixed.

## Automatic promotion

`run create --auto-promote [--check-policy P]` is accepted only when the named
policy carries the team's approval, recorded as `approval: team` in the
policy file, and its `auto_promote` is true; otherwise it is refused,
exit 1, with a message naming the policy and stating that team
approval is pending.

At the end of a `run start` walk, once every unit is complete, the tool
calls `maybe_auto_promote(conn, run_id)`: with the run's `auto_promote` flag
true, it runs the resolved policy's checks over the run's candidates and
promotes on a pass; otherwise it prints `auto-promote off (policy
<ref>)` and does nothing further, immediately before `start`'s own
final `run=<id> state=complete` line. Every run created so far prints
this line, since no shipped policy permits automatic promotion.
Tests exercise the path end to end with a fixture policy. In production
it can currently only print: no policy carries the approval to act.

## Not decided here

- The team's own sign-off on a policy, beyond `rebuild-trial@1`'s trial
  approval, whether an approved policy permits automatic promotion, and
  the content of any policy approved for it. These are scientific
  questions for the team.
- Checks that read S3 rather than only the database.
