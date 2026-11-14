# Decisions

**Status: DRAFT**

Any team member can add a ruling directly, with one dated line and the
author's name. CI on `main` is the only gate. Once recorded here, a
ruling belongs to the team. Design pages state the rule and cite this
page where attribution matters.

(decision-open-questions)=
## Open questions

Questions no ruling has closed yet, one line each with why it is open.
A ruling that closes one goes under Rulings and its line leaves.

- **The reference's tie order** under `selection_type = "nframes"`
  (coverage selection's is ruled, {ref}`ruling <decision-reference-coverage>`):
  whether a reference's frames tied on
  `mjdobs` order by `dev`'s key, distance from the tile centre then the
  file name, in place of the run's `rid`. `dev`'s key was chosen because
  `dev`'s launcher orders by it (`order by b.mjdobs, dist`) and it decides
  the `max_frames` cut by coverage. Two intakes of field 4686831 then give
  byte-equal references. It moves outputs against run 219, so rapid PR 584
  holds it until Ben rules on the move (the exercise page's Reference frame
  order).
- **GBTDS's gate bounds**: whether GBTDS gets core and ring bounds of its
  own. Replayed at `min_epochs`, the gate holds every run 139 epoch on
  the core (−0.036 to −0.048 against the HLWAS-derived ±0.025), so the
  HLWAS bounds would hold every GBTDS set (rapid PRs 465, 470).
- **A false-positive tolerance**: whether an acceptance that compares
  false-positive counts allows for the count's own epoch-to-epoch spread.
  The OpenUniverse zero-point candidate failed only on false positives,
  493 against 492 inside the capped 500 (rapid PR 451), and the SFFT
  default only on false positives per epoch, 102.7 against 101.7
  (rapid PRs 485, 486; Ben accepted that row, its reference differing,
  {ref}`the SFFT default <decision-sfft-default>`).
- **SMDC's resources the rebuild may not need**: whether the alerts bucket,
  MSK, the bulk lane, unused parameter leaves and authority records are
  kept or removed. Open until the rebuild's publication and bulk
  processing are decided (rapid_systems `docs/rebuild-smdc-retirement.md`,
  `docs/questions.md`).

## Rulings

(decision-base-1e5a0b6d-rb)=
**From `rapid-rebuild:132` the image builds on base `1e5a0b6d` (photutils 3.1.1), and the `rb` scores that base moves are accepted without a bisect**: the pin on base `576304f3` is lifted, and a later change's like-for-like reference is a run on the same base, run 237 the first, never a run across the base change. On run 187's SCA 3 sample, run 237 (`:132`) against run 235 (`:131`, base `576304f3`) has the same 2,537,235 xsources at the same rows and positions, and `rb` differs by more than 1e-6 on 2,488,689 of them, max 0.95. Sources with S/N > 20 rise 3.8 %; scored candidates move +0.005 %, and packets and the sets the gate holds are equal. The xsources' finder does not read `min_separation`, so the cause is the re-locked base, not {ref}`the 3x3 box <decision-finder-3x3-box>`; which package moves the scores is unverified. (Ben, 2026-11-12 21:37 UTC; finder-3x3-accept, rapid PR 605)

(decision-finder-3x3-box)=
**The PSF-fit finder's local maximum is the 3x3 box, `[difference.psfcat_diffimage] min_separation` 1.5 on photutils 3.1, and its residual against 3.0.0 is accepted** (rapid PR 605): `dev`'s 1.0 drew the 3x3 box on photutils 3.0.0, whose region was larger than the circle for radii under 2. 3.1.0 fixed that (CHANGES.rst, #2493), so on 3.1.1 1.0 is the 4-neighbour plus, and the re-locked base scored about 2.4 times the candidates a difference (runs 231 and 229). `DAOStarFinder` takes no footprint argument, so the value is 1.5 (`xx**2 + yy**2 <= 2.25`, the full box). Photutils stays unpinned. Measured on job 109322 (expid 5013401 SCA 3) against 3.0.0: finder rows 11,930 / 16,547 (positive / negative) against 11,930 / 16,506. +51 negative and +6 positive rows lie within 4 px of a masked pixel (3.1.0's #2377: masked pixels no longer suppress nearby peaks); −10 negative and −6 positive rows have centroids off the image (3.1.1's cut). Scored 11,923 / 16,536 against 11,924 / 16,485; negative sources 2,592 against 2,717. Source counts near masked pixels therefore move slightly against `dev`. The commented `[reference.psfcat]` twin moves to 1.5 with it. (Ben, 2026-11-12 19:38 UTC)

(decision-drill-checks)=
**The weekly restore drill reads every page on the pgBackRest leg only**: the snapshot leg restores the newest DLM set on the canary and requires recovery to complete, no invalid-page line, the newest bookkeeping row within the 24 hours before the set, a clean stop and `pg_wal` still the link into the WAL volume; it no longer runs `pg_checksums --check`. A volume made from a snapshot fetches each block from S3 at its first read, and the whole-cluster read ran at 6.9 MB/s over 422 GiB on 2026-11-11, which is most of a day; the scheduled drill was killed at its 60-minute cap with the volumes still attached. So the snapshot leg shows that a set attaches, recovers and is fresh, in 150 s, and does not show that every page of it reads. The pgBackRest leg, which writes the volumes itself, keeps the full read and stays the drill's proof of a whole checksum-clean copy. The restore runs with eight workers in place of the configuration's two (102 MB/s against 223 MB/s), and the runbook's restore recipe carries the same flag. Measured 2026-11-11 on volumes matching rapid-db's, 320 GB of backup: restore 24 min, replay of 3,180 archived WAL segments 22 min, checksum read 35 min, the drill 86 min. Named and dropped: a provisioned volume initialization rate to keep the snapshot leg's read, and more throughput on the drill's volumes, which would stop the drill's restore time being rapid-db's. (Ben, 2026-11-11 17:21 UTC, delegating the drill's redesign to the session; rapid_systems PR 526)

(decision-catalog-ab-zeropoints)=
**Catalog magnitudes are on AB zero points, set at run time**, departing from `dev`'s `MAG_ZEROPOINT` of 0 in every SExtractor section, whose catalog magnitudes are instrumental: the science-image catalog and every difference-image catalog, positive and negative, of ZOGY, SFFT and the naive subtraction take the reformatted science image's `ZPTMAG` (the zero point for DN/s; the difference images are on the science image's flux scale), and the reference mosaic's catalog takes `zprefimg`, the `MAGZP` the coadd was scaled to. The gain-match runs stay at 0, because gain matching adds the reference zero point to their magnitudes itself. The settings tables keep `dev`'s 0; the job's copy is changed, never the run's stored body. No stored row carries these magnitudes (`sources` and `xsources` have no magnitude column), so the catalog files change and, through the reference catalog, the alert packet's `refMatch.magAuto`, which is AB on the reference's `MAGZP` where it was instrumental; the wire format is the same, and the packet registry's text and the 00.07 `refMatch` schema say AB (rapid 4dfd8bba). Ported from commissioning 810a26e9. ([reference](reference), [difference](difference); Azalee, 2026-11-10)

(decision-sfft-kernel-masking)=
**SFFT's kernel-fit masking is ported from commissioning and is on for flight** (amends {ref}`the HLWAS SFFT block <decision-hlwas-sfft-block>`'s "recorded, not built"; not in `dev`): commissioning ed2f1a73's `--zeromargin`, which leaves out of the kernel fit the pixels that are 0 in either image (the stage's fill for DQ-masked NaNs) and those within the margin of one, and `--bsmaskisoarea` / `--bsmaskisofactor`, which also mask catalog sources of large isophotal area with a radius scaled by it, are in `sfft_rapid_crowded.py`, and the stage passes each only when its `[difference.sfft]` key (`sfft_zero_margin`, `sfft_bsmask_isoarea`, `sfft_bsmask_isofactor`) is non-empty. The base ships them empty, so every dataset's command is unchanged; the flight overlay sets commissioning's 2, 2000 and 2.0. Commissioning chose them on its first run (program 1062, F062, WFI06, job 95), where the fit was dominated by one saturated star and by 500 to 1,250 zero-filled pixels inside source footprints carrying 22% to 29% of its (sci − ref)²: kernel sum 1.050 before, 0.997 after. They are not measured on 1049, and were tuned with SATURATED masked, as the flight overlay's mask masks it ({ref}`the flight DQ mask <decision-dq-mask-base>`). The simulations keep the lever off, unmeasured. (Azalee, 2026-11-10, port/comm-sfft-kernel-masking)

(decision-sfft-mask-offset)=
**SFFT's bright and saturated source masks are centred on the catalog position, for every dataset** (a fix to `dev`'s script, from commissioning ed2f1a73, with no setting): the discs were drawn at `X - x - 1`, 2 px off in x and y; a 1-based catalog maps to the 0-based grid as `X - x + 1`. The fix changes the SFFT masks of every dataset whose block masks from the gain-match catalogs, {ref}`the base block <decision-sfft-block-base>` included, so an SFFT difference differs from an earlier run's by it. The bright-pixel growth moves to a distance transform, the same disc (pixel-identical on commissioning's job 95) without the hours `binary_dilation` takes at a 100 px radius. (Azalee, 2026-11-05, port/comm-sfft-kernel-masking)

(decision-flight-crossconv-off)=
**The flight-1049 overlay sets `[difference.sfft] crossconv_flag` false** (a divergence from {ref}`the base block <decision-sfft-block-base>` for flight data only): the commissioning pipeline's `[SFFT]` value (its commit a7778505's settings), which is `dev`'s socsims setting (025e42b3, Russ Laher, 2026-05-29) carried onto commissioning, not a flight measurement. SFFT runs without `--crossconv --refpsf`, so its difference PSF is the science PSF and the published differencer does not use the reference PSF; the block's other keys stay the base's, `sfft_use_segmentation` included, since the base sets it explicitly. The base stays true, so no simulation changes; GBTDS and RimTimSim carry false on their own overlays already. Not measured on the rebuild. (Azalee, 2026-11-10)

(decision-nominal-zptmag)=
**Flight reference inputs are scaled by the on-orbit nominal zero point of their filter, not their own `ZPTMAG`**: `[reference.awaicgen] use_nominal_zptmag`, commissioning's flag (8a4a172d), is true in `flight-1049.toml` and false in the base, so the simulations are unchanged. Under it each frame's scale factor uses its filter's value in the run's `[intake.nominal_zptmag]`, the one table intake also falls back to, and the flight overlay carries commissioning 687c93b2's on-orbit values (the median over 18 SCAs of the files' own zero points). The frame's header `ZPTMAG` still feeds `zptmag_rms`, and the reference records `ZPSOURCE` `nominal`. Commissioning ships the flag false, and IMSS's req26 runs it true; flight data takes it on because its per-frame calibration still moves with the CRDS context, and a run can turn it off with `--set` ([reference](reference)). (Azalee, 2026-11-05)

