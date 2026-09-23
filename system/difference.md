# The difference stage

**Status: DRAFT**

What the `difference` stage reads, what it runs, what it publishes, what
`register` records for it, and the settings it takes. Written 2026-09-23
from the port that landed on the pipeline repository's `rebuild` branch
(`rapidpipe/stages/difference.py`, `rapidpipe/settings/difference.toml`,
`rapidpipe/products/diffimage.py`, `rapidpipe/db/diffimages.py`). The
port follows the lead's rule of 2026-09-22: minimise differences to
`dev`, and design in, off by default, anything that can be left unused.
The [products](products) page fixes the vocabulary and the field list;
this page records how the stage meets them.

## In plain terms

The stage takes one detector image and the reference for its field,
subtracts one from the other with ZOGY exactly as the `dev` science
pipeline does, and writes the difference image, its uncertainty and
significance images, and four source catalogs. SFFT and a plain
subtraction also run, as in `dev`, but only ZOGY's result is registered
unless a setting says otherwise. The stage touches no database;
`register` records its manifest afterwards.

## Inputs

The stage's `--inputs` manifest is an input set: its `outputs` list the
products the attempt consumes, with their files beside it.

| Entry | Members | Registration block |
|---|---|---|
| one `l2-image` | `image`, the delivered file (gzipped or not) | as `admit` writes it; the stage reads the exposure time, the info bits, the centre and the corners |
| one `reference-image` | `image`, `coverage`, `uncertainty` | `infobits`; `rfid`, the legacy `refimages` row of a reference registered by `dev`, else null |
| one `reference-catalog` | `catalog`, the reference's SExtractor catalog | none; the stage reads its FWHM column |
| two `psf` | `psf` | none; the key's `applies_to` is `science` or `reference` |

Every member's size and SHA-256 is checked before use; a mismatch, a
missing entry or a malformed block exits 65.

## What it runs

The steps are `dev`'s, in `dev`'s order, one module each under
`rapidpipe.science.difference`. The delivered image is moved to the
primary HDU, padded to an odd size and converted to DN/s, with a
simple-model uncertainty image. SExtractor catalogs the science image for
its FWHM. The science image's SIP distortion is rewritten as PV, and
SWarp resamples the reference image, coverage map and uncertainty image
onto the science grid. bkgest subtracts the science background. Gain
matching compares SExtractor catalogs of the two images to find the
reference's scale factor and the median offsets between them; with too
few matched sources it falls back to the zero points and zero offsets.
NaNs in ZOGY's inputs are replaced and extreme artifact pixels in the
science image are repaired; the reference is shifted by the median
offsets. ZOGY runs as `dev` runs it, by subprocess. Its difference and
significance images are masked where the reference coverage is below
threshold, the replaced NaNs are restored, and negative copies are made.
An uncertainty image for the difference follows, and then SExtractor and
Photutils catalogs, positive and negative.

SFFT then runs in its own environment, and the naive subtraction after
it, each with its own catalogs. An SFFT failure is not fatal: the stage
continues and notes the failure in the execution record's `notes`.

External tools run with the stage's work directory as their current
directory and with `dev`'s file names and command lines, so each tool
sees what it saw in `dev`.

## Outputs

One `difference-image` instance for ZOGY, with members `difference`,
`uncertainty`, `significance` and `psf`, and four `source-catalog`
entries naming it: SExtractor positive and negative, Photutils positive
and negative. A Photutils catalog that could not be made has no entry;
its bit in the catalog-outcome mask says so.

With `[sfft] register_sfft` on and SFFT successful, a second
`difference-image` instance carries SFFT's result, with members
`difference`, `uncertainty`, and `psf` and `kernel` where SFFT wrote
them, and its own four catalogs. A failed SFFT run adds nothing: never a
partial bundle. The naive subtraction's files are diagnostics and never
an instance.

Every working file stays under `diff/` in the attempt's output location,
as `dev` uploads its intermediates for diagnosis.

## Registration

The difference-image entry's `registration` block, and the column each
field fills when `register` records it. The `source-catalog` block is
`{"source_count": n}`, and nothing is written for it beyond its instance
row until `load`.

| Block field | Meaning | Column |
|---|---|---|
| `centre`, `corners` | the image centre and four corners (RA, Dec), bottom-left first; the l2 instance's values, as `dev` registers the science image's | `ra0`, `dec0` to `ra4`, `dec4` |
| `catalog_outcome_bits` | `dev`'s six-bit mask, one bit per differencer and sign with no Photutils catalog | `infobitssci` |
| `infobits_science` | the l2 image's quality bits | carried, not registered |
| `infobits_reference` | the reference's info bits | `infobitsref` |
| `source_counts` | `{sextractor, photutils}` by `{positive, negative}`; null where a catalog was not made | `diffimmeta.source_counts`; the SExtractor positive count also in `nsexcatsources` |
| `registration_residual` | `x_rms`, `y_rms`: ZOGY's astrometric inputs, the `[zogy] astrometric_sigma` setting (0.0); `x_median`, `y_median`: the measured offsets applied | `dxrmsfin`, `dyrmsfin`, `dxmedianfin`, `dymedianfin` |
| `reference_scale_factor` | the gain-matching scale factor applied to the reference | `scalefacref` |
| `detection_role` | the member the catalogs were detected on | carried |
| `md5` | the primary member's MD5 | `checksum` |
| `reference_rfid` | the legacy `refimages` row, for a reference registered by `dev` | used to resolve `rfid` |

