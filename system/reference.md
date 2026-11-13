# The reference stage

**Status: current**

`reference` coadds the L2 images its job names into one reference image
for a field, filter and SCA, catalogs the mosaic with SExtractor and,
when the run turns it on, with Photutils, and declares its tables for the
publisher. It runs `dev`'s reference
pipeline (`ppid` 12, `pipeline/referenceImageSubs.py`) in `dev`'s order
under the foundation's `run(job)` contract: `rapidpipe/stages/reference.py`
and `rapidpipe/science/reference/` on the pipeline repository's
`rebuild` branch. The [foundation](foundation) page states the records
it works within, and the [stage contract](stage-contract) page what a
stage is.

## Scope and inputs

The scope is `{"field", "fid", "sca"}`: the Roman tessellation tile,
the filter id and the first SCA among the frames. The frames are `input`
rows of product `l2files` whose key has the scope's filter, of any SCA,
each row read by its own key's SCA. With `[reference.psfcat] enabled` the
job also names the `psfs` rows of its filter and scope SCA that
`[difference] reference_psf` calls for: the science row under
`"measured"` and `"science"`, the run's set's reference row under
`"precomputed"`, and both under `"measured"` with a `reference_psf_set`
named, the set's row being the measurement's fallback. Any other product,
filter or SCA, or a PSF the settings do not call for, fails the job. The
launcher chooses the frames and the rows and records them; the stage reads
exactly those rows and their files through `prefix.get`, and never
selects frames itself.

Frames are coadded in order of `mjdobs`. Fewer than `min_frames` fails
the job; frames past `max_frames` are left out and named in the
manifest as `not_coadded`. Every frame's `FILTER`, normalised to RAPID's
spelling (`W146`, not `F146`) by the one map in
`rapidpipe.products.filters`, must be the scope's filter.

Under `[reference.selection] selection_type = "coverage"` the loop
chooses the frames by how much of the reference they cover
([loop](loop), One pass), and `min_frames` is not used: one frame is
enough when it covers enough. The stage reads the named rows' corners
(`ra1` to `dec4`), estimates their coverage on a grid every 25 px of the
mosaic, and coadds the frames whose footprint meets the reference; a
frame that misses it is skipped and named in the manifest. The geometry
is commissioning's (d586136b, ebd95254, debbc6e4), in
`rapidpipe.products.coverage`, so the loop and the stage share it.

## What it runs

Each step is a module of `rapidpipe.science.reference`:

1. **Preparation.** Each frame's HDU 1 is divided by `EXPTIME` and
   scaled to the filter's zero point by `10 ** (0.4 * (zprefimg -
   ZPTMAG))`, with an uncertainty image from the gain and read-noise
   model. With `[reference.awaicgen] use_nominal_zptmag` true, the
   `ZPTMAG` in that factor is the filter's value in the run's
   `[intake.nominal_zptmag]` table, not the frame's header value, so
   every frame of a filter gets the same scale factor; a filter missing
   from the table fails the job. The header value still feeds the grade's
   `zptmag_rms` (bit 10). This is commissioning's override (687c93b2,
   8a4a172d), for flight data whose per-frame calibration is still
   settling ({ref}`decisions <decision-nominal-zptmag>`).
2. **awaicgen** coadds the prepared frames, tile-centred, at the
   `[mosaic]` geometry, into a mosaic with its coverage and uncertainty
   maps.
3. **Measurements**: `cov5percent`, the median coverage and pixel
   uncertainty and the clipped image statistics, as `dev` computes them
   for `refimmeta`, which records them ({ref}`ruling <decision-refimmeta>`).
4. **SExtractor** runs on the mosaic with the uncertainty map as weight,
   its `MAG_ZEROPOINT` the `MAGZP` the coadd was scaled to, so the
   catalog's magnitudes are AB where `dev`'s are instrumental
   ({ref}`ruling <decision-catalog-ab-zeropoints>`), and gives the
   catalog's FWHM statistics: the mode over point sources and the
   `fwhm_percentile` percentile of the same sample.
5. **The reference PSF and the PSF-fit catalog**, with
   `[reference.psfcat] enabled` only. The PSF follows `[difference]
   reference_psf`, so the catalog uses the same kind of reference PSF as
   differencing ({ref}`ruling <decision-reference-psf-stored>`).
   `"precomputed"` takes the set's row, its MD5 checked against the row,
   its stamp an odd square with a positive sum; a per-filter set is
   computed for any orientation, so it fits awaicgen's north-up mosaic.
   `"science"` takes the science row. `"measured"` measures the PSF on the
   mosaic's covered pixels with the difference stage's measurement, the
   science row giving the stamp's size, the floor of a star's width and
   the wings; any measurement error falls back to the set's row when the
   run names one, and otherwise leaves no PSF and so no catalog. The
   science PSF is in the detector frame and the mosaic north up, and it is
   not rotated: under `"measured"` its width floor does not depend on the
   roll, but its wings do, and under `"science"` the whole stamp does. A
   set file that fails its checks, or a fallback that does, fails the job
   with exit 65. The catalog is `dev`'s Photutils PSF-fit catalog, the
   difference stage's catalog code run on the mosaic with its uncertainty
   map under `[reference.psfcat]`: a text catalog, its finder catalog, the
   joined Parquet and the fit's residual. With the PSF the stage also
   computes the two limiting magnitudes at `maglim_snr` on the mosaic's
   zero point, one from the median `flux_err` of the catalog's sources and
   one from the mosaic's clipped background noise and the PSF's noise
   pixels.
6. **The grade**: `dev`'s reference InfoBits and status (`dev` cb53d2c7,
   fdc7fa79), the bits defined in `cdf/infobitsref.txt` and their
   thresholds in `[reference.infobits]`. A bit is set when its condition
   holds; a metric that could not be computed sets none. Status is 0
   when a fatal bit (2, 5, 7, 8, 16) is set, else 1. With the catalog
   attempted, its bits are live: 5 and 6 the two limiting magnitudes, 7
   its source count, which is 0 when it was not made, and 16 a catalog not
   made, because there was no PSF or no source survived its finder. With
   `[reference.psfcat] enabled` false the four bits are never set: a
   catalog not attempted is not one that failed.
7. **The header stamp** on the mosaic and its uncertainty map: `dev`'s
   `BUNIT`, `FIELD`, `FILTER`, `COV5PERC`, `NFRAMES`, `JDSTART`,
   `JDEND`, `MAGZP`, `TOTEXPTM`, `INFOBITS` (its comment listing the set
   bits), `STATUS`, the `BIT`*nn* definitions in use and one
   `INFIL`*nnn* per frame, then `RPRUN`, `RPJOB`, `RPATTMPT` and
   `RPSTAGE` naming the run, job, attempt and stage. `ZPSOURCE`, after
   `MAGZP`, says what scaled the inputs: `header` or `nominal`. Under coverage
   selection the stamp adds commissioning's `COVFRAC` (the measured
   fraction), `COVDEPTH` (`min_coverage_depth`) and `COVTARG`
   (`min_coverage_fraction`) after the `BIT`*nn* cards.

Under coverage selection two checks bracket awaicgen, each a timed step
in `job_metrics`. Before it, `coverage_estimate` judges the named frames'
estimate against `min_coverage_fraction` with
`coverage_estimate_tolerance` (0.05) either side: below the band the job
fails at once. After it, `verify` measures the fraction of the
coverage map's pixels at `min_coverage_depth` or deeper; below
`min_coverage_fraction` the job fails. Commissioning makes the same
check on every coadd, so the stage does too; an estimate above the band
is expected to pass it. Either failure exits 65 before a manifest, the
fraction its reason, as a rejected declared input does; nothing is
published and the job's files stay under its prefix. Commissioning ends
such a job with exit 33, which the rebuild does not carry
({ref}`ruling <decision-coverage-held>`).

`MAGZP` is the filter's zero point (26.863 for W146), which the
[difference](difference) stage's gain matching reads from the file. The
job fails when awaicgen or SExtractor leaves no output, or when the
catalog has no source with a usable FWHM, where `dev` checks no exit
code.

A status 0 reference is published with its grade but not made
official: its rows load, the stage refuses its own binding, and the job
fails with its fatal bits as the reason. No difference is made against
it, as `dev` and commissioning never use a status 0 reference
(`get_best_reference_image` selects `status > 0`). A person may still
accept it with `official change`, without a rerun
({ref}`ruling <decision-reference-status-0>`). Whether a later run
builds it again is open; today a new run plans it again from the frames
it has then ({ref}`decision-open-questions`).

## Declared outputs

The files go under `ref/` in the attempt's prefix: the mosaic, its
coverage and uncertainty maps under awaicgen's names, and the
SExtractor catalog. With the PSF-fit catalog on, they also hold the PSF
the catalog used, `refimage_psf.fits`, and the catalog's
`refimage_psfcat.txt`, `refimage_psfcat_finder.txt`,
`refimage_psfcat.parquet` and `refimage_psfcat_residual.fits`. The
manifest declares these tables:

| Table | Rows |
|---|---|
| `refimages` | one, keyed (dataset, field, fid); `nframes`, `cov5percent`, the grade's `status` and `infobits`, and the stamped mosaic's MD5 |
| `refimimages` | one per coadded L2 row, (`rfid`, `rid`) |
| `refimcatalogs` | the mosaic catalog, `cattype` 1, which `packet` reads for reference-star matches; and the PSF-fit catalog, `cattype` 2, when it was made |
| `refimmeta` | one, keyed by `rfid`: `dev`'s quality measurements under `dev`'s names, `hp6` and `hp9` of the reference's centre, `mjdobsmin` and `mjdobsmax` of the coadded frames, the mosaic's statistics, the catalog's FWHM and source count; `npucatsources` the PSF-fit catalog's source count, 0 when it could not be made and null with the catalog off ({ref}`ruling <decision-refimmeta>`) |
| `psfs` | under `"measured"`, when the measurement succeeded: 18 `reference` rows, one per SCA, sharing `refimage_psf.fits` and its MD5, with `psf_set` `refimage-<field>-<filter>` in Roman's filter spelling ({ref}`ruling <decision-reference-psf-stored>`) |

The `psfs` rows bind with the reference in one change group. The loop
expects their 18 keys of every `"measured"` reference, so a measurement
that fell back to the set writes none and the manifest's `unbound`
leaves those keys out of the binding. A status 0 reference's manifest
carries `refused` with its fatal bits, and its whole binding, `psfs` keys
included, is refused.

The stage draws `rfid` from the `refimages` identity sequence while it
reads its inputs, so the child rows carry it before publication. An
imported reference keeps the source system's id as an import-only
value, and no `refimmeta` row. The manifest also records `dev`'s `refimmeta` measurements, the
JD range, the total exposure time, the zero point and `zptmag_source`
(`header` or `nominal`, as `ZPSOURCE`), and under coverage
selection `coverage`: the selected and skipped `rid`s, the estimate, its
decision and the measured fraction. With the catalog on it also records
the catalog's source count, `npsfcatsources`, its `psfcat_flag`, and the
reference PSF's record `refpsf`: the mode, the set and row it read, and
under `"measured"` the stars it was built from, whether it fell back and
the measurement's error.

## Settings

The run's `[reference]` table in `rapidpipe/settings/foundation-thin.toml`
holds one subtable per `dev` ini section, with `dev`'s values:

| Table | Holds |
|---|---|
| `[reference.selection]` | `min_frames` 2, `max_frames` 25; `selection_type` `"nframes"` (`dev`'s rule) or `"coverage"`, with commissioning's `min_coverage_depth` 1, `min_coverage_fraction` 0.5, `max_coverage_depth` 4, `max_coverage_fraction` 1.0 and `coverage_estimate_tolerance` 0.05, which `"nframes"` ignores. The flight overlay sets `"coverage"` and `max_frames` 50 and keeps commissioning's committed 0.5; IMSS's req26 ran 0.4, which the side-by-side sets by `--set` ({ref}`ruling <decision-reference-coverage>`) |
| `[reference.instrument]` | `sca_gain` 2.0, `sca_readout_noise` 9.4 |
| `[reference.mosaic]` | `naxis1`, `naxis2` 9100 (`dev` 1518042b), `cdelt1` and `cdelt2` as `dev` writes them, `rotation` 0.0; an empty `ra_center` and `dec_center` take the tile centre from the closed-form tessellation |
| `[reference.awaicgen]` | every awaicgen option `dev`'s launcher passes, the output names, and `zprefimg_<filter>` per filter with the scalar `zprefimg` 17.0 as fallback; `use_nominal_zptmag` false, commissioning's flag (8a4a172d): true scales each input by its filter's `[intake.nominal_zptmag]` value instead of its own `ZPTMAG` ([datasets](datasets): true in `flight.toml`); a run body stored before the flag has none and scales by `ZPTMAG` |
| `[reference.sextractor_refimage]` | `dev`'s `SEXTRACTOR_REFIMAGE` section verbatim; its `sextractor_mag_zeropoint` 0.0 is replaced in the job's copy by `MAGZP` at run time ({ref}`ruling <decision-catalog-ab-zeropoints>`) |
| `[reference.paths]` | the repository and tool configuration paths of the pipeline image, the tools on `PATH`, and `work_subdirectory` `ref` |
| `[reference.psfcat]` | `enabled` false in the base, so the simulations' references are unchanged; true makes the PSF-fit catalog with the PSF `[difference] reference_psf` chooses. The finder's values are `dev`'s `PSFCAT_REFIMAGE`, `min_separation` 1.5 as the difference stage's; the flight overlay turns it on with `sharphi` 1.8 ({ref}`ruling <decision-reference-psfcat-sharphi>`) |
| `[reference.fake_sources]` | `inject_fake_sources_flag` false; fake-source injection is not ported, and true is refused |
| `[reference.infobits]` | `dev`'s `REFIMAGE_INFOBITS` thresholds `t00` to `t10` (provisional, "loose enough that a normal reference image raises no bit"), `fwhm_percentile` 90, `maglim_snr` 5, `fatalinfobits` 2, 5, 7, 8, 16 |
| `[reference.statistics]` | `clip_correction_seed` 0, pinned as the difference stage's so the same frames give the same catalog; a negative value reproduces `dev`'s unseeded draw for the clipped-statistics correction |

The mosaic, the two SExtractor values and the grade carry `dev`'s
latest reference changes (2026-10-24).

## Measured

On SMDC on 2026-10-21, on Batch with one vCPU, the stage coadded 25
frames of field 4658155, SCA 8, W146 in 227 s in the container, peaking
at 1.35 GiB, and wrote 595 MB: three 196 MB maps and a catalog of 5,248
sources. Against the reference `dev` built from 25 other frames, the
mosaic's finite fraction (0.32712 against 0.32711) and `cov5percent`
(32.682 against 32.683) agree, the clipped residual after rescaling by
the zero-point ratio has median 3.2e-5 against `dev`'s own scatter of
1.3e-3, and the pixels correlate at 0.9962.

At the 9100 px mosaic a three-frame HLWAS reference (`001_0001`, SCA 8,
F146) peaks at 4.5 GiB against 2.8 GiB at 7000 px, inside the stage's
6 GiB ask, writes 331 MB a map against 196 MB, and takes 53 to 56 s,
awaicgen 22 to 23 s of it. At that pointing every covered pixel lies
inside the central 7000 px, so nothing downstream changes: the
resampled templates agree to 7e-4 DN/s. Graded by the port and by
`dev`'s own code (with its Photutils catalog made), the 288 references
whose files remain all have status 1 and the same bits both ways: bit 0
(median background above 1.0 DN/s, not fatal) on 282, bit 1 (noise
above 0.1 DN/s) on the five deep or crowded ones. The point-source mode
and the SExtractor seeing of 0.25 separate the catalog: on the thin
field's reference, CLASS_STAR above 0.8 / below 0.2 went from 411 / 1
to 1,059 / 1,447 of about 4,300, and `fwhmmedpix` reads 2.425 px where
the all-source median read 2.70; the pixels are unchanged.
References built before these changes (rapid PRs 406 and 416) carry the
all-source median under `fwhmmedpix`, status 1 and infobits 0.

## Not decided here

- Eligibility and selection under `"nframes"`: which frames a launcher
  may choose for a field. The night's reference took the first 25 epochs
  by `mjdobs` because none of `dev`'s 25 frames was in the night. Under
  `"coverage"` the frames are chosen by coverage
  ({ref}`ruling <decision-reference-coverage>`).
- When a reference is rebuilt. The loop never rebuilds a published one,
  and a reference job that failed, a coadd short of its coverage among
  them, holds its field's key until a person reruns it.
- Whether a status 0 reference is built again, and when
  ({ref}`decision-open-questions`).
- A reference PSF for a mosaic at a fixed position angle (a GBTDS
  reference with a per-SCA set at that angle): the `psfs` rows per set,
  filter and SCA allow it, but no overlay or set builds one.
- The imported reference has no `refimimages` rows, since the source
  system's rows do not name its members.