(decision-reference-coverage)=
**A run may choose a reference's frames by their coverage of it, `[reference.selection] selection_type = "coverage"`, commissioning's rule**; the base stays `"nframes"`, `dev`'s ({ref}`ruling <decision-reference-by-field>`), and flight-1049 sets `"coverage"` with `max_frames` 50. The loop's pool is every selected row whose `overlapfields` meet any tile under the reference's 9100 px footprint (commissioning's `overlapfields &&` the tiles, d586136b, where `dev` and `"nframes"` take `@>` the field), walked in `mjdobs` order, then distance from the reference's centre, then the L2 key (expid, sca, fid); a frame whose footprint misses the reference is skipped without spending the cap (debbc6e4), and selection stops once `max_coverage_fraction` (1.0) of the reference's pixels are `max_coverage_depth` (4) deep or at `max_frames` (ebd95254). The order settles the open tie question for coverage selection: rows tie on `mjdobs` in practice only within one exposure, whose 18 SCAs share it, and distance then keeps the SCAs covering the middle of the reference when the cap cuts an exposure, where the field rule takes the lowest-numbered SCA whatever sky it covers. This is rapid PR 584's order with a different backstop: the L2 key, the loop's existing tie-break, decides two rows of equal `mjdobs` and exactly equal distance, which essentially never occur, in place of the file name. Why: the field rule filled the cap with frames that barely or never touched the reference; on commissioning's jid6318 its 50 frames left 2.7% of pixels four deep, and coverage selection's 42 left 58.4%. (Azalee, 2026-11-10; port/comm-refimage-coverage-selection, commissioning d586136b, ebd95254, debbc6e4, 2ebffce3)

(decision-coverage-held)=
**Too little coverage holds a field; it is not a failure**: an estimate below `min_coverage_fraction` less `coverage_estimate_tolerance` (0.05) is held by the loop before any job, reported under `held` as `estimated coverage X < Z` on every pass, with or without a reference bound, as too few frames are held under a bound; a coadd whose coverage map measures below `min_coverage_fraction` declines ({ref}`ruling <decision-job-declined>`), and its field goes back to held, planned again only when its selected frames change. Neither makes `rapidpipe loop` exit 1, and no exit code is added: commissioning ends both as exit 33 (d586136b, 702d0cad), which the rebuild does not carry. (Azalee, 2026-11-10; port/comm-refimage-coverage-selection)

(decision-job-declined)=
**A job may end `declined`, a new `jobs.state`**: its stage ended normally and has nothing to publish, so it declares no table and gives its reason in the manifest's `declined`. The publisher loads no rows and opens no binding; it stores the manifest and the reason (`refusal`) on the job, with no `published_attempt`. A declined job is not failed: `job run` stops on it as on a published one, `job wait` ends on it, the loop's pending, failed and taken lists leave it out, and `validate_run.py`'s counts do not fail on it. The reference stage is the first to decline, under coverage selection; the files stay under the job's prefix. rapid's `database/2026-11-10-reference-coverage.sql` widens the state check. (Azalee, 2026-11-10; port/comm-refimage-coverage-selection)

(decision-gbtds-sfft-socsims)=
**The GBTDS overlay carries `dev`'s socsims `[difference.sfft]` block, not the base's OpenUniverse block** (a divergence from {ref}`the base block <decision-sfft-block-base>` for this dataset; `dev` ships the socsims block for socsim data, so this is `dev`'s value): `crossconv_flag` false, bsmask 20000 within 30 px, no gain-match catalogs, no segmentation, in `rapidpipe/settings/datasets/gbtds-r00340.toml`, as `gbtds-r00340-fakesrc.toml` carries it. Under the base block every SFFT difference of `r00340-gb3` raised `Singular matrix` in the kernel solve, exit 70 (run 157, `rapid-rebuild:95`), so GBTDS published nothing; ZOGY is no fallback since `diff_flavor` is retired ({ref}`ruling <decision-sfft-only-registered>`). Sampled on `rapid-rebuild:103` (rapid PR 535's merge, run 164, epoch 2014201, F146 SCA 2): the difference job completes, CLEAN, core +0.0529 and ring −0.0177 against ZOGY run 139's −0.0485 and −0.0386, the core outside the HLWAS-derived ±0.025 (no GBTDS bound is named), the difference 5,324 s against 889. Why the base block's solve is singular on this field is a finding for Russ Laher, not read here. (Ben, 2026-11-07, sfft-singular; sfft-block-base task 1, rapid PR 535)

