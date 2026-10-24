# The difference stage

**Status: DRAFT**

`difference` subtracts one epoch's L2 image from the reference its job
names, with ZOGY and with SFFT, catalogs both, and declares one
differencer's image and source set for the publisher: the one
`[difference] diff_flavor` names, shipped as `zogy`
({ref}`ruling <decision-published-differencer>`). The other
differencer's PSF-fit catalogs stay under the prefix as diagnostics, and
the naive subtraction runs as `dev` runs it, for its outcome bits. The stage ports the science of `dev`'s
`pipeline/awsBatchSubmitJobs_runSingleSciencePipeline.py`, refreshed to
`dev` at d6aac515, under the foundation's `run(job)` contract:
`rapidpipe/stages/difference.py` and `rapidpipe/science/difference/` on
the pipeline repository's `rebuild` branch. The [foundation](foundation)
page states the records it works within, and the
[stage contract](stage-contract) page what a stage is.

## Scope and inputs

The scope is `{"expid", "sca", "fid"}`, the epoch's key without the
dataset, which is the run's. The job names exactly three `input` rows,
read in one short transaction and fetched through `prefix.get`:

| Product | Which |
|---|---|
| `l2files` | the epoch's own row |
| `refimages` | one reference of the scope's filter, imported or made by the [reference](reference) stage; its coverage and uncertainty maps sit beside the mosaic, and its mosaic catalog (`refimcatalogs`, `cattype` 1) gives the reference FWHM |
| `psfs`, kind `science` | the science image's PSF for the scope's filter and SCA |

Any other product, a second input of one kind, a `psfs` row of another
kind, or an input whose key is not the scope's fails the job before a
manifest is written.

