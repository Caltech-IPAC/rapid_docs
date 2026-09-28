# The reference stage

**Status: DRAFT**

The `reference` stage coadds already-admitted science frames for one
field and filter with `awaicgen`, catalogs the coadd with SExtractor,
and stamps bookkeeping keywords on the result. It ports `dev`'s chain
as a transform stage: an input set names the frames, the tools run in
the same order, and the stage writes one reference-image bundle and one
reference-catalog instance. It declares `custody` database access: it
reads the database only for the read guard and writes no rows. `register` records both products afterwards, the same
division `difference` and `finalize` already use.

The stage is planned from the inventory of `dev`'s reference pipeline,
`ppid` 12
(`pipeline/awsBatchSubmitJobs_launchSingleReferenceImagePipeline.py`,
`pipeline/referenceImageSubs.py`), onto the pipeline
repository's `rebuild` branch as `rapidpipe/stages/reference.py`,
`rapidpipe/science/reference/`, `rapidpipe/settings/reference.toml` and
the packaged `cdf/rapidSex*RefImage*` files. Every ported stage
minimises differences from `dev` and designs in, off by default,
anything that could be left unused. The [products](products) page fixes
the vocabulary.

## Inputs

Stage `reference` has unit kind `field` and unit id `<rtid>/<filter>`
(for example `4711398/W146`). It builds one reference per (field,
filter) per run. The filter is part of the logical key, so a run may
build several filters of one field.

Filter names are RAPID's own spelling, `W146` not `F146`: FITS `FILTER`
headers and the `filters` table carry `W146`, and lookups against
`filters` match that name exactly. A unit id or manifest may give the
Roman spelling instead; it is normalised to the RAPID spelling with
`dev`'s own `roman_to_rapid_filter_names` map before any comparison or
lookup, so `4711398/F146` and `4711398/W146` name the same unit.

`--inputs` is an input-set manifest listing N `l2-image` entries,
member role `image`, the delivered `.fits.gz`, all of one filter. The
stage checks each frame's `FILTER` header value, normalised, against
the unit's filter, checks `N >= [selection] min_frames` (`dev` 2) and
coadds at most `[selection] max_frames` (`dev` 25) frames in manifest
order; any violation of those three checks exits 65.

The launcher selects overlapping frames to build the manifest, using
`dev`'s `get_overlapping_l2files`: science images of the same filter,
`overlapfields @> field`, `vbest >
0`, `mjdobs` in `[start, end)`, ordered by `mjdobs` then distance from
the tile centre. `reference` does not check this selection rule.
Eligibility and selection beyond it remain undecided (see
[specification](specification), "Not decided here").

## What it runs

The steps are `dev`'s, in `dev`'s order, one module each under
`rapidpipe.science.reference`:

1. **Per-frame preparation.** Divide HDU 1's data by `EXPTIME`
   (`BUNIT` becomes `DN/s`), then scale it to the filter zero point by
   `× 10^(0.4 × (zprefimg − ZPTMAG))`. Build an uncertainty image from
   a gain and read-noise model,
   `sqrt(|data_norm| · exptime / gain + rn²) / exptime × scale`. Both
   are written as PRIMARY-HDU FITS files carrying the frame's SCI
   header. Accumulate the JD range and total exposure time across the
   frames.
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

3. **SExtractor.** Runs on the mosaic image with the uncertainty image
   as its weight, the same convention `dev`'s
   `generateSExtractorReferenceImageCatalog` uses, against the packaged
   `SEXTRACTOR_REFIMAGE` configuration.
4. **Measurements.** `cov5percent`, the median coverage, the median
   pixel uncertainty, the clipped image statistics and the catalog FWHM
   (median, min, max, read from the SExtractor catalog as `dev`'s
   `parse_ascii_text_sextractor_catalog` does) are computed exactly as
   `dev` computes them for `refimmeta`.

## Outputs and the header