(decision-rimtimsim-sfft-socsims)=
**The RimTimSim overlay carries `dev`'s socsims `[difference.sfft]` block, not the base's OpenUniverse block** (a divergence from {ref}`the base block <decision-sfft-block-base>` for this dataset, `dev`'s socsims value): the same five keys in `rapidpipe/settings/datasets/rimtimsim-260622.toml`; cross-convolution was off for a RimTimSim file already by `dev`'s rule. Under the base block F213 epoch 4571's SFFT difference raised `Singular matrix`, exit 70, on both attempts (run 156, `rapid-rebuild:95`). Sampled on `rapid-rebuild:103` (run 163, F213 epoch 4571): the difference job completes, CLEAN, core +0.0510 and ring +0.0907 against ZOGY run 124's −0.0694 and −0.0339, both outside the gate's bounds and the ring nearly three times farther from zero, with 32,132 positive candidates above S/N 20 of 123,630 (uncapped since rapid PR 529) and the difference 8,317 s against 2,643: the block makes the solve succeed, not the subtraction good. Why the base block's solve is singular on this field is a finding for Russ Laher, not read here. (Ben, 2026-11-07, sfft-singular; sfft-block-base task 1, rapid PR 535)

(decision-retire-runs-1-68)=
**Runs 1 to 68's packet and forced rows that name no object are retired**, not kept in a legacy child and not left behind by a fresh database: those runs predate the object catalog, so their 745,777 `packets` rows name no `objects` row and 4,524,605 of their `forced` rows carry an aid `objects` does not hold, and the field-children split cannot file either by field. rapid's `database/2026-11-04-a-retire-runs-1-68.sql` deletes them, first of the 2026-11-04 files; their `sources` rows stay, so the scorecards keep their inputs, and so do `objects_chain`, `memberships_chain`, their jobs and their bindings. Their 1,326 `forced` rows whose aid `objects` does hold stay and are filed by it. (Ben, 2026-11-07 04:18 UTC; retire-1-68, rapid PR 533)

(decision-operator-steps-uniform)=
**Operator steps are uniform across the team**: the two steps that make a merged rapid commit runnable on SMDC, applying a dated schema file to the `rapid` database and building and registering the image for the commit, run from every team workstation under its own instance role with no profile set, and the person who merges a PR applies any dated file it carries, then builds and registers the image. There is no named operator and no per-person grant: one managed policy, `rapid-workstation-operator`, attaches to the workstation roster (`WorkstationSubmitterRoleNames`), so a teammate added to the roster gets both steps. What every workstation can now do: push images to `rapid-pipeline`; stage a template and run the `rapid-batch` change set under that stack's CloudFormation role, the route the `deploy` hook takes to repin `rapid-rebuild` (never `rapid-rebuild-production`); send `AWS-RunShellScript` to rapid-db by its tags, which runs the dated file as `postgres`. Accepted with it: SendCommand on rapid-db is root on the database host, which every team member already reaches through Project-Power-User; and the `rapid-batch` change set runs under a role that can change more of that stack than the job-definition row, which only the hook's one-row guard limits. This closes the earlier idea of fencing Power-User humans from the database superuser secret. The recipes are rapid_systems `docs/reference/operator-runbook.md` sections 13 and 14. (Ben, 2026-11-06 19:23 UTC and #pipeline 11:54 PST; rebuild-operator task 3, rapid_systems PR 486)

(decision-dlm-prepost)=
**rapid-db's daily DLM set is application-consistent, through AWS's pre and post script**: before the set starts, DLM runs the `rapid-db-dlm-prepost` SSM document on rapid-db: `CHECKPOINT` in the `rapid-postgres` container, `sync`, a 60 s auto-thaw armed, then `fsfreeze` of `/var/lib/pgsql` and `/var/lib/pgsql-wal`; after it starts, the document thaws both. A failed pre-script falls back to a crash-consistent set rather than skipping the day (`ExecuteOperationOnScriptFailure`), with no retry; an auto-thaw that beats the post-script reports exit 203, never success. A dead-man alarm, `rapid-db-snapshot-set-age`, pages when the newest complete set (data-1, data-2 and wal, one start time, all completed) is older than 26 h or its age stops arriving. `pg_backup_start` was named and dropped: DLM cannot hold a session across its own snapshot start, and fsfreeze is the route AWS documents. Measured on rapid-db by hand, 2026-10-28: the freeze held 2.0 s (07:12:14.569 to 07:12:16.584 UTC), the CHECKPOINT 59 ms; on a scratch filesystem the auto-thaw released an unanswered freeze at 60.06 s and a pre that failed on its second mount thawed the first. The gap it closes: the policy sat in ERROR from 06:06 to 14:04 UTC on 2026-10-27 unobserved, and every set had been crash-consistent. (Ben, 2026-10-27 18:47 UTC, the design `rapid-db-verification.md`; dlm-prepost task 1, rapid_systems PR 449)

(decision-sfft-published)=
**SFFT is the published differencer**: the difference job publishes the
SFFT image and SFFT's positive PSF-fit catalog as `diffimages` and
`sources`, and the packet's cutouts and forced photometry read the SFFT
image, its PSF and uncertainty. This is `dev`'s choice since b725007d
(2026-04-20; `diff_flavor = sfft`). ZOGY still runs; its catalogs are
diagnostics. With SFFT off, or on a nonzero SFFT exit, the job fails
rather than falling back to ZOGY. The switch precedes the measurement:
rapid PR 408 switches, and the paired measurement against the ZOGY runs
80 and 81 adds its numbers here.
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
iteration (the pipeline repository's runbook, part 11). The [foundation](foundation) and
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
`dev`, with no knob. (Recorded under the standing rule for a divergence
with no knob, Ben, 2026-10-24 14:02 UTC; rapid PR 393)

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
(Recorded under the standing rule for a divergence with no knob, Ben,
2026-10-24 19:22 UTC; rapid PR 407)

(decision-pixel-columns-background)=
**`dev`'s pixel columns fall back to the image itself when their background fails**:
`sumrat`, `nneg` and `nbad` are measured on every SFFT PSF-fit source
after a 64 px local background is subtracted, as `dev` measures them
(c32e28f6), and are carried on `sources`. When the background fails, the
columns are measured on the unsubtracted image with a warning, as `dev`'s
`_compute_pixel_catalog_cols` does. `dev`'s ini gives the reason the
background matters: on its socsims SFFT images, at a pedestal of -2 to
-6 DN/s, sumrat > 0.4 keeps 0.60 of injected sources at S/N 5 to 10 on
the image itself and 0.95 after the background. Measured on HLWAS
injected `001_0001` SCA 8, three epochs (rapid PR 422, run 96): sumrat >
0.4 keeps 0.997 of the 391 injected candidates, 0.68 of the 6,464 noise
candidates and 0.90 of the 2,257 bright-flagged ones; the columns cost
4.3 to 5.2 s a difference. Until rapid PR 500 a failed background failed
the job. On run 158, the socsims 10/21 window under `dev`'s socsims SFFT
block, that failed 6 of 1,998 differences, all SCA 18: photutils 3.0
drops every mesh box that keeps under 90 % of its pixels after the
3-sigma clip, and a heavy-tailed SFFT difference keeps 88.5 %. Russ's
run of the same images exited 0 on all 1,998. (rapid PRs 422, 500)

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

Ben's rulings of 2026-10-08 and 2026-11-07 on the pipeline's Python
environment, the rapid-python RPM. The infrastructure repository's
rapid-python README states the design they produced.

(decision-python-stasis-shape)=
**STASIS's shape**: the environment takes the shape of STScI's STASIS
deliveries: conda-forge supplies the interpreter only (python and pip),
and everything else is one hash-pinned pip lock compiled by uv. The
PyPI-to-conda override map, the guard against a package in both layers,
the conda-lock proof and the hand caps go. The envhouse becomes a
wheelhouse, and the offline replay's import gate stays the bar. The
RPM, its path and the promotion chain are unchanged. (Ben, 2026-11-07
08:41 UTC; infrastructure PR 494)

(decision-python-stasis-pins)=
**STASIS's pins**: the tracked delivery is the newest STASIS Roman
delivery that is not a release candidate (`ROMANDP-1.1.0+26Q4_B23` at
the re-platform); a release candidate is tracked only when Ben names
it. The delivery's exact pins bind the Roman stack, a committed list of
28 names (romancal, roman-datamodels, rad, stcal, stpipe, romanisim,
crds, pysiaf, gwcs, the asdf family, the stsci packages, tweakwcs,
drizzle, spherical-geometry, numpy, astropy, photutils, scipy, pandas,
pyarrow, matplotlib, galsim); uv solves everything else at its newest,
and the interpreter's patch release and pip float. Taking every pin the
delivery carries would have held 38 housekeeping libraries, among them
certifi, cryptography and urllib3, at the delivery's August versions.
(Ben, 2026-11-07 08:46 and 19:06 UTC)

(decision-python-overrides)=
**Override list**: an override is one floor line in the requirements
file with its reason, who and when, earned by a named fix or by a
package that cannot solve against a delivery pin. A floor on a stack
name replaces the delivery's pin. The re-lock retires a floor once the
delivery's pin meets it, returning the line to the bare name, and
reports it; a floor off the stack list replaces no pin and never
retires. At the re-platform: `sip_tpv>=2`, the release without
`pkg_resources`, so setuptools is no longer capped (Ben, 2026-11-07
08:39 UTC), and `astrocut>=1.4`, without which uv backtracks astrocut
to a release with no S3 support. (Ben, 2026-11-07 08:46 UTC)

(decision-python-one-env)=
**One environment**: the single-environment design holds, at the same
breadth, notebook tooling included. The Kafka client stays:
kafka-python, aws-glue-schema-registry and
aws-msk-iam-sasl-signer-python. onnxruntime is in the environment;
TensorFlow and Keras are not. (Ben, 2026-10-08; onnxruntime 2026-11-07
08:50 UTC)

(decision-python-version)=
**Python version**: Python 3.13 first, from the delivery's 3.13 set.
The minor then follows one rule: the newest minor in bugfix phase that
the tracked delivery ships and for which every compiled package has a
wheel, taken at a re-lock as a one-line change. That is 3.14 at the
first re-lock after the re-platform. (Ben, 2026-10-08 for 3.13;
2026-11-07 09:00 and 21:12 UTC)

(decision-python-astroquery)=
**astroquery**: a direct entry in the requirements file, not only a
transitive dependency. (Ben, 2026-10-08)

(decision-python-nexus-packages)=
**Roman Research Nexus packages**: the environment carries what the team
expects from the Nexus: sncosmo, healsparse, skyproj, ipympl and
astrocut. (Ben, 2026-10-08)

(decision-python-build-on-change)=
**Build on change**: the promoter builds the rapid-python RPM only when
its inputs are new. A NEVRA that is already published, with unchanged
tracked inputs, is taken from the published object instead of being
rebuilt. A changed lock under an unchanged NEVRA still meets the
immutable-NEVRA refusal. Version is the resolve date. (Ben, 2026-10-08)

(decision-python-spec-committed)=
**Committed spec**: the rapid-python spec is a committed file, not
generated. (Ben, 2026-10-08)

(decision-python-import-list)=
**One import list**: a single list of the environment's import names,
read by every consumer: the offline-replay gate, the RPM smoke test and
the fixtures. (Ben, 2026-10-08)

(decision-python-relock)=
**Re-lock cadence**: the environment is re-locked weekly, Wednesday at
04:00 UTC, the Wednesday chain's slot after the pins bump, and on any
push to main that changes its inputs. The re-lock pull request merges
itself once validation is green on it and the envhouse build has
imported every module on the import list offline. This reopened the
earlier rule that a re-lock is never merged automatically: the import
proof is the gate that rule lacked. (Ben, 2026-10-08 for the automatic
merge; weekly 2026-11-07 19:07 UTC, replacing monthly)

(decision-python-envhouse-retirement)=
**Envhouse retirement deferred**: the envhouse, now a wheelhouse, stays
until build on change has run for a few releases. (Ben, 2026-10-08)

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
**Step ledgers**: stay ephemeral. The 632 citations of working steps
and review rounds in code and pages are replaced by the design-page section they
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

## Pending team review

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
  (2026-09-28)
- **Promoting a retried date.** A `--retry-failed` run cannot be
  promoted alone: its after-instances depend on the seed run's
  candidates and on the field's reference. Today a person promotes the
  reference run, the seed run and the retry run in that order, and
  rolls them back in reverse. The team decides whether `run
  promote-plan` of a seeded run includes its seed chain's candidates in
  one request. (2026-09-28)
- **Imported references are unreleased.** A reference imported
  launcher-side by `tools/register-reference.py` ran no released image,
  so its promotion records a `--allow-unreleased` exception. The team
  decides whether reference import runs through a released image.
  (2026-09-28)
- **Checks before promotion.** Neither the loop's failed run nor a
  hand-run `--retry-failed` run carried check results, so promotion
  refused under `rebuild-trial@1`; a person ran `check run` on both
  before promoting. The team decides whether the loop and the retry
  path run the policy's checks themselves. (2026-09-28)
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
  `--retry-failed`; a person runs the retry by hand. (2026-09-28)

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
  build returns it now. (2026-09-27)
- `run cancel` from a workstation needs `batch:TerminateJob` on the
  workstation role, not yet granted. (2026-09-24)
- **Custody database access.** A stage's database access is `none`,
  `custody`, `read` or `read-write`; `custody` connects only for the
  read guard. `admit`, `reference`, `difference` and `finalize` declare
  it, since the guard needs the database whenever their input names a
  registered instance, and `none` skips the guard ([stage
  contract](stage-contract), "Declaration"). (2026-09-28)
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
- `difference` runs SFFT's subtraction pass without its two kernel-phase
  stacks, a divergence from `dev`'s `modules/sfft/sfft_rapid_crowded.py`
  where `dev` has no knob. sfft 1.7.3 fills `Kab_Wla` and `Kab_Wmb`,
  19 full-frame complex128 planes each, 9,697 MiB on a 4089 x 4089 frame.
  Each plane depends on the row or the column alone, so
  `modules/sfft/sfft_lowmem.py` computes one column and one row and hands
  the library's own compiled kernel zero-stride views. On run 212's
  job 66156 the anon peak goes 15,014 → 6,238 MiB with every output equal
  at full precision; across run 187's SCA 3 sample, runs 217 and 218
  (rapid PR 576, merged `03f79e9c`; the exercise post's "Memory diet"). (2026-11-10)

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
{ref}`the weekly re-lock <decision-python-relock>`)

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
constraint; adopted on merit after an independent review, 2026-10-06)

(decision-freeze-reopened)=
**Freeze reopened, identical membership firm**: production installs the
canary's recorded version set, with explicit versions and a baseline
snapshot for errata, and the canary re-runs its install at Thursday
admission if any repository moved. Identical package membership across
hosts stays firm. The design is stated on the weekly-maintenance page,
not as a ruling. (Ben, 2026-10-06)

(decision-extensibility)=
**Flexibility for team development**: the transaction runs on every merge
to main as well as on Wednesday, and the window applies the last bundle
with valid proofs. Workstations converge on demand outside the window.
New packages and dependencies enter by pull request and are published
the same day. Per-user environments are outside the managed set. The
design page carries this as an Extensibility section. (Ben, requirement,
2026-10-06)

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
**The published differencer is a setting, `[difference] diff_flavor`, shipped as `zogy`** (supersedes {ref}`the SFFT entry above <decision-sfft-published>`): dev's `diff_flavor = sfft` (b725007d, 2026-04-20) was taken as the default on 2026-10-24 19:22 UTC (rapid PR 408) and measured the same afternoon on the same bytes (run 88 against run 81, HLWAS injected passes 4 to 6; run 89 against run 80, OpenUniverse): under the raw SFFT catalog false positives per epoch 228 → 385, injected detection at AB 25 0.99 → 0.00, core fraction +0.003 → +0.252, OpenUniverse detected 35 → 24 of 410. SFFT leaves about a quarter of each bright star's flux in its core on HLWAS, so the 500-source cap fills with star residuals; dev measured SFFT on GBTDS socsims only and never publishes the raw catalog (sumrat, nneg, nbad and the prefilter pass 37 to 41 per cent). The default returns to `zogy` with the measurement in the toml comment; SFFT keeps running in every difference job, its PSF-fit catalogs stay under the prefix as diagnostics, and the queue items dev-columns, dev-prefilter and sfft-core are the route back to `sfft` if they earn it. (Ben, 2026-10-24 21:19 UTC: "proceed as you judge best" on the recommendation to revert until the remedy proves SFFT; superseded below by {ref}`the SFFT default <decision-sfft-default>`)

(decision-gate-coverage-registration)=
**The quality gate also holds on lost sky and misregistration**: new, not dev's (dev has no gate). A packet set is held when its difference's `usable_fraction` is below 0.9 or its registration offset `hypot(registration_dx_px, registration_dy_px)` is above 0.25 px, the bounds read on every published difference job SMDC holds (runs 46 to 95): usable fraction healthy from 0.9385 (run 72 SCA 16) to 1.0, constant per SCA, with run 72 SCA 9 (reference from another SCA's frames) at 0.704; offset healthy at most 0.123 px (run 49 F129, 25 stars), the tail growing as stars fall, so the bound is twice that, set for a WCS offset like HLWAS's 1 px. Replayed through `decide` over 4,623 recorded sets: run 72's three SCA 9 sets held, no healthy set held. Lost sky and a misregistration are checked first, since they inflate the count and the residuals checked after them. (gate-metrics, rapid PR 426, 2026-10-24)

(decision-dev-prefilter)=
**`dev`'s database prefilter is the behaviour under `diff_flavor = "sfft"`, and the default stays `zogy`**: `source_set` keeps an SFFT candidate only when its `sumrat` is finite and above `[difference.database_prefilter] sumrat_prefilter_threshold` (0.4, `dev`'s `[DATABASE_PREFILTER]`, c931b001) and its nearest pixel is at least 2 px from the edge, then caps at 500; ZOGY's catalog is not prefiltered; `""` turns all of it off. Two divergences from `dev`'s PSF loader, with no knob: the 2 px edge is `dev`'s XSources cut (57559572), which its PSF path lacks; and a null `sumrat` is rejected, where `dev` passes it (on SFFT's catalog almost every null is a stamp off the image, which the edge removes anyway). Measured on the same bytes at 14860f57 (HLWAS injected `001_0001` SCA 8, passes 4 to 6, against run 81's reference; the null epoch against run 95's): detected of 600 ZOGY 542, raw SFFT 256, prefiltered SFFT 275; AB 24 to 25, 93, 59 and 78 of 96; false positives per epoch, mean (highest), 214 (233), 385 (390) and 388 (390), bright-flagged 0.62, 0.75 and 0.86; null packets 182, 471 and 478. The cut keeps 0.67 to 0.71 of SFFT's candidates, and the bright-star residuals it keeps refill the cap. The rule (prefiltered SFFT at least as good as ZOGY on every count) went to `zogy`. The gate's core and ring are image metrics that the cut does not touch. Arm A's healthy differences sit inside the shipped bounds (core −0.0011 to +0.0032, ring −0.0000 to +0.0017), so the bounds stay. SFFT's core of +0.251 to +0.271 is its failure, never calibrated. (dev-prefilter task 1, rapid PRs 431 and 432, 2026-10-24)

(decision-hlwas-sfft-block)=
**The HLWAS overlay carries dev's OpenUniverse SFFT block** (`crossconv_flag`, `sfft_use_segmentation` and `sfft_use_gainmatch_catalogs` true, bsmask 50 within 100 px), read only under `diff_flavor = "sfft"`, so no published row changes. The decision: a dataset's value on its overlay, chosen by the rule that a configuration must sit inside the gate's healthy core (±0.011) and ring (±0.015) ranges, fit on no input dev's ini names as broken, and recover at least the socsims block's injected sources. On one epoch pair on the same bytes (HLWAS injected `001_0001` SCA 8 F146 expid 4040101 against run 81's reference, runs 108 to 110), three configurations were measured:

