
# Operations: live processing, reprocessing and development together

**Status: DRAFT, a proposal.** This page holds operations proposals the
team has not yet ruled on; what landed is stated on [loop](loop),
[products](products), [runs](runs) and [checks](checks). Nothing on this
page changes code, schema or another page's rules. The
[specification](specification), [runs](runs), [products](products) and
[loop](loop) pages remain the design authority; where this page proposes
a change to them, it says which sentence would change.

## What this page assumes about the mission

Three mission interfaces are not yet defined ([specification](specification),
Edges). This page assumes the following, and the recommendation is
conditional on them.

- **Delivery manifest.** Each delivery arrives with a manifest naming, per
  file, the exposure, detector, delivered version and checksum: the
  shape `admit`'s delivery manifest already reads ([products](products),
  the l2 image). Where the files land and how RAPID learns of them is a
  location the stream lists, not a message it must receive.
- **Re-delivery signalling.** A corrected file carries a higher delivered
  version for the same exposure and detector. An identical re-delivery
  carries the same version and the same checksum. The same version with
  a different checksum is a mission error, not a correction.
- **Date completeness.** No completeness signal is assumed. If the mission
  provides one (a per-date manifest closing the day), the stream can use
  it; the recommendation below does not depend on it.
- **Latency.** The provisional requirement is within an hour per
  detector image, from delivery to its alert current
  ({ref}`latency ruling <decision-latency>`); the team confirms or
  replaces the number. A different number changes the batch size, not
  the shape (Closure and latency, below).

## Three shapes

### The model as written: a run per date, the loop is the continuity

Plain sentence: each processing date is one production run, and the loop
walks the dates a spec names, binding each date's catalog to the
previous date's.

Nothing changes in code. What strains: a late delivery has no run to
enter; a date must be complete before its run is created, which trades
latency for completeness with no signal to decide on; a corrected frame
makes a new logical key, so its promotion adds a second current product
instead of replacing the first; a reprocessing campaign's promotions add
beside production's for the same reason; and outage catch-up needs a
person to write the dates into a spec.

### One long-lived operations run

Plain sentence: all operations processing is one run that grows as
deliveries arrive.

