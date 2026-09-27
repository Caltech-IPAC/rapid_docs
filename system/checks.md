# Candidate checks

**Status: DRAFT**

What a check is, the two checks the rebuild ships, how a check policy is
defined and versioned, how promotion validates against one, and
automatic promotion's design. Written 2026-09-24 from supervisor step
6's rulings (R1 through R6). The [runs](runs) page's Promotion
eligibility paragraph and the [specification](specification)'s
Promotion section state the requirement; this page records how the
rebuild meets it.

## In plain terms

A check is a function that looks at one product instance already in
the database and records whether it passes. A check policy is a named,
versioned list of checks with their bounds, some required and some
advisory, and it carries its own approval level: unapproved policies
gate nothing, a trial-approved policy can gate a person's promotion,
and only a lead-approved one can gate an automatic one. Promotion runs
the policy's required checks and refuses if any is missing or failed;
nothing about this page changes what promotion already does with a
passing or failing check, it defines what running one means. Automatic
promotion is built and tested, and stays off in production until the
lead approves a policy for it.

Plainly: `rebuild-trial@1`, the policy every promotion in this rebuild
has run under so far, carries a trial approval this supervisor step
recorded, not the lead's own sign-off. That trial approval is enough to
gate a person's `run promote` by hand, which is what every demonstration
on this page and the [runs](runs) page has done. It is not enough to
gate an automatic promotion, and no policy the rebuild ships is. The
lead's own approval of a policy, and whether any policy the lead
approves also permits automatic promotion, are both still open
(supervisor step 9, 2026-09-25).

## What a check is

A check is a named, versioned Python function over one product
instance, registered in `rapidpipe/checks/`: a registry keyed
`name@version`, declared with `@check("difference-image-statistics",
"1")`. Its signature is `(conn, instance_id, params: dict) ->
CheckResult(outcome 'passed'|'failed', detail dict)`. Running a check
always records a `checks` row: instance, check name, version, the
required flag from the policy that ran it, outcome, and a detail
document of the measurements, the bounds, the params it ran under and
the reason for the outcome; a check that raises records `failed` with
the error in `detail`, never nothing. Recording the params matters
because a policy can override a shipped check's bounds: a result
recorded under other params is not a result under these, so the
promotion gate below only ever counts a row whose recorded params equal
the resolving policy's params for that check. Versions are strings, and
a changed threshold or a changed measurement is a new version, not an
edit to an existing one. A check reads the database; it may read S3 in
a later step, but both checks this page ships are database-only (R1,
2026-09-24; params recorded and matched, 2026-09-24).

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
instance. It now finds its reference by slot rather than walking
dependencies by hand: the candidate's slot already names its exposure,
detector and catalog type ([products](products) page), so the check
looks for another current `source-set` instance sharing that same slot,
any differencer, or, when `params` names a `reference_run`, that run's
instance for the same slot instead. A candidate or a would-be reference
without a slot is not a reference; the check's own runner fills every
candidate's slot first, so a set only misses one when its producer is
still unresolved (below). It compares the candidate's
`result_sets.row_count` against the reference's and passes when
`|candidate − reference| / reference` is at most `params.tolerance`.
When no reference instance exists, the outcome follows
`params.missing_reference`, recorded in `detail`; policy
`rebuild-trial@1` sets that to pass (supervisor step 5a, 2026-09-26,
replacing the dependency walk by science identity this check used
before).

Policy `rebuild-trial@1` marks `difference-image-statistics` required
and `catalog-counts-vs-reference` advisory, required false (R2,
2026-09-24).

## Check policies

A check policy is a named, versioned TOML file shipped in the package,
at `rapidpipe/checks/policies/<name>@<version>.toml`, loaded by the
same `name@version` key as a check. Its fields are `name`, `version`,
`approval` (`none`, `trial` or `lead`), `approved_by` (nullable; who
granted the recorded approval level), `auto_promote` (boolean), and a
`[[checks]]` table per check listing its name, version, kind, required
flag and params. A policy is immutable once landed; a change to any of
these is a new version, never an edit in place. Promotion, manual or
automatic, refuses a policy whose `approval` is `none`; automatic
promotion additionally requires `lead` and `auto_promote` true, so a
`trial`-approved policy can gate a person's promotion but never an
automatic one (R3, 2026-09-24, amended by the plan review, 2026-09-24).