- The shipped socsims block reproduces run 88's core +0.251 and ring +0.021.
- The catalog path alone is the same fit to the digit, since its 20000 threshold selects no source.
- The OpenUniverse block gives core −0.000 and ring −0.009, beside ZOGY's −0.001 and +0.002. Its S/N > 20 candidates are 184 positive and 12 negative, against the socsims block's 771 and 300. It matches 179 of the epoch's 200 injected sources against 130 (ZOGY 183). It fits 1.6% of the pixels, its reference catalog selects 62 sources, and its decorrelation sigmas come from pixels 96% segmentation background.

The cause is located, not the kernel: the stage zeroes the science image's DQ-masked NaNs before SFFT. On this frame that is 5,096 px in coverage, 0.03% of the frame but 31% of Σ(reference²), the brightest stars' cores. Under the socsims block they enter the unmasked kernel fit and pull its photometric ratio down. SFFT's own `run_sfft_rapid` on the same inputs with only those pixels masked gives core −0.014 and ring −0.013. Excluding them from SFFT's fit is recorded, not built. (sfft-core task 1, rapid PR 435, 2026-10-24; superseded below by {ref}`the base block <decision-sfft-block-base>`; the exclusion built and on for flight by {ref}`the kernel-fit masking <decision-sfft-kernel-masking>`)

(decision-rimtimsim-epsf)=
**RimTimSim's science PSF is reduced from CRDS's ePSF for its detector and filter**: new, not dev's. `dev`'s RimTimSim runs read the WebbPSF library file per SCA and filter (`WFI_SCA02_F213_PSF_DET_DIST.fits`, registered by `db_register_sciimg_psfs.py`) from its own bucket; the rebuild's psf stage reduces CRDS ePSF references, and the lite files name none, so the dataset's overlay names the references CRDS's `roman_0077` answers for WFI02 (`roman_wfi_epsf_0280` F213, `0266` F087) in `[psf.epsf]`. Measured: the F087 stars are 1.08 times the stamp's sigma and the subtraction's core fraction is −0.005 to +0.024; the F213 stars are 1.04 times it and the core −0.050 to −0.075 (runs 100 and 99, five epochs each). (rimtimsim-reader, rapid PR 429, 2026-10-24)

(decision-hlwas-sfft-rearm)=
**The HLWAS overlay does not set `diff_flavor = "sfft"`: under its SFFT block, SFFT with dev's prefilter misses one condition of dev-prefilter's rule against ZOGY, detecting 530 of 600 injected sources against ZOGY's 542.** dev-prefilter's arm C was re-run once on the same bytes at `rapid-rebuild:77` (`a761ae23`), now under the overlay's OpenUniverse block (HLWAS injected `001_0001` SCA 8 F146 passes 4 to 6 against run 81's references, runs 114 and 113 null against run 95's). Arm A's rows (runs 103, 104 at `:76`, the same ZOGY code) were read again, not re-run. The rule, verbatim as set before the measurement: SFFT ships only if it detects at least as many of the 600 in total and at AB 24 to 25, and has no more false positives per epoch and null packets per epoch than A, on both the mean and the highest epoch. The re-run added that every difference sit inside the gate's core ±0.025 and ring ±0.015.

- **It fails on one condition only**: detected 530 against 542. It loses 13 at AB 26 and 26.5 (46 → 41, 20 → 12) and gains one at AB 25.5, net 12.
- **It meets or beats A on the others**:
  - AB 24 to 25: 93 of 96 against 93.
  - False positives per epoch, mean (highest): 102 (118) against 214 (233), bright-flagged 0.21 against 0.62.
  - Null packets: 86 against 182.
  - Core: −0.0002 to +0.0004. Ring: −0.0092 to −0.0069. All inside both bounds, and every set sends past `min_epochs`.
- **Against arm C under the socsims block** (runs 107 and 106): detected 530 against 275, false positives 102 against 388, null packets 86 against 478.
- **The cap no longer fills**: 449 to 486 candidates per injected difference, 271 on the null.

The global default stays `zogy`, and OpenUniverse and GBTDS are unmeasured under their own blocks. (sfft-rearm task 1, 2026-10-24; superseded below by {ref}`the SFFT default <decision-sfft-default>`)

(decision-psfcat-nan-fill)=
**The difference's PSF-fit catalog fills its non-finite pixels from their neighbours for the finder and passes them as `mask=`**: a divergence from dev (dev runs DAOStarFinder and `PSFPhotometry` on the masked difference with its NaNs in place, no knob). Under photutils 3.0.0, DAOStarFinder convolves and measures with the NaNs in place, mask or not, so a star within about 4 px of one masked pixel was never found; part 12 step 6 measured a quarter of SCA 7's area blinded. The fill is `interpolate_replace_nans` with a Gaussian of σ 1 px (a hole wider than the kernel is 0), not a zero fill, which split a star with a masked peak into four rows; the fit ignores the masked pixels. Same bytes (`r00342-inj1` `001_0001` F146 passes 4 to 6, ZOGY, against run 72's and run 81's references): SCA 7 detected below AB 25 0.728 → **0.959** (within 5 px of a mask 9 → 81 of 93, beyond 275 → 293 of 297), false positives per epoch 174 (highest 186) → 165 (167), runs 115 → 117; SCA 8, the control, 542 → 545 of 600, false positives 214 (233) → 214 (233), runs 103 → 116. A star whose own peak pixel is masked is still missed. (finder-mask task 1, rapid PR 439, 2026-10-25)

(decision-reference-by-field)=
**The loop builds a field's reference from the L2 rows whose `overlapfields` list the field, as dev does**: this replaces the earlier rule, which took only the rows whose own field is that field (`rapidpipe.foundation.loop.plan`, no knob). dev's launcher (`awsBatchSubmitJobs_launchSingleReferenceImagePipeline.py`, `get_overlapping_l2files`) takes every L2 file whose `overlapfields` lists the field.

