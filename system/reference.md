# The reference stage

**Status: DRAFT**

What the `reference` stage reads, what it runs, what it publishes, what
`register` records for it, and the settings it takes. Written 2026-09-24
from the rulings of supervisor step 8 (2026-09-24) and the inventory of
`dev`'s reference pipeline, `ppid` 12
(`pipeline/awsBatchSubmitJobs_launchSingleReferenceImagePipeline.py`,
`pipeline/referenceImageSubs.py`), planned onto the pipeline
repository's `rebuild` branch as `rapidpipe/stages/reference.py`,
`rapidpipe/science/reference/`, `rapidpipe/settings/reference.toml` and
the packaged `cdf/rapidSex*RefImage*` files. The port follows the
lead's rule of 2026-09-22: minimise differences to `dev`, and design
in, off by default, anything that can be left unused. The
[products](products) page fixes the vocabulary; this page records how
the stage meets it.

## In plain terms

`dev` builds a reference image for one field and filter by coadding a
handful of already-admitted science frames with `awaicgen`, cataloging
the coadd with SExtractor, and stamping the result with bookkeeping
keywords before registering it. The rebuild ports that chain as a
transform stage: `reference` reads an input set naming the frames to
coadd, runs the same tools in the same order, and writes one
reference-image bundle and one reference-catalog instance. It touches
no database; `register` records both afterwards, the same division
`difference` and `finalize` already use.

## Inputs

Stage `reference`, unit kind `field`, unit id `<rtid>/<filter>` (for
example `4711398/F146`): one reference per (field, filter) per run, the
filter part of the logical key so a run may build several filters of
one field. `reference` is a transform stage and declares no database
access (supervisor step 8, ruling R1, 2026-09-24).

`--inputs` is an input-set manifest listing N `l2-image` entries,
member role `image`, the delivered `.fits.gz`, all of one filter. The
stage checks each frame's `FILTER` header value against the unit's
filter, checks `N >= [selection] min_frames` (`dev` 2) and coadds at
most `[selection] max_frames` (`dev` 25) frames in manifest order;
any violation of those three checks exits 65 (ruling R2, 2026-09-24).

Which frames overlap the field is not this stage's decision: it is the
launcher's selection rule, `dev`'s `get_overlapping_l2files` --
science images of the same filter, `overlapfields @> field`, `vbest >
0`, `mjdobs` in `[start, end)`, ordered by `mjdobs` then distance from
the tile centre. That rule is recorded here because it is the rule
step 7's launcher implements to build the manifest `reference` reads;
`reference` itself does not check it and reads no database. Eligibility
and selection beyond that sentence stay not decided (ruling R2,
2026-09-24; see [specification](specification), "Not decided here").

## What it runs

The steps are `dev`'s, in `dev`'s order, one module each under
`rapidpipe.science.reference` (ruling R4, 2026-09-24):

1. **Per-frame preparation.** For each input frame: HDU 1's data is
   divided by `EXPTIME` (`BUNIT` becomes `DN/s`), then scaled to the
   filter zero point by `× 10^(0.4 × (zprefimg − ZPTMAG))`. An
   uncertainty image is built from a gain and read-noise model,
   `sqrt(|data_norm| · exptime / gain + rn²) / exptime × scale`. Both
   are written as PRIMARY-HDU FITS files carrying the frame's SCI
   header. The JD range and the total exposure time are accumulated
   across the frames as they are prepared.
2. **awaicgen.** Run from the stage's work directory over the prepared
   image and uncertainty lists, tile-centred, at the mosaic geometry in
   `[mosaic]` and 0.11 arcsec pixels:

   | Flag | Meaning |
   |---|---|
   | `-f1` | the input-image list file |
   | `-f3` | the input-uncertainty list file |
   | `-X`, `-Y` | mosaic size in pixels, `naxis1`, `naxis2` |
   | `-R`, `-D` | mosaic centre, RA and Dec |
   | `-C` | mosaic rotation |
   | `-pa` | pixel scale, arcsec |
   | `-wf` | inverse-variance weighting flag |
   | `-sf` | pixel-flux-scale flag |
   | `-sc` | simple-coadd flag |
   | `-nt` | thread count |
   | `-o1`, `-o2`, `-o3` | output mosaic image, coverage map, uncertainty image |
   | `-v` | verbose |

   awaicgen writes the mosaic image, a coverage map and an uncertainty
   image.
3. **SExtractor.** Runs on the mosaic image with the uncertainty image
   as its weight, the same convention `dev`'s
   `generateSExtractorReferenceImageCatalog` uses, against the packaged
   `SEXTRACTOR_REFIMAGE` configuration.
4. **Measurements.** `cov5percent`, the median coverage, the median
   pixel uncertainty, the clipped image statistics and the catalog FWHM
   (median, min, max, read from the SExtractor catalog as `dev`'s
   `parse_ascii_text_sextractor_catalog` does) are computed exactly as
   `dev` computes them for `refimmeta`.