Two policies ship with the rebuild. `rebuild-trial@1`'s bounds are set
from the control run's measured values with generous margins:
`scalefacref` in `[1e-3, 1e5]`, `dxrmsfin` and `dyrmsfin` each at most
2.0 pixels, `|dxmedianfin|` and `|dymedianfin|` each at most 1.0 pixel,
`nsexcatsources` in `[1000, 1e6]`, and the SExtractor positive-to-negative
ratio in `[0.1, 10]`. `rebuild-strict@1` runs the same two checks but
exists only to demonstrate a refusal and exercise the gate, with bounds
the control run cannot meet: `scalefacref` in `[0.99, 1.01]`, the same
two RMS measurements each at most 0.01 pixel, and `nsexcatsources` at
most 1000. Both carry `approval: trial`, `approved_by` recording this
step's own supervisor grant, and `auto_promote` false. This trial approval
satisfies the mechanism the runs and specification pages ask for well
enough to demonstrate manual promotion by hand; it is not the lead's own
sign-off, which is a recorded open item, and neither policy permits
automatic promotion regardless. There is no policy table in the
database: the promotion row records the policy's version string and the
ids of the check rows it relied on, which is the durable record of what
ran; the TOML file is the versioned definition of what the policy meant
at that version (R3, 2026-09-24).

## The promotion gate

`promote()` takes an optional check policy. `promote_run` and `run
promote` resolve which one to validate against in this order: an
explicit `--check-policy`, then the run's own `check_policy_ref`, then
the default `rebuild-trial@1`. Promotion first refuses an unapproved
policy (`approval: none`) before looking at any check result. Every
promotion under an approved policy is then validated under its version:
for each after-instance, every policy check whose kind matches that
instance must have a latest `checks` row, for that check's name,
version and the policy's own params for it, with outcome `passed` when
the policy marks it required; ties in `happened_at` break by row id, and
the read locks the rows it relies on, so a check recorded after the read
started is not counted. A missing or failed required check refuses the
whole promotion, exit 64, naming the instance, the check and the
outcome in the message; a failed or missing advisory check is recorded
but does not refuse. The promotion row records `check_policy_version`
and `check_result_ids`, the rows it relied on. A kind the policy names
no check for passes trivially, and there is no unchecked-exception
flag: a deliverable of a kind the policy does cover always goes through
this gate.

Promotion also walks every dependency to its roots, not only the
after-instances themselves (supervisor step 6, 2026-09-26).
`_validate_promotion_eligibility` follows `dependencies` recursively for
each after-instance, cycle-guarded rather than depth-capped. An ancestor
that is itself `current` or `superseded` passes, since its own chain was
judged when it was promoted, but the walk continues past it rather than
stopping there, so a rejected grandparent behind a current parent still
refuses the promotion. An ancestor that is itself an after-instance of
the same promotion gets no exemption from this walk: it is judged by
its own run's resolved policy like any other ancestor, and the
promotion's own gate above still covers it separately as an
after-instance. Any ancestor that is not `current` or `superseded` must
be `accepted`; one that is `pending`, `rejected`, `unselected`,
`scratch`, `incomplete` or `deleted` refuses the whole promotion, exit
64, naming the after-instance, the ancestor, its kind, its state and the
check or custody behind it: "... depends on 01... (difference-image,
rejected: difference-image-statistics@1 failed; accept it with `check
accept` or replace it)". A refusal changes no selection or custody; the
transaction raises before anything is written.

Rollback skips both gates: it restores a selection an earlier promotion
already admitted, the same treatment the released-image check and the
dependency walk above give it (R4, 2026-09-24, amended by the plan
review, 2026-09-24; the transitive walk, supervisor step 6, 2026-09-26).

## Acceptance