The reference image's PSF is not an input: it is derived data, measured
by the job ({ref}`ruling <decision-reference-psf-measured>`). Right after
the resampled reference's background is subtracted, the job finds its
stars (DAOStarFinder at 8σ on the pixels finite and covered at the
coverage threshold; peak at least 400 times the clipped noise and at
most 3,500 DN/s, no neighbour within 14 pixels,
the whole 31-pixel stamp usable, and a second-moment width between the
science PSF's and 0.4 pixel more, since resampling only widens a star
while defect pixels are narrower and galaxies wider), builds an
effective PSF from the brightest 100 (`EPSFBuilder`, oversampling 4),
evaluates it at the pixel centres of a stamp the science PSF's size,
re-centred to 0.01 pixel (a secant step, and a grid search where the
step stalls, since the evaluated centroid's two axes are coupled), takes the science PSF's wings beyond 10 pixels (the measured
core within 6, a cosine taper between), normalises it, and gives that to
ZOGY, SFFT and the naive catalogs as the reference PSF. The wings are the
science PSF's because the ePSF is built on 31-pixel stamps and holds
nothing beyond 15 pixels, where the science PSF still holds 3.3% of its
flux: given the truncated stamp, ZOGY left a ring 10 to 20 pixels out at
every bright star (run 42, pass 4: 190 of 449 sources above S/N 20), and a
sub-pixel resampling kernel leaves the wings unchanged. Fewer than ten stars stops the job with
exit 65 and `refpsf: N stars, 10 needed` on the job row; there is no
fallback. The stamp is published as `refimage_psf.fits.gz`, and the
manifest's `metrics` hold `refpsf_sigma_px`, `refpsf_stars`,
`sci_psf_sigma_px` and `psf_centroid_offset_x_px` and `_y_px` (the
reference stamp's centroid minus the science stamp's). On run 17's pass 4
reference the measurement takes 4.6 s and gives 1.080 pixels from 38
stars, against the science ePSF's 0.947. The peak floor was first 20
DN/s, set on F146, where it is 886 times the noise; in F184 and F213 it
left 8 and 6 stars of 2,100 and 683 detections and failed every
difference, so it is stated in units of the noise (fixes task 5, 400σ:
45 and 19 stars on the resampled references).

**Quality numbers.** Beside those, the manifest's `metrics` carry the
measurements that would have shown the null test's detections to be
artefacts on its first run, each from arrays the job already holds and
absent, never zero, when it cannot be made: the registration offset
(median centroid of science minus resampled reference at the reference
PSF's stars, before the subpixel shift), the reference stars' width and
its ratio to the science PSF's, the core (within 2.5 pixels) and ring
(2.5 to 6) fractions of the difference over star flux at the 30 brightest
isolated stars, the noise correlation, the usable fraction (finite and
covered pixels), the candidates before the cap and the sources after it,
those above S/N 20, and the share on a reference-catalog source within 3
pixels. The database's `job_metrics` view exposes every job's metrics by
run, stage and scope, and `scripts/inspect_run.py` renders them per run,
with a gallery of the residual stars, each cutout divided by its star's
reference flux, before the run's checks. The metrics also hold the
science stars' own width (`sci_star_sigma_px`) and its ratio to the
science PSF's, the reference's scale factor (`scalefacref`), the
sources near bright stars and in their rings above S/N 20, and every
job's peak resident memory (`peak_rss_kib`, the process and its largest
child). The {ref}`quality gate <foundation-quality-gate>` reads them.

**The bright-star footprint flag.** What the null test leaves above S/N
20 after the fixes is bright stars, and that residual is flagged, not
fixed ({ref}`ruling <decision-bright-star-flag>`). The job sets bit
`1 << 14` (16384) of `sources.flags` on every kept source inside the
footprint of a bright reference source, a mosaic-catalog source with
aperture S/N above 100, whose footprint is a disc of radius
`max(4, 9.5 × 10^(0.2 (15 − m)))` pixels at its magnitude `m` on the
reference's zero point. Nothing is dropped. The bit is informational:
association and the packet stage clear it before their flag tests, so a
flagged source is associated and triggers, and its packet carries the
bit in `psfFitFlags` with no schema change. The metrics count the
flagged sources and their share of those above S/N 20
(`bright_footprint_fraction`), and the packet job counts its flagged
packets. The radius law, derived on run 46's published sources, flags
21 of 23, 15 of 19 and 11 of 15 of the sources above S/N 20 on F146 SCA
8, the fixes' own bright-star counts on those epochs.

## What it runs

The steps follow `dev`'s order, one module each under
`rapidpipe.science.difference`, and every external tool runs in the
work directory with `dev`'s file names and command lines.

The L2 image is moved to the primary HDU and converted to DN/s, with a
simple-model uncertainty image. SExtractor catalogs it for the FWHM of
its point sources. Its SIP distortion is rewritten as PV, and SWarp
resamples the reference, its coverage and its uncertainty onto the
science grid. bkgest subtracts the background of the science image and
of the resampled reference. Gain matching compares the two images'
SExtractor catalogs for the reference's scale factor and the median
offsets, using the science image's own zero point and the reference's
`MAGZP`; with too few matched sources it falls back to the zero points
and zero offsets.

NaNs in ZOGY's inputs are replaced, extreme artifact pixels are
repaired, and the reference is shifted by the median offsets. ZOGY runs
by subprocess. Its difference and significance images are masked where
the reference coverage is below threshold, the NaNs are restored, and
negative copies are made. The stage then makes the difference's
uncertainty image and the positive and negative SExtractor and
Photutils PSF-fit catalogs. SFFT and the naive subtraction follow with
their own catalogs.

Every external tool runs checked, SFFT included: a nonzero exit fails
the job with exit 70 and `ToolFailed: <tool> exited with code <n>; its
last <k> output lines: …` (up to 20 lines) on the job row, with no
fallback to the other differencer
({ref}`ruling <decision-tool-exit-checked>`). Nothing is caught around the
Photutils PSF fit: on an empty field photutils returns no table, which
is the empty catalog, and it raises only on a fault, such as a zero or
NaN uncertainty under a source, which fails the job.

**`dev`'s pixel columns.** On every row of both SFFT PSF-fit catalogs,
before the cap and whichever differencer is published, the job measures
`dev`'s `sumrat` (`sum(p) / sum(|p|)` over a 5 x 5 stamp after a 3 x 3
truncated median filter), `nneg` and `nbad` (the stamp's finite
negative and non-finite pixels), each after a 64 px Background2D local
background subtracted from a copy of the image, each catalog on the
image its sources are positive in. They are columns of the catalog
files and of `sources`, nullable: an unmeasurable value (the stamp off
the image) is NaN in the file and null on the row. A failed local
background fails the job, where `dev` measures on the unsubtracted image
({ref}`ruling <decision-pixel-columns-fail>`). They cost 4.3 to 5.2 s a
difference (`pixel_columns_s`).

