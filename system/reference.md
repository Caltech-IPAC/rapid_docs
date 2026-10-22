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
   and gives the catalog's FWHM statistics.
5. **The header stamp** on the mosaic and its uncertainty map: `dev`'s
   `BUNIT`, `FIELD`, `FILTER`, `COV5PERC`, `NFRAMES`, `JDSTART`,
   `JDEND`, `MAGZP`, `TOTEXPTM` and one `INFIL`*nnn* per frame, then
   `RPRUN`, `RPJOB`, `RPATTMPT` and `RPSTAGE` naming the run, job,
   attempt and stage.

`MAGZP` is the filter's zero point (26.863 for W146), which the
[difference](difference) stage's gain matching reads from the file. The
job fails when awaicgen or SExtractor leaves no output, or when the
catalog has no source with a usable FWHM, where `dev` checks no exit
code.

## Declared outputs

The files go under `ref/` in the attempt's prefix: the mosaic, its
coverage and uncertainty maps under awaicgen's names, and the
SExtractor catalog. The manifest declares three tables:

| Table | Rows |
|---|---|
| `refimages` | one, keyed (dataset, field, fid); `nframes`, `cov5percent`, `status` 1, `infobits` 0, and the stamped mosaic's MD5 |
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
| `[reference.mosaic]` | `naxis1`, `naxis2` 7000, `cdelt1` and `cdelt2` as `dev` writes them, `rotation` 0.0; an empty `ra_center` and `dec_center` take the tile centre from the closed-form tessellation |
| `[reference.awaicgen]` | every awaicgen option `dev`'s launcher passes, the output names, and `zprefimg_<filter>` per filter with the scalar `zprefimg` 17.0 as fallback |
| `[reference.sextractor_refimage]` | `dev`'s `SEXTRACTOR_REFIMAGE` section verbatim |
| `[reference.paths]` | the repository and tool configuration paths of the pipeline image, the tools on `PATH`, and `work_subdirectory` `ref` |
| `[reference.psfcat]` | `enabled` false: `dev`'s Photutils reference catalog needs a reference PSF input and is not produced; true is refused |
| `[reference.fake_sources]` | `inject_fake_sources_flag` false; fake-source injection is not ported, and true is refused |
| `[reference.statistics]` | `clip_correction_seed` -1, `dev`'s unseeded draw for the clipped-statistics correction |

Three keys hold `dev`'s values from before its latest reference changes
(the 9100-pixel mosaic and two SExtractor values), left for the stage's
own refresh from `dev`.

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
- The Photutils reference catalog, and where its PSF would come from:
  `dev`'s script that makes one is not called from `dev`'s reference
  pipeline either.
- The imported reference has no `refimimages` rows, since the source
  system's rows do not name its members.
