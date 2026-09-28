# The difference stage

**Status: DRAFT**

The `difference` stage takes one detector image and the reference for
its field, subtracts them with ZOGY exactly as the `dev` science pipeline
does, and writes the difference, uncertainty and significance images
and four source catalogs. SFFT and a plain subtraction also run, as in
`dev`. The stage touches no database; `register` records its manifest
afterwards.

The stage lands on the pipeline repository's `rebuild` branch
(`rapidpipe/stages/difference.py`, `rapidpipe/settings/difference.toml`,
`rapidpipe/products/diffimage.py`, `rapidpipe/db/diffimages.py`). Every
ported stage minimises differences from `dev` and designs in, off by
default, anything that could be left unused. The [products](products)
page fixes the vocabulary and field list used here.

## Inputs

The `--inputs` manifest is an input set: its `outputs` list the products
the attempt consumes, with their files beside the manifest.

| Entry | Members | Registration block |
|---|---|---|
| one `l2-image` | `image`, the delivered file (gzipped or not) | as `admit` writes it; the stage reads the exposure time, the info bits, the centre and the corners |
| one `reference-image` | `image`, `coverage`, `uncertainty` | `infobits`; `rfid`, the legacy `refimages` row of a reference registered by `dev`, else null |
| one `reference-catalog` | `catalog`, the reference's SExtractor catalog | none; the stage reads its FWHM column |
| two `psf` | `psf` | none; each input-set entry's role, `applies_to`, is `science` or `reference` |

Every member's size and SHA-256 is checked before use; a mismatch, a
missing entry or a malformed block exits 65.

## What it runs

The steps follow `dev`'s order, one module each under
`rapidpipe.science.difference`. External tools run in the stage's work
directory with `dev`'s file names and command lines, so each tool sees
what it saw in `dev`.

The delivered image is moved to the primary HDU, padded to an odd size
and converted to DN/s, with a simple-model uncertainty image. SExtractor
catalogs the science image for its FWHM. The science image's SIP
distortion is rewritten as PV, and SWarp resamples the reference image,
coverage map and uncertainty image onto the science grid. bkgest then
subtracts the science background.

Gain matching compares the two images' SExtractor catalogs to find the
reference's scale factor and the median offsets between the images.
It uses the science image's own zero point and the reference's `MAGZP`
header keyword, stamped on the coadd by the reference stage, unless
`[awaicgen] zprefimg` overrides that value. With too few matched
sources, it falls back to these zero points and zero offsets.

NaNs in ZOGY's inputs are replaced and extreme artifact pixels in the
science image are repaired; the reference is shifted by the median
offsets. ZOGY runs by subprocess, as in `dev`. Its difference and
significance images are masked where the reference coverage is below
threshold, the replaced NaNs are restored, and negative copies are made.
The stage then makes the difference's uncertainty image and the positive
and negative SExtractor and Photutils catalogs.

SFFT then runs in its own environment, and the naive subtraction after
it, each with its own catalogs. An SFFT failure is not fatal: the stage
continues and notes the failure in the execution record's `notes`.

## Outputs

ZOGY produces one `difference-image` instance with members `difference`,
`uncertainty`, `significance` and `psf`, and four `source-catalog`
entries naming it: SExtractor positive and negative, Photutils positive
and negative. A Photutils catalog that could not be made has no entry;
its bit in the catalog-outcome mask records the failure.

`[sfft] register_sfft` is on by default: when SFFT
succeeds, a second `difference-image` instance carries its result, with
members `difference`, `uncertainty`, and `psf` and `kernel` where SFFT
wrote them, and its own four catalogs. Turning the setting off keeps
SFFT's files as diagnostics only. A failed SFFT run adds nothing either
way: never a partial bundle. Promotion chooses which registered instance
is current downstream; that choice is outside this stage. The naive
subtraction's files stay diagnostics, never registered as an instance.

Every working file stays under `diff/` in the attempt's output location,
as `dev` uploads its intermediates for diagnosis.

## Registration

`register` maps the difference-image entry's `registration` block to
columns as follows. The `source-catalog` block is `{"source_count": n}`;
only its instance row is written before `load`.