The remaining columns come from lookups and allocations:

| Column | Source |
|---|---|
| `rid`, `expid`, `sca`, `field`, `fid`, `jd` | the l2 instance's `l2files` row; `jd` is its `mjdobs` plus 2400000.5, as `dev`'s `addDiffImage` computes it |
| `rfid` | the reference instance's `refimages` row, through the `instance` column the migration `20260923-02-refimages-instance.sql` adds; for a reference registered by `dev`, the block's `reference_rfid` |
| `ppid` | the differencer: `zogy` is 15, the science pipeline's row, as in `dev`; `sfft` has no row yet and is refused |
| `hp6`, `hp9` | derived from the centre, on both tables |
| `version` | the next number for (`rid`, `ppid`) within the run |
| `svid` | the `swversions` row whose `cvstag` is the run's code revision, made on first use |
| `vbest`, `status` | 0 and 0 |
| `filename` | the primary member under the attempt's output location |
| `run`, `attempt`, `instance` | the manifest and the registering attempt, on both tables |

## Settings

`rapidpipe/settings/difference.toml` holds every `dev` setting a step
reads, with `dev`'s value, taken from `cdf/awsBatchSubmitJobs_launchSingleSciencePipeline.ini`
on `dev`. The tables below list them; the four tool tables
(`[sextractor_sciimage]`, `[sextractor_gainmatch]`,
`[sextractor_diffimage]`, `[swarp]`) are `dev`'s sections verbatim and
are not repeated here. Settings new with the port are marked.

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
| `[awaicgen] zprefimg` | 17.0 | the reference zero point gain matching uses |
| `[zogy] astrometric_uncert_x`, `astrometric_uncert_y` | 0.05, 0.05 | gain matching's fallback RMS |
| `[zogy] astrometric_sigma` | 0.0 | new: ZOGY's astrometric inputs, registered as `dxrmsfin` and `dyrmsfin`; 0.0 is `dev`'s override (lead, 2026-09-22) |
| `[zogy] post_zogy_keep_diffimg_lower_cov_map_thresh` | 0.5 | the coverage threshold for masking |
| `[zogy] zogy_sn_sr_from_uncertainty_maps` | true | ZOGY's noise arguments from the uncertainty maps |
| `[zogy] zogy_output_*_file` | `zogy_diffimage.fits`, `diffpsf.fits`, `scorrimage.fits` | ZOGY's output names |
| `[zogy] detection_role` | `significance` | new: the member ZOGY's catalogs detect on |
| `[sfft] run_sfft`, `crossconv_flag` | true, false | SFFT runs as in `dev`; cross-convolution is forced off for rimtimsim data, as in `dev` |
| `[sfft] sfft_bsmask_value`, `sfft_bsmask_radius`, `sfft_use_gainmatch_catalogs`, `sfft_use_segmentation` | `20000.0`, `30.0`, false, false | the socsims block; an empty `sfft_bsmask_value` selects `dev`'s file-name fallback |
| `[sfft] python_cmd`, `sfft_code`, `activate_cmd` | `python3.11`, `/code/modules/sfft/sfft_rapid_rimtimsim.py`, `source /sfft_env/bin/activate` | hard-coded in `dev` |
| `[sfft] register_sfft` | false | new: register SFFT's result as its own instance (lead, 2026-09-22) |
| `[sfft] detection_role` | `difference` | new: the member SFFT's catalogs detect on (the cross-convolved image with `crossconv_flag`, as in `dev`) |
| `[naive_diffimage] naive_diffimage_flag`, `naive_output_diffimage_file` | true, `naive_diffimage_masked.fits` | the naive subtraction, a diagnostic |
| `[bkgest]` | `dev`'s values | bkgest's options and output names |
| `[gainmatch]` | `dev`'s values | the gain-matching thresholds |
| `[psfcat_diffimage]` | `dev`'s values | the Photutils catalog's settings and output names |
| `[fake_sources] inject_fake_sources_flag` | false | fake-source injection is not ported; true exits 64 |
| `[statistics] clip_correction_seed` | -1 | new: seeds the clipped-statistics correction's random draw; negative is `dev`'s unseeded draw |

## Not decided here

- Who composes the input-set manifest for a production run, and the
  `psf` kind's `applies_to` key field.
- A `pipelines` row for SFFT, which its registration needs.
- The real-tool run of the stage fixture and the IMSS comparison, the
  lead's gate before operational use.
