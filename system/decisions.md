# Decisions

**Status: DRAFT**

Any team member can add a ruling directly, with one dated line and the
author's name. CI on `main` is the only gate. Once recorded here, a
ruling belongs to the team. Design pages state the rule and cite this
page where attribution matters.

## Rulings

(decision-sfft-published)=
**SFFT is the published differencer**: the difference job publishes the
SFFT image and SFFT's positive PSF-fit catalog as `diffimages` and
`sources`, and the packet's cutouts and forced photometry read the SFFT
image, its PSF and uncertainty. This is `dev`'s choice since b725007d
(2026-04-20; `diff_flavor = sfft`). ZOGY still runs; its catalogs are
diagnostics. With SFFT off, or on a nonzero SFFT exit, the job fails
rather than falling back to ZOGY. The switch precedes the measurement:
rapid PR 408 switches, and the paired measurement against the ZOGY runs
80 and 81, by brief `differencer`'s second task, adds its numbers here.
(Ben, 2026-10-24 19:22 UTC)
Measured on the same bytes (rapid PR 418; runs 88 and 89 against 81
and 80): on HLWAS injected `001_0001` SCA 8, three epochs, SFFT detects
256 of 600 against ZOGY's 542 and none fainter than AB 24.5; false
positives per epoch are 385 against 228; its core fraction is +0.25 against +0.003,
so bright-star cores fill the 500-source cap. On OpenUniverse TDS,
ten epochs, it detects 24 of 410 evaluated transients against 35, with
stars subtracted cleanly (core +0.005) and the cap filled by sources
matched to no truth row. Difference seconds are unchanged.


Ben's rulings of 2026-10-24 04:00 to 04:40 UTC on the second
iteration (brief `night-2026-10-24`). The [foundation](foundation) and
[difference](difference) pages state the rules they set.

(decision-bright-star-flag)=
**The bright-star residual is flagged, not fixed**: what the null test
leaves above S/N 20 after the fixes, bright stars, gets an informational
flag bit and a fraction in the metrics; nothing is dropped. SCAs 4 and
5's excess gets one metric, the science stars' width against the ePSF,
and F213's flux scale a metric and one check of the zero-point table.
Measured: the radius law flags 21 of 23, 15 of 19 and 11 of 15 of
run 46's sources above S/N 20 on F146 SCA 8; the science stars are 1.5
to 3.3% wider than the ePSF on SCAs 4, 5 and 8 alike; the table agrees
with the files to 0.035 mag. (Ben, 2026-10-24 UTC)

(decision-spot-probe)=
**Spot is a probe, not production**: a run that names a Spot queue
sends a stage's backlog there with one attempt per submission, and
every next attempt, and any straggler past a hedge factor, runs on
demand; nothing is retried on Spot. It supersedes
{ref}`Spot stays parked <decision-spot-parked>` for runs that opt in.
Measured: the injected footprint's Spot twin finished 2.1 min after its
on-demand run, with no reclaim, at $1.30 against $2.03 priced by lane.
(Ben, 2026-10-24 UTC)

Ben's rulings of 2026-10-22 on what follows the wide-area ramp, made
stepwise between 12:57 and 13:23 PDT, and one of the same evening. The
[foundation](foundation) page states the design they shaped, and the
[loop](loop) and [difference](difference) pages the rules they set.

(decision-housekeeping-first)=
**Housekeeping first, then the disjoint reference, then injection**:
the ramp's bytes and waits grow with every step after it, so the
housekeeping lands before the ramp grows. Cutting it to two items, and
injection first, were named and not taken. (Ben, 2026-10-22 PDT)

(decision-breadth-before-injection)=
**The other filters before injection**: after the housekeeping and the
disjoint reference, the other filters run without injection, each
filter a dataset of its own with its own live run, each image's PSF
from its file's CRDS ePSF reference, and injection follows.
This brings the first half of the breadth step forward, for experience
running the pipeline over several filters. (Ben, 2026-10-22 16:03 PDT)

(decision-reference-bound)=
**The reference's epochs are a run setting, an `mjdobs` bound**: a run
names which of a field's epochs may build its reference by a date, not
a list of passes, because a date generalises to GBTDS, which has no
passes. The pass list was recommended and not taken.
(Ben, 2026-10-22 PDT)

(decision-chain-admission-order)=
**A reference stays per dataset, field and filter, and a field's chain
is in the loop's admission order**: two SCAs on the same sky are the
same field, and the SCA is in the PSF key the difference stage reads
per epoch, so a reference per SCA would double references where
pointings overlap and buy nothing. The loop admits in `mjdobs` order
across every SCA of its selection; an earlier epoch that arrives after
later ones is a rerun from that epoch, and the loop never
re-associates. (Ben, 2026-10-22 PDT)
The chain half is superseded by
{ref}`association in the difference job <decision-association-in-difference>`
(2026-10-24); the reference half stands.

(decision-injection-outside)=
**Injection is outside the pipeline, as a dataset**: a one-time job
injects sources into the SOC files and writes them under a new dataset,
which the pipeline takes in like any other. Injection inside a stage is
kept for later, if injection becomes per run rather than per dataset.
(Ben, 2026-10-22 PDT)

(decision-producer-last)=
**The container-side producer stays, last**: producing packets to Kafka
from the packet stage's own Batch job is the last code milestone, and
`publish` stays as the verb that publishes again. Dropping it was named
and not taken. (Ben, 2026-10-22 PDT)

(decision-catalogs-dataset)=
**The `catalogs` key gains the dataset**, as every other key has, so a
footprint's Gaia copy is one product per dataset and its name no
longer carries the footprint. (Ben, 2026-10-22 PDT)

(decision-difference-trimmed)=
**Difference outputs are trimmed** to the difference, its uncertainty,
the mask and the catalog, gzipped as the intake's are; a variant is
made again by a rerun, and there is no setting to keep more. A storage
lifecycle rule was named and not taken. (Ben, 2026-10-22 PDT)

(decision-gbtds-after-injection)=
**GBTDS comes after injection**, not beside it; its WCS re-derivation
is the intake's first extra step when it does. (Ben, 2026-10-22 PDT)

(decision-psf-from-epsf)=
**The PSF comes from the file's CRDS ePSF reference**: each image's
science PSF is derived from the ePSF reference its own file names,
which is the calibration's PSF and what flight data will carry; the
simulation's rendering PSF is not a product. (Ben, 2026-10-22 13:08 PDT)

