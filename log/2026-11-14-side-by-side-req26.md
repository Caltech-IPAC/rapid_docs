---
blogpost: true
date: 2026-11-14
author: side-by-side-req26 run
category: log
---

# The side-by-side with IMSS's req26, 2026-11

This is the comparison the go or no-go reads. On 2026-11-11 IMSS ran
`dev` over program 1049's plan 02 as `procreqs` req26: 266 science jobs
in F158 and F062 over all 18 SCAs, differenced against the references
req24 built from plan 01. On 2026-11-14 the rebuild ran the same plan
once, as run 250, on the merged image. This post sets the two side by
side, image by image, and scores them against the pass bar Ben set on
2026-11-14.

Every one of IMSS's 266 images is comparable, and every bar that can be
measured on the two runs is met on all 266, in each filter and together.
The SExtractor detection counts agree at a median ratio of 1.000 on both
signs, the 3 px aperture fluxes of the matched detections agree at a
median ratio of 1.000, the matched positions agree to 0.0001 px at the
median, and at least 99.6% of the rebuild's xsources carry a real-bogus
score on every image. Each of the 196 references the two runs share was
built from the same frames in the same order. The gate held 140 of the
286 packet sets, and 5 of them were judged on another exposure's
difference, a known defect of this image.

## The bars

Each bar is measured on the 266 comparable images (133 F158, 133 F062).
A bar is met or not met only when it was measured on every comparable
image.

| Bar | F158 | F062 | Both | Verdict |
|---|---|---|---|---|
| SFFT SExtractor detection counts within 5% at the median, positive | median ratio 1.0000 (0.9996 to 1.0008), 131 of 133 equal | 1.0000 (0.9985 to 1.0008), 131 equal | 1.0000, 262 of 266 equal | met, 266 of 266 measured |
| The same, negative | 1.0000 (0.9975 to 1.0012), 130 equal | 1.0000 (1.0000 to 1.0000), 133 equal | 1.0000, 263 equal | met, 266 of 266 |
| Matched-pair aperture flux within 1% at the median | per-image median ratio 1.0000 on every image | 1.0000 on every image | 1.0000 | met, 266 of 266 |
| Matched positions within 0.1 px | per-image median offset 0.0000 to 0.0002 px, 95th percentile at most 0.0030 px | median 0.0001 px, 95th percentile at most 0.0002 px | every image under 0.1 px at its 95th percentile | met, 266 of 266 |
| At least 95% of xsources scored by real-bogus | lowest image 99.63%, pooled 99.96% | lowest 99.73%, pooled 99.95% | 0 images under 95% | met, 266 of 266 |
| Each field's reference built from the frames IMSS selected | 98 of 98 shared references equal as sets and in order | 98 of 98 | 196 of 196 | met |
| Every held field, flagged reference and failed job with its reason | below | below | below | met |
| HLWAS's injected sample, alongside | from the records, not re-run on this image | | | not evaluable on this image |
| The team's eyes on a gallery, alongside | the panels are named below | | | not claimed |

The counts are the rebuild's difference manifests'
`difference.xsources.read` per sign against the row counts of IMSS's
`sfftdiffimage_masked.txt` and `sfftdiffimage_masked_negative.txt`. In
total the rebuild reads 350,955 positive and 368,147 negative rows
against IMSS's 350,956 and 368,149. Under the loader rule (rebuild's
`rapidpipe.science.difference.xsources` at run 250's thresholds, sumrat
0.4, rb 0.0, aperture S/N 5.0 and the 2 px edge cut, applied to IMSS's
catalogs as files) the rebuild keeps 231,142 positive and 185,391
negative rows against 231,056 and 185,317; the kept ratio per image runs
0.9942 to 1.0052, equal on 183 images of each sign.

A pair is a rebuild xsource and the nearest IMSS row kept by the loader
rule, of the same sign, within 0.5 px (the X-path baseline's radius).
416,212 of the rebuild's 416,533 kept rows pair (99.9%; no image under
98.9%). The flux is SExtractor's `FLUX_APER_1`, the 3 px aperture, the
rebuild's over IMSS's. PSF-fit flux is left out of the bar because
IMSS's photutils version is not established.

The real-bogus share is the rebuild's loaded `xsources` with a finite
`rb` over all its loaded `xsources`. IMSS's own catalogs score the same
share under the loader rule (lowest image 99.63%).

HLWAS's injected sample stands on the record only: run 240 on the
ports-only image `rapid-rebuild:134`, before the recreate, recovered 193
of 200, as the nightly drift's run 238 did. It was not re-run on
`rapid-rebuild:136`, so it says nothing about this image.

## What was tested

