# Operations: live processing, reprocessing and development together

**Status: DRAFT, a proposal.** Nothing on this page changes code, schema
or another page's rulings; each section says whether it records a
settled ruling or proposes one.

Written 2026-09-26 by the rebuild direction pass, for the lead and the
team, from the lead's concern of that morning: the system is naturally
biased toward batch processing of simulations, and operations will bring
data arriving in a stream from the spacecraft, so the run model has to
serve continuous survey processing, bulk reprocessing, and parallel
testing and development at the same time. This page takes every use
case the team will have, traces them running together under three
candidate shapes of the run model, and recommends one. It also carries
the loop's five open calls, a proposed production check policy,
reference eligibility, the product-identity mechanism under the lead's
2026-09-26 principle, and the run-model rule for a production run's
staged inputs. The [specification](specification), [runs](runs),
[products](products) and [loop](loop) pages remain the design
authority; where this page proposes a change to them, it says which
sentence would change.

## In plain terms

Operations is a named stream that turns each batch of new deliveries
into one ordinary run, frozen at creation like every other run. Anything
that changes an earlier result, a corrected frame, a new release, new
settings, is another run, never an edit to a finished one. Consumers see
whatever promotion last selected, and promotion replaces the earlier
selection for the same science slot: the same exposure and detector for
an image, the same field for a catalog. A developer's run is an
ordinary scratch run beside all of this and touches none of it.

That is the recommendation. It is the model as written, with three
additions: the stream discovers its own deliveries instead of reading a
hand-written list; promotion supersedes by science slot rather than by
the instance-bearing key it uses today; and one table says which inputs
a product may be built from and which it may be published from. Each
addition is a proposal below, with its cost.

## The use cases

| Use case | What the team does | Served today? |
|---|---|---|
| Continuous survey processing | Deliveries arrive through the day; each is admitted, differenced, loaded, crossmatched into its field's catalog and alerted on, without a person | Partly: the loop processes a fixed list of dates from a spec written by hand |
| Late delivery | A frame observed on an earlier date arrives after that date's run | No: a run freezes its inputs, and nothing says which later run takes the frame |
| Identical re-delivery | The same file arrives twice | No rule: a second admission would make a second `l2-image` instance of the same key |
| Corrected delivery | The mission re-delivers a frame with a new version after its difference image, sources, catalog and alerts exist | No: the new version is a different logical key, and promotion today accumulates rather than supersedes |
| Bulk reprocessing | Rerun months of data under a new release or new settings, then switch consumers to it | Partly: a production run with auto-promote off, but its derived products sit beside the old ones instead of replacing them ([runs](runs), Promotion) |
| Development beside production | A developer runs a stage or a chain against real inputs without touching production | Yes: scratch runs, scratch bucket, trial database, `rapid-rebuild` job definition |
| A stage on a slice | Test one stage on a handful of units | Yes: `run create` with one stage and `run start --unit` |
| Recovery of a failed date | Resume or replace a date that failed | Yes, with one wording conflict: [loop](loop) says `--retry-failed` resumes the same run, while the code seeds a replacement run when the date has a failed unit (Recovery, below) |
| Science comparison | Compare two runs' outputs over the same inputs | Partly: `run compare` compares metadata; a science comparison needs matched products by science slot, which today's keys cannot give across runs |
| Outage catch-up | After a day or a week without processing, clear the backlog in order | Partly: the loop walks the dates a spec names, in order, one at a time |
| References, photometry, exports | The slower pipelines, on their own cadence | Yes: independent runs, bound as inputs by instance |

## What this page assumes about the mission

Three mission interfaces are not yet defined ([specification](specification),
Edges). The traces below assume the following, and the recommendation is
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
- **Latency.** No delivery-to-alert latency requirement is established on
  any page. The page assumes alerts are wanted within hours of delivery,
  not within minutes; a minutes-scale requirement changes the batch size,
  not the shape (Closure and latency, below).

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
slot (Replacement scope); and publication follows the eligibility table
(Dependency eligibility). What does not change: runs, units, attempts,
custody, the promotion lock, release binding, recovery, the base-catalog
rule, deletion and the scratch path.

## The modes together

Four traces, each run under the recommended shape, with how the other
two shapes fare.

