# The reference stage

**Status: DRAFT**

`reference` coadds the L2 images its job names into one reference image
for a field, filter and SCA, catalogs the mosaic with SExtractor, and
declares three tables for the publisher. It runs `dev`'s reference
pipeline (`ppid` 12, `pipeline/referenceImageSubs.py`) in `dev`'s order
under the foundation's `run(job)` contract: `rapidpipe/stages/reference.py`
and `rapidpipe/science/reference/` on the pipeline repository's
`rebuild` branch. The [foundation](foundation) page states the records
it works within, and the [stage contract](stage-contract) page what a
stage is.

## Scope and inputs

The scope is `{"field", "fid", "sca"}`: the Roman tessellation tile,
the filter id and the SCA. Every input is an `input` row of product
`l2files` whose key has the scope's filter and SCA; any other product
fails the job. The launcher chooses the frames and records them; the
stage reads exactly those rows and their files through
`prefix.get`, and never selects frames itself.

Frames are coadded in order of `mjdobs`. Fewer than `min_frames` fails
the job; frames past `max_frames` are left out and named in the
manifest as `not_coadded`. Every frame's `FILTER`, normalised to RAPID's
spelling (`W146`, not `F146`) by the one map in
`rapidpipe.products.filters`, must be the scope's filter.

## What it runs

Each step is a module of `rapidpipe.science.reference`:

1. **Preparation.** Each frame's HDU 1 is divided by `EXPTIME` and
   scaled to the filter's zero point, with an uncertainty image from the
   gain and read-noise model.
2. **awaicgen** coadds the prepared frames, tile-centred, at the
   `[mosaic]` geometry, into a mosaic with its coverage and uncertainty
   maps.
3. **Measurements**: `cov5percent`, the median coverage and pixel
   uncertainty and the clipped image statistics, as `dev` computes them
   for `refimmeta`.
4. **SExtractor** runs on the mosaic with the uncertainty map as weight,
   and gives the catalog's FWHM statistics: the mode over point sources
   and the `fwhm_percentile` percentile of the same sample.
5. **The grade**: `dev`'s reference InfoBits and status (`dev` cb53d2c7,
   fdc7fa79), the bits defined in `cdf/infobitsref.txt` and their
   thresholds in `[reference.infobits]`. A bit is set when its condition
   holds; a metric that could not be computed sets none. Status is 0
   when a fatal bit (2, 5, 7, 8, 16) is set, else 1. The bits of the
   Photutils catalog and the PSF (5, 6, 7, 16) are never set, because
   this build makes neither: a catalog not attempted is not one that
   failed.
6. **The header stamp** on the mosaic and its uncertainty map: `dev`'s
   `BUNIT`, `FIELD`, `FILTER`, `COV5PERC`, `NFRAMES`, `JDSTART`,
   `JDEND`, `MAGZP`, `TOTEXPTM`, `INFOBITS` (its comment listing the set
   bits), `STATUS`, the `BIT`*nn* definitions in use and one
   `INFIL`*nnn* per frame, then `RPRUN`, `RPJOB`, `RPATTMPT` and
   `RPSTAGE` naming the run, job, attempt and stage.

`MAGZP` is the filter's zero point (26.863 for W146), which the
[difference](difference) stage's gain matching reads from the file. The
job fails when awaicgen or SExtractor leaves no output, or when the
catalog has no source with a usable FWHM, where `dev` checks no exit
code.

A status-0 reference is published and differenced against. `dev`'s
science pipeline differences against the reference it has just built,
whatever its status, and never reuses a status-0 reference
(`get_best_reference_image` selects `status > 0`); the loop builds a
field's reference once, so here the status is a recorded verdict, not a
gate.

## Declared outputs

The files go under `ref/` in the attempt's prefix: the mosaic, its
coverage and uncertainty maps under awaicgen's names, and the
SExtractor catalog. The manifest declares three tables:

| Table | Rows |
|---|---|
| `refimages` | one, keyed (dataset, field, fid); `nframes`, `cov5percent`, the grade's `status` and `infobits`, and the stamped mosaic's MD5 |
| `refimimages` | one per coadded L2 row, (`rfid`, `rid`) |
| `refimcatalogs` | one, the mosaic catalog, `cattype` 1, which `packet` reads for reference-star matches |

The stage draws `rfid` from the `refimages` identity sequence while it
reads its inputs, so the child rows carry it before publication. An
imported reference keeps the source system's id as an import-only
value. The manifest also records `dev`'s `refimmeta` measurements, the
JD range, the total exposure time and the zero point.

## Settings

The run's `[reference]` table in `rapidpipe/settings/foundation-thin.toml`
holds one subtable per `dev` ini section, with `dev`'s values:

| Table | Holds |
|---|---|
| `[reference.selection]` | `min_frames` 2, `max_frames` 25 |
| `[reference.instrument]` | `sca_gain` 2.0, `sca_readout_noise` 9.4 |
| `[reference.mosaic]` | `naxis1`, `naxis2` 9100 (`dev` 1518042b), `cdelt1` and `cdelt2` as `dev` writes them, `rotation` 0.0; an empty `ra_center` and `dec_center` take the tile centre from the closed-form tessellation |
| `[reference.awaicgen]` | every awaicgen option `dev`'s launcher passes, the output names, and `zprefimg_<filter>` per filter with the scalar `zprefimg` 17.0 as fallback |
| `[reference.sextractor_refimage]` | `dev`'s `SEXTRACTOR_REFIMAGE` section verbatim |
| `[reference.paths]` | the repository and tool configuration paths of the pipeline image, the tools on `PATH`, and `work_subdirectory` `ref` |
| `[reference.psfcat]` | `enabled` false: `dev`'s Photutils reference catalog needs a reference PSF input and is not produced; true is refused |
| `[reference.fake_sources]` | `inject_fake_sources_flag` false; fake-source injection is not ported, and true is refused |
| `[reference.infobits]` | `dev`'s `REFIMAGE_INFOBITS` thresholds `t00` to `t10` (provisional, "loose enough that a normal reference image raises no bit"), `fwhm_percentile` 90, `maglim_snr` 5, `fatalinfobits` 2, 5, 7, 8, 16 |
| `[reference.statistics]` | `clip_correction_seed` -1, `dev`'s unseeded draw for the clipped-statistics correction |

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

## Not decided here

- Eligibility and selection: which frames a launcher may choose for a
  field, and when a reference is rebuilt. The night's reference took the
  first 25 epochs by `mjdobs` because none of `dev`'s 25 frames was in
  the night.
- `[reference.statistics] clip_correction_seed` is still -1, so the
  catalog's source count varies run to run by a few sources as the
  difference stage's did before its seed was pinned.
- The Photutils reference catalog, and where its PSF would come from.
  `dev`'s reference pipeline makes one from a per-filter reference PSF
  file; without it the grade's bits 5, 6, 7 and 16 stay unset.
- The imported reference has no `refimimages` rows, since the source
  system's rows do not name its members.