| Item | The rebuild, run 250 | `dev`, IMSS's req26 |
|---|---|---|
| Code | `rebuild` `3f5045086a1912b47a82488f954afd87965ce556`; checks and this comparison from `cd45414f` (rapid PR 624, which changes no image) | `dev`'s pipeline as IMSS ran it, 2026-11-11 |
| Image | job definition `rapid-rebuild:136`, `sha256:1efd8acfc44f42dd96dec99a82baa6c594f4f3096db3fe00944e9d62b86a0760`, on every one of the run's 1,346 Batch jobs | IMSS's own |
| Settings | overlay `flight.toml`, survey CAR198, the reference bound MJD 61346.751675 (plan 01 before, plan 02 after), `min_coverage_fraction` 0.4 by `--set` as IMSS used; `settings_hash` `sha256:b67caede…1fbdd`, equal to runs 241, 245 and 247 | `min_coverage_fraction` 0.4, SFFT without cross-convolution, the gain-match catalogs and segmentation on |
| Inputs | the 576 program 1049 files under the inputs bucket's `flight/` (288 plan 01, 288 plan 02), every frame IMSS's req24 and req26 reference lists name among them, all of program 1049 | the same files as IMSS's `.fits.gz` |
| Science PSF | Jacob's `phavg` library, the 144 files of `g0009-psf-1043/psfs/` imported before any intake; the 36 of F158 and F062 are the run's science `psfs` bindings, and the loop planned no `psf` job | the same library, `sciimage_psf_phavg_fid<N>_sca<NN>.fits` in every science config |
| Catalogs | gaia DR3, NED 36.1_20260527_v2 and NED-LVS 20260424 by one import, `ss` rolling by a second | |
| References | 196 built of 198, 14 to 42 frames (median 32), every one status 1 and infobits 1 | req24's 198, from the same plan 01 frames |

The run's image digest, settings body, input list and PSF identities are
recorded together in `run-record.json` under the evidence path below.

## The references

The rebuild planned 198 references, one per field and filter of plan
02's 288 images. IMSS's references for those 99 fields are req24's for
90 of them (the ones req26's science differenced against) and req26's
own for the other 9. Every one of the 266 science configs names a req24
reference, so the 16 references req26 built were differenced by no
science job of req26.

- **196 built, all comparable.** Each one's frames, in the rebuild's
  selection order, equal IMSS's `input_images_used_for_refimage` list for
  the same field and filter, entry for entry.
- **No reference on either side: field 3018409**, both filters. The
  rebuild refused it at measured coverage 0.3819 against 0.4 (jobs
  134003 and 134004, exit 65), as IMSS refused it at 0.3822 (req26
  jid10099 and jid10109, exit 33). Its two plan 02 images,
  `r0104902002001001001_0001_wfi09_f062` and
  `r0104902002001002002_0001_wfi09_f158`, are differenced by neither.
- **Status 0: none.** All 196 are status 1, infobits 1.
- **req24's other 9 fields** (3002030, 3014314, 3014316, 3022505,
  3026606, 3034802, 3038891, 3047086, 3047088, both filters) have a
  reference at IMSS and no plan 02 image in either run.

## The images IMSS did not difference

IMSS's 266 are 22 short of plan 02's 288. Two are field 3018409's,
above. The other 20 lie in the 8 fields whose references req26 built
itself (3002031, 3018418, 3026603, 3026605, 3030708, 3034799, 3038897,
3047085): req26 built those references and ran no science on them. The
rebuild differenced all 20, against references whose frames equal req26's
for the same field and filter; they have no IMSS catalog to compare and
are listed in `plan02-smdc-only.csv`.

## Rows against rows