Fake-source injection is not ported: it is a test-only branch in `dev`,
recorded here and left out (ruling R3, 2026-09-24).

## Outputs and the header

One `reference-image` bundle instance: primary member role `image`
(`awaicgen_output_mosaic_image.fits`), members `coverage` and
`uncertainty`. One `reference-catalog` instance, member role `catalog`
(`awaicgen_output_mosaic_refimsexcat.txt`), key `{"reference": <reference
instance>, "catalog_type": "sextractor"}` (ruling R5, 2026-09-24).

Header keywords are written on the mosaic image and the uncertainty
image as `dev`'s `addKeywordsToReferenceImageHeader` writes them:
`BUNIT`, `FIELD`, `FILTER`, `COV5PERC`, `NFRAMES`, `JDSTART`, `JDEND`,
`MAGZP`, `TOTEXPTM`, and one `INFIL`*nnn* per input frame, plus the
run-model stamp `finalize` already uses (`RUN`, `ATTEMPT`, `INSTANCE`,
`STAGE`). Both files are rewritten with astropy's `checksum=True`, so
`CHECKSUM` and `DATASUM` are recomputed (ruling R4, 2026-09-24).

Three departures from `dev` are recorded here rather than hidden in the
code: `FID` is not stamped, because it is a database id and `register`
derives it, not the stage; `[psfcat]` -- `dev`'s Photutils reference
catalog -- is designed in and off, since it needs a PSF input this step
does not produce; and fake-source injection is not ported at all
(rulings R3-R5, 2026-09-24).

## Identity

The reference-image logical key is `{"field": "<rtid>", "filter":
"<name>", "recipe": "awaicgen", "version": "<selection digest>"}`. The
selection digest is the first 16 hex characters of the SHA-256 over the
sorted constituent `l2-image` instance ids, joined by newlines, plus the
resolved settings hash: rebuilding the same selection makes another
instance of the same logical product, and a different selection makes a
new one. `refimages.version` is not this digest -- it is the legacy
per-(`field`, `fid`, `ppid`) counter the table has always carried,
allocated at registration the way [products](products) describes for
every legacy version column, and it keeps counting instances of the
logical product the way `dev`'s schema expects (ruling R5, 2026-09-24).

## Registration

`register` learns both new kinds, `rapidpipe/products/refimage.py` and
`rapidpipe/db/refimages.py` (ruling R7, 2026-09-24).