This breaks more than it fixes. Freeze-at-creation goes: the run's input
set changes after creation, which is exactly the provenance the
specification's Runs section exists to protect. Promotion's default unit,
a whole run, becomes meaningless, so every promotion is piecemeal. A
release change would put two releases inside one run, against
[releases](releases)' "a run never spans a release". `run create --seed
--only-failed` would seed a replacement for the whole of operations
rather than for one date. The per-date association base becomes a
same-run read, which skips the selected-attempt rule the cross-run read
applies. Checks and alert provenance lose their batch: every alert names
the same run, so the run no longer says which code and settings made it.
Scratch expiry is untouched (a production run never expires) and
development is untouched (it still needs its own scratch runs), so the
cost buys nothing for those modes. Rejected.

### A named stream whose runs are its batches

Plain sentence: operations is a named stream that turns each batch of new
deliveries into one ordinary frozen run.

The stream is the schedule identity the loop already has: the
`processing-date-loop` registry row, its spec, and its `loop_dates`
rows. What changes: the stream discovers deliveries it has not yet
admitted instead of reading them from the spec; a date may take more
than one batch (Closure and latency); promotion supersedes by science
slot (Replacement scope); and publication follows the eligibility
table on [products](products), "Reading across runs". What does not
change: runs, units, attempts, custody, the promotion lock, release binding, recovery, the base-catalog
rule, deletion and the scratch path.

## Recommendation, and where the first cuts differ

The named stream of batch runs. It keeps every boundary the run model
already draws, one release, one frozen input set, one promotion, one
recovery scope per run, and adds only the continuity operations needs.

Three points settle how the shape behaves:

- On a corrected frame, the repair replays the descendants, and the
  replay may be batched. The corrected frame's own products wait for the
  same switch rather than being promoted alone: promoting the frame at
  once and deferring the catalog publishes both versions in one catalog.
- A date admits several batches when the latency requirement is shorter
  than a day, by the same mechanism as a new date.
- The stream is thin configuration: the existing schedule identity and
  its rows, with no new service, table or scheduler.

## Replacement scope

Promotion supersedes by science slot. Each kind's identity key and slot
are on [products](products), "Identity"; slot replacement, including the
rule that an `association-set` promotion replaces only an ancestor of the
set it promotes, is on [runs](runs), "Rules". What stays open here is
the replacement the chain switch below makes:

- **A new delivered version** of (E, D): the `l2-image` slot (E, D) and
  every slot keyed on (E, D), and each affected field's catalog slots,
  all in the one chain-switch promotion a correction run ends in.

One atomic before and after, for an overlap of live and reprocessing:
the campaign's switch promotion lists, per slot, the expected current
instance (the stream's) and its replacement (the campaign's). If the stream promoted a new
batch between the campaign's plan and its promotion, at least one
expected instance no longer matches, the whole switch is refused, and
the campaign replans against the new selection (stale-plan refusal, as
the promotion lock does today). Rollback is the recorded inverse, refused
if the switch's after-selection is no longer current, as today.

### The chain switch

One mechanism serves both a reprocessing campaign and a correction run:
the switch that moves a stream from one catalog chain to another.

A reprocessing campaign is a set of ordinary production runs under a new
release or new settings, auto-promote off, on the bulk queue (Capacity,
below). A correction run is an ordinary production run seeded on each
affected field's last association set before a corrected frame's epoch;
it replays the field's batches up to the stream's head with the
corrected version in place, regenerating the association, statistics
and pruned sets and the alert containers of the frames those fields
hold. Corrections may be batched into one correction run on a schedule
the team sets; until the switch, consumers keep the earlier selection.
A frame is *awaiting correction* when the stream has admitted a higher
delivered version for its (exposure, detector) than the version the
current catalog of its field holds, and no chain switch has applied it
yet; only the stream's own admissions count.

1. The replacing run (a campaign or a correction run) has processed every
   delivery up to the stream's most recent complete batch.
2. It takes the stream's schedule lock, the advisory lock `loop run`
   already holds for its whole run, so no new batch starts during the
   switch; if a batch completed after step 1, it processes that batch's
   deliveries first, still under the lock.
3. No batch of the stream may be left open on the old chain, because its
   frozen inputs bind the old head and a resumed batch would extend it.
   Before the switch, each open, failed or timed-out batch is either
   finished (and then covered as in step 2) or cancelled, with its
   deliveries recorded as not processed, so the replacing run's catch-up
   takes them. The switch refuses while any batch of the schedule is
   open.
4. One promotion replaces every slot the replacing run covers, file
   products and result sets together, each against its expected
   predecessor. The boundary, the stream's last batch covered, is in the
   promotion's request context.
5. In the same transaction the stream's records gain a switch row naming
   each field's adopted head. The base-catalog rule reads the most recent
   complete row or switch row of the schedule, so the stream's next batch
   extends the adopted head.

A person makes the switch; it is the one promotion into a catalog slot
that is not an extension of the current chain. Its rollback restores the
earlier selections and adds a switch row back to the earlier heads. The
records change is additive: `loop_dates` gains a batch sequence (so a
date can hold several batches) and a row kind (`batch` or `switch`).

## Closure and latency

The arrival outcomes, a later batch for the same date, a refused
identical re-delivery, a quarantined checksum mismatch and a deferred
corrected version, are on the [loop](loop) page, "Discovery and
batches". The batch cadence stays open. The provisional latency, within
an hour per detector image ({ref}`latency ruling <decision-latency>`),
points to per-delivery batches with an event or roughly 30-minute window
trigger.

If the latency requirement is a day or more, one batch per date after a
fixed cutoff hour is enough, and the stream is the loop as written plus
discovery. If it is minutes, batches become per delivery and the trigger
becomes an event rather than a window. The run model's shape holds; whether
the stages and the queues keep up at that scale is unverified (the
`difference` stage alone runs about 58 minutes per detector image today;
Capacity, below), and a chain switch holds the schedule
lock while it catches up, which pauses live batches for that time. The page does not declare operations ready
until the team confirms the latency and the mission states the delivery
interface.

## The loop's five calls

Of the loop's five calls, two stay open here; the others are on the
[loop](loop) page.

- **Cadence** (proposed): a fixed `window:cron(...)` at an interval of
  half the latency budget; a firing that discovers nothing exits 0 and
  writes nothing. An event trigger only if the latency requirement is
  minutes.
- **Production check policy** (proposed, below).

## A production check policy

Proposed as `rebuild-production@1`, with `auto_promote = true`
requested. Approval semantics: a policy is immutable once landed
([checks](checks)), so the file lands once, already carrying the
team's approval, recorded as `approval = "team"` with `approved_by` set
to the approver's login, in a pull request the team approves; until
then its content lives only in the table below, and no file for it
exists to be edited. No other path raises a policy to `team`.
`rebuild-trial@1` stays at trial approval. Team approval of this policy
is pending.

Bounds from real data: the 15357 difference images `dev` recorded in
production `diffimmeta`, taking each measure's 1st to
99th percentile and widening by half:

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
the factor moves to order one, so its bound is set from the first
production batches under that ruling, not from `dev`. The catalog-count check
stays advisory until earlier production runs have made current source
sets for the same frames to compare against; it compares with another
run's source set, never with a reference catalog ([checks](checks)).

## Reference eligibility and selection

Proposed: a reference image is eligible for a field and filter when it
is current in that slot, built by the recipe the stream's spec names,
from constituents that are all current or superseded. Selection is then
trivial: the one current reference in the (field, filter) slot, which is
`dev`'s rule (the reference with `vbest` set). A new reference promoted
mid-stream is used by later batches; difference images made against the
earlier one keep it, as their identity key says, until a reprocessing
replaces them. Where the reference PSF is resolved from stays open.

## Staged inputs of a production run

A production run stages its difference input set, a copy of the l2
image, reference bundle and PSFs plus the manifest, under the scratch
bucket's `rapidpipe/runs/<run-id>/inputs/`, because the launcher
host cannot write the products bucket and [tool](tool) puts every input
set under the scratch root. Proposed run-model rule: a production run's
staged input sets are part of its provenance and are retained for the
run's lifetime; nothing expires or deletes them while the run's row
exists. That holds today without a change: scratch expiry and `run
delete` act only on scratch runs, and the scratch bucket has no
lifecycle rule. The rule is written down so a later
lifecycle rule does not quietly break it.

## Capacity

Two queues exist: `rapid-queue-prompt` (priority 10, on-demand
`rapid-ce-prompt`, 5000 vCPU) and `rapid-queue-bulk` (priority 1, Spot
`rapid-ce-bulk`, 10000 vCPU). Measured rebuild jobs put `difference` at
a median of about 58 minutes of execution per detector image, the only stage over the 30-minute target;
`alerts` ran about 25 minutes on production runs, and every other stage
under a minute. Proposed lanes: the stream on prompt; reprocessing
campaigns and correction runs on bulk; scratch runs on bulk by default,
prompt by request. That is the specification's "scratch runs cannot
consume capacity reserved for regular operations" with the queues that
already exist.

## Not decided here

- Confirmation of the provisional delivery-to-alert latency
  ({ref}`latency ruling <decision-latency>`), and the mission's delivery
  manifest and completeness signal.
- How often correction runs run: per correction, or batched on a
  schedule; the team's.
- Whether alert history for a late-arriving earlier epoch is ordered by
  observation time or by arrival; the team's.
- Team approval of `rebuild-production@1` and its `scalefacref` bound.
- Where the reference PSF is resolved from.