(decision-reference-psf-measured)=
**The reference PSF is derived data, measured in the difference job**:
the PSF ZOGY uses for the reference is built from the stars of the
resampled reference the job has just made and recorded in its manifest,
not an input chosen at launch, because ZOGY needs the PSF of the image
it is given and each resampling widens it: on run 17 (r00342 F146 SCA
8) the resampled reference's stars were 15% wider than the science
ePSF the `psf` stage had handed ZOGY for both, the cause of 73% of the
null test's detections. Fewer than ten stars fails the job; there is no
fallback. `dev` has no knob here (a static, offline-compiled reference
PSF per detector), so this is a divergence from `dev`.
(Ben, 2026-10-23 23:22 UTC, fixes-2026-10-23)

(decision-association-in-difference)=
**Association runs in the difference job, reconciled at publish**: the
difference job matches its sources against its field's objects of its
run as they stand when it reads them, founds an object for each
unmatched source, and publishes sources, memberships and founded objects
together; the per-field chain of associate jobs, its admission order and
its exclusions are retired, and an object's statistics are the sums of
its official memberships, read through a view. Two epochs of a field in
flight at once can both found an object at one new source, so the
publisher, serialised per run and field, attaches a job's founded
objects to any founded since its read, the memberships rebased to the
surviving origin; object ids never change after publication. `dev`'s
route, crossmatch after difference against the catalog as it stands,
is the one taken; its duplicate-tolerant merge pass (`xmerges`), which
changes object ids after alerts have carried them, is named and not
taken. Measured: run 46's chained passes (`r00342-fx-f146`, SCAs 4, 5
and 8, three epochs) held nine associate jobs of 1.2 s each across 19.3
minutes; the read of the old chain view on one of its fields took 422
ms. (Ben, the plan's amendment of 2026-10-24 00:55 UTC;
night-2026-10-24 task 7)
"Its field's objects" became each touched field's objects with
{ref}`association by the source's field <decision-association-by-source-field>`
(2026-10-24).

(decision-association-by-source-field)=
**Association is by the source's field**: every accepted source of a
difference image is matched against the objects of its own field and
its neighbouring fields, and founds an object in its own field when
nothing matches, whichever image detected it; the publisher locks every
field that gained an object or a membership and each one's neighbours,
in ascending order, so two jobs founding either side of a boundary
serialise and reconcile. `dev`'s pass 2, where a source outside its
image's own field only joins an object already there (inside the
field's inclusion cone), is named and not taken: a field no image is
centred on founds nothing, so on run 72 (`r00342-inj1`, the injected
SCA 8 footprint, 162 epochs) 0.96 of the injected sources were
detected and 0.40 alerted, and 15,485 of the 15,655 detected injected
sources outside their image's field lay in a field no image of the run
is centred on. The packet's forced window follows: the images covering
the object, whichever field each is centred on. A divergence from
`dev`, with no knob. (Session decision under the standing rule, Ben's
yolo of 2026-10-24 14:02 UTC; day-2026-10-24 task 1)

(decision-tool-exit-checked)=
**An external tool's nonzero exit fails the job**: SExtractor, SWarp,
ZOGY, bkgest, awaicgen and SFFT raise a named failure (`ToolFailed`:
the tool, its exit code and its last 20 output lines, stderr included)
and the job row's `refusal` carries it, as it now carries any failed
job's exception type and message. `dev`'s `execute_command` returns the
code and its pipeline never reads it but SFFT's, so a failed tool
surfaced as a missing file later, or not at all when it left a partial
one. SFFT was the one exemption until
{ref}`SFFT became the published differencer <decision-sfft-published>`;
no stage is exempt now. Measured on HLWAS `001_0001` SCA 8 F146, epoch
4040101: with the difference stage's SExtractor pointed at `cat`, run 83's
difference job failed at its first SExtractor call with exit 70 and
`ToolFailed: cat exited with code 1` and `cat`'s two lines on its row,
not rerun; its twin run 84 published as run 82 did (773 against 774
candidates, Intel against AMD). A divergence from `dev`, with no knob.
(Session decision under the standing rule, Ben's envelope of 2026-10-24
19:22 UTC; err-tools task 1, rapid PR 407)

(decision-pixel-columns-fail)=
**`dev`'s pixel columns fail the job when their background fails**:
`sumrat`, `nneg` and `nbad` are measured on every SFFT PSF-fit source
after a 64 px local background is subtracted, as `dev` measures them
(c32e28f6), and are carried on `sources`. `dev` catches a failed
background and measures on the unsubtracted image; here the failure
fails the job, as every fault in the stage does. `dev`'s ini gives the
reason the background matters: on its socsims SFFT images, at a
pedestal of -2 to -6 DN/s, sumrat > 0.4 keeps 0.60 of injected sources
at S/N 5 to 10 on the image itself and 0.95 after the background.
Measured on HLWAS injected `001_0001` SCA 8, three epochs (rapid PR
422, run 96): sumrat > 0.4 keeps 0.997 of the 391 injected candidates,
0.68 of the 6,464 noise candidates and 0.90 of the 2,257 bright-flagged
ones; the columns cost 4.3 to 5.2 s a difference. A divergence from
`dev`, with no knob. (Session decision under the standing rule, Ben's
envelope of 2026-10-24 19:22 UTC; dev-columns task 1)

(decision-spot-parked)=
**Spot stays parked**: the rebuild's jobs run on demand; the cost
figure is read and recorded, and nothing hangs on it.
(Ben, 2026-10-22 13:23 PDT)
Superseded for runs that opt in by
{ref}`Spot as a probe <decision-spot-probe>` (2026-10-24).

Ben's rulings of 2026-10-21 evening on the instance type and the plan
in force. The [foundation](foundation) page states the design they
shaped, and the [stage contract](stage-contract) page the execution
record.

(decision-instance-type)=
**The instance type is recorded and no family is pinned**: every job
records the instance type it ran on beside its image digest, and the
compute environment is not pinned to one instance family.
(Ben, 2026-10-21 20:41 PDT)

(decision-hlwas-direction)=
**The exercised HLWAS pipeline is the plan in force**: the direction
question is set aside; the plan is a heavily exercised pipeline from
ASDF intake through Kafka publication, with the data entirely within
SMDC and nothing imported from another centre, starting with the SOC
HLWAS simulation without source injection, and iterating and ramping
once it runs end to end. The test is that the chain has the right
shape and functions on simple data. (Ben, 2026-10-21 20:50 PDT)

Ben's rulings of 2026-10-21 on the night through the chain. The
[foundation](foundation) page states the design they shaped, and the
[stage contract](stage-contract) page the retry and the PSF input.

(decision-latency-later)=
**Latency is later**: latency and performance optimisation are a later
task. The current focus is coherent, validated machinery end to end;
every run takes metrics and records improvements it sees, and no
measurement gates anything. (Ben, 2026-10-21)