**Live processing and a bulk reprocessing competing for the same products
and the same capacity.** The stream runs release R1. A reprocessing
campaign under release R2 starts at the first date and works forward,
as ordinary production runs with auto-promote off, on the bulk queue
(Capacity, below). Neither promotes over the other by accident: the
stream's promotions carry, per slot, the instance they expect to
replace, and the campaign's do the same, so whichever promotes second
against a stale expectation is refused and replans ([runs](runs),
Promotion: "checks every expected previous selection ... and refuses the
whole request on any mismatch"). Expected-before checks protect against
concurrent writes; they do not prove the campaign covers every delivery
the stream has processed. That is the *chain switch*'s job (below): the
campaign catches up to the stream's head, takes the stream's schedule
lock so no new batch starts, processes the deliveries up to the
stream's last batch, and then one promotion replaces every slot the
campaign covers, images, source sets, and each field's catalog,
statistics and pruned sets, with before and after recorded, and writes a
switch row in the stream's records naming each field's adopted head. The
stream's spec moves to R2 in the same step; its next batch binds the
adopted head as its base. One rollback restores R1's selection. Under the model as
written this trace fails at the promotion: the campaign's derived
products have keys that embed its own instance ids, so they add beside
R1's rather than replace them. Under a long-lived run there is no
second run to compare or switch to.

**A partial delivery and where the date's boundary sits.** Half of a
date's detector images arrive by the time the trigger fires. The stream
makes one batch of what has arrived and processes it; the rest arrive
later and enter the next batch, which is a second run for the same
processing date. Each batch's catalog step binds, per field, the most
recent complete batch's association set, so the second batch's objects
accumulate onto the first's exactly as a new date's do today. A date has
no boundary the pipeline must wait for; it is a label on the batches
that processed its frames. Under the model as written the date's run
either waits (latency) or closes early and strands the late half.

**Catch-up after an outage.** The stream was down for three days.
Deliveries kept landing in the inbox. The first firing discovers every
unadmitted delivery; the stream groups them by processing date, oldest
first, and makes one batch per date, in order, so each field's chain
advances in observation order. The live backlog's age is the age of the
oldest unadmitted delivery, which `loop show` can print. Under the model
as written someone writes the three dates into a spec first.

**A corrected earlier frame, after later dates' catalogs and alerts
exist.** Frame F (exposure E, detector D) was delivered as version 1 on
day 1, and days 2 to 5 have since run. Version 2 of F arrives on day 6.

- Admission: the stream admits version 2 in day 6's batch; it is a new
  instance of the `l2-image` slot (E, D) with a higher delivered version.
- The frame and the catalog: the batch differences and loads version 2,
  but a corrected frame does not enter the live catalog step. Appending
  its sources to the current head would leave version 1's sources in
  the same catalog, since the head holds them from day 1 onward, and
  prune would keep both. The frame's products stay candidates.
- Repair: a *correction run*, an ordinary production run seeded on each
  affected field's last association set before day 1, replays the
  field's batches from day 1 to the stream's head with version 2 in
  place of version 1, regenerating the association, statistics and
  pruned sets and the alert containers of the frames those fields hold.
  It ends in a chain switch, the same step a reprocessing campaign ends
  in: one promotion selects the corrected frame's products and the
  repaired field selections together, against their expected
  predecessors, and the stream adopts the repaired heads. Corrections may
  be batched into one correction run on a schedule the lead sets; until
  the switch, consumers keep the earlier selection, version 1 included.
- Alerts already delivered stay historical records. Any correction or
  withdrawal sent outside the account belongs to the delivery adapter
  ([specification](specification), Edges).

A field whose catalog holds a source set from a frame whose current
`l2-image` is now a different delivered version is *awaiting correction*,
and that can be asked of the database: follow the association chain's
source sets to their difference images and l2 instances, and compare
each with the current instance in its (exposure, detector) slot. This is
different from ordinary advancement, where a new association set
supersedes its base but no l2 image changes, so an extended chain is
never flagged for having a superseded ancestor.

The cost of a correction run grows with the batches after the corrected
epoch, which is why it is batched rather than run on every admission.
Under a long-lived run the correction would edit history inside the
run; under the model as written the corrected frame's products would
sit beside the old ones as two current selections.

## Recommendation, and where the first cuts differ

The named stream of batch runs. It keeps every boundary the run model
already draws, one release, one frozen input set, one promotion, one
recovery scope per run, and adds only the continuity operations needs.

Two first cuts existed before this page. Codex Astra's, written the same
morning, recommends the same shape in its own sentence: "operations
advances through frozen batches; corrections create replacement runs,
never edit completed ones." Claude's earlier leaning was the named
stream. This page agrees with both on the shape and records three
differences:

- On a corrected frame, both cuts replay descendants; this page adds
  that the replay may be batched, and that the corrected frame's own
  products wait for the same switch rather than being promoted alone.
  An earlier draft of this page promoted the frame at once and deferred
  the catalog; Codex's co-work review of that draft (2026-09-26) showed
  it publishes both versions in one catalog, and the draft was
  withdrawn.
- Codex's cut leaves open whether a date admits several batches. This
  page says it does, when the latency requirement is shorter than a day,
  and says it is the same mechanism as a new date.
- Codex's cut keeps "stream" as thin configuration. So does this page:
  the stream is the existing schedule identity and its rows, with no new
  service, table or scheduler.

## Replacement scope

The lead ruled the principle on 2026-09-26: a logical key is built only
from delivered facts and science choices, never from an instance id;
instances still reference the exact input instances they consumed;
promotion supersedes, never accumulates. The principle alone does not
say what a new instance replaces, because a changed delivered version,
reference recipe or settings hash is a different logical key. This page
proposes two keys per kind:

- the **identity key**: everything that makes one product scientifically
  different from another, the ruled logical key;
- the **slot**: the part of the identity key a consumer selects on,
  "the current X for Y". At most one instance is current per kind and
  slot, and promotion replaces by slot.

| Kind | Slot | Identity key adds |
|---|---|---|
| `l2-image` | exposure, detector | delivered version |
| `psf` | filter, detector | version |
| `reference-image` | field, filter | recipe, selection digest |
| `reference-catalog` | field, filter, catalog type | the reference's identity key |
| `difference-image` | exposure, detector, differencer | delivered version, the reference's identity key, settings hash |
| `source-catalog` | exposure, detector, differencer, catalog type, sign | the difference image's identity key |
| `source-set` | exposure, detector, differencer, catalog type | the difference image's identity key |
| `alert-container` | exposure, detector, differencer | the difference image's identity key, alert schema version |
| `association-set` | field | crossmatch settings hash, the selection digest of the source sets it holds |
| `pruned-set` | field | the association set's identity key, pruning settings hash |
| `statistics-set` | field, membership kind (association or pruned) | the membership set's identity key |
| `light-curve` | field, request id | the object set's identity key |
| `catalog-export` | field, export type | the selection digest (as today) |

What each change withdraws, at promotion:

- **A new delivered version** of (E, D): the `l2-image` slot (E, D) and
  every slot keyed on (E, D), and each affected field's catalog slots,
  all in the one chain-switch promotion a correction run ends in (the
  fourth trace above).
- **A new reference recipe or reference selection** for (field, filter):
  the `reference-image` and `reference-catalog` slots. Difference images
  made against the old reference keep their slots; a reprocessing
  replaces them when the lead chooses to.
- **New settings** for a stage: every slot of that kind the promoting
  run produced, and nothing else. A reprocessing with new difference
  settings therefore replaces the old difference images, which the
  current [runs](runs) Promotion paragraph says it does not ("a
  reprocessing with changed settings therefore sits beside the old
  result"). That sentence is the one this proposal changes.

One atomic before and after, for an overlap of live and reprocessing:
the campaign's switch promotion lists, per slot, the expected current
instance (R1's) and its replacement (R2's). If the stream promoted a new
batch between the campaign's plan and its promotion, at least one
expected instance no longer matches, the whole switch is refused, and
the campaign replans against the new selection (stale-plan refusal, as
the promotion lock does today). Rollback is the recorded inverse, refused
if the switch's after-selection is no longer current, as today.

An accumulating slot needs one more rule: a promotion into an
`association-set` slot must replace either nothing or an ancestor of the
set it promotes (the same chain), unless it is a chain switch. This
keeps a live batch from replacing a campaign's chain head with its own
older chain by accident.

### The chain switch

One mechanism serves both a reprocessing campaign and a correction run:
the switch that moves a stream from one catalog chain to another.

1. The replacing run (a campaign or a correction run) has processed every
   delivery up to the stream's most recent complete batch.
2. It takes the stream's schedule lock, the advisory lock `loop run`
   already holds for its whole run, so no new batch starts during the
   switch; if a batch completed after step 1, it processes that batch's
   deliveries first, still under the lock.
3. One promotion replaces every slot the replacing run covers, file
   products and result sets together, each against its expected
   predecessor. The boundary, the stream's last batch covered, is in the
   promotion's request context.
4. In the same transaction the stream's records gain a switch row naming
   each field's adopted head. The base-catalog rule reads the most recent
   complete row or switch row of the schedule, so the stream's next batch
   extends the adopted head.

A person makes the switch; it is the one promotion into a catalog slot
that is not an extension of the current chain. Its rollback restores the
earlier selections and adds a switch row back to the earlier heads. The
records change is additive: `loop_dates` gains a batch sequence (so a
date can hold several batches) and a row kind (`batch` or `switch`).

## Closure and latency

Assumed: alerts wanted within hours of delivery; no completeness signal
from the mission. Under that assumption a date admits several immutable
batches, and each is a run.

| Arrival | What happens |
|---|---|
| Before the date's first batch | Enters that batch |
| After a batch of its date ran | Enters the next batch, a second run for the same date; its field chain extends the first batch's |
| Identical re-delivery | Refused at discovery: same exposure, detector, delivered version and checksum as an admitted instance; recorded, no run |
| Same version, different checksum | Quarantined: recorded as a mission error, not admitted, reported in `loop show`; a person decides |
| Corrected version after descendants exist | Admitted and differenced in the next batch, kept out of the live catalog; its products wait for a correction run's chain switch (the fourth trace above) |

If the latency requirement is a day or more, one batch per date after a
fixed cutoff hour is enough, and the stream is the loop as written plus
discovery. If it is minutes, batches become per delivery and the trigger
becomes an event rather than a window; the shape holds, the capacity
reservation matters more. The page does not declare operations ready
until the lead or the mission states the latency and the delivery
interface.

## Dependency eligibility

Readability is not scientific acceptance. A stage may *read* an input it
may not *publish from*. Today [products](products) gives the reading
rule for result sets only, and says a check-refused candidate is
readable; file products carry no rule. The proposed table covers both.

| Input's state | A stage of another run may read it | A product built from it may be promoted |
|---|---|---|
| Scratch, own run | yes | no (scratch never leaves scratch) |
| Scratch, another run | no, exit 65 | no |
| Candidate, from an unselected attempt | no, exit 65 | no |
| Candidate, selected, checks not run | yes | only if promoted together with it, in one promotion |
| Candidate, selected, a required check failed | yes | no, until a person accepts it with a recorded reason or it is replaced |
| Current | yes | yes |
| Superseded (current before, candidate now) | yes, as any candidate from a selected attempt; an extended catalog chain reads its superseded ancestors this way today | yes |

The same rule applies to file products (l2 images, references, PSFs) as
to result sets, which closes the open question [products](products)
records under "Reading across runs". The answer to "does a failed
upstream science check block descendant publication": yes. A date whose
promotion was refused still feeds the next date's catalog, as the loop
does today, but the next date's catalog cannot be published until the
refused date is accepted or repaired. That makes a refusal loud: it
holds its field's catalog until someone acts, rather than letting a
catalog that contains rejected data become current. This is a change to
the loop's behaviour and is proposed, not landed.

## The loop's five calls

The lead folded these into this page on 2026-09-26 (12:25).

- **What a firing processes** (proposed): every admitted-but-unprocessed
  delivery the stream discovers in its inbox location, grouped into one
  batch per processing date, oldest first. The spec keeps schedule,
  release, policy, owner, lane and attempts; its `[[dates]]` list stays
  for proofs and backfills only.
- **Cadence** (proposed): a fixed `window:cron(...)` at an interval of
  half the latency budget; a firing that discovers nothing exits 0 and
  writes nothing. An event trigger only if the latency requirement is
  minutes.
- **Release binding** (proposed): the spec names a tag explicitly, and
  moving operations to a new release is a one-line spec change made on
  purpose; `release cut` does not edit the spec, and there is no
  "current" alias, which would move operations on every cut.
- **Production check policy** (proposed, below).
- **The proof spec** stays unrepaired (the lead, 2026-09-26, 12:25). Its
  `difference_template` prefix was deleted in the 2026-09-25 cleanup; a
  discovering stream does not need it.

## A production check policy

Proposed as `rebuild-production@1`, `approval = "none"` until the lead
approves it, `auto_promote = true` requested. Approval semantics: the
lead's approval is a commit, by the lead or merged on the lead's review,
that sets `approval = "lead"` and `approved_by` to the lead's login; no
other path raises a policy to `lead`. `rebuild-trial@1` stays at trial
approval (the lead, 2026-09-26, 12:26). Lead approval of this policy is
explicitly pending.

Bounds from real data: the 15357 difference images `dev` recorded in
production `diffimmeta` (read 2026-09-26), taking each measure's 1st to
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
`dev`'s values come from a fixed `zprefimg` of 17.0; under the lead's
2026-09-26 ruling that gain matching reads `MAGZP` from the reference,
the factor moves to order one, so its bound is set from the first
production batches under that ruling, not from `dev`. The catalog-count
check stays advisory until a current reference catalog exists to
compare against.

## Reference eligibility and selection

Proposed: a reference image is eligible for a field and filter when it
is current in that slot, built by the recipe the stream's spec names,
from constituents that are all current or accepted. Selection is then
trivial: the one current reference in the (field, filter) slot, which is
`dev`'s rule (the reference with `vbest` set). A new reference promoted
mid-stream is used by later batches; difference images made against the
earlier one keep it, as their identity key says, until a reprocessing
replaces them. Where the reference PSF is resolved from stays open.

## The product-identity mechanism and its cost

Proposed mechanism: `product_instances` gains a `slot` column (text,
canonical JSON of the slot fields) beside `logical_key`, which is
rebuilt from delivered facts and science choices. The partial unique
index on current selections moves from (kind, logical key) to (kind,
slot). Promotion's deliverable list, its expected-before check and its
rollback work per slot. The loop's promotions then carry one change per
slot, not per instance-keyed product. `vbest` maintenance maps onto the
slot directly.

Cost, stated: one additive migration (the column, a backfill for
existing rows derived through `dependencies`, the new index); changes to
`register` (compute both keys per kind), `promote`, `promote_run`,
rollback, the loop's promotion, and the `catalog-counts-vs-reference`
check, which today walks dependencies to find its reference by science
identity and would read the slot instead; tests for each. The old index
stays until no open run's release predates the change (additive rule,
[releases](releases)). About three to four days of work including the
trial-database backfill, more than a light-touch change, so this is a
proposal for the lead.

## Staged inputs of a production run

Production run 01M3B18KDDJT92VW3V54RYV9HM (the P4 demonstration) staged
its difference input set, a copy of the l2 image, reference bundle and
PSFs plus the manifest, under the scratch bucket's
`rapidpipe/runs/01M3B18KDDJT92VW3V54RYV9HM/inputs/`, because the launcher
host cannot write the products bucket and [tool](tool) puts every input
set under the scratch root. Proposed run-model rule: a production run's
staged input sets are part of its provenance and are retained for the
run's lifetime; nothing expires or deletes them while the run's row
exists. That holds today without a change: scratch expiry and `run
delete` act only on scratch runs, and the scratch bucket has no
lifecycle rule (read 2026-09-26). The rule is written down so a later
lifecycle rule does not quietly break it.

## Capacity

Two queues exist: `rapid-queue-prompt` (priority 10, on-demand
`rapid-ce-prompt`, 5000 vCPU) and `rapid-queue-bulk` (priority 1, Spot
`rapid-ce-bulk`, 10000 vCPU). Every rebuild job so far has run on the
prompt queue. Proposed lanes: the stream on prompt; reprocessing
campaigns and correction runs on bulk; scratch runs on bulk by default,
prompt by request. That is the specification's "scratch runs cannot
consume capacity reserved for regular operations" with the queues that
already exist.

## Recovery wording

[loop](loop) says `loop run --retry-failed` reopens a failed date and
resumes the same run. The code does that only for a failed date whose
run has no failed or cancelled unit; a date with a failed unit is
seeded into a replacement run (`run create --seed --only-failed`
semantics). The loop page is corrected to say so in the direction
pass's documentation fixes (rapid_docs #36).

## What changes and what does not

Changes, each a proposal: delivery discovery in the stream; several
batches per date; supersession by slot, with the `slot` column; the
eligibility table, including for file products; correction runs as
ordinary runs ending in the chain switch, with its switch row and batch
sequence in `loop_dates`; lanes mapped to the two queues; the production
check policy.

Does not change: the run as a frozen pass; units, attempts, custody and
the promotion lock; release binding per run; the base-catalog rule
(it reads one more row kind);
deletion; the scratch path for development and slices; the registry row
as the scheduler.

## Not decided here

- The delivery-to-alert latency requirement, and the mission's delivery
  manifest and completeness signal.
- How often correction runs run: per correction, or batched on a
  schedule; the lead's.
- Whether alert history for a late-arriving earlier epoch is ordered by
  observation time or by arrival; the lead's.
- Lead approval of `rebuild-production@1` and its `scalefacref` bound.
- Where the reference PSF is resolved from.