The per-image table is `per-image.csv` under the evidence path: one row
for each of the 266 (stem, filter, SCA, IMSS's field and jid, the
rebuild's difference job and reference), with both sides' read and kept
counts per sign and their ratios, the pairs, the median aperture-flux
ratio, the median and 95th-percentile offset, the real-bogus shares, the
gate metrics (core, ring, usable fraction, registration offset) and the
packet set's state. Summarised:

| Row | Rebuild, run 250 | `dev`, req26 | Ratio Q1 / median / Q3 (min, max) | Images equal |
|---|---|---|---|---|
| SExtractor read, positive | 350,955 | 350,956 | 1.000 / 1.000 / 1.000 (0.9985, 1.0008) | 262 of 266 |
| SExtractor read, negative | 368,147 | 368,149 | 1.000 / 1.000 / 1.000 (0.9975, 1.0012) | 263 of 266 |
| Kept by the loader rule, positive | 231,142 | 231,056 | 1.000 / 1.000 / 1.001 (0.9987, 1.0052) | 183 of 266 |
| Kept by the loader rule, negative | 185,391 | 185,317 | 1.000 / 1.000 / 1.001 (0.9942, 1.0049) | 183 of 266 |

The kept counts differ by more than the read counts. As in the X-path
baseline, the rebuild recomputes rb and sumrat itself, and a row near a
cut can fall either side of it; that cause is not re-read here.

## The gate and the packets

All 286 packet jobs published, and each wrote its set: 370,789 packets,
2,000 a set at most (6,620 triggers dropped by the cap). The gate sent
146 sets (195,590 packets) and held 140.

| | Sets | Sent | Held | Usable fraction | Ring | Core | S/N > 20 |
|---|---|---|---|---|---|---|---|
| F158 | 143 | 109 | 34 | 9 | 8 | 8 | 9 |
| F062 | 143 | 37 | 106 | 11 | 61 | 27 | 7 |
| Both | 286 | 146 | 140 | 20 | 69 | 35 | 16 |

Of the 266 compared images, 135 sets were sent and 131 held. The
consumer read 195,590 packets from the topic against the 195,590 sent,
and the 112,050 packets of the 84 sets it sampled were valid against
their schema and byte-equal to the sets written. `check_run.sh` read validate 5 of 6
(lineage, tables, catalog, packets and forced PASS; counts FAIL on the
two refused references), the reader 286 of 286 sets CLEAN and the
consumer CLEAN.

The gate's metrics over the 286 differences, under `reference_psf =
"science"` with the `phavg` PSFs: core fraction median +0.0108 (−0.0085
to +0.0467), ring −0.0112 (−0.0379 to +0.0023), usable fraction 0.9966
(0.760 to 0.999), registration offset 0.041 px (0.001 to 0.123). The
bounds are HLWAS's (core ±0.025, ring ±0.015, usable 0.9, registration
0.25 px); this post changes none.

**Sets judged on another exposure's difference.** The gate reads a
packet set's first `sources` input, and a set names several, so it can
judge one image's set on another's metrics (`gate-own-difference` fixes
it on `rebuild`; no image carries the fix yet). By flight-phavg-psf's
method, applied here to every set, sent ones included, 5 of 286 were
judged on a difference that is not their own: 3 held and 2 sent. Judged
on its own difference, three would have had the other answer: 134209
(held on usable fraction, its own would send), 134801 (held on ring, its
own would send) and 134439 (sent, its own would be held on ring). The
recorded answers stand; `gate-audit.csv` lists every set.

## Failed jobs and held fields

- **References 134003 and 134004**, field 3018409 SCA 9: coverage 0.3819
  under 0.4, as above. The run's only failed jobs.
- **Start failures**: 12 Batch attempts ended "Task failed to start"
  (10 packet, 2 difference jobs). Each job published on the loop's own
  rerun, so none was resubmitted by hand and no field is missing for it.
- **The `ss` match failed in every packet set**: "no ss day at or before
  20261112 (oldest is 20261113)". The `ss` root holds no day before plan
  02's exposures, as flight-trial-1 found, so no packet carries a solar
  system match.
- **Held fields**: the loop held no field.

## Known differences between the two systems

- **The packets.** The rebuild's come from `xsources` and are gated;
  IMSS's alerts come from its PSF-fit Sources and are not gated. Their
  Avro files were not copied from IMSS, so the two alert streams are not
  compared.
- **Recomputed extra columns.** The rebuild computes rb and sumrat
  itself, which moves the loader rule's kept rows by up to half a per
  cent per image.
- **The `ss` catalog.** No day of it precedes plan 02 (above).
- **The gate's source set.** Above.

## Where things are

Run 250's products are under the outputs root's `250/`, its rows in
SMDC's database under run 250 and dataset `side-by-side-req26`. This
comparison's working set is under `250/qa/side-by-side-req26/`: the
per-image table (`per-image.csv`), the matched pairs (`pairs.parquet`),
the references (`references.tsv`), the 20 images only the rebuild
differenced (`plan02-smdc-only.csv`), the gate audit (`gate-audit.csv`),
IMSS's catalogs under the loader rule (`imss-counts.csv`,
`imss-xsources.parquet`), IMSS's roster (`science.tsv`) and job configs
and input lists as read (`imss/`), the rebuild's rows as read (`dump/`),
`run-record.json`, the loop log, the check's output, the scripts that
made each table (`scripts/`) and the inspect directory (`inspect/`,
`run-250.md` and 39 difference panels). IMSS's files stay under the
inputs bucket's `g0010-imss-req26/`, whose `jid10117`, `jid10249`,
`jid10250` and `jid10382` directories hold its difference images.

## What is not claimed

- **The gallery.** The inspect panels exist; the team has not looked at
  them, and this post claims nothing for that bar.
- **HLWAS on this image.** Not re-run.
- **The alert streams.** Not compared (above).
- **PSF-fit flux.** Left out of the bar.
- **Pixel identity.** The catalogs agree; the difference images were not
  compared pixel by pixel.
- **The cause of the kept-count spread and of the 4 positive and 3
  negative images whose read counts differ.** Not read.
- **Breadth.** One plan of one program, one run on each side.