(decision-psf-kind)=
**The PSF key gains a kind**: a `psfs` row is `science` or `reference`,
and the kind is in its scientific key, so the two PSFs of one filter
and SCA are distinct products. (Ben, 2026-10-21)

(decision-read-role)=
**The read role selects**: the team's read role has `SELECT` on every
table and view of the foundation's schema, and on those created later.
(Ben, 2026-10-21)

(decision-batch-retry)=
**Batch retries exit 75 and nothing else**: three attempts, the first
run and two retries, on the stage contract's temporary dependency
failure; every other exit ends the job. (Ben, 2026-10-21)

Ben's ruling of 2026-10-21 on the SMDC step. The
[foundation](foundation) page states the procedure it shaped.

(decision-smdc-prototype)=
**SMDC is a prototype**: the foundation's move onto SMDC needs no
attended migration, no backup before the schema is replaced and no
fence on the pooler; it proceeds as far as the plan allows.
(Ben, 2026-10-21)

Ben's ruling of 2026-10-20 on the foundation. The
[foundation](foundation) page states the design it opened.

(decision-foundation-dev-prior-art)=
**`dev`'s shapes are prior art**: the rule that the rebuild coexist with
`dev`'s schema, and the principle that every port minimise its
differences from `dev`, are revoked. `dev`'s table shapes and column
names are kept where they cost nothing and the team's queries read
them. (Ben, 2026-10-20)

Ben's rulings of 2026-10-08 on the pipeline's Python environment, the
rapid-python RPM, after a review of the environment. The infrastructure
repository's rapid-python README states the design they produced.

(decision-python-one-env)=
**One environment**: the single-environment design holds. The Kafka
client stays: kafka-python, aws-glue-schema-registry and
aws-msk-iam-sasl-signer-python remain in the environment file.
(Ben, 2026-10-08)

(decision-python-version)=
**Python version**: the environment moves to Python 3.13. If the
conda-lock solve on 3.13 still fails after two corrective attempts, the
environment falls back to 3.14 and the reason is recorded.
(Ben, 2026-10-08)

(decision-python-astroquery)=
**astroquery**: a direct conda-forge entry in the environment file, not
only a transitive dependency. (Ben, 2026-10-08)

(decision-python-romancal-floor)=
**romancal floor**: the pip block requires `romancal>=1.1`.
(Ben, 2026-10-08)

(decision-python-base-variants)=
**Base variants**: matplotlib, photutils and astropy are taken as
`matplotlib-base`, `photutils-base` and `astropy-base`. The lock showed
what the full metapackages pull in and the pipeline never imports:
pyside6 and qt6-main for matplotlib, rasterio and GDAL for photutils,
ipydatagrid for astropy. (Ben, 2026-10-08)

(decision-python-nexus-packages)=
**Roman Research Nexus packages**: the environment carries what the team
expects from the Nexus: sncosmo, healsparse, skyproj and ipympl from
conda-forge, and astrocut from PyPI, where it is the only source.
(Ben, 2026-10-08)

(decision-python-build-on-change)=
**Build on change**: the promoter builds the rapid-python RPM only when
its inputs are new. A NEVRA that is already published, with unchanged
tracked inputs, is taken from the published object instead of being
rebuilt. A changed lock under an unchanged NEVRA still meets the
immutable-NEVRA refusal. (Ben, 2026-10-08)

(decision-python-spec-committed)=
**Committed spec**: the rapid-python spec is a committed file, not
generated. The spec generator, its block directory, the shared prep
block and the generator's freshness check go. (Ben, 2026-10-08)

(decision-python-import-list)=
**One import list**: a single list of the environment's import names,
read by every consumer: the offline-replay gate, the RPM smoke test, the
fixtures and the re-lock's import proof. (Ben, 2026-10-08)

(decision-python-relock)=
**Re-lock cadence**: the environment is re-locked monthly on a schedule,
and on any push to main that changes its environment file. The weekly
bump no longer tracks it: the pin table's conda-lock row, its
locked-inputs token and the bump's resolver and probe for it go. The
re-lock pull request merges itself once validation is green on it and
the re-lock job has proved that the new lock imports every module on
the import list. This reopens the earlier rule that a re-lock is never
merged automatically: the import proof is the gate that rule lacked.
(Ben, 2026-10-08)

(decision-python-envhouse-retirement)=
**Envhouse retirement deferred**: the envhouse stays until build on
change has run for a few releases. Until then the only change to it is
the switch to the envhouse keyed by the lock's hash. (Ben, 2026-10-08)

Ben's rulings of 2026-09-27 on the rebuild's open questions.

(decision-trial-database)=
**SMDC database**: dedicated to the rebuild. dev's scripts never run
against it, read or write. The shared-writer hazards (vbest, prune,
swversions) are a cutover item, not a defect. (Ben, 2026-09-27)

(decision-science-flow)=
**dev-to-rebuild science flow**: the rebuild side owns it. Each ported
module under `rapidpipe/science` pins its source dev file and commit.
A CI script on `rebuild` reports later dev commits that touched each
pinned source. Porting stays by hand. (Ben, 2026-09-27)

(decision-loop-promotion)=
**Loop promotion**: follow the spec. The loop uses the same auto-promote
gate as `run start`. Under a trial policy a date's production run stays
a candidate until a person promotes it or a team-approved policy with
automatic promotion exists. Change loop.md and the unit test that
expects the opposite. (Ben, 2026-09-27)

(decision-acceptance)=
**Acceptance**: "required checks pass" only. The acceptances table,
`check accept` and the nine derived ancestor states go. The ancestor
walk reduces to "every ancestor is current or superseded". Fix a false
failure in the policy file. (Ben, 2026-09-27)

(decision-legacy-compatibility)=
**Legacy compatibility**: remove without a probe. The `logical_key`
selector and `_recorded_inverse` path in promote,
`_repair_stranded_succeeded_attempts`, and the rederive-once migration
go; rapid_rebuild is disposable. (Ben, 2026-09-27)