## Declared outputs

The stage publishes, under `diff/` in the attempt's prefix, the files
that a person or the packet stage reads, and nothing else
({ref}`ruling <decision-difference-trimmed>`). `dev` uploads every working file
for diagnosis; on the HLWAS ramp that was 72 files and 2.5 GB a job,
89% of the run's bytes. What is kept, and the reader that earns it; the
published differencer's files carry its prefix (`zogy_diffimage_…`
under `zogy`, `sfftdiffimage_…` under `sfft`):

| File | Why it is kept |
|---|---|
| `zogy_diffimage_masked.fits.gz` or `sfftdiffimage_masked.fits.gz` | the difference; the `diffimages` row names it, and `packet` reads it for the difference cutout and forced photometry |
| `zogy_diffimage_uncert_masked.fits.gz` or `sfftdiffimage_uncert_masked.fits.gz` | its uncertainty, read by forced photometry |
| `awaicgen_output_mosaic_cov_map_resampled.fits.gz` | the mask: the resampled reference coverage map the difference is masked with |
| `zogy_diffimage_masked_psfcat[_negative].parquet`, `sfftdiffimage_masked_psfcat[_negative].parquet` | the catalogs, uncapped: the published differencer's positive one is the catalog `sources` is the capped set of; the other three are diagnostics read by no stage; SFFT's two carry the pixel columns |
| `diffpsf.fits.gz` or `sfftdiffpsf.fits.gz` | the difference's PSF, for forced photometry on the difference |
| `refimage_psf.fits.gz` | the reference PSF the job measured and gave the differencers |
| `bkg_subbed_science_image.fits.gz` | forced photometry on the science image, and the science cutout |
| `awaicgen_output_mosaic_image_resampled_gainmatched.fits.gz` | the template cutout |

The difference, its uncertainty, the mask and the published catalog
are the ruling's. Three of the others are what `packet` reads, the
reference PSF is the job's own measurement, kept for whoever checks
the subtraction (15 KB), and the three other catalogs are what a
comparison of the differencers reads. Every
FITS file is gzipped at level 1 as the intake's are, the `diffimages`
row names the `.fits.gz`, and its checksum is the MD5 of the gzipped
file. Everything else, the unpublished differencer's and the naive
images, the intermediates and the input copies, is removed before the upload.
There is no setting to keep more: a variant is made again by rerunning
the job. `packet` finds a difference image's PSF and uncertainty from
the image's own file name, so a run published before the trim, with
plain FITS, or under the other differencer, reads as before. Trimming and compressing change no pixel: the
packets of four epochs published both ways had byte-equal cutouts, 781
of 781.

The manifest declares four tables:

| Table | Rows |
|---|---|
| `diffimages` | one, the published differencer's image, keyed (dataset, expid, sca, fid); `rid`, `rfid`, `field`, `jd`, the centre and four corners, `infobitssci` (`dev`'s catalog-outcome mask, one bit per differencer and sign with no PSF-fit catalog), `infobitsref` (the reference's grade), `status` 1, the file's MD5 |
| `sources` | the published differencer's positive PSF-fit catalog, mapped onto the `sources` columns exactly as the import maps `dev`'s, inside `dev`'s fit-position bounds, under `sfft` through `dev`'s database prefilter (below), then the brightest `max_sources` by flux over its error (0 keeps every source); `sumrat`, `nneg` and `nbad` from the catalog, null under `zogy` |
| `objects` | the objects this job founded: one per accepted source that matched no object of its own field or a neighbouring field as the job read them, founded in the source's own field, its id the position hash of that source |
| `memberships` | this epoch's matches, onto objects it read and onto those it founded: each with the source's offsets from the object's founding position and its flux, the membership's share of the object's sufficient sums |

**`dev`'s database prefilter**, under `diff_flavor = "sfft"` only, ports
the cut `dev`'s loader makes on SFFT's catalog: after the fit-position
bounds and before the cap, a source is kept when its `sumrat` is finite
and above `[difference.database_prefilter] sumrat_prefilter_threshold`
(0.4) and its nearest pixel is at least 2 px from every edge. A null
`sumrat` is rejected, where `dev` passes it, and the edge cut is
`dev`'s XSources rule applied here to the PSF-fit catalog. `""`
applies none of it, the raw SFFT control. `dev`'s real/bogus cut is not
there, since no score is computed. Under `sfft` the metrics'
`n_candidates` counts after the cut; under `zogy` the source set is not
prefiltered.

The stage draws `pid` from the `diffimages` identity sequence while it
reads its inputs, so the source rows carry it. A run has one published
differencer, so the other's and the naive images are never rows.
A missing PSF-fit catalog of the published differencer publishes an
empty source set with its outcome bit set (`sources` is declared valid
when empty, `empty_ok`), where `dev`'s loader skips the job. The manifest also
records the zero point and where it came from, both FWHMs, the scale
factor, the registration residuals, the catalog counts, the count of
sources before the cap, `differencer` and both differencers' source
counts, and the published files with
their plain and gzipped bytes, the gzip's seconds and what was removed.

## Association

The difference job associates its own sources
({ref}`ruling <decision-association-in-difference>`), each by its own
field ({ref}`ruling <decision-association-by-source-field>`). After the
catalog, it groups the sources the run's `[associate]` table accepts
(fit flags zero once the informational bright-footprint bit is cleared,
S/N at least `min_snr`) by the tessellation field each falls in,
wherever on the image that is. It reads the run's objects in those
fields and their neighbours in one short query, the objects every
published difference job of the run has founded there, and records that
read exactly: one `objects` input per (field, founding job) it saw, in
the manifest's `reads`, which the publisher writes to `job_inputs`.
This is the one input read at execution rather than named at launch.
It then runs `dev`'s first crossmatch pass in memory over every
accepted source: a source matches every object within `match_radius`,
and a source that matches none founds an object in its own field. The
radius is far below a field's width, so matching against the objects
read is matching against the source's own field and its neighbours.
`dev`'s second pass, where a source in a neighbouring field joins
objects only, inside the field's inclusion cone, is not taken: under it
a field no image is centred on founded nothing, and on the injected
SCA 8 footprint 0.40 of the injected sources were alerted while 0.96
were detected. Under the field rule 0.97 of the detected are alerted.

The manifest's `catalog` names `fields`: every field that gained an
object or a membership, and each one's neighbours. At publish, under
transaction-scoped locks on the run and each of those fields, taken in
ascending field order in one statement, the publisher reads the objects
founded since the job's read in those fields, by jobs not in its
recorded read. Two jobs founding either side of a boundary share a
lock, so they serialise, and no lock cycle can form. A founded object within the radius of one of them is
not inserted; its memberships go to that object, each one whose source
is within the radius of it, rebased to its origin. The manifest records
the outcome as `reconcile`. Two epochs of one field in flight at once
therefore publish one object per star, whichever finishes first giving
it its id. A membership onto an object the job read is kept as matched;
a source that a job in flight founded nearby is not added to it, as a
sequential run would have, an edge case the reconcile does not cover.

The metrics add `n_objects_read`, `n_objects_founded`,
`n_memberships` and `n_sources_out_of_field`, the accepted sources
outside the image's own field.

## Settings

The run's `[difference]` table in `rapidpipe/settings/foundation-thin.toml`
holds `max_sources` (500), `dev`'s fit-position bounds and the published
differencer, and one
subtable per `dev` ini section with `dev`'s values. The tool tables
(`[difference.sextractor_sciimage]`, `_gainmatch`, `_diffimage`,
`_diffimage_sfft`, `_diffimage_naive` and `[difference.swarp]`) copy
`dev`'s sections verbatim. The others, where a value is new with the
port or departs from `dev`:

| Setting | Value | Meaning |
|---|---|---|
| `diff_flavor` | `"zogy"` | the published differencer, `dev`'s `[ALERTS] diff_flavor`: `"zogy"` or `"sfft"`, anything else refused; `dev`'s value is `sfft`, and `zogy` is shipped because on HLWAS the raw SFFT catalog fills the cap with bright-star residuals (Measured, below) |
| `[difference.paths] python`, `[difference.sfft] python_cmd`, `activate_cmd` | empty | ZOGY and SFFT run in the stage's own interpreter; `dev` hard-codes `python3.11` and its own SFFT environment |
| `[difference.paths] bkgest_code`, `bkgest_include_dir` | `bkgest`, `/opt/rapid/share/bkgest` | bkgest as the pipeline image installs it, where `dev`'s `/code/c` tree is absent |
| `[difference.paths] work_subdirectory` | `diff` | the working directory under the attempt's prefix |
| `[difference.awaicgen] zprefimg` | empty | an override of the reference zero point; empty reads the reference's `MAGZP` |
| `[difference.zogy] astrometric_sigma` | 0.0 | ZOGY's astrometric inputs, 0.0 as `dev` overrides them |
| `[difference.sfft] run_sfft`, `crossconv_flag` | true, false | SFFT runs, without cross-convolution for these simulations, as in `dev`; under `diff_flavor = "sfft"`, `run_sfft = false` fails the settings check |
| `[difference.sumrat]` | `stamp_size` 5, `filter_size` 3, `lower_median` false | `dev`'s `[SUMRAT]`; `false` takes the mean of the two middle values of an even count, so pure noise's sumrat is about 0, where ZTF's median is biased to about −0.32 |
| `[difference.extra_catalog_cols]` | `nneg_nbad_stamp_size` 5, `pixel_cols_bkg_box` 64, `pixel_cols_bkg_filter_size` 3 | `dev`'s `[EXTRA_CATALOG_COLS]`: the `nneg` and `nbad` stamp and the local background the three columns are measured after |
| `[difference.database_prefilter] sumrat_prefilter_threshold` | 0.4 | `dev`'s `[DATABASE_PREFILTER]`, applied under `sfft` only; `""` applies no prefilter |
| `[difference.naive_diffimage] naive_diffimage_flag` | true | the naive subtraction runs, a diagnostic |
| `[difference.fake_sources] inject_fake_sources_flag` | false | fake-source injection is not ported; true is refused |
| `reference_psf` | `"measured"` | the reference PSF the differencers are given: `"measured"`, from the resampled reference's stars, or `"science"`, the science PSF for both images, for a field whose reference stars cannot be measured (the GBTDS bulge, [datasets](datasets)) |
| `[difference.statistics] clip_correction_seed` | 0 | seeds the clipped-statistics correction's random draw; negative is `dev`'s unseeded draw |

With the seed pinned, the same inputs give the same pixels and rows,
apart from the FITS `DATE` cards and bkgest's time-stamped tables. The
unseeded draw moves every clipped standard deviation by about 3e-4 and,
through the PSF-fit threshold, the source count by a few: 5,539 to
5,544 for one epoch over four runs. Two seeded executions of one epoch
on the same instance type were identical row for row. A third on a
different CPU family gave the same 5,536 sources with 2,156 rows
differing in some column, most by less than a microarcsecond; the cause
is likely floating point that depends on the CPU, and is not verified.

## Measured

On SMDC on 2026-10-21, on Batch with one vCPU and 24 GiB, 69 epochs of
field 4658155, SCA 8, W146 against the 25-frame reference took 1,091 to
1,181 s each in the container (median 1,124 s), against 1,324 to
1,369 s on a two-frame reference; the cause of the difference was not
probed. The largest child process peaked at 14.54 GiB whatever the
reference, and each job wrote 72 files, about 2.8 GB, before the trim.
On 2026-10-23, on the HLWAS data, a trimmed job published 10 objects,
247 MB, against 2,547 MB in 72 for the same epochs before; the gzip
took 7 to 9 s of a 227 s median container, the same median as before.
Uncapped, the
epochs gave 4,708 to 5,748 sources, 365,104 in all, 0.975 of `dev`'s
own catalogs' total.

Against `dev`'s night, which used a reference of 25 frames outside it,
the port's difference images correlate with `dev`'s at 0.961 to 0.978,
with a median absolute deviation of 4.79 against `dev`'s 4.87. Source
positions mostly do not coincide: about 21% of the port's sources lie
within 0.055″ of one of `dev`'s, and the two brightest-500 lists share
12%. With the same reference as `dev`, an earlier host run of one epoch
correlated with `dev`'s difference at 0.99989. The real-tool run
against fixed inputs and the IMSS comparison remain the team's gate
before operational use.

**ZOGY against raw SFFT, on the same bytes** (2026-10-24, rapid PR 418):
the same L2 arrays, reference and PSF rows differenced both ways, with
SFFT's raw positive catalog published and no prefilter.

| | ZOGY | SFFT |
|---|---|---|
| HLWAS injected, `001_0001` SCA 8 F146, passes 4 to 6 (runs 81, 88): detected of 600 injected | 542 | 256 |
| the same: detected at AB 24 / 25 | 0.97 / 0.99 | 0.61 / 0.00 |
| the same: false positives per epoch (bright-flagged) | 228 (145) | 385 (289) |
| the same: core fraction | +0.003 | +0.252 |
| OpenUniverse TDS, H158 SCA 10, ten epochs (runs 80, 89): detected of 410 evaluated | 35 | 24 |
| the same: core fraction | +0.005 | +0.005 |
| difference seconds, median (HLWAS; OpenUniverse) | 205; 292 | 219; 279 |

On HLWAS SFFT leaves about a quarter of each bright star's flux in its
core, so the 500-source cap fills with stars; on OpenUniverse its stars
subtract cleanly and the cap fills with candidates matched to no truth
row. `sumrat > 0.4` keeps 0.90 of the bright-flagged SFFT candidates on
the HLWAS sample, so the column alone does not remove them (run 96: 0.997
of 391 injected, 0.68 of 6,464 noise).

With `dev`'s prefilter on the same injected bytes (rapid PR 432, runs
103, 105 and 107 on `rapid-rebuild:76`), SFFT detects 275 of 600 against
raw SFFT's 256 and ZOGY's 542, none in the AB 25 bin (ZOGY 57 of 57),
with 388 false positives per epoch against 385 and 214. The cut keeps
about 0.7 of SFFT's candidates, but the bright-star residuals it keeps
refill the cap. On the null epoch (runs 104, 102, 106) the packets are
182, 471 and 478. The core and ring fractions are image metrics, the
same with the cut and without it, so the gate's bounds, read on ZOGY,
stand for the shipped flavour.

## Not decided here

- Source-level parity with `dev`. The two references are 25 different
  frames, so their noise differs, and most of a chip's sources sit near
  the 5σ PSF-fit threshold, where which noise peaks cross it would
  differ while the images agree; that reading fits every figure and is
  not verified. A check needs the same reference frames or injected
  sources with known positions.
- `dev`'s real/bogus score and its prefilter cut, left out of the thin
  chain: no score is computed.
- Whether the published differencer returns to `sfft`. `dev`'s pixel
  columns and its prefilter do not bring SFFT's catalog to ZOGY's on
  HLWAS (Measured), so the route is SFFT's own configuration. Under
  SFFT `n_sources_snr_gt20` sits at the cap on every epoch, so the
  gate's count check cannot see an SFFT epoch off-scale.
- Whether the naive subtraction keeps running now that only its
  outcome bits remain of it. Turning it off is a settings change with a
  science consequence, the bits.