| Block field | Meaning | Column |
|---|---|---|
| `centre`, `corners` | the image centre and four corners (RA, Dec), bottom-left first; the l2 instance's values, as `dev` registers the science image's | `ra0`, `dec0` to `ra4`, `dec4` |
| `catalog_outcome_bits` | `dev`'s six-bit mask, one bit per differencer and sign with no Photutils catalog | `infobitssci` |
| `infobits_science` | the l2 image's quality bits | carried, not registered |
| `infobits_reference` | the reference's info bits | `infobitsref` |
| `source_counts` | `{sextractor, photutils}` by `{positive, negative}`; null where a catalog was not made | `diffimmeta.source_counts`; the SExtractor positive count also in `nsexcatsources` |
| `registration_residual` | `x_rms`, `y_rms`: the measured astrometric residual RMS from gain matching, not the value ZOGY itself is fed; `x_median`, `y_median`: the measured offsets applied | `dxrmsfin`, `dyrmsfin`, `dxmedianfin`, `dymedianfin` |
| `reference_scale_factor` | the gain-matching scale factor applied to the reference | `scalefacref` |
| `detection_role` | the member the catalogs were detected on | carried |
| `md5` | the primary member's MD5 | `checksum` |
| `reference_rfid` | the legacy `refimages` row, for a reference registered by `dev` | used to resolve `rfid` |

The remaining columns come from lookups and allocations:

| Column | Source |
|---|---|
| `rid`, `expid`, `sca`, `field`, `fid`, `jd` | the l2 instance's `l2files` row; `jd` is its `mjdobs` plus 2400000.5, as `dev`'s `addDiffImage` computes it |
| `rfid` | the reference instance's `refimages` row, through the `instance` column the migration `20260923-02-refimages-instance.sql` adds; for a reference registered by `dev`, the block's `reference_rfid` |
| `ppid` | the differencer: `zogy` is 15, the science pipeline's row, as in `dev`; `sfft` is 16, priority 6, script `sfft_rapid_rimtimsim.py`, its own `pipelines` row added by the migration `20260924-01-pipelines-sfft.sql` |
| `hp6`, `hp9` | derived from the centre, on both tables |
| `version` | the next number for (`rid`, `ppid`) within the run |
| `svid` | the `swversions` row whose `cvstag` is the run's code revision, made on first use |
| `vbest`, `status` | 0 and 0 |
| `filename` | the primary member under the attempt's output location |
| `run`, `attempt`, `instance` | the manifest and the registering attempt, on both tables |

## Settings

`rapidpipe/settings/difference.toml` holds every `dev` setting a step
reads, with `dev`'s value from
`cdf/awsBatchSubmitJobs_launchSingleSciencePipeline.ini` on `dev`.
The table below lists them except for the four tool tables
(`[sextractor_sciimage]`, `[sextractor_gainmatch]`,
`[sextractor_diffimage]`, `[swarp]`), which copy `dev`'s sections
verbatim. Settings new with the port are marked.