The `reference-image` registration block: `md5` (the primary member),
`status` 1, `infobits` 0 (`dev`'s TODO; no code sets bits yet), `field`
(int), `filter`, `ra_center` and `dec_center` (the mosaic centre, for
`hp6`/`hp9`), `constituents` (the ordered list of coadded `l2-image`
instance ids), `nframes`, `mjdobs_min`, `mjdobs_max`, `jd_start`,
`jd_end`, `total_exptime`, `zero_point` (`zprefimg`), `cov5percent`,
`medncov`, `medpixunc`, `npixnan`, `clmean`, `clstddev`, `clnoutliers`,
`gmedian`, `datascale`, `gmin`, `gmax`, `fwhmmedpix`, `fwhmminpix`,
`fwhmmaxpix`, `nsexcatsources`, `npucatsources` (null when `[psfcat]` is
off; its nullability is checked against the baseline and recorded),
`settings_hash`. `dev`'s `refimmeta` names are kept for the measurements
because they are the target columns. The `reference-catalog` block:
`md5`, `status` 1, `catalog_type` (`sextractor` maps to `cattype` 1,
`psf` to 2), `source_count` (ruling R6, 2026-09-24).

Registration writes four tables:

- `refimages`, one row, through `dev`'s unchanged `addRefImage`: `field`,
  `hp6`/`hp9` from the centre, `fid` from the `filters` table by name,
  `ppid` 12, `status`, `filename` (the primary member's location),
  `checksum` (`md5`), `infobits`, `svid`, then `run`/`attempt`/`instance`
  set the way `psfs.py` sets them. `vbest` stays 0; promotion is the
  step 3 ruling's job, not registration's.
- `refimmeta`, one row, through `registerRefImMeta` with the block's
  measurements.
- `refimimages`, one `(rfid, rid)` row per constituent whose
  `l2files.instance` matches an admitted frame -- a constituent without
  a matching `l2files` row fails registration, exit 65: the run must
  register its admitted frames before it can register a reference built
  from them.
- `refimcatalogs`, one row, through `registerRefImCatalog`, with `rfid`
  resolved from the reference instance (registered earlier in the same
  manifest, or already present in `refimages`), `ppid` 12, `cattype`,
  and `field`/`hp6`/`hp9`/`fid` copied from the `refimages` row.

An instance already registered is a no-op on replay, `register_manifest`'s
usual rule; conflicting content for an existing instance id is an error.
No new migration is needed: `20260923-02-refimages-instance.sql` already
covers `refimages`, and the three satellite tables are reached by `rfid`
and carry no run columns of their own, so the existing FK cleanup map
already handles them. Where a stored function the trial database lacks
is needed, it is ported inline into the register code, as `sources.py`
already does, and recorded (ruling R7, 2026-09-24).

## Settings

`rapidpipe/settings/reference.toml` holds every `dev` setting the stage
reads, taken from `awsBatchSubmitJobs_launchSingleReferenceImagePipeline.ini`
on `dev` (ruling R3, 2026-09-24):

| Setting | Default | Meaning |
|---|---|---|
| `[selection] min_frames` | 2 | fewest frames the stage will coadd |
| `[selection] max_frames` | 25 | most frames the stage will coadd; extra manifest entries beyond this are not read |
| `[instrument] sca_gain`, `sca_readout_noise` | 2.0, 9.4 | `dev`'s science ini values, as `difference.toml` |
| `[mosaic] naxis1`, `naxis2` | 7000, 7000 | mosaic size, pixels |
| `[mosaic] pixel_scale_arcsec` | 0.11 | mosaic pixel scale |
| `[mosaic] rotation` | 0.0 | mosaic rotation |
| `[mosaic] ra_center`, `dec_center` | empty, empty | empty means the tile centre from the closed-form tessellation the rebuild already ships (`RomanTessellationClosedForm`), the same lookup `crossmatch`'s cone uses |
| `[awaicgen] inv_var_weight_flag` | 0 | `dev`'s value |
| `[awaicgen] pixelflux_scale_flag` | 1 | `dev`'s value |
| `[awaicgen] simple_coadd_flag` | 1 | `dev`'s value |
| `[awaicgen] num_threads` | 2 | `dev`'s value |
| `[awaicgen]` list and output file names | `dev`'s names | `awaicgen_output_mosaic_image_file`, `_cov_map_file`, `_uncert_image_file` and the input list file names, `dev`'s values |
| `[awaicgen] zprefimg_<filter>` | per filter, `dev`'s ini | the zero point for gain matching and normalisation; a filter with no entry falls back to `zprefimg` 17.0, `dev`'s scalar default |
| `[sextractor]` | `dev`'s `SEXTRACTOR_REFIMAGE` section | params, filter and star/galaxy classifier files, the packaged `cdf/rapidSexParamsRefImage.inp`, `cdf/rapidSexRefImageFilter.conv`, `cdf/rapidSexRefImageStarGalaxyClassifier.nnw` |
| `[psfcat] enabled` | false | `dev`'s Photutils reference catalog; designed in, off, since it needs a PSF input this step does not produce |
| `[paths]` | as `difference.toml` | `rapid_sw`, `cfg_path`, and the external tools (`awaicgen`, `sextractor`) on `PATH` |
| `[fake_sources] inject_fake_sources_flag` | false | fake-source injection is not ported; true exits 64, the same convention `difference.toml` uses |

## Exit codes

| Code | When |
|---|---|
| 0 | built: the bundle and the catalog were written and the manifest published |
| 64 | a setting is missing, empty or invalid, including a true `[fake_sources] inject_fake_sources_flag` |
| 65 | the input set is not all one filter, does not meet `[selection] min_frames`, exceeds `[selection] max_frames`, or a member fails its size or SHA-256 check |
| 70 | any unclassified error, including a failure in awaicgen or SExtractor |
| 75 | not used: the stage's tools run locally, with no temporary dependency to retry |

## Local execution

```
rapidpipe stage reference --run <run-id> --unit <rtid>/<filter> --attempt <attempt-id> \
    --inputs <dir-or-s3-prefix> --outputs <dir-or-s3-prefix> \
    [--settings <toml>] [--dry-run]
```

the one invocation form every stage shares ([stage-contract](stage-contract)).
A selftest fixture is planned under `rapidpipe/selftest/fixtures/reference/`:
three tiny synthetic frames under 1 MB, a fake `awaicgen` that mean-stacks
the reformatted inputs onto a small TAN mosaic, and the existing fake
`sex` pattern; `--real-tools` runs the image's own `awaicgen` and `sex`
on the same frames. Registered in `selftest/runner.py`'s `STAGE_NAMES`
and the Makefile as `stage-reference`, the same pattern every other
stage's fixture follows (ruling R8, 2026-09-24).

## Not decided here

- Eligibility and the selection rule beyond dev's SQL: which frames a
  launcher may choose to overlap a field, and when a reference should be
  rebuilt.
- Where the reference PSF is resolved from, for the Photutils reference
  catalog `[psfcat]` designs in.
- The Photutils reference catalog itself: `dev`'s script that produces
  one, `scripts/generate_refim_psfs.py`, is not called from
  `referenceImageSubs.py` in `dev` either, and how it would be wired in
  is not decided.
- `reference_sets`: whether a named, reusable grouping of reference
  instances is needed beyond the logical key's own identity.
