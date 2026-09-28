# Operations: live processing, reprocessing and development together

**Status: DRAFT, a proposal.** The team has not yet ruled on these
operations proposals. Landed behaviour is on [loop](loop),
[products](products), [runs](runs) and [checks](checks). This page changes
no code, schema or other page's rules. [Specification](specification),
[runs](runs), [products](products) and [loop](loop) remain the design
authority; proposed changes identify the sentence they would change.

## What this page assumes about the mission

Three mission interfaces remain undefined ([specification](specification),
Edges). The recommendation depends on the following assumptions.

- **Delivery manifest.** Each delivery arrives with a manifest naming, per
  file, the exposure, detector, delivered version and checksum: the
  shape `admit` already reads ([products](products), the l2 image).
  RAPID discovers files by listing their delivery location; it does not
  need a message.
- **Re-delivery signalling.** A corrected file carries a higher delivered
  version for the same exposure and detector. An identical re-delivery
  carries the same version and the same checksum. The same version with
  a different checksum is a mission error, not a correction.
- **Date completeness.** No completeness signal is assumed. If the mission
  provides one (a per-date manifest closing the day), the stream can use
  it; the recommendation below does not depend on it.
- **Latency.** The provisional requirement is within an hour per
  detector image, from delivery until its alert is current
  ({ref}`latency ruling <decision-latency>`); the team confirms or
  replaces the number. A different number changes the batch size, not
  the shape (Closure and latency, below).

## Three shapes

### The model as written: a run per date, the loop is the continuity

Each processing date is one production run. The loop walks the dates
a spec names, binding each date's catalog to the previous date's.

No code changes, but a late delivery has no run to enter. A date must be
complete before its run is created, trading latency for completeness
without a signal to decide on. A corrected frame makes a new logical
key, so promotion adds a second current product; reprocessing promotions
likewise add beside production's. Outage catch-up needs a person to
write the dates into a spec.

### One long-lived operations run

All operations processing is one run that grows as deliveries arrive.
This shape is rejected.