- **The frames.** A reference is planned for a field and filter that a selected row has as its own field; with a bound, a row at or after it. Its frames are the selected official rows of the filter before the bound whose `overlapfields` list the field, of any SCA, in `mjdobs` order.
- **What is not ported.** dev's second sort key, distance from the tile centre, is not ported, so this is membership parity, not full parity. The reference stage coadds in `mjdobs` order, so the order matters only past `max_frames` (25).
- **Amended for coverage selection.** Under `selection_type = "coverage"` the pool widens to the rows whose `overlapfields` meet any tile under the reference's footprint (`&&`, not `@>`), and the distance key is ported, from the reference's centre, before the L2 key; this rule stays `"nframes"`, the base ({ref}`ruling <decision-reference-coverage>`, Azalee, 2026-11-10).
- **Why it changed.** On flight program 1049's four dithered F158 WFI02 epochs, 0.04 degrees apart, the frames' centres fall in three fields: epoch 1 in 3014319, epochs 2 and 3 in 3014320, epoch 4 in 3010224. Under the earlier rule the loop built no reference epoch 4 could be differenced against, and run 118's had to be submitted by hand.
- **Flight, measured.** Under this rule the loop alone (run 126) builds field 3010224's reference from epochs 1 to 3 and differences epoch 4 against it. Every measured number of epoch 4 matches run 118's hand-built reference: core +0.0013, ring −0.0050, usable fraction 0.781, 328 packets. No reference is built for the two fields nothing is differenced against.
- **HLWAS, measured.** On a fixed pointing the rule picks the same frames. The injected sample, `r00342-inj1` `001_0001` SCA 8 F146 passes 4 to 6 under ZOGY (run 127), builds its reference from passes 1 to 3, the frames run 81's reference holds. It detects 546 of 600 against run 116's 545, with false positives per epoch 213 mean and 233 highest against 214 and 233.

(flight-first task 1, 2026-10-25; ref-overlap task 1, rapid PR 450, 2026-10-25)

(decision-naive-no-psfcat)=
**The difference job makes no Photutils PSF-fit catalog for the naive subtraction**: a divergence from dev, which fits both naive catalogs, positive and negative, with no knob to turn them off. They are diagnostics nothing reads: they are not published, and no stage or script opens them. The naive image, its uncertainty and its SExtractor catalogs are still made, and `naive_diffimage_flag` is unchanged. A catalog not run sets no outcome bit, so `infobitssci` bits 4 and 5 are never set. Same bytes, measured on RimTimSim F213 field 4682737 SCA 2, epoch 4571, against run 99's reference and PSF rows (runs 122 on `:78` and 124 on `:79`, both CLEAN). The difference job takes 4,169 s before and **2,645 s** after; the naive catalogs had taken 1,247 s and 245 s. The 500 `sources` rows are equal in every non-identity column. The `diffimages` row is equal but for `checksum`, whose file differs only in its job-id and timestamp header cards; the pixels are equal. (diff-trim task 1, rapid PR 446, 2026-10-25)

(decision-older-contract-retired)=
**The older stage contract is retired; `run(job)` is the one contract**: `admit`, `finalize`, the shared runner `run_stage`, the per-stage settings files, the `rapidpipe stage` and `rapidpipe selftest` commands and `finalize`'s fixture are deleted from `rebuild`, and git keeps them. The loop never ran either stage. Retiring the code does not answer whether a post-processing stage (database ids in headers, the header stamp) returns: that stays the [migration](migration) page's question for the team. (mig-contracts task 1, rapid PR 464, 2026-10-25)

(decision-minvcpus-zero)=
**`MinvCpus` stays 0 on both compute environments**: `rapid-ce-prompt` and `rapid-ce-bulk` keep `MinvCpus: 0` (rapid_systems `cloudformation/rapid-batch.yaml`), so an idle lane holds no instance and every campaign pass that finds it idle waits for scale-up. Measured once, on the prompt lane from cold (desiredvCpus 0, no container instance in its ECS cluster at 06:47:51 UTC): a no-op job on `rapid-rebuild:89` waited **154 s** from `createdAt` to `startedAt`, against the regroup's estimate of up to 15 minutes. Why no floor: latency is later ({ref}`Latency is later <decision-latency-later>`); passes run unattended, so the wait delays no person and no pass has a deadline; and a floor is a dated change, its revert and a deploy each way, for a cost nobody has seen bite. Reopen when a campaign pass's scale-up wait misses a deadline someone has named. (minvcpus-line task 1, 2026-10-26)

(decision-throwaway-hand-deletes)=
**Throwaway runs' output prefixes in the scratch bucket are deleted by hand; no lifecycle rule expires them**: a throwaway run's scratch output stays until someone deletes its prefix. The accrual that raised the question: about 2.1 TB of throwaway runs' scratch prefixes deleted by hand on 2026-10-24 (runs 13 to 16, 18 to 45, 51, 52, 55 and 56). Why no rule: an automatic S3 expiry is a standing delete, which the unattended runs' envelope reserves to Ben, with an age nobody has named; and a `throwaway/` prefix to scope it would need an output-prefix change in the pipeline's settings and products, for one cost seen once. Reopen when hand deletes recur often enough that someone names an age. (Ben, 2026-10-26; throwaway-lifecycle task 1)

(decision-reliability-null)=
**The three reliability fields ship null**: alert schema 00.07's `reliability`, `reliabilityThreshold` and `reliabilityVersion` are null on every packet, a divergence from `dev`, which fills them from its RuBR-AT real/bogus classifier (883e3876: the score from `sources.rb`, the threshold and model name from its configuration). They stay null until the published differencer is ruled and a scorer is validated on its catalogs: scoring the published ZOGY catalogs with `dev`'s RuBR-AT model is unvalidated, and a threshold or model name beside no score would mislead. The rest of 00.07 ships as `dev` defines it, the Roman observation identifiers and `survey` filled from `exposures` and `surveys`. (Ben, 2026-10-26; port-schema-07 task 1; superseded below by {ref}`the score on SFFT's catalog <decision-reliability-scored>`)

(decision-sfft-default)=
**The published differencer is SFFT with `dev`'s prefilter, `[difference] diff_flavor` shipped as `sfft`** (supersedes {ref}`the differencer as a setting <decision-published-differencer>` and {ref}`the HLWAS rearm <decision-hlwas-sfft-rearm>`): the team follows `dev`, which since `dev` PR 478 (2026-10-26) registers SFFT's difference images only, ZOGY optional. ZOGY still runs in every difference job, its catalogs kept as diagnostics, and a run (`--set difference.diff_flavor="zogy"`) or a dataset's overlay selects it. The measured trade, HLWAS `001_0001` SCA 8 F146 under the HLWAS overlay's SFFT block, SFFT runs 145 and 146 on `rapid-rebuild:91` against ZOGY's 144 and 127:

- Injected passes 4 to 6: detected 533 against 546 of 600; at AB 26 and 26.5, 41 and 12 against 47 and 20 of 60.
- False positives per epoch, mean (highest): 102.7 (119) against 213.3 (233).
- Null epoch 4040101: 86 packets against 181; core +0.000463, ring −0.007423, inside the gate's bounds.

The SFFT rows are runs 145 and 146. Run 146's false positives, 102.7, are one per epoch above run 114's 101.7, the SFFT arm's earlier row; run 114 differenced against run 81's reference (rfid 90018), run 146 against the loop-built one (rfid 90109), the same stack as run 127's ZOGY row, so Ben accepted run 146 as the row. OpenUniverse, GBTDS, flight and RimTimSim follow the default unmeasured, under the gate. (Ben, 2026-10-26 21:00 UTC, the direction; 2026-10-26 23:27 UTC, "accept 146"; sfft-default task 1, rapid PRs 485, 486 and 490)