(decision-latency)=
**Fan-out and latency**: the rough requirement is within an hour per
detector image, from delivery until its alert is current, typically,
with a dense-field tail accepted. RAPID's time is short against the
exposure-to-L2 delay. This requires per-delivery batches with an event
or ~30-minute window trigger (operations.md's own rule) and within-date
fan-out over detector images. The difference stage's ~58 min runtime
(mostly Photutils PSF fits) is the binding constraint. Parallel dates
and lanes follow the number. (Ben, 2026-09-27; provisional, the team
confirms or replaces the number)

(decision-step-ledgers)=
**Step ledgers**: stay ephemeral. The 632 "supervisor step / R / A"
citations in code and pages are replaced by the design-page section they
implement; the 313 dated narration lines leave the pages.
(Ben, 2026-09-27)

(decision-authority)=
**Authority**: remove the lead role; the team owns the design. Any team
member can edit the decisions page in rapid_docs directly, adding one
dated line per ruling with its author. Once recorded, a ruling is the
team's, with no review gate; CI on `main` stays. Every "the lead's" on
the pages becomes the team's. Record the rulings above as Ben's, dated
today. Team communication about the rebuild remains Ben's to open.
(Ben, 2026-09-27)

## Earlier rulings

Ben made these rulings while he held the lead role. The authority ruling
makes them the team's; each page states the rule.

- 2026-09-21: keep the `dev` schema: rename or drop nothing; add
  columns and tables where the vocabulary needs them
  ([foundation](foundation)). The rebuild's schema coexists with `dev`'s and
  writes it ([foundation](foundation)).
- 2026-09-21: retain run records in full; deleting a run's data changes
  state, not history ([foundation](foundation)).
- 2026-09-21: current result sets are readable by any run as frozen
  inputs, by instance id; scratch result sets only within their own run
  ([foundation](foundation)).
- 2026-09-22: every ported stage minimises differences from `dev` and
  makes anything that could be left unused optional and off by default
  (every stage page). The catalog stage's detection member is per-differencer
  and recorded with the instance; `vbest` stays the query surface
  ([foundation](foundation)).
- 2026-09-22: all promotions take one transaction-scoped advisory lock
  ([foundation](foundation)).
- 2026-09-23: `dev`'s once-per-date CLUSTER and ANALYZE move to their
  own `maintain` stage ([maintain](maintain), [load](load)).
- 2026-09-23: only one producer's frozen inputs bind at a time
  ([foundation](foundation)); rebuild deletion and cleanup never touch anything
  `dev` wrote ([foundation](foundation)).
- 2026-09-23: no per-child UNIQUE on `(pid, id, isdiffpos)`; SFFT loads
  against its own `pid`; a psf instance's `version` equals the allocated
  legacy number and `psfs`' key stays global ([load](load)).
- 2026-09-23: ZOGY's astrometric-sigma setting stays 0.0 as in `dev`;
  SFFT's interpreter settings default to empty ([difference](difference)).
- 2026-09-24: SFFT's `pipelines` row is `ppid` 16, priority 6
  ([difference](difference), [finalize](finalize)).
- 2026-09-26: gain matching reads the reference's own `MAGZP` header by
  default, with `[awaicgen] zprefimg` as an override; SFFT registers as
  its own `difference-image` instance by default; promotion chooses which
  differencer's instance is current downstream
  ([difference](difference), [reference](reference)).
- 2026-09-26: each source's field is its own tessellation tile, a stated
  departure from `dev` ([load](load)).
- 2026-09-26: the proof spec stays unrepaired ([operations](operations)).

## Carried from the build, pending team review

These rulings come from build sessions and their reviews. Each remains
in force as its page states it until the team confirms, changes or
removes it here.

### Checks

- **Trial policy.** `rebuild-trial@1`'s `approval: trial` is a trial
  approval, not the team's sign-off; promotion refuses a policy with
  `approval: none`, and automatic promotion needs a team approval and
  `auto_promote: true` ([foundation](foundation)). (2026-09-24, 2026-09-25)
- Every check records a row; one that raises records `failed`. (2026-09-24)
- `catalog-counts-vs-reference@1` finds its reference by slot;
  `rebuild-trial@1` marks `difference-image-statistics` required and
  `catalog-counts-vs-reference` advisory. (2026-09-24, 2026-09-26)
- `run_policy_checks` fills every candidate's slot before any check
  runs. (2026-09-26)
- Known, unfixed defect: the gate can miss a check-result row committed
  after its read. (2026-09-27)
- Checks run outside the pipeline image, on a workstation or the
  launcher host, reaching the database through the instance role.
  (2026-09-24)

### Runs and promotion

- `promotion_changes` carries a nullable `slot`. A replacement's kind
  and slot must match the requested selector. `StalePlan` refuses if
  the selection or the run's candidates have moved since the plan.
  (2026-09-26)
- An after-instance with no before is accepted only if the slot has no
  current occupant. In an `association-set` slot with a non-null
  expected-before, the before must be an ancestor of the after. (2026-09-24)
- Promotion's dependency walk covers every ancestor recursively;
  rollback skips the check-policy gate, the walk and the
  association-set chain-direction rule. (2026-09-24, 2026-09-26,
  2026-09-27)
- Released-image validation and check-policy validation are separate.
  (2026-09-24, 2026-09-26)
- A same-request ancestor passes the dependency walk and is validated
  separately against the same eligibility rule and check policy as any
  other after-instance. (2026-09-27)
- Rollback reverses by slot only; a recorded change with no slot is
  refused as not reversible. (2026-09-27)
- A policy refusal (`PromotionRefused`, `StalePlan`,
  `CheckPolicyRefused`) exits 1; an argument-shaped refusal or an
  unknown run, instance or promotion id exits 64. (2026-09-27)
- The check-policy gate keeps its `FOR SHARE` lock on the `checks`
  rows it reads. The pipeline role can update `checks` rows, so the
  table is not append-only. (2026-09-27)
- The `approval` value `lead` is renamed `team`. (2026-09-27)
- Seeding a replacement run from a failed one is `--seed --only-failed`;
  seeded instances re-kinded to production become candidates.
  (2026-09-24)
- Run deletion locks the run, verifies the owner, and refuses while a
  frozen input binding depends on it or a reference row would be
  orphaned; the science-row cleanup set is fixed on [foundation](foundation).
  (2026-09-24)
- Every submission binds its input set before allocating the attempt.
  A name that resolves to nothing is logged, not refused. An unreadable
  manifest refuses with exit 65 before anything is written. (2026-09-25)
- A retry after a failed commit writes a fresh result set; only the
  calling attempt's own prior try or a succeeded attempt's set is reused
  ([crossmatch](crossmatch), [statistics](statistics), [prune](prune)).
  (2026-09-25)
- A scratch run reads the `_SCRATCH`-suffixed job definition and never
  falls back to the unsuffixed one. (2026-09-24)
- **Launcher retries.** The rebuild's job definitions carry one Batch
  attempt. After exit 75, a reclaimed host or a container that never
  started, the launcher resubmits the unit as a fresh attempt. The run's
  maximum attempts per unit includes reclaims and defaults to 1. Retries
  stay within that limit; a run must set it to allow them.
  Carried from the build, pending team review.
  (Claude for Ben, 2026-09-28)
- **Promoting a retried date.** A `--retry-failed` run cannot be
  promoted alone: its after-instances depend on the seed run's
  candidates and on the field's reference. Today a person promotes the
  reference run, the seed run and the retry run in that order, and
  rolls them back in reverse. The team decides whether `run
  promote-plan` of a seeded run includes its seed chain's candidates in
  one request. Carried from the build, pending team review.
  (Claude for Ben, 2026-09-28)
- **Imported references are unreleased.** A reference imported
  launcher-side by `tools/register-reference.py` ran no released image,
  so its promotion records a `--allow-unreleased` exception. The team
  decides whether reference import runs through a released image.
  Carried from the build, pending team review.
  (Claude for Ben, 2026-09-28)
- **Checks before promotion.** Neither the loop's failed run nor a
  hand-run `--retry-failed` run carried check results, so promotion
  refused under `rebuild-trial@1`; a person ran `check run` on both
  before promoting. The team decides whether the loop and the retry
  path run the policy's checks themselves. Carried from the build,
  pending team review. (Claude for Ben, 2026-09-28)
- Runs written under the first-run prefix stay where they were written.
  (2026-09-24)

### Loop

- The SSM runbook's `executionTimeout` is 21600 s. (2026-09-24)
- The loop's chain carries two `register` steps, after `admit` and
  after `finalize`, since `finalize` never registers the raw difference
  instance; promoting two candidates for the same kind and key is
  refused. (2026-09-26)
- A field's base catalog is the newest earlier complete date's
  association set; each date records `base_promoted` and
  `bases_skipped`. (2026-09-24, 2026-09-25, 2026-09-26)
- A schedule's first date has no base, so a stream over an
  already-current sky continues the existing schedule until a chain
  switch exists. (2026-09-27)
- A finished run takes no new units. (2026-09-25)
- Discovery refuses identical re-delivery, quarantines a checksum
  conflict and defers a corrected version ([loop](loop)). (2026-09-26)
- Under a check policy without automatic promotion, the loop leaves a
  date's run a candidate rather than refusing it. The next date's base
  still binds to it, so a person promotes in date order, earlier dates
  first. (2026-09-27)
- **No retry in the window.** The scheduled window cannot retry a
  failed date because `op-processing-date-loop.sh` passes no
  `--retry-failed`; a person runs the retry by hand. Carried from the
  build, pending team review. (Claude for Ben, 2026-09-28)

### Stage contract and tool

- **Package layer order.** A unit test enforces the subpackage layer
  order on [stage-contract](stage-contract) across every module and
  top-level import, including lazy and relative imports. (2026-09-27)
- **`tests/cli` scope.** When patched code moves, a `tests/cli` edit may
  change only the module path of a monkeypatch target or an import.
  Assertions, scenarios and fixtures stay unchanged. (2026-09-27)
- **CLI surface on `launch`.** `rapidpipe.cli` takes from
  `rapidpipe.launch` only its public functions and the exceptions they
  raise; a unit test enforces it. (2026-09-27)
- **Sky-partition geometry.** The pure HEALPix and tessellation
  derivations `db` needs live in `rapidpipe.products`, not
  `rapidpipe.science`; `products` is no longer standard-library only,
  since it imports numpy, healpy and the tessellation code.
  ([stage-contract](stage-contract)) (2026-09-27)
- **Running checks against a run.** That code lives in `rapidpipe.runs`,
  not `rapidpipe.checks`, since `checks` sits below `runs` in the layer
  order. ([stage-contract](stage-contract), [foundation](foundation)) (2026-09-27)
- **`run --help` grouping.** `rapidpipe run --help` groups its
  subcommands under five titled sections, lifecycle, recovery,
  promotion, housekeeping and inspection ([tool](tool)); no subcommand
  name changes. (2026-09-27)
- `maintain` is a fifth stage and `detector-date` a fifth unit kind.
  (2026-09-24)
- `alerts` and `export` read named, completed result sets; `export`
  writes files only; no stage changes another run's results or the
  current selection. (2026-09-24)
- A stage's `validate_inputs` runs after generic validation and before
  the `--dry-run` return. (2026-09-24)
- A stage never exits 1 or 2; the tool's exit 70 covers every
  unclassified error and a parse failure exits 64; exit 65's family is
  listed on [tool](tool). (2026-09-25, 2026-09-26)
- `photometry` and `export` are declared stages that exit 69 past
  validation where not yet ported. (2026-09-24, superseded below)
- **Photometry stub removed.** The rebuild carries no photometry stage;
  forced photometry stays `dev`'s `forcedPhotometryForField.py`. Exit
  code 69 stays reserved in the stage contract, since no stage in this
  build returns it now. Carried from the build, pending team review. (2026-09-27)
- `run cancel` from a workstation needs `batch:TerminateJob` on the
  workstation role, not yet granted. (2026-09-24)
- **Custody database access.** A stage's database access is `none`,
  `custody`, `read` or `read-write`; `custody` connects only for the
  read guard. `admit`, `reference`, `difference` and `finalize` declare
  it, since the guard needs the database whenever their input names a
  registered instance, and `none` skips the guard ([stage
  contract](stage-contract), "Declaration"). Carried from the build, pending team review. (Claude for Ben, 2026-09-28)
- A stage declaration carries no argument schema or resource defaults:
  nothing read them, and the Batch job definition owns resources
  ([stage contract](stage-contract)). `run create` takes no `--lane`,
  `--profile` or `--db-target`. The run's lane, resource profile and
  database target columns keep their defaults (`local`, `local`, the
  connection's database) but control no behaviour. (2026-09-27)

### Releases

- [foundation](foundation) defines the release command, tag form
  (`rebuild-v0.<n>`, annotated, remote authoritative), and `releases`
  and `release_deployments` tables. Account-specific steps are hooks.
  Migrations are applied with recorded checksums before a cut records.
  A run submits only to its release's job-definition revision;
  promotion requires released-image provenance. Each consumer has one
  pin row per cut. Selftests are evidence, not a gate. (2026-09-24)
- Migrations are additive while an earlier release's runs are open;
  `cut` refuses while any release row is incomplete unless resumed.
  (2026-09-25)

### Stages

- `alerts` first registers `alert-container` and `alert-set`. The outbox
  locator is an Avro block offset and length plus the record's ordinal.
  An input naming the wrong base or two pruned sets for one association
  set exits 65. (2026-09-24, 2026-09-25)
- Finalize's chain order is `difference -> finalize -> register ->
  load`, one `register` pass. (2026-09-24)
- `reference` is a transform stage with no database access. It
  normalises filter spellings, bounds frame counts and runs steps in
  `dev`'s order; fake-source injection is not ported. [Reference](reference)
  defines the catalog key, full SHA-256 selection digest, global
  `refimages.version` counter under an advisory lock, `refimages.attempt`
  recording the producing attempt, nullable `npucatsources`, and replay
  checked against the stored block. (2026-09-24)
- `statistics` reads crossmatch's completion manifest; an association
  set is its own rows plus its base's, recursively; its source sets
  already decide "best". (2026-09-24)
- `prune` excludes a pair unless its difference image is best
  (`vbest > 0`, maintained by promotion) or was made by this run, and
  depends on promotion maintaining `vbest`, not yet built. (2026-09-24)
- `export`'s catalog key hashes the full sorted set of source-set ids; a
  catalog labelled by one field may hold rows of another. (2026-09-24)
- The per-stage log's final line reaches its S3 copy. (2026-09-26)

### Products

(decision-slot-identity)=
- **Association-set identity.** The slot-identity table on
  [foundation](foundation) is the sole statement. An association set's
  identity adds the field, crossmatch settings hash, sorted source-set
  identities, and a hash of its base's own identity; the proposal's shorter
  wording, which omitted the base, is withdrawn with the table copy it
  sat in. (2026-09-27)

(decision-pending-sharing-rule)=
- **Sharing rule widening.** The specification lets any run read
  *current* result sets and keeps scratch within its run; the eligibility
  table on [foundation](foundation) also lets another run's stage read a
  *selected candidate*, whatever its check outcome. The team must decide
  whether selected candidates are readable across runs, then align the
  specification or the table. (2026-09-26)
- The database derives every instance's provenance key, identity key
  and slot, with identity and slot derived for every kind. A cycle-guard
  failure leaves the whole batch unresolved. (2026-09-26)
- The reading and promotion-eligibility table applies identically to
  file products and result sets. (2026-09-26)
- The `refimages` field lists and the `catalog-export` registration
  fields are fixed with their stages. (2026-09-24)

## Weekly maintenance on SMDC

Ben's rulings of 2026-10-06 on weekly maintenance on SMDC. The
weekly-maintenance page of the infrastructure repository states the
design these rulings produced. Where a later ruling reverses an earlier
one, the earlier entry says "superseded below" and points at the later
one.

(decision-maintenance-purpose)=
**Purpose and shape**: weekly maintenance exists to comply with the SMDC
security policy with minimal production impact. It has two parts:
preparation (packages, images, proof) and then implementation. (Ben,
2026-10-06)

(decision-maintenance-scope)=
**Vendor and community packages**: agent command-line tools, editors,
browsers, the database admin console and third-party repositories are
part of the process, not excluded from it. (Ben, 2026-10-06)

(decision-security-advisories)=
**Security advisories**: security advisories are accepted outright, with
no cooldown on security content. (Ben, 2026-10-06)

(decision-maintenance-window)=
**One window for every host**: one fixed-UTC weekly window, falling on
Thursday morning Pacific time and reserved for four hours, covers every host, so
the team keeps one simple model. (Ben, 2026-10-06)

(decision-ami-bake)=
**Golden AMI**: the image is baked only when the base image changes, with
no age limit. Red Hat refreshes the line every four to six weeks
(measured gaps of 28, 40 and 42 days). (Ben, 2026-10-06)

(decision-no-idle-checks)=
**No idle checks**: nothing waits for a host or the pipeline to be idle.
The window is reserved time, and launchers avoid it. (Ben, 2026-10-06)

(decision-parallel-tracks)=
**Two tracks**: workstations and the production chain run in parallel,
given the canary proof. (Ben, 2026-10-06)

(decision-preparation-day)=
**Preparation the day before**: preparation runs the day before the
window, at the same hour. (Ben, 2026-10-06)

(decision-no-auto-retry)=
**No automatic retry after a stop**: a person resolves a stop. The rule
is to be re-evaluated with experience. (Ben, 2026-10-06)

(decision-roll-or-patch)=
**Roll or patch**: a host is rolled or patched in a given week, never
both. (Ben, 2026-10-06; superseded below by
{ref}`the roll decided by image identity <decision-maintenance-redesign>`)

(decision-workstation-failure)=
**Workstation failure**: a workstation failure is a finding, not a stop.
(Ben, 2026-10-06)

(decision-retention)=
**Retention**: retention is a lifecycle property of each store: the AMI
keep count at bake, the registry lifecycle policy, and the admin cache
quota and alarm. There is no cleanup step. (Ben, 2026-10-06)

(decision-identical-package-set)=
**Identical package set**: every EC2 host carries the identical package
set, and its role is the services enabled. The database tools, the
connection pooler and the admin console move into the AMI. Production
hosts therefore carry desktop packages with their services off, a
trade the team accepts. (Ben, 2026-10-06)

(decision-package-set-not-frozen)=
**Package set not frozen**: hosts install what the repositories hold at
install time and record it. (Ben, 2026-10-06; superseded below by
{ref}`the freeze reopened <decision-freeze-reopened>`)

(decision-single-cooldown)=
**One cooldown**: a single 14-day cooldown applies, for OS and database
base images only (the host AMI, the UBI container base, the Batch image
and the Postgres image base). Everything else, pins and agent
command-line tools included, is accepted once CI passes. (Ben,
2026-10-06)

(decision-database-image-chain)=
**Database image chain**: the database container digest stays in the
database tools package's unit file, and the chain stays as it runs
today: the image is built on main and attested, the promoter pushes and
repins, and the next run publishes the package. A branch-build shortcut
was adopted and then withdrawn, because the attestation verifier binds
the image to a build on main. (Ben, 2026-10-06; superseded below by
{ref}`one builder and publisher <decision-one-builder>`)

(decision-application-image)=
**Pipeline application image**: the image refreshes only at a release
cut. The report lists deployed digests with their base age. (Ben,
2026-10-06)

(decision-quiet-period)=
**Promoter pause**: the promoter is unscheduled on preparation day and
window day, and the identity of the served set is the SHA-256 of the
served `repomd.xml`, not the promoter's marker. (Ben, 2026-10-06;
superseded below by
{ref}`the Wednesday transaction <decision-maintenance-redesign>`)

(decision-batch-failure)=
**Batch compute-environment failure**: a Batch compute-environment
failure is a stop, not a finding, because production failure is a stop.
(Ben, 2026-10-06)

(decision-preparation-own-day)=
**Preparation keeps its own day**: preparation stays a step of its own
instead of moving inside the window. (Ben, 2026-10-06)

(decision-reservation-flat)=
**Flat reservation**: the reservation stays four hours every week. A
variable reservation was considered and rejected, since database
maintenance is expected to dominate. (Ben, 2026-10-06)

(decision-thursday-window)=
**Thursday window**: the window is on Thursday with preparation on
Wednesday, so that the recovery window is a business day. No recorded
reason for Friday existed, and the argument for a late-breaking patch
applies equally to either day. (Ben, 2026-10-06)

(decision-workflow-pins)=
**Workflow-file pins**: Actions SHAs and the AlmaLinux and UBI container
bases are bumped by giving the bump a token with workflow-edit
permission, rather than by moving the digests out of workflow files. The
team accepts that an unattended job may rewrite CI, gated by the
validate run. (Ben, 2026-10-06)

(decision-one-pin-table)=
**One pin table, one bump**: everything external is a row of one pin
table: workflow-file pins, vendor release assets, the RHEL AMI family,
the ECS image family and the Python environment's conda-lock inputs. One
weekly bump with the App token resolves them under the single cooldown
rule, in one pull request that auto-merges on green, with an explicit
dispatch of every downstream build. The Python environment's resolve is
a phase of the bump (conda-lock plus the offline-replay gate) and is no
longer attended. (Ben, 2026-10-06; the weekly bump's day is superseded
below by
{ref}`the Wednesday transaction <decision-maintenance-redesign>`; the
Python environment's place in the bump is superseded above by
{ref}`the monthly re-lock <decision-python-relock>`)

(decision-one-builder)=
**One builder and publisher**: the promoter builds every artefact derived
from main in one run (RPMs, Python environment, base container and
database image) and publishes them together under the served index hash.
The bump pull request writes the database unit file's digest from the
attested build it dispatched, so the post-publish repin commit and the
second promotion go. The attestation verifier accepts the attestation of
the exact commit that became main by fast-forward (this clause is
superseded below by the two-commit database image sequence in
{ref}`the Wednesday transaction <decision-maintenance-redesign>`). This
reverses the earlier ruling that kept the two-hop chain. (Ben,
2026-10-06)

(decision-no-weekly-application-image)=
**No weekly application image**: a weekly promoter rebuild and window
deploy of the pipeline application image is declined. The image stays
release-bound, the one named exception, with the base-age line in the
report. (Ben, 2026-10-06)

(decision-deploy-from-main)=
**Infrastructure deploys from main**: a promoter phase validates,
previews and deploys every stack whose template or data changed in the
published commit, under the maintenance role, with a drift check as
proof. Host-replacing changes are refused and left to the window. The
maintenance stack deploys last and never mid-run. (Ben, 2026-10-06; the
clauses on which stacks deploy and on host replacement are superseded
below by {ref}`the Wednesday transaction <decision-maintenance-redesign>`,
which prepares production stack changes on Wednesday and applies them
inside Thursday's lock, deploys build-substrate stacks at once, and
refuses host-replacing, removing and durable-replacing changes)

(decision-health-signal)=
**One health signal**: every pin-table row carries three ages (newest
upstream, newest published, oldest deployed), recorded daily. Its state
is current, cooling or stalled. A row is stalled when the published
version lags upstream by the cooldown plus a week, or the deployed
version lags the published one by a week, and a stalled row is an
escalation with an owner. Per-chain alarms stay as diagnostics. (Ben,
2026-10-06; the owner clause is superseded below by
{ref}`team-owned escalation <decision-team-owned-escalation>`)

(decision-release-cut)=
**Release cut**: the release cut runs unattended in CodeBuild on a tag
push: migrate, build, deploy, pins, then the Batch selftests recorded
against the release. A cut with no selftest result within a day is a
stalled-release escalation. A person decides what to tag, and nothing
runs on the admin host. (Ben, 2026-10-06)

(decision-no-scheduled-rotation)=
**No scheduled secret rotation**: scheduled database secret rotation is
declined. The rotation row stays parked and attended, because it is
hygiene, not compliance. (Ben, 2026-10-06)

(decision-team-owned-escalation)=
**Team-owned escalation**: a named escalation owner is declined.
Everything is team-owned, and every alarm and escalation routes to the
team's alert list. (Ben, 2026-10-06)

(decision-maintenance-redesign)=
**Wednesday transaction and the redesign adopted on merit**: Ben opened
his earlier rulings for challenge ("don't be overconstrained by my
rulings, I want to do this right"), and the design was adopted on merit
after an independent review. One Wednesday transaction replaces the
Sunday bump, the five-day promoter and the promoter pause: the bump runs
early Wednesday, the promoter builds from the merged state, and
preparation follows later that day. A human merge waits for Wednesday
(superseded below by
{ref}`flexibility for team development <decision-extensibility>`, which
runs the transaction on every merge and keeps Wednesday as the scheduled
discovery), and a release cut builds from the last publication. Production stack
changes are prepared on Wednesday and applied inside Thursday's lock,
build-substrate stacks deploy at once, and host-replacing, removing and
durable-replacing changes are refused. Vendor and community packages
count for compliance per host and are not exempt by origin; a failed
install is a finding with an exposure and a deadline, and the production
track continues. A roll is decided per host by image identity, not by
week. The database image is bound by a two-commit sequence (the pin
commit is attested and the unit-file commit is its child). Currency is
reported with identities and an unknown state, admission control at
window entry replaces idle checks, the retention table is extended, and
an acceptance list is met before arming. (Ben, by lifting the
constraint; Claude, on merit; 2026-10-06)

(decision-freeze-reopened)=
**Freeze reopened, identical membership firm**: production installs the
canary's recorded version set, with explicit versions and a baseline
snapshot for errata, and the canary re-runs its install at Thursday
admission if any repository moved. Identical package membership across
hosts stays firm. The design is stated on the weekly-maintenance page,
not as a ruling. (Ben; design by Claude, 2026-10-06)

(decision-extensibility)=
**Flexibility for team development**: the transaction runs on every merge
to main as well as on Wednesday, and the window applies the last bundle
with valid proofs. Workstations converge on demand outside the window.
New packages and dependencies enter by pull request and are published
the same day. Per-user environments are outside the managed set. The
design page carries this as an Extensibility section. (Ben, requirement;
design by Claude, 2026-10-06)

(decision-timetable)=
**Timetable**: the on-merge transaction is serialised and coalesced;
scheduled discovery runs once a week early on Wednesday; preparation
runs on Wednesday and waits for the bump's publication up to a latest
start; the Thursday window is reserved for four hours and reopens
admissions on completion; four daily rows run by completion before the
window hour, with the mirror hourly; a release cut runs any day on a tag
under the maintenance exclusion; the report runs Thursday as a
standalone job. The Saturday sweep hour is the first commissioning fact
to confirm with SMDC. (Ben, 2026-10-06)

(decision-no-smdc-query-now)=
**Commissioning facts stay open**: asking SMDC now for the sweep hour,
the deadline clock origin and the scan lag is declined. They stay
commissioning facts. (Ben, 2026-10-06)

(decision-published-differencer)=
**The published differencer is a setting, `[difference] diff_flavor`, shipped as `zogy`** (supersedes {ref}`the SFFT entry above <decision-sfft-published>`): dev's `diff_flavor = sfft` (b725007d, 2026-04-20) was taken as the default on 2026-10-24 19:22 UTC (rapid PR 408) and measured the same afternoon on the same bytes (run 88 against run 81, HLWAS injected passes 4 to 6; run 89 against run 80, OpenUniverse): under the raw SFFT catalog false positives per epoch 228 → 385, injected detection at AB 25 0.99 → 0.00, core fraction +0.003 → +0.252, OpenUniverse detected 35 → 24 of 410. SFFT leaves about a quarter of each bright star's flux in its core on HLWAS, so the 500-source cap fills with star residuals; dev measured SFFT on GBTDS socsims only and never publishes the raw catalog (sumrat, nneg, nbad and the prefilter pass 37 to 41 per cent). The default returns to `zogy` with the measurement in the toml comment; SFFT keeps running in every difference job, its PSF-fit catalogs stay under the prefix as diagnostics, and the queue items dev-columns, dev-prefilter and sfft-core are the route back to `sfft` if they earn it. (Ben, 2026-10-24 21:19 UTC: "proceed as you judge best" on the recommendation to revert until the remedy proves SFFT)

(decision-gate-coverage-registration)=
**The quality gate also holds on lost sky and misregistration**: new, not dev's (dev has no gate). A packet set is held when its difference's `usable_fraction` is below 0.9 or its registration offset `hypot(registration_dx_px, registration_dy_px)` is above 0.25 px, the bounds read on every published difference job SMDC holds (runs 46 to 95): usable fraction healthy from 0.9385 (run 72 SCA 16) to 1.0, constant per SCA, with run 72 SCA 9 (reference from another SCA's frames) at 0.704; offset healthy at most 0.123 px (run 49 F129, 25 stars), the tail growing as stars fall, so the bound is twice that, set for a WCS offset like HLWAS's 1 px. Replayed through `decide` over 4,623 recorded sets: run 72's three SCA 9 sets held, no healthy set held. Lost sky and a misregistration are checked first, since they inflate the count and the residuals checked after them. (gate-metrics, rapid PR 426, 2026-10-24)

(decision-dev-prefilter)=
**`dev`'s database prefilter is the behaviour under `diff_flavor = "sfft"`, and the default stays `zogy`**: `source_set` keeps an SFFT candidate only when its `sumrat` is finite and above `[difference.database_prefilter] sumrat_prefilter_threshold` (0.4, `dev`'s `[DATABASE_PREFILTER]`, c931b001) and its nearest pixel is at least 2 px from the edge, then caps at 500; ZOGY's catalog is not prefiltered; `""` turns all of it off. Two divergences from `dev`'s PSF loader, with no knob: the 2 px edge is `dev`'s XSources cut (57559572), which its PSF path lacks; and a null `sumrat` is rejected, where `dev` passes it (on SFFT's catalog almost every null is a stamp off the image, which the edge removes anyway). Measured on the same bytes at 14860f57 (HLWAS injected `001_0001` SCA 8, passes 4 to 6, against run 81's reference; the null epoch against run 95's): detected of 600 ZOGY 542, raw SFFT 256, prefiltered SFFT 275; AB 24 to 25, 93, 59 and 78 of 96; false positives per epoch, mean (highest), 214 (233), 385 (390) and 388 (390), bright-flagged 0.62, 0.75 and 0.86; null packets 182, 471 and 478. The cut keeps 0.67 to 0.71 of SFFT's candidates, and the bright-star residuals it keeps refill the cap. The rule (prefiltered SFFT at least as good as ZOGY on every count) went to `zogy`. The gate's core and ring are image metrics that the cut does not touch. Arm A's healthy differences sit inside the shipped bounds (core −0.0011 to +0.0032, ring −0.0000 to +0.0017), so the bounds stay. SFFT's core of +0.251 to +0.271 is its failure, never calibrated. (dev-prefilter task 1, rapid PRs 431 and 432, 2026-10-24)

(decision-hlwas-sfft-block)=
**The HLWAS overlay carries dev's OpenUniverse SFFT block** (`crossconv_flag`, `sfft_use_segmentation` and `sfft_use_gainmatch_catalogs` true, bsmask 50 within 100 px), read only under `diff_flavor = "sfft"`, so no published row changes. The decision: a dataset's value on its overlay, chosen by the rule that a configuration must sit inside the gate's healthy core (±0.011) and ring (±0.015) ranges, fit on no input dev's ini names as broken, and recover at least the socsims block's injected sources. On one epoch pair on the same bytes (HLWAS injected `001_0001` SCA 8 F146 expid 4040101 against run 81's reference, runs 108 to 110), three configurations were measured:

- The shipped socsims block reproduces run 88's core +0.251 and ring +0.021.
- The catalog path alone is the same fit to the digit, since its 20000 threshold selects no source.
- The OpenUniverse block gives core −0.000 and ring −0.009, beside ZOGY's −0.001 and +0.002. Its S/N > 20 candidates are 184 positive and 12 negative, against the socsims block's 771 and 300. It matches 179 of the epoch's 200 injected sources against 130 (ZOGY 183). It fits 1.6% of the pixels, its reference catalog selects 62 sources, and its decorrelation sigmas come from pixels 96% segmentation background.

The cause is located, not the kernel: the stage zeroes the science image's DQ-masked NaNs before SFFT. On this frame that is 5,096 px in coverage, 0.03% of the frame but 31% of Σ(reference²), the brightest stars' cores. Under the socsims block they enter the unmasked kernel fit and pull its photometric ratio down. SFFT's own `run_sfft_rapid` on the same inputs with only those pixels masked gives core −0.014 and ring −0.013. Excluding them from SFFT's fit is recorded, not built. (sfft-core task 1, rapid PR 435, 2026-10-24)

(decision-rimtimsim-epsf)=
**RimTimSim's science PSF is reduced from CRDS's ePSF for its detector and filter**: new, not dev's. `dev`'s RimTimSim runs read the WebbPSF library file per SCA and filter (`WFI_SCA02_F213_PSF_DET_DIST.fits`, registered by `db_register_sciimg_psfs.py`) from its own bucket; the rebuild's psf stage reduces CRDS ePSF references, and the lite files name none, so the dataset's overlay names the references CRDS's `roman_0077` answers for WFI02 (`roman_wfi_epsf_0280` F213, `0266` F087) in `[psf.epsf]`. Measured: the F087 stars are 1.08 times the stamp's sigma and the subtraction's core fraction is −0.005 to +0.024; the F213 stars are 1.04 times it and the core −0.050 to −0.075 (runs 100 and 99, five epochs each). (rimtimsim-reader, rapid PR 429, 2026-10-24)