One `reference-image` bundle instance: primary member role `image`
(`awaicgen_output_mosaic_image.fits`), members `coverage` and
`uncertainty`. One `reference-catalog` instance, member role `catalog`
(`awaicgen_output_mosaic_refimsexcat.txt`), key `{"reference": <reference
instance>, "catalog_type": "sextractor"}`.

Header keywords are written on the mosaic image and the uncertainty
image as `dev`'s `addKeywordsToReferenceImageHeader` writes them:
`BUNIT`, `FIELD`, `FILTER`, `COV5PERC`, `NFRAMES`, `JDSTART`, `JDEND`,
`MAGZP`, `TOTEXPTM`, and one `INFIL`*nnn* per input frame, plus the
run-model stamp `finalize` already uses (`RUN`, `ATTEMPT`, `INSTANCE`,
`STAGE`). Both files are rewritten with astropy's `checksum=True`, so
`CHECKSUM` and `DATASUM` are recomputed.

`FID` is not stamped: it is a database id that `register` derives.
The other departures from `dev` concern optional work. `[psfcat]`,
`dev`'s Photutils reference catalog, is designed in and off because it
needs a PSF input this step does not produce. Fake-source injection,
a test-only branch in `dev`, is not ported.

Gain matching in `difference` reads `zero_point` from the reference
image's `MAGZP` header keyword. Its `[awaicgen] zprefimg` setting
remains available only as an explicit override of that header value.

## Identity

The reference-image logical key is `{"field": "<rtid>", "filter":
"<name>", "recipe": "awaicgen", "version": "<selection digest>"}`. The
selection digest is the full hex-encoded SHA-256 digest over the sorted
constituent `l2-image` instance ids, joined by newlines, plus the
resolved settings hash. Rebuilding the same selection makes another
instance of the same logical product; a different selection makes a
new product. Truncating the digest offers no benefit and adds collision
risk, so the full digest is kept.

`refimages.version` is a separate legacy per-(`field`, `fid`, `ppid`)
counter, allocated at registration as [products](products) describes
for every legacy version column. `dev`'s unchanged `addRefImage`
allocates `coalesce(max(version), 0) + 1` over the whole `refimages`
table for that triple, across all runs. The row records `run`,
`attempt` and `instance`, but the run does not bound the counter. This
corrects the earlier "within the run" wording.

A transaction-level advisory lock,
`pg_advisory_xact_lock(hashtext('refimages:<field>:<fid>:<ppid>'))`,
serialises attempts registering the same `(field, fid, ppid)`. It is
taken before `addRefImage` allocates the version and released
automatically at transaction end, preventing a race on
`MAX(version) + 1`. Concurrency beyond that lock remains undecided
(see Not decided here).

## Registration

`register` handles both new kinds through
`rapidpipe/products/refimage.py` and `rapidpipe/db/refimages.py`.