(decision-reliability-scored)=
**The difference job scores SFFT's catalog with `dev`'s RuBR-AT model, and nothing is cut on the score** (supersedes {ref}`reliability null <decision-reliability-null>`; the cut on the score since added by {ref}`the separate prefilter tables <decision-sources-prefilter>`): every candidate of SFFT's PSF-fit catalogs, both signs (the negative on the negated difference, {ref}`ruling <decision-negative-sources>`), and every xsource ({ref}`ruling <decision-xsources>`) carries `dev`'s `compute_rb` score and label (model `2026-10-06_canonical9_seed42`), loaded as `rb` and `rblabel` on `sources` and `xsources`; a scored trigger's packet carries `reliability`, `reliabilityThreshold` (0.5134, the model's `threshold.json`) and `reliabilityVersion`; an unscored source's three fields are null. ZOGY's catalogs are never scored: the model is SFFT-trained, and since {ref}`the SFFT-only ruling <decision-sfft-only-registered>` SFFT's catalogs are the only ones published. Two divergences from `dev`: `dev`'s loader drops a scored source with `rb` ≤ 0 (`[DATABASE_PREFILTER] rb_prefilter_threshold = 0.0`), the rebuild then cut nothing on the score, so scoring changed no selection (since {ref}`the separate prefilter tables <decision-sources-prefilter>` both `sources` and `xsources` are cut at `rb` ≤ 0, as `dev`'s); and a classifier failure fails the difference job, where `dev` skips the columns with a warning. **ONNX is the model contract** (Ben, 2026-11-07 08:50 UTC): a delivered model is a prefix holding the `.onnx` file, the feature scaler and the threshold under `SHA256SUMS`; training keeps TensorFlow and Keras and exports the checkpoint to ONNX as its last act (`modules/rubrat/training/export_onnx.py`, called by `train_rb.py`); the difference job loads the model once on `onnxruntime` in its own process and scores every catalog with it, and the pipeline image carries `onnxruntime` and no TensorFlow or Keras. The 2026-10-06 model's export sits under `rubrat-onnx/2026-10-06_canonical9_seed42/`, a sibling of its `rubrat/` prefix with the same version string, because the inputs bucket is write-once and the `rubrat/` prefix's `SHA256SUMS` could not take the file. On run 152's candidates its scores equal the TensorFlow sidecar's within 1.6e-6, every label equal (rapid-onnx task 3, rapid PR 542). This replaces the sidecar of 2026-10-27, a virtual environment holding TensorFlow and Keras that the classifier ran in as a subprocess. (Ben, 2026-10-27 01:42 UTC, the sidecar; rb-port task 1, rapid PR 493)

(decision-sfft-block-base)=
**The base settings' `[difference.sfft]` block is `dev`'s OpenUniverse block, not its socsims block** (supersedes {ref}`the HLWAS overlay's block <decision-hlwas-sfft-block>`): `crossconv_flag`, `sfft_use_segmentation` and `sfft_use_gainmatch_catalogs` true, bsmask 50 within 100 px, for every dataset without a block of its own; the HLWAS overlay no longer carries one. `dev` ships the socsims block for socsim data. The divergence is for a property of the stage, not of a dataset: the stage zeroes the science image's DQ-masked NaNs before SFFT, and under the socsims block those zeroed cores enter the unmasked kernel fit; on HLWAS `001_0001` SCA 8 F146 epoch 4040101 that is core +0.251 and ring +0.021 against the OpenUniverse block's −0.000 and −0.009 (sfft-core, runs 108 to 111). Since {ref}`the SFFT default <decision-sfft-default>` the four other overlays published SFFT under the socsims block, unmeasured. HLWAS's resolved settings are byte-identical before and after the move; `dev`'s rule that turns cross-convolution off for a RimTimSim file stands. Sampled one epoch each on `rapid-rebuild:95` (sfft-block-base, runs 153 to 157): HLWAS's null epoch 4040101 reads 86 packets, core +0.000463, ring −0.007423 (run 151: 86, +0.000445, −0.007365; references rfid 90119 against 90113); OpenUniverse epoch 28737 detects 4 of 56 as ZOGY's run 125 did, false positives 496 against 493, core −0.0057 against −0.0202, ring −0.0005 against +0.0136; flight 1049 e4 core +0.0097, ring −0.0122, 324 packets against run 126's +0.0013, −0.0050, 328, the gate holding both at `min_epochs` on usable 0.781. No overlay is pinned to ZOGY: the gate would send OpenUniverse's set under both differencers, and flight's, GBTDS's and RimTimSim's ZOGY rows (runs 126, 139, 124) are held themselves. **Open**: on GBTDS `r00340-gb3` (both epochs) and RimTimSim F213 epoch 4571 every difference job fails under this block, SFFT's kernel solve raising `Singular matrix` (exit 70, RimTimSim's second attempt the same; science frames with 144,464 and 82,866 SExtractor sources); before it they ran SFFT under the socsims block. Ruled 2026-11-07: both carry the socsims block on their own overlays ({ref}`GBTDS <decision-gbtds-sfft-socsims>`, {ref}`RimTimSim <decision-rimtimsim-sfft-socsims>`); the cause is not read. (sfft-block-base task 1, rapid PR 495)

(decision-gaia-mirror)=
**The Gaia product is one mirror per release, read as a cone per chip, not a box per dataset** (keeps {ref}`the catalogs key <decision-catalogs-dataset>`): the team's Gaia DR3 copy is `dev`'s (a41c4d7b): LINCC's HATS partitions of `gaiadr3.gaia_source`, each leaf cut to the matcher's columns and keyed by `_healpix_29`, with `hats.properties`, `partition_info.csv` and an ingest record `gaia.json` that carries the reference epoch, built once per release by `python -m rapidpipe.science.catalogs.store ingest-gaia` into the catalogs bucket (rapid_systems' `roman-rapid-catalogs`: no deletes, create-once sealed per release, one prefix per catalog and release; not the references bucket, whose noun means the coadded reference image here) under `gaia/<version>/`. A dataset's `catalogs` row names that prefix as its location, registered by one import job that copies nothing, so the key stays (dataset, name, version) and the loop's one-catalog rule stands. The packet job reads the chip's cone, the centre and half-diagonal widened by the largest proper motion over the epoch offset, as the row groups whose `_healpix_29` statistics overlap it, and records the catalog job, the release, `ref_epoch` and the leaves and row groups read; the intake's WCS offset metric reads the same cone. The match is unchanged. Why: the box per dataset was built by hand from the ESA archive, whose release 3.15 (2026-10-14) times an anonymous query out at one minute and returns what it had, so one query gave 34,171, 23,499, 19,082 and 29,856 rows on four runs, and nothing downstream could tell; a bulge box is millions of rows every packet job would read whole. A synthetic catalog (OpenUniverse's truth stars on Gaia's schema) is written in the same layout from its table by the same script. The mirror is the only layout the pipeline reads: the box files the live runs of 2026-10-25 recorded stay bound to those runs, and a job of one of them reruns under its own revision's image, as any job does. (Emily Everetts, 2026-10-29)

(decision-home-az)=
**The VPC has one home AZ, us-east-1b, and compute AZs for Batch**: the NAT gateway and the interface-endpoint ENIs sit in the fleet's AZ only (`HOME_AZ` in rapid_systems `cloudformation/gen-lib.sh`), every private route table points at that NAT, and the other AZs (1a, 1c, 1d and 1f: every one that offers the Batch instance types; 1e offers none and MSK may not use it) carry a private subnet, an EFS and a scratch mount target, and nothing else. Both Batch compute environments list all five private subnets; MSK keeps its three brokers in 1a, 1b and 1c, fixed at its creation. Supersedes the per-AZ NAT gateways and per-AZ endpoint ENIs of 2026-07 ("matching the sibling SMDC account"): rapid-db and every host are single-AZ in 1b (rapid_systems `docs/requirements.md` L-single-az-fleet), so redundancy elsewhere could not outlive the database and cost $183 a month. What it buys: Spot and On-Demand capacity pools in five AZs, against the observed failure, `InsufficientInstanceCapacity` on 2026-08-25, 2026-10-31 and 2026-11-02, the last refusing every pair tried in 1a, 1b and 1c; the first smoke job on the Spot lane after the change ran in us-east-1d. What it gives up: internet egress for the 1a and 1c hosts and for every Batch job depends on 1b's NAT (SSM, S3, EFS and MSK do not go through it), and a job outside 1b pays $0.01/GB each way to rapid-db and the brokers, as 1a and 1c jobs already did. Deployed 2026-11-03 01:03 to 01:15 UTC by change sets with no replacement (rapid_systems PR 463); the plan and its Codex pass are in the state vault, `plans/rapid-vpc-home-az.md`. (Ben, 2026-11-03 00:54 UTC)

(decision-production-retained-releases)=
**Production runs on retained releases only; the release is the commit**: `rapid-rebuild-production`, the one job definition whose role writes products, runs only a rapid commit the retained-releases marker lists. Its identity is `rebuild-<commit>`; its image is one build of that commit, tagged `rebuild-<commit>-<base8>` after the first eight hex of the base image's digest, so the same commit can be built again on each patched base under ECR's immutable tags. Four pieces carry it, all in rapid_systems. `verify-release-retention.sh --retain <release>` keeps a release: each image goes to the backups bucket's no-expiry `archive/` prefix as an OCI archive with its digest preserved, never to a registry, and the marker records each object and digest. The Wednesday `production-rebuild` operation builds production's commit on the newest base and pushes it, registering and repinning nothing. `release-hooks/promote <commit>` alone repins production: it refuses unless the marker lists the commit, promotes the newest build of it, and executes a change set of production's row only; `commit` and `deploy` repin scratch's `rapid-rebuild` and never production. The Friday retention deletes every unpinned build image older than seven days, so a build `promote` supersedes is gone on the first Friday after. Why: Inspector scans every ECR repository in the account and the Science Cloud weekly vulnerability notice counts every digest there, so a release kept in a registry carries its findings onto the notice for as long as it is kept, while a production run must stay on one code release for months inside the patch windows. A promote is due when the operations ledger shows a fixable finding on the production digest against its SLA; a finding in the application's dependencies is fixed by a lock-bump commit on `rapid`, a new release through retain and promote, because the lock files are part of the commit, and the rebuild patches only the OS layer. A promote takes effect at the next processing date. (Ben, 2026-11-04 00:32 UTC; release-retention-cycle tasks 1 to 5, rapid_systems PRs 470 to 474)

(decision-sources-children)=
**`sources` is split into child tables by UT observation date and SCA, inheriting the parent and loaded by `COPY`, as in `dev`, logged**: one child per UT day of `mjdobs` and SCA, `sources_<yyyymmdd>_<sca>`, made by the publisher when a source set first needs it, through `create_catalog_child`, which runs as the schema's owner: `LIKE` the parent, then `INHERIT`, as `dev`'s loaders make theirs. The publisher loads each child by bulk `COPY`, as `dev`'s loaders do, for fast loading. The parent holds no rows: a `CHECK (false)` its children do not inherit refuses one. Each child carries a `CHECK` on its date range and SCA, which `dev`'s lack, so a row cannot land in the wrong child and a query on a date or SCA skips the others. The children are logged, where `dev`'s are unlogged, because PostgreSQL empties an unlogged table after a crash and a published row is never deleted. SMDC's existing rows move into their children by `database/2026-11-04-sources-children.sql`. `xsources`, `dev`'s table of the SFFT difference image's SExtractor catalogs, comes to the rebuild with the same children and the same `COPY` in its own change. (Russ Laher, 2026-11-04)

(decision-xsources)=
**`xsources` comes to the rebuild as `dev`'s XSources (d2657f7d), written by the difference job beside its source set**: every source of the SFFT difference image's positive and negative SExtractor catalogs that `dev`'s loader keeps (inside the image more than 2 px from its edge; not cut by `[DATABASE_PREFILTER]`: finite sumrat at or below 0.4, finite rb at or below 0.0, finite 3 px aperture S/N at or below 5), uncapped, with the extra columns `dev`'s `compute_extra_cols_sxtractor` adds (pixel columns, DAOStarFinder sharpness and roundness, a 5 × 5 PSF fit on the prefiltered sources only, RuBR-AT score and label). Split and loaded like `sources`: inheriting children `xsources_<yyyymmdd>_<sca>`, bulk `COPY`. Official with its source set (`xsources_official`). Three choices: a failure in the extra columns fails the job (`dev` loads the catalog without them); the rb cut applied to `xsources` alone, as `dev`'s loader does, while `sources` kept {ref}`the rb-port ruling <decision-reliability-scored>` (since {ref}`the separate prefilter tables <decision-sources-prefilter>` `sources` are cut on rb too, and the `xsources`' cuts are `[difference.xsources_database_prefilter]`); both signs are scored, as `dev` does, the negative with the negated difference image on a model trained on positive sources. The port's PSF-fit columns equal `dev`'s own code on a synthetic image to 0.0. The table reaches SMDC by `database/2026-11-04-xsources.sql`. (Russ Laher, 2026-11-04)

(decision-skip-sources)=
**A run may skip loading `sources` records; `xsources` are always loaded**: `[difference] skip_loading_sources_records`, false by default (as `dev` can leave out its sources loader). True declares the difference job's source set with no rows, so its binding opens and its `xsources` stay official through it; nothing is associated and the epoch's packet set is empty; the quality metrics are those of the set computed, so the gate is unchanged. (Russ Laher, 2026-11-04)

(decision-children-reads)=
**The pipeline, the operator scripts and the named queries query the child tables of `sources` and `xsources` their task needs, not the parents**: a parent (or its `_official` view) is read by none of them. A source set's child is named by its difference image's L2 `mjdobs` (its own `jd` without an L2 row) and SCA, `source_set_child` in the schema and `rapidpipe.foundation.children` in Python, so finding it touches no parent; SQL reads sets' rows through `sources_of(jobs)` and `xsources_of(jobs)`. The packet job reads its own set and its triggers' members from their children; `validate_run.py`, `completeness.py`, `completeness_ou.py`, `inspect_run.py` and `queries.sql` read through `sources_of`, each shown to return what it returned on the parents; the publisher analyses only the children it loaded; a unit test fails on any parent read in the pipeline, the scripts or the named queries. (Russ Laher, 2026-11-04)

(decision-field-children)=
**`objects`, `memberships`, `packets` and `forced` are split into child tables by field, inheriting their parents and loaded by `COPY`**: one child per Roman tessellation field, `<parent>_<field>`, made by the publisher through `create_field_child`, which runs as the schema's owner, as `create_catalog_child` does. `dev` splits `astroobjects` and `merges` by field as standalone `LIKE` tables that do not inherit a prototype; here each child inherits its parent, as the `sources` children do, so the official views and a query by hand on a parent stay correct, and each carries a `CHECK` on its field. `dev` does not split its packet or forced-photometry records; here they are split with the objects. Every row is filed under its object's field: `memberships`, `packets` and `forced` gain a `field` column, the field of the object (`object_job`, `aid`) the row belongs to, so an object's row, memberships, packet rows and forced photometry share one field's four children. A membership the publisher's reconcile attaches to an object founded in a neighbouring field takes that object's field; if that field has no `memberships` child yet, the loading transaction makes one. The publisher records the fields each job's rows went to in `job_fields`. Readers query the children their task needs, never a parent, as for `sources` ({ref}`ruling <decision-children-reads>`): `<parent>_in(fields)`, `<parent>_of(jobs)` and `objects_official_in(fields)`. The named query `objects_in_cone` takes the fields the cone touches, which the caller computes. SMDC's existing rows move into their children by `database/2026-11-04-field-children.sql`. (Russ Laher, 2026-11-04)

(decision-xobjects)=
**`xobjects` and `xmemberships` come to the rebuild as `dev`'s XAstroObjects and XMerges (crossMatchXSources.py, d6364970), written by the SFFT difference job from its `xsources`**: the xsources' cross-match is the sources' association over them, as `dev`'s crossMatchXSources is crossMatchSources over XSources. The xsources with SExtractor `flags` equal to `[associate] xsource_flags` (0, as `dev`) and a finite position and `fluxap` are matched, positive and negative together (`dev` does not partition on `isdiffpos`), within `match_radius` against the dataset's xobjects of every run in their fields and those fields' neighbours ({ref}`ruling <decision-objects-across-runs>`; the dataset is the boundary within which objects and xobjects are shared, Ben, 2026-11-14). Each unmatched xsource founds an xobject in its own field, its id `radec_index` of its position and its `flux0` its `fluxap`, as `dev`'s. As for objects, not as `dev`: `dev`'s second pass is replaced by the field rule ({ref}`ruling <decision-association-by-source-field>`); duplicate founders are reconciled at publish, under the same field locks as the objects, rather than merged later; statistics are sufficient sums on each xmembership (`xobjects_official`), not `dev`'s XAstroObjectsMeta; and a superseded source set's xmemberships leave the official view rather than being pruned (`dev`'s pruneNotBestXMerges). Both tables are split into child tables by field, inheriting their parents, loaded by `COPY` and read from the children only ({ref}`ruling <decision-field-children>`). They reach SMDC by `database/2026-11-04-xobjects.sql`. Alert production was then unchanged, still made from `objects` and `memberships`; it now comes from `xobjects` and `xmemberships` by default ({ref}`ruling <decision-packets-from-xsources>`). (Russ Laher, 2026-11-04)

(decision-sources-prefilter)=
**`sources` and `xsources` take their prefilter thresholds from separate tables, `sources` are cut on rb and S/N too, and the import's `sources` are prefiltered** (supersedes, for `sources`, {ref}`the rb-port ruling's <decision-reliability-scored>` "nothing is cut on the score"): `dev` reads one `[DATABASE_PREFILTER]` for both of its loaders. Here `[difference.sources_database_prefilter]` holds the `sources`' cuts, applied to both signs' PSF-fit catalogs after the fit-position bounds and before the cap, by the difference job and by the import. `[difference.xsources_database_prefilter]`, `dev`'s section with `dev`'s values (sumrat 0.4, rb 0.0, aperture S/N 5.0), holds the `xsources`' cuts, and also selects the xsources the PSF fits run on. Either set can change without the other. Russ's direct commit bf1bf83c (2026-11-07, "for initial test", no pull request) set the `xsources`' `snr_prefilter_threshold` to `""`; it ran nowhere, and rapid PR 547 restored `dev`'s 5.0 before the X-path baseline run (rapid-xpath-baseline task 1). The `sources`' three:

- `sumrat_prefilter_threshold` (0.4): a source is kept when its sumrat is finite and above it and its nearest pixel is at least 2 px from every edge, as {ref}`dev-prefilter <decision-dev-prefilter>` states; `""` applies neither.
- `rb_prefilter_threshold` (0.0, `dev`'s): a source with a finite rb score at or below it is dropped, and an unscored source passes, as `dev`'s loader does.
- `snr_prefilter_threshold` (`""`, no cut): a source whose PSF-fit S/N, `flux_fit / flux_err`, the S/N the cap ranks by, is at or below it is dropped. `dev` makes no S/N cut on its sources, and its xsources' S/N is the 3 px aperture's, which PSF-fit sources lack, so a value here is a departure. It ships off: what the cut costs in recovered transients is unmeasured (the test fixture's transient at PSF-fit S/N about 4 fell under 5.0), and a value is set once a run has measured it (Ben Rusholme, 2026-11-07).

Each of rb and S/N is `""` for no such cut. A run therefore keeps fewer `sources` than before, those scored at rb ≤ 0 no longer loaded, and the metrics' `n_candidates` counts after these cuts. The import had applied no prefilter to its `sources`, of either sign, a departure no page recorded; it now applies the run's `[difference.sources_database_prefilter]` as the difference job does ({ref}`ruling <decision-import-both-signs>`), so an imported PSF-fit catalog without `sumrat` (one `dev` made before e4a49c97, 2026-10-01) keeps no sources unless that threshold is `""`, and one without rb scores is not cut on rb. The tables were `dev`'s one `[DATABASE_PREFILTER]`, shared as `[difference.database_prefilter]`; a run body stored before this change has only that table, and its `sources` take its `sumrat_prefilter_threshold` and are cut on neither rb nor S/N, and its `xsources` take its three, as they did. (Russ Laher, 2026-11-07)

(decision-import-both-signs)=
**The import loads `sources` from SFFT's positive and negative PSF-fit catalogs and `xsources` from its positive and negative SExtractor catalogs, as the difference job does**: the import had loaded the positive PSF-fit catalog only and no `xsources`, so an imported epoch's set held less than a made one ({ref}`ruling <decision-negative-sources>`). The negative PSF-fit catalog, `sfftdiffimage_masked_psfcat_negative.parquet`, is mapped as the positive is, `isdiffpos` false and its `sid` its catalog `id` plus the positive catalog's largest, and `[import] max_sources` caps each sign; a difference directory without it imports no negative sources, as the difference job publishes none without its catalog, and the manifest says so. The xsources are read as `dev`'s XSources loader (`loadSECatIntoDBSourcesTable.py`) reads them, from `sfftdiffimage_masked.txt` and `sfftdiffimage_masked_negative.txt`, `dev`'s names with `crossconv_flag` false, as the imported images are named. Their extra columns, the rb score and label among them, are the ones `dev`'s pipeline wrote into each catalog, its fill value -999 loaded as null, so the import recomputes and rescores nothing; a catalog without them (`dev` loads it so when adding them fails) loads them null. The kept rows are `dev`'s loader's: inside the image more than 2 pixels from its edge and not cut by the run's `[difference.xsources_database_prefilter]` thresholds ({ref}`ruling <decision-sources-prefilter>`; a run body stored before that split, by its `[difference.database_prefilter]`). `xsid` numbers the kept rows from 1, positive first ({ref}`ruling <decision-per-set-source-ids>`). A difference directory with neither SExtractor catalog imports no `xsources`, and the manifest says so; one with only one of the two fails the job, where `dev`'s loader skips the job with a warning. The import still makes no `objects` or `xobjects`. (Russ Laher, 2026-11-07)

(decision-per-set-source-ids)=
**`sid` and `xsid` are numbered within their source set, not drawn from database sequences as `dev`'s are** (`dev`: `sources_sid_seq`, `xsources_xsid_seq`): a source is identified by `(job, sid)`, an xsource by `(job, xsid)`, each unique only with its job, and the same `sid` recurs in other sets. The difference job assigns them before publishing, so its memberships, xmemberships and packets can name them: a positive source's `sid` is its PSF-fit catalog `id`, a negative's that `id` plus the positive catalog's largest ({ref}`ruling <decision-negative-sources>`), and `xsid` numbers the kept xsources from 1, positive first. A packet's `diaSourceId` is the trigger's `sid`, so it is unique within its packet set, not across the stream as `dev`'s is; a reader identifies a detection by its set and `diaSourceId` together. Switching to sequences, as `dev`, was considered and not taken. (Russ Laher, 2026-11-06)

(decision-negative-sources)=
**`sources` take SFFT's positive and negative PSF-fit catalogs, uncapped, as `dev`'s loader** (`loadPSFCatIntoDBSourcesTable.py`, which loads both, `isdiffpos` false for the negative): the rebuild had loaded the positive catalog only, capped at the brightest 500 by S/N, a departure no page recorded. Each row carries its catalog's sign as `isdiffpos`; a negative row's `sid` is its catalog `id` plus the positive catalog's largest `id`, so a set's two catalogs number apart and a packet's `diaSourceId` stays unique within the set. The negative catalog is scored by RuBR-AT on the negated difference, as `dev`'s `compute_extra_cols_photutils` scores it, and goes through the same prefilter. Negative sources are associated and alerted as positive ones are (`dev` partitions neither; the packet's `isNegative` is `not isdiffpos`). `[difference] max_sources` and `[import] max_sources` ship -1, which means no cap, keeping every source, as `dev` caps nothing; a non-negative value keeps the brightest that many (per sign in the difference job), 0 keeping none, and anything below -1 is refused. Only the positive SFFT image is registered in `diffimages` ({ref}`ruling <decision-sfft-only-registered>`). The quality metrics stay the positive sources', so the gate is unchanged; `n_sources_negative` and `n_candidates_negative` count the negatives. (Russ Laher, 2026-11-06)

(decision-sfft-only-registered)=
**Only SFFT's positive difference image is registered in `diffimages`, and SFFT always runs**, as in `dev` (PR 478, ab097bce: "the SFFT difference image is the only one registered in the DiffImages database table", `[SFFT] run_sfft` "must be True"). `[difference.sfft] run_sfft = false` fails the settings check. `[difference] diff_flavor`, which let a run publish ZOGY's image and source set instead ({ref}`ruling <decision-published-differencer>`, {ref}`the SFFT default <decision-sfft-default>`), is retired: the base settings no longer carry it, so a run or overlay naming it is refused at `run create`, and the difference job refuses a run body from before that names anything but `"sfft"`. `sources`, `xsources`, the rb scores and `dev`'s prefilter are therefore always SFFT's. ZOGY's PSF-fit catalogs stay diagnostics, and ZOGY itself may be skipped ({ref}`ruling <decision-run-zogy>`). `diffimages` rows already published from ZOGY stay as they are, and the packet stage still reads such a window image with ZOGY's PSF. (Russ Laher, 2026-11-06)

(decision-run-zogy)=
**`[difference.zogy] run_zogy = false` skips ZOGY, as `dev`'s `[ZOGY] run_zogy` (PR 478, f8cda2ee)**: the difference job then makes no ZOGY difference image, significance image, difference PSF, uncertainty image or catalogs, and catalog-outcome bits 0 and 1 are never set. SFFT and the naive subtraction run as before, and everything published is SFFT's, as under `run_zogy = true`. The default is true, as `dev`'s. SFFT always runs ({ref}`ruling <decision-sfft-only-registered>`), so `dev`'s fallback, ZOGY run anyway when SFFT is off, has no case. One departure from `dev`: an SFFT failure with ZOGY skipped fails the job with exit 70 (`ToolFailed`) as every tool's failure does ({ref}`ruling <decision-tool-exit-checked>`), where `dev` exits 65. The manifest's `zogy_source_counts` is null when ZOGY is skipped. (Russ Laher, 2026-11-06)

(decision-packets-from-xsources)=
**Packets and forced photometry are made from `xsources`, `xobjects` and `xmemberships` by default; `[packet] alert_catalog` chooses** (supersedes the "alert production is unchanged" clause of {ref}`the xobjects ruling <decision-xobjects>`): `"xsources"`, shipped, or `"sources"`, the path before this ruling. A run body without the key, stored before it, keeps `"sources"`, so older runs replay unchanged. Under `"xsources"` the packet job's triggers are its source set's xsources whose SExtractor `flags` equal `[associate] xsource_flags` and that the difference job made xmembers of an xobject; the lowest `xaid` wins, as for objects. History, `nDiaSources` and `raSigma`/`decSigma` come from the xobject's official xmemberships and the set's own; forced photometry is measured at the xobject's founding position. The xsources are prefiltered by `[difference.xsources_database_prefilter]`, so that table, not `[difference.sources_database_prefilter]`, selects what can alert. The loop is unchanged: the packet job still names its `sources` input, the binding through which the set's xsources are official ({ref}`ruling <decision-skip-sources>`), and the source sets it reads are recorded as `sources` reads for the same reason. With `skip_loading_sources_records` true the epoch's packet set is therefore no longer empty. A `diaSource` from an xsource: `diaSourceId` the `xsid`, `diaObjectId` the `xaid`; `ra`, `dec` the windowed SExtractor position; `x`, `y` `XWIN_IMAGE` and `YWIN_IMAGE` less one (zero-based, as `xfit`, `yfit`); `psfFlux` `xsources.fluxfit`, `psfFluxErr` `fluxfit / snrfit` and `snr` their ratio, with `psfFitFlags` `flagsfit`, `psfRChi2`, `psfNdata`, `psfCfit`, `sharpness`, `roundness1` and `roundness2` from their xsource columns. An xsource that was not fitted (null or non-finite `fluxfit` or `snrfit`, or `snrfit` 0) takes the 3 px aperture, `FLUX_APER_1` and `FLUXERR_APER_1`, for `psfFlux` and `psfFluxErr`, with `psfFitFlags` 0. `apFlux` and `apFluxErr` are always the 3 px aperture. `xErr`, `yErr`, `psfQfit` and `peak` are null (not in `xsources`); `reliability` is `xsources.rb`. `[packet] max_alerts` ranks by that `snr`'s absolute value, as for `sources` (`dev` ranks by the signed S/N). The `packets`, `forced` and `external` tables keep their columns: `aid` holds the `xaid` and `sid` the `xsid`, and the run's `alert_catalog` says which tables they name; no column records it. The schema's 00.07 doc strings are unchanged: the `apFlux` doc still says "(stub)". `scripts/read_packets.py` and `scripts/validate_run.py` check a set against the tables its run's `alert_catalog` names, and `scripts/completeness.py` and `completeness_ou.py` join the packets to that catalog's detections (an xsource's flux its fit's, else the 3 px aperture's). `dev` makes its alerts from `sources`, `astroobjects` and `merges`; this is new. (Russ Laher, 2026-11-07)

(decision-release-is-a-build)=
**A production release is one built image, and promoting it archives it** (supersedes the commit as the release, the marker gate and the Wednesday rebuild of {ref}`the retained-releases ruling <decision-production-retained-releases>`; production still runs on retained releases only): a release is a rapid commit built on one base image, named by the build's digest. The same commit on another base is another release, because the base carries the Python and the science packages the code runs on. `release-hooks/promote <digest>` takes a build tagged `rebuild-<commit>-<base8>`, copies it to the backups bucket's `archive/production/images/` as an OCI archive with its digest read back, and only then repins `rapid-rebuild-production`, by the same change set of production's row alone. The archive holds exactly what production runs. The Wednesday `production-rebuild` operation is removed and nothing rebuilds an old commit on a newer base; production moves by promoting a newer build that scratch has run. Why: on 2026-11-11 the Wednesday rebuild failed, and the cycle turned out never to have been able to promote. The commit production held, of 2026-11-03, pins TensorFlow for Python 3.13, and the base moved to Python 3.14 on 2026-11-07. The same week's re-lock of the base moved the difference stage's candidate counts about 2.4 times on an unchanged commit (runs 229 and 231), so a rebuild on a new base is not the release that was checked. The marker gate compared a rapid commit with a field that holds a rapid_systems commit, and the retain step archived the base image, not the build. What it gives up: a fix for a finding on production's image no longer arrives as the same code on a patched base. It arrives with a newer build, so it brings newer pipeline code and needs the acceptance any promote needs. First promote the same day: rapid `0fd55314` on base `576304f3`, `rapid-rebuild-production:92`. (Ben, 2026-11-11 16:26 UTC; rapid_systems PR 525)

(decision-objects-without-survey)=
**Objects and xobjects name no survey**: `objects` and `xobjects` drop their `survey` column, and with it `survey` in their unique key, in their field index and in the key of the difference job's recorded `objects` and `xobjects` reads, which is now `dataset` and `field`. Why: surveys overlap, and an object or xobject may be defined by light-curve points from more than one survey, so a single survey on its row would name one of them and misname the rest. The run still records the survey it was run for (`runs.survey`, and the live binding of a survey and dataset), and an object's founding job names its run. A difference job matches every run's objects of its dataset ({ref}`ruling <decision-objects-across-runs>`), so an object's members may come from runs of more than one survey. `queries.sql`'s `field_objects_and_members` and `objects_in_cone` select on dataset and field. SMDC's `public` schema takes it by being recreated from `schema.sql` at the cutover, not by a dated file (Ben, 2026-11-14), since its contents are test runs; an image on either side of it writes the other shape. `dev`'s `astroobjects` and `xastroobjects` carry no survey, so this returns to `dev`'s columns. (Russ Laher, 2026-11-12)

(decision-objects-across-runs)=
**A difference job matches every run's objects and xobjects of its dataset in its fields, not its own run's alone** (supersedes "its field's objects of its run" and "serialised per run and field" in {ref}`association in the difference job <decision-association-in-difference>`, and "the run's xobjects" in {ref}`xobjects <decision-xobjects>`). Why: surveys overlap, and an object's light curve may hold points from runs of more than one survey (a GBTDS run and an HLWAS run over one field); a run takes one `[intake] program_id`, so run-scoped objects could never gather them. The read is `objects_in(fields, dataset)` and `xobjects_in(fields, dataset)`, the dataset's filter inside each field child's query (`field_dataset_rows`, replacing run-scoped-reads' run filter); every published difference job's objects count, of any run, live or not, as `dev`'s `astroobjects` hold every pipeline run's. Another dataset's objects are never read: the dataset is the boundary within which objects are shared, the set of inputs whose objects one catalog holds, so flight is one dataset and a trial or a test takes a name of its own (Ben, 2026-11-14). The publisher's field locks move from (run, field) to (dataset, field), the first key `hashtext(dataset)`, so two runs' jobs founding at one star serialise and the later attaches to the earlier's object at publish, as two jobs of one run did. Consequences: a retune of a dataset already processed, a new run over the same exposures, joins the earlier runs' objects and founds almost none of its own; its memberships are its own rows, official with its source sets, and an object's statistics through `objects_official` sum the official memberships of every run. A field's read grows with every run of its dataset, the size that spilled to temp files when six runs' rows of a field were read (run 228, throughput-record), now read by design; not yet measured on any run. SMDC's `public` schema takes it with no-survey's change, recreated from `schema.sql` at the cutover. (Russ Laher, 2026-11-12)

(decision-dq-mask-base)=
**The flight overlay sets the DQ mask with SATURATED, `[intake] dq_mask_bits = 34671619`, and the base stays `dev`'s 0**: DO_NOT_USE, SATURATED, DEAD, HOT, NONLINEAR, NO_LIN_CORR and UNRELIABLE_FLAT, commissioning PR 238's default (`dqMaskSubs.py`, 5300a6fc). Commissioning records no reason for SATURATED; the reason here is flight program 1049, where SATURATED marks 0.001% to 0.002% of each frame, real saturated cores whose fluxes are wrong ([datasets](datasets.md#flight-data-program-1049)). Keeping them out of SFFT's kernel fit is inferred, not measured, and flight takes this mask together with {ref}`SFFT's kernel-fit masking <decision-sfft-kernel-masking>`, never without it: zero-filled saturated cores in an unmasked kernel fit were commissioning's job 95 failure. The base's 0 masks nothing, so a dataset whose overlay names no mask is unchanged. The simulation overlays keep what they had: HLWAS and GBTDS set `34671617`, without SATURATED, which flags every HLWAS star core above about 100 DN/s ({ref}`measurements <measurement-dq-mask>`); RimTimSim, the socsims lite files and OpenUniverse name no mask. (Azalee, 2026-11-10; the value on the flight overlay rather than the base, the rebuild-migration plan's verdict on rapid 611, Ben's go 2026-11-14 06:55 UTC)