| Setting | Default | Meaning |
|---|---|---|
| `[paths] rapid_sw`, `cfg_path` | `/code`, `/code/cdf` | where the pipeline image puts the repository and its tool configuration files |
| `[paths] python` | empty | new: the interpreter for `py_zogy.py`; empty is the stage's own (`dev` hard-codes `/usr/bin/python3.11`) |
| `[paths] zogy_code` | `/code/modules/zogy/v21Aug2018/py_zogy.py` | ZOGY |
| `[paths] bkgest_code`, `bkgest_include_dir` | `bkgest`, `/opt/rapid/share/bkgest` | bkgest, on `PATH`, and its include files as the pipeline image installs them; `dev` uses `/code/c/bin/bkgest` and `/code/c/include`, absent from the image (rapid #93) |
| `[paths] sextractor`, `swarp` | `sex`, `swarp` | the tools, on `PATH` |
| `[paths] work_subdirectory` | `diff` | new: the working directory under the attempt's output location |
| `[instrument] sca_gain`, `sca_readout_noise` | 2.0, 9.4 | the socsims values |
| `[sci_image] saturation_level` | 2500000.0 | DN |
| `[sci_image] repair_extreme_artifact_pixels`, `extreme_artifact_threshold` | true, 10000.0 | artifact repair before differencing |
| `[ref_image] saturation_level` | 100000.0 | `dev` reads `[SEXTRACTOR_REFIMAGE] sextractor_SATUR_LEVEL` |
| `[awaicgen] zprefimg` | empty | an explicit override of the reference zero point gain matching uses; empty (the default) reads it from the reference image's own `MAGZP` header keyword instead (see [reference](reference)) |
| `[zogy] astrometric_uncert_x`, `astrometric_uncert_y` | 0.05, 0.05 | gain matching's fallback RMS |
| `[zogy] astrometric_sigma` | 0.0 | new: ZOGY's own astrometric inputs, always 0.0 as `dev`'s override; `dxrmsfin` and `dyrmsfin` register the measured residual RMS from gain matching instead, not this setting |
| `[zogy] post_zogy_keep_diffimg_lower_cov_map_thresh` | 0.5 | the coverage threshold for masking |
| `[zogy] zogy_sn_sr_from_uncertainty_maps` | true | ZOGY's noise arguments from the uncertainty maps |
| `[zogy] zogy_output_*_file` | `zogy_diffimage.fits`, `diffpsf.fits`, `scorrimage.fits` | ZOGY's output names |
| `[zogy] detection_role` | `significance` | new: the member ZOGY's catalogs detect on |
| `[sfft] run_sfft`, `crossconv_flag` | true, false | SFFT runs as in `dev`; cross-convolution is forced off for rimtimsim data, as in `dev` |
| `[sfft] sfft_bsmask_value`, `sfft_bsmask_radius`, `sfft_use_gainmatch_catalogs`, `sfft_use_segmentation` | `20000.0`, `30.0`, false, false | the socsims block; an empty `sfft_bsmask_value` selects `dev`'s file-name fallback |
| `[sfft] sfft_code` | `/code/modules/sfft/sfft_rapid_rimtimsim.py` | hard-coded in `dev` |
| `[sfft] python_cmd`, `activate_cmd` | empty, empty | new: empty `python_cmd` selects the stage's own interpreter, the same convention as `[paths] python`; empty `activate_cmd` runs SFFT in the stage's own environment rather than activating one. Neither is a venv gap: the base image resolves sfft 1.7.3 into the main conda environment, `/sfft_env` exists nowhere, and `dev`'s `python3.11` is an smdc-layer alias for 3.14. `dev`'s values, `python3.11` and `source /sfft_env/bin/activate`, remain selectable. |
| `[sfft] register_sfft` | true | new: register SFFT's result as its own instance, alongside ZOGY's |
| `[sfft] detection_role` | `difference` | new: the member SFFT's catalogs detect on (the cross-convolved image with `crossconv_flag`, as in `dev`) |
| `[naive_diffimage] naive_diffimage_flag`, `naive_output_diffimage_file` | true, `naive_diffimage_masked.fits` | the naive subtraction, a diagnostic |
| `[bkgest]` | `dev`'s values | bkgest's options and output names |
| `[gainmatch]` | `dev`'s values | the gain-matching thresholds |
| `[psfcat_diffimage]` | `dev`'s values | the Photutils catalog's settings and output names |
| `[fake_sources] inject_fake_sources_flag` | false | fake-source injection is not ported; true exits 64 |
| `[statistics] clip_correction_seed` | -1 | new: seeds the clipped-statistics correction's random draw; negative is `dev`'s unseeded draw |

## Fixture and selftest

`rapidpipe selftest --stage difference`, with `--real-tools`, runs as
an ordinary AWS Batch job inside the deployed pipeline image, against
its digest (rapid #103, #104, #105). This replaces the earlier
`rapid-admin` docker fixture venue. The fixture's real-tool expectations
come from a measured run and are deterministic across docker and Batch.
Catalog row counts are checked within `max(3 sources, 2%)`: SExtractor
and Photutils catalogs vary by a few sources between runs on
pixel-identical images.

On dev's pid-1105 inputs, with dev's settings of the time (gain 1.0,
read noise 8.5, ZOGY noise from image scatter), the rebuilt stage
reproduces dev's ZOGY difference to numerical equivalence: 0.93% of
pixels differ from dev's by more than 1e-3 DN, and the median relative
difference is 1.5e-6. Every difference above 0.011 DN sits within about
300 pixels of two science-image pixels of 10,000 DN or more. Dev's
artifact-repair step (`625b8dcf`, ported by the rebuild) now removes
those pixels; the comparison run predates that dev change.

Gain matching, the background subtraction, the resampled and gain-matched
reference, the naive difference and ZOGY's own PSF are identical or differ only at
float precision. With the rebuild's defaults, differences from that
same comparison come from later dev changes also ported by the rebuild:
the instrument's gain and read noise (`8428314b`) and ZOGY's noise
inputs from the uncertainty maps rather than image scatter (`df5117c3`).

The real-tool run against fixed inputs and the IMSS comparison remain
the team's gate before operational use, and that gate has not run.