The `reference-image` registration block: `md5` (the primary member),
`status` 1, `infobits` 0 (`dev`'s TODO; no code sets bits yet), `field`
(int), `filter`, `ra_center` and `dec_center` (the mosaic centre, for
`hp6`/`hp9`), `constituents` (the ordered list of coadded `l2-image`
instance ids), `nframes`, `mjdobs_min`, `mjdobs_max`, `jd_start`,
`jd_end`, `total_exptime`, `zero_point` (`zprefimg`), `cov5percent`,
`medncov`, `medpixunc`, `npixnan`, `clmean`, `clstddev`, `clnoutliers`,
`gmedian`, `datascale`, `gmin`, `gmax`, `fwhmmedpix`, `fwhmminpix`,
`fwhmmaxpix`, `nsexcatsources`, `npucatsources`, `settings_hash`. The
block's `nsexcatsources` field maps to `dev`'s column
`refimmeta.nsxcatsources`, whose spelling differs. The measurements
keep `dev`'s `refimmeta` names because they are the target columns.
`npucatsources` is null when `[psfcat]` is off; the migration needed
for that null is described below.

The `reference-catalog` block:
`md5`, `status` 1, `catalog_type` (`sextractor` maps to `cattype` 1,
`psf` to 2), `source_count`.

Registration writes four tables:

- `refimages`, one row, through `dev`'s unchanged `addRefImage`: `field`,
  `hp6`/`hp9` from the centre, `fid` from the `filters` table by name,
  `ppid` 12, `status`, `filename` (the primary member's location),
  `checksum` (`md5`), `infobits`, `svid`, then `run` and `instance` set
  as in `psfs.py`. `attempt` is the *producing* `reference` attempt
  carried in the manifest it wrote.
  `psfs.py`, `diffimages` and `l2files` all record the *registering*
  attempt in their own `attempt` columns instead; `refimages` is the one
  exception. `vbest` stays 0; the promotion ruling governs promotion.
- `refimmeta`, one row, through `registerRefImMeta` with the block's
  measurements.
- `refimimages`, one `(rfid, rid)` row per constituent whose
  `l2files.instance` matches an admitted frame. A constituent without
  a matching `l2files` row fails registration, exit 65: the run must
  register its admitted frames before it can register a reference built
  from them.
- `refimcatalogs`, one row, through `registerRefImCatalog`, with `rfid`
  resolved from the reference instance (registered earlier in the same
  manifest, or already present in `refimages`), `ppid` 12, `cattype`,
  and `field`/`hp6`/`hp9`/`fid` copied from the `refimages` row.

Replay checks the registration block as well as `register_manifest`'s
identity and member-metadata comparison. If an already-registered
instance's stored block matches the manifest's, replay is a no-op and
writes no satellite row twice. A different block is an error:
`addRefImage` and `registerRefImCatalog` would otherwise silently update
an existing row.

Two migrations are needed. `20260923-02-refimages-instance.sql` already
covers `refimages`; `20260924-09` drops the baseline schema's `NOT NULL`
constraint on `refimmeta.npucatsources` before a null can be written.
The three satellite tables have no run column and are reached only
through their owning `refimages` row's `rfid`. That relationship alone
does not provide deletion handling. The [runs](runs) page's deletion
section fixes cleanup of a scratch run's own reference, amending its
cleanup-set sentence. Any needed stored function missing from the trial
database is ported inline into the register code, as `sources.py`
already does, and recorded.

## Settings

`rapidpipe/settings/reference.toml` holds every `dev` setting the stage
reads, taken from `awsBatchSubmitJobs_launchSingleReferenceImagePipeline.ini`
on `dev`:

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
| `[awaicgen] zprefimg_<filter>` | per filter, `dev`'s ini | the zero point this stage normalises frames to before coadding; a filter with no entry falls back to `zprefimg` 17.0, `dev`'s scalar default. Stamped as `MAGZP` on the coadd, which `difference`'s gain matching reads by default (see [difference](difference)); `difference.toml`'s own, separate `[awaicgen] zprefimg` is now an override of that header, not a second source of truth |
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

The invocation form is shared by every stage
([stage-contract](stage-contract)):

```
rapidpipe stage reference --run <run-id> --unit <rtid>/<filter> --attempt <attempt-id> \
    --inputs <dir-or-s3-prefix> --outputs <dir-or-s3-prefix> \
    [--settings <toml>] [--dry-run]
```

A selftest fixture is planned under `rapidpipe/selftest/fixtures/reference/`:
three tiny synthetic frames under 1 MB, a fake `awaicgen` that mean-stacks
the reformatted inputs onto a small TAN mosaic, and the existing fake
`sex` pattern; `--real-tools` runs the image's own `awaicgen` and `sex`
on the same frames. The fixture is registered in `selftest/runner.py`'s
`STAGE_NAMES` and the Makefile as `stage-reference`, following the other
stages' fixture pattern.

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
- Concurrency of registration beyond the advisory lock: the lock
  serialises the `(field, fid, ppid)` version allocation, but `svid`
  allocation (the latest global software-revision row) and the general
  question of two runs registering references for the same field and
  filter at once are not otherwise addressed here.
- The Roman-to-RAPID filter map exists twice, once in
  `rapidpipe/science/reference/prep.py` and once in
  `rapidpipe/products/refimage.py`; unifying the two into one place is
  left for later.