Changing the input set after creation loses the frozen provenance
protected by the specification's Runs section. Whole-run promotion
becomes meaningless, so every promotion is piecemeal. A release change
puts two releases in one run, against [releases](releases)' "a run never
spans a release". `run create --seed
--only-failed` seeds a replacement for all operations instead of one
date. The per-date association base becomes a same-run read, skipping
the cross-run selected-attempt rule.

Checks and alert provenance lose their batch. Every alert names the
same run, which no longer identifies the code and settings that made
it. Neither scratch expiry nor development benefits: production runs
never expire, and development still needs its own scratch runs.

### A named stream whose runs are its batches

Operations is a named stream that turns each batch of new deliveries
into an ordinary frozen run. It uses the loop's existing schedule
identity: the `processing-date-loop` registry row, its spec and its
`loop_dates` rows.

The stream discovers unadmitted deliveries instead of reading them
from the spec. A date may have several batches (Closure and latency);
promotion supersedes by science slot (Replacement scope); publication
follows [products](products), "Reading across runs", and its eligibility
table. Runs, units, attempts, custody, the promotion lock, release
binding, recovery, the base-catalog rule, deletion and the scratch path
stay unchanged.

## Recommendation, and where the first cuts differ

The recommendation is a named stream of batch runs. Each run keeps one
release, frozen input set, promotion and recovery scope. Continuity uses
the existing schedule identity and rows, with no new service, table or
scheduler.

A correction replays the frame's descendants, possibly in batches.
The frame's own products wait for the same switch: promoting the frame
before the catalog would publish both versions in one catalog. When
latency must be shorter than a day, a date admits several batches by
the same mechanism as a new date.

## Replacement scope

Promotion supersedes by science slot. Each kind's identity key and slot
are on [products](products), "Identity". [Runs](runs), "Rules", defines
slot replacement, including the rule that an `association-set`
promotion replaces only an ancestor of the set it promotes.

The chain switch below remains open. For a new delivered version of
(E, D), one promotion at the end of a correction run replaces the
`l2-image` slot (E, D), every slot keyed on (E, D), and each affected
field's catalog slots.

When live processing and reprocessing overlap, the campaign's switch
lists each slot's expected current instance (the stream's) and
replacement (the campaign's) in one atomic promotion. If the stream
promotes a batch after the campaign plans its switch, at least one
expected instance no longer matches. The whole switch is refused, and
the campaign replans against the new selection, as today's promotion
lock refuses stale plans. Rollback applies the recorded inverse and,
as today, refuses if the switch's after-selection is no longer current.

### The chain switch

A chain switch moves a stream to another catalog chain after either
a reprocessing campaign or a correction run.

A reprocessing campaign is a set of ordinary production runs under a new
release or new settings, with auto-promote off, on the bulk queue
(Capacity, below). A correction run is an ordinary production run
seeded on each affected field's last association set before the
corrected frame's epoch. It replays the field's batches to the stream's
head with the corrected version, regenerating association, statistics
and pruned sets and the alert containers for frames in those fields.

Corrections may share a run on a schedule the team sets. Consumers keep
the earlier selection until the switch. A frame is *awaiting correction*
when the stream has admitted a higher delivered version for its
(exposure, detector) than its field's current catalog holds, and no
chain switch has applied it. Only the stream's own admissions count.

1. The replacing run (a campaign or a correction run) has processed every
   delivery up to the stream's most recent complete batch.
2. It takes the stream's schedule lock, the advisory lock `loop run`
   already holds throughout its run. No new batch can start during the
   switch. If a batch completed after step 1, the replacing run first
   processes its deliveries under the lock.
3. Every open, failed or timed-out batch must finish (and be covered as
   in step 2) or be cancelled with its deliveries recorded as not
   processed, so the replacing run catches them up. The switch refuses
   while any batch of the schedule is open: its frozen inputs bind the
   old head, which it would extend on resuming.
4. One promotion replaces every covered slot against its expected
   predecessor, file products and result sets together. Its request
   context records the boundary: the stream's last batch covered.
5. The same transaction adds a switch row naming each field's adopted
   head. The base-catalog rule reads the schedule's most recent complete
   row or switch row, so the next batch extends the adopted head.

A person makes the switch; it is the one promotion into a catalog slot
that is not an extension of the current chain. Its rollback restores the
earlier selections and adds a switch row back to the earlier heads. The
records change is additive: `loop_dates` gains a batch sequence (so a
date can hold several batches) and a row kind (`batch` or `switch`).

## Closure and latency

[Loop](loop), "Discovery and batches", states the arrival outcomes:
a later batch for the same date, refusal of an identical re-delivery,
quarantine of a checksum mismatch, and deferral of a corrected version.
Batch cadence remains open. The provisional latency, within
an hour per detector image ({ref}`latency ruling <decision-latency>`),
points to per-delivery batches with an event or roughly 30-minute window
trigger.

If the latency requirement is a day or more, one batch per date after a
fixed cutoff hour is enough, and the stream is the loop as written plus
discovery. If it is minutes, batches become per delivery and the trigger
becomes an event rather than a window. The run model still holds, but
whether stages and queues can keep up is unverified: `difference`
alone takes about 58 minutes per detector image today (Capacity,
below). A chain switch also pauses live batches while it catches up
under the schedule lock. Operations are not declared ready until the
team confirms the latency and the mission states the delivery interface.

## The loop's five calls

Two of the loop's five calls remain open here; [loop](loop) covers the
others.

- **Cadence** (proposed): a fixed `window:cron(...)` at an interval of
  half the latency budget; a firing that discovers nothing exits 0 and
  writes nothing. An event trigger only if the latency requirement is
  minutes.
- **Production check policy** (proposed, below).

## A production check policy

The proposed `rebuild-production@1` requests `auto_promote = true`;
team approval is pending. A policy is immutable once landed
([checks](checks)), so its file must land in a team-approved pull
request carrying `approval = "team"` and `approved_by` set to the
approver's login. Until then, its content exists only in the table below,
with no file to edit. No other path raises a policy to `team`.
`rebuild-trial@1` keeps trial approval.

Proposed bounds use the 15357 difference images `dev` recorded in
production `diffimmeta`: each measure's 1st to 99th percentile,
widened by half.

| Measure | 1st, 50th, 99th percentile | Proposed bound |
|---|---|---|
| `dxrmsfin` | 0.18, 0.28, 0.38 px | at most 0.6 |
| `dyrmsfin` | 0.37, 0.49, 0.61 px | at most 0.9 |
| `abs(dxmedianfin)` | 0.002, 0.12, 0.30 px | at most 0.45 |
| `abs(dymedianfin)` | 0.20, 0.38, 0.59 px | at most 0.9 |
| `nsexcatsources` | 19083, 95166, 106362 | within [9500, 160000] |
| `scalefacref` | 8889, 10286, 18820 | not set: see below |

`scalefacref` depends on the reference zero point gain matching uses.
`dev`'s values come from a fixed `zprefimg` of 17.0; under the ruling
that gain matching reads `MAGZP` from the reference,
the factor moves to order one. Its bound therefore comes from the first
production batches under that ruling, not from `dev`.

The catalog-count check stays advisory until earlier production runs
provide current source sets for the same frames. It compares another
run's source set, never a reference catalog ([checks](checks)).

## Reference eligibility and selection

Proposed: a reference image is eligible for a field and filter if it is
current in that slot, built by the recipe named in the stream's spec,
and made from constituents that are all current or superseded. Selection
takes the one current reference in the (field, filter) slot, following
`dev`'s rule (the reference with `vbest` set).

Later batches use a new reference promoted mid-stream. Existing
difference images retain the earlier reference in their identity key
until reprocessing replaces them. Where the reference PSF is resolved
from remains open.

## Staged inputs of a production run

A production run stages its difference input set under the scratch
bucket's `rapidpipe/runs/<run-id>/inputs/`: copies of the l2 image,
reference bundle and PSFs, plus the manifest. The launcher host cannot
write the products bucket, and [tool](tool) puts every input set under
the scratch root.

Proposed run-model rule: staged production inputs are provenance,
retained for the run's lifetime. Nothing expires or deletes them while
the run's row exists. This already holds: scratch expiry and `run
delete` affect only scratch runs, and the scratch bucket has no
lifecycle rule. Stating the rule protects it against a later lifecycle
rule.

## Capacity

Two queues exist: `rapid-queue-prompt` (priority 10, on-demand
`rapid-ce-prompt`, 5000 vCPU) and `rapid-queue-bulk` (priority 1, Spot
`rapid-ce-bulk`, 10000 vCPU). Measured rebuild jobs put `difference` at
a median of about 58 minutes of execution per detector image, the only
stage over the 30-minute target. `alerts` ran about 25 minutes on
production runs; every other stage took under a minute.

Proposed lanes use these queues to meet the specification's "scratch
runs cannot consume capacity reserved for regular operations": the
stream uses prompt; reprocessing campaigns and correction runs use
bulk; scratch runs use bulk by default, prompt by request.

## Not decided here

- Confirmation of the provisional delivery-to-alert latency
  ({ref}`latency ruling <decision-latency>`), and the mission's delivery
  manifest and completeness signal.
- The team's choice of correction cadence: per correction or batched
  on a schedule.
- The team's choice of alert-history order for a late-arriving earlier
  epoch: observation time or arrival.
- Team approval of `rebuild-production@1` and its `scalefacref` bound.
- Where the reference PSF is resolved from.
