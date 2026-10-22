# The difference stage

**Status: DRAFT**

`difference` subtracts one epoch's L2 image from the reference its job
names, with ZOGY, catalogs the result, and declares the difference
image and its source set for the publisher. SFFT and the naive
subtraction run beside ZOGY as `dev` runs them, and their files stay
under the prefix for diagnosis. The stage ports the science of `dev`'s
`pipeline/awsBatchSubmitJobs_runSingleSciencePipeline.py`, refreshed to
`dev` at d6aac515, under the foundation's `run(job)` contract:
`rapidpipe/stages/difference.py` and `rapidpipe/science/difference/` on
the pipeline repository's `rebuild` branch. The [foundation](foundation)
page states the records it works within, and the
[stage contract](stage-contract) page what a stage is.

## Scope and inputs

The scope is `{"expid", "sca", "fid"}`, the epoch's key without the
dataset, which is the run's. The job names exactly four `input` rows,
read in one short transaction and fetched through `prefix.get`:

| Product | Which |
|---|---|
| `l2files` | the epoch's own row |
| `refimages` | one reference of the scope's filter, imported or made by the [reference](reference) stage; its coverage and uncertainty maps sit beside the mosaic, and its mosaic catalog (`refimcatalogs`, `cattype` 1) gives the reference FWHM |
| `psfs`, kind `science` | the science image's PSF for the scope's filter and SCA |
| `psfs`, kind `reference` | the reference image's PSF for the same filter and SCA |

The two PSFs are told apart by the `kind` in their key, read from the
row, so the stage never reads a PSF file's header to decide which is
which. Any other product, a second input of one kind, or an input whose
key is not the scope's fails the job before a manifest is written.

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

Every working file stays under `diff/` in the attempt's prefix, as
`dev` uploads its intermediates; `packet` reads the ZOGY difference
image's neighbours there (its uncertainty map, `diffpsf.fits`, the
background-subtracted science image and the gain-matched reference).
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
sources before the cap, and SFFT's outcome.

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
reference, and each job wrote 72 files, about 2.8 GB. Uncapped, the
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