Acceptance is separate from selection. The dependency walk above treats
a candidate instance as eligible once it is `accepted`, and neither the
walk nor `check accept` itself changes an instance's custody: an
accepted instance stays a candidate. Acceptance is recorded, not
inferred. An `acceptances` row (`instance`, `who`, `reason`,
`policy_ref`, `check_ids`, `happened_at`, `detail`) names who accepted
an instance, why, which check-policy version was in force, and the
latest row of every policy check for the instance's kind as the
evidence (supervisor step 6, 2026-09-26).

`rapidpipe check accept <run> --instance <id> --reason "<text>"
[--who]` records one. It refuses, exit 64, unless the instance belongs
to the run and its state is `rejected`: a `pending` instance says run
the checks first; an `accepted`, `current` or `superseded` instance says
it is already accepted; an `unselected`, `scratch`, `incomplete` or
`deleted` instance is not acceptable at all. Acceptance applies to any
kind an instance can take, file products included: `rebuild-trial@1`
already requires `difference-image-statistics` on difference images,
so a difference image is exactly the kind of instance `check accept`
exists for, the same as a result set.

There is no revocation in this step: a wrong acceptance is corrected by
replacing the product, not by unmarking the acceptance row. Acceptance
survives supersession, since the state `superseded` is decided before
`accepted` (above): an instance accepted as a candidate keeps that
acceptance once it is promoted and later superseded.

## Automatic promotion

Automatic promotion is designed in and switched off. `run create
--auto-promote [--check-policy P]` is accepted only when the named
policy's `approval` is `lead` and its `auto_promote` is true; otherwise
it is refused, exit 64, with a message naming the policy and stating
that lead approval is pending. Neither shipped policy carries lead
approval, so neither permits it. At the end
of a `run start` walk, once every unit is complete, the tool calls
`maybe_auto_promote(conn, run_id)`: with the run's `auto_promote` flag
true, it runs the resolved policy's checks over the run's candidates and
promotes on a pass; otherwise it prints `auto-promote off (policy
<ref>)` and does nothing further, immediately before `start`'s own
final `run=<id> state=complete` line. Every run created so far prints
this line, since no shipped policy permits automatic promotion (live
evidence, supervisor step 6, 2026-09-24). The path is exercised end to
end against a fixture policy in tests; in production it can currently
only print, because no policy carries the approval that would let it
act (R5, 2026-09-24).

## The check commands

`rapidpipe check list` prints the registered checks and the shipped
policies. `run_policy_checks`, the runner both `check run` and the
promotion gate call, fills every candidate's slot before running a
single check, so `catalog-counts-vs-reference` never sees a slot the
fill itself could have resolved (supervisor step 5a, 2026-09-26).
`check run <run> [--policy P] [--instance I] [--check
NAME@V] [--param k=v]…` runs every applicable policy check over the
run's candidate instances from their selected attempts, or over the one
named instance or check, records a row for each, and prints one line
per result: instance, kind, logical key, check, version, required
flag, outcome, summary; it exits 0 if every result passed and 1 if any
failed. `check show <run> [--instance I]` prints the run's recorded
check results, newest first, then one line per candidate or current
instance of the run: `acceptance instance=<id> kind=<kind> state=<state>
<detail>`, detail naming the deciding check and outcome, the acceptance
row id, or the custody behind the state (Acceptance, above; supervisor
step 6, 2026-09-26). `rapidpipe check accept <run> --instance <id>
--reason "<text>" [--who]` records an acceptance for a `rejected`
instance (Acceptance, above). Checks run launcher-side, on
rapid-rusholme, reaching the database through the instance role; none
of this touches the pipeline image (R6, 2026-09-24).

## Not decided here

- The lead's own sign-off on a policy, beyond this step's trial
  approval, and the content of any policy the lead approves for
  automatic promotion: both scientific, and the lead's.
- Checks that read S3 rather than only the database.
- Revoking a recorded acceptance: a wrong one is corrected today by
  replacing the product, not by unmarking the `acceptances` row
  (Acceptance, above; supervisor step 6, 2026-09-26).
