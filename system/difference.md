# The difference stage

**Status: DRAFT**

`difference` subtracts one epoch's L2 image from the reference its job
names, with ZOGY, catalogs the result, and declares the difference
image and its source set for the publisher. SFFT and the naive
subtraction run beside ZOGY as `dev` runs them, for their outcome bits;
their files are not published. The stage ports the science of `dev`'s
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
coverage threshold; peak 20 to 3,500 DN/s, no neighbour within 14 pixels,
the whole 31-pixel stamp usable, and a second-moment width between the
science PSF's and 0.4 pixel more, since resampling only widens a star
while defect pixels are narrower and galaxies wider), builds an
effective PSF from the brightest 100 (`EPSFBuilder`, oversampling 4),
evaluates it at the pixel centres of a 61-pixel stamp re-centred to
0.01 pixel and normalised, and gives that to ZOGY, SFFT and the naive
catalogs as the reference PSF. Fewer than ten stars stops the job with
exit 65 and `refpsf: N stars, 10 needed` on the job row; there is no
fallback. The stamp is published as `refimage_psf.fits.gz`, and the
manifest's `metrics` hold `refpsf_sigma_px`, `refpsf_stars`,
`sci_psf_sigma_px` and `psf_centroid_offset_px` (the reference stamp's
centroid minus the science stamp's). On run 17's pass 4 reference the
measurement takes 4.6 s and gives 1.080 pixels from 38 stars, against
the science ePSF's 0.947.

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
their own catalogs; an SFFT failure is recorded in the manifest and is
not fatal.

## Declared outputs

The stage publishes, under `diff/` in the attempt's prefix, the files
that a person or the packet stage reads, and nothing else
({ref}`ruling <decision-difference-trimmed>`). `dev` uploads every working file
for diagnosis; on the HLWAS ramp that was 72 files and 2.5 GB a job,
89% of the run's bytes. What is kept, and the reader that earns it:

| File | Why it is kept |
|---|---|
| `zogy_diffimage_masked.fits.gz` | the difference; the `diffimages` row names it, and `packet` reads it for the difference cutout and forced photometry |
| `zogy_diffimage_uncert_masked.fits.gz` | its uncertainty, read by forced photometry |
| `awaicgen_output_mosaic_cov_map_resampled.fits.gz` | the mask: the resampled reference coverage map the difference is masked with |
| `zogy_diffimage_masked_psfcat.parquet` | the catalog: ZOGY's positive PSF-fit catalog, uncapped, of which `sources` is the capped set |
| `diffpsf.fits.gz` | the difference's PSF, for forced photometry on the difference |
| `refimage_psf.fits.gz` | the reference PSF the job measured and gave ZOGY |
| `bkg_subbed_science_image.fits.gz` | forced photometry on the science image, and the science cutout |
| `awaicgen_output_mosaic_image_resampled_gainmatched.fits.gz` | the template cutout |

The first four are the ruling's: the difference, its uncertainty, the
mask and the catalog. Three of the others are what `packet` reads, and
the reference PSF is the job's own measurement, kept for whoever checks
the subtraction (15 KB). Every
FITS file is gzipped at level 1 as the intake's are, the `diffimages`
row names the `.fits.gz`, and its checksum is the MD5 of the gzipped
file. Everything else, the SFFT and naive products, the negatives,
the intermediates and the input copies, is removed before the upload.
There is no setting to keep more: a variant is made again by rerunning
the job. `packet` reads a difference image's neighbours with the same
suffix as the image, so a run published before the trim, with plain
FITS, reads as before. Trimming and compressing change no pixel: the
packets of four epochs published both ways had byte-equal cutouts, 781
of 781.

The manifest declares two tables:

| Table | Rows |
|---|---|
| `diffimages` | one, the ZOGY image, keyed (dataset, expid, sca, fid); `rid`, `rfid`, `field`, `jd`, the centre and four corners, `infobitssci` (`dev`'s catalog-outcome mask, one bit per differencer and sign with no PSF-fit catalog), `infobitsref`, `status` 1, the file's MD5 |
| `sources` | the ZOGY positive PSF-fit catalog, mapped onto the `sources` columns exactly as the import maps `dev`'s, the brightest `max_sources` by flux over its error (0 keeps every source) |

The stage draws `pid` from the `diffimages` identity sequence while it
reads its inputs, so the source rows carry it. A run has one
differencer, so the SFFT and naive images are never published as rows.
A missing ZOGY PSF-fit catalog publishes an empty source set with its
outcome bit set, where `dev`'s loader skips the job. The manifest also
records the zero point and where it came from, both FWHMs, the scale
factor, the registration residuals, the catalog counts, the count of
sources before the cap, SFFT's outcome, and the published files with
their plain and gzipped bytes, the gzip's seconds and what was removed.

## Settings

The run's `[difference]` table in `rapidpipe/settings/foundation-thin.toml`
holds `max_sources` (500) and `dev`'s fit-position bounds, and one
subtable per `dev` ini section with `dev`'s values. The tool tables
(`[difference.sextractor_sciimage]`, `_gainmatch`, `_diffimage`,
`_diffimage_sfft`, `_diffimage_naive` and `[difference.swarp]`) copy
`dev`'s sections verbatim. The others, where a value is new with the
port or departs from `dev`:

| Setting | Value | Meaning |
|---|---|---|
| `[difference.paths] python`, `[difference.sfft] python_cmd`, `activate_cmd` | empty | ZOGY and SFFT run in the stage's own interpreter; `dev` hard-codes `python3.11` and its own SFFT environment |
| `[difference.paths] bkgest_code`, `bkgest_include_dir` | `bkgest`, `/opt/rapid/share/bkgest` | bkgest as the pipeline image installs it, where `dev`'s `/code/c` tree is absent |
| `[difference.paths] work_subdirectory` | `diff` | the working directory under the attempt's prefix |
| `[difference.awaicgen] zprefimg` | empty | an override of the reference zero point; empty reads the reference's `MAGZP` |
| `[difference.zogy] astrometric_sigma` | 0.0 | ZOGY's astrometric inputs, 0.0 as `dev` overrides them |
| `[difference.sfft] run_sfft`, `crossconv_flag` | true, false | SFFT runs, without cross-convolution for these simulations, as in `dev` |
| `[difference.naive_diffimage] naive_diffimage_flag` | true | the naive subtraction runs, a diagnostic |
| `[difference.fake_sources] inject_fake_sources_flag` | false | fake-source injection is not ported; true is refused |
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

## Not decided here

- Source-level parity with `dev`. The two references are 25 different
  frames, so their noise differs, and most of a chip's sources sit near
  the 5σ PSF-fit threshold, where which noise peaks cross it would
  differ while the images agree; that reading fits every figure and is
  not verified. A check needs the same reference frames or injected
  sources with known positions.
- sumrat, real/bogus and the extra SFFT catalog columns, and `dev`'s
  loader prefilter, left out of the thin chain.
- Whether SFFT and the naive subtraction keep running now that only
  their outcome bits remain of them. Turning them off is a settings
  change with a science consequence, the bits.
