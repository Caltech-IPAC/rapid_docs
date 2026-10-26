# The intake stage

**Status: current**

The `intake` stage turns one SOC L2 file, a calibrated Roman image in
ASDF, into the L2 product the rest of the chain reads: a gzipped FITS
file in `dev`'s layout, one `l2files` row and, for one SCA of each
exposure, one `exposures` row. It is
where a run's data enter the record, so a run that starts from intake
owns every byte from the raw file to the packet. The
[foundation](foundation) page states the records it works within, and
the [stage contract](stage-contract) page what a stage is.

The stage is `rapidpipe/stages/intake.py` on the pipeline repository's
`rebuild` branch. Its conversion, `rapidpipe/science/intake.py`, is
ported from `dev`'s `pipeline/ingestL2Files.py` with `dev`'s logic
unchanged.

## Scope and inputs

A job's scope is one file of one dataset: `{"dataset": ..., "file":
<stem>}`, where the stem is the SOC file name without its
`_cal.asdf` suffix. The file itself is read from the run's source
root, `[intake] source_root`, a URL prefix given in the run's settings
overlay at `run create` and never in the shipped settings. A public
source root is read anonymously when `[intake] unsigned` is true; a
signed read is not tried after an anonymous one fails.

The job names one input by key: the `psfs` set holding the science PSF
of the file's filter and SCA, used for the limiting magnitude and for
the check that it was made from the file's own ePSF reference. The
`_wcs.asdf` sidecar SOC delivers beside each file is not read, since
the calibrated file carries the same gWCS, fit results and metadata.

## What it runs

1. Fetch `<source_root><stem>_cal.asdf` through `prefix.get`.
2. Parse the stem's program, plan, pass, segment, observation, visit,
   exposure, SCA and filter, and check them against the file's own
   observation metadata and detector. A contradiction fails the job
   before any manifest.
3. Convert with `dev`'s `build_fits_file`: a 16-HDU FITS whose primary
   header holds every scalar of the ASDF metadata as a `HIERARCH` card;
   the science array in DN with a degree-5 SIP distortion fitted to the
   gWCS, every coefficient to fifth order present; the other arrays
   scaled by their exposure-time exponent, half-precision arrays
   widened; and the tables as binary tables. The uncompressed file is
   made in a temporary directory and only the gzipped one is kept.
4. Gzip at `[intake] gzip_level`.
5. Check that the science PSF was made from this file's own ePSF
   reference: the basename of the file's `meta.ref_file.epsf` card must
   be the PSF file's `EPSFREF`, which the [psf](psf) stage writes and
   `dev`'s copied F146 files also carry. A mismatch fails the job before
   any manifest, naming both; a PSF or a file that names no reference
   is accepted.
6. Measure the limiting magnitude with the science PSF, as `import`
   does.
7. Derive the image centre, corners, tessellation field, overlapping
   fields and HEALPix indexes, as `import` does.
8. Write the rows and the manifest.

The fitted SIP reproduces the gWCS to well under the fit's own 0.1
pixel bound: on a real file, to below 1e-5 arcsec at the corners and
the centre. The difference stage reformats the science image itself,
so intake does not.

## Declared outputs

| Output | Key | Notes |
|---|---|---|
| the gzipped FITS | | under the attempt's prefix; the `l2files` row's `filename` is its URL |
| `l2files` | dataset, expid, sca, fid | the file's footprint, field, overlapping fields, HEALPix indexes, WCS columns and limiting magnitude |
| `exposures` | dataset, expid | one per exposure: `exptime`, `program_id` (the setting below) and the converted header's Roman observation identifiers, `dev`'s columns (`execution_plan`, `pass`, `segment`, `observation`, `visit`, `exposure`, `visit_id`, `observation_id`), null for a reader whose files carry none |

The manifest records the file's provenance: its observation
identifiers, romancal's version and the summary of its Gaia WCS fit
(status, geometry, matches, rms and mean absolute error, rotation),
with the conversion's bytes and step times.

**The `expid`.** `dev` draws an `expid` from a sequence keyed by the
observation date. In the foundation the key is the producer's, and a
SOC exposure's own identifier, 23 digits, fits no `integer` column, so
intake packs the identifiers that vary within a program and plan:
`pass * 10**6 + observation * 10**4 + visit * 10**2 + exposure`, each of
observation, visit and exposure below 100. The 18 SCAs of one exposure
share it, as they share `dev`'s one `Exposures` row.

**The shared `exposures` key.** Because the 18 SCAs share an
`exposures` key, only one job may expect it with no open binding. The
loop has the first intake of an exposure expect it and every other
intake of that exposure leave it out of its expects. An intake writes
the `exposures` row only when its job expects the key, so an exposure
has one row. Before this, every intake wrote it, and the 18-SCA ramp
left 102 unbound duplicates.

The `SWVERS` keyword is `job <id>`: the job names its run, and the run
its code revision.

## Settings

The run's `[intake]` table, with `dev`'s hard-coded values as keys:

| Key | Value | `dev` |
|---|---|---|
| `source_root` | the run's overlay only | |
| `unsigned` | false | |
| `reader` | `"soc-l2"` | the only format `dev` reads; `"openuniverse"` reads OpenUniverse 2024's `simple_model` ASDF through the same conversion; `"rimtimsim"` reads RimTimSim's `<stem>.fits.gz`, `dev`'s converted lite files, into the same layout with `dev`'s converter's headers, the image in DN with the file's WCS and zero point, no uncertainty or DQ HDU ([datasets](datasets)) |
| `sip_degree` | 5 | `SIPDISTORTIONDEGREE`'s default |
| `sip_max_pix_error` | 0.1 | the `to_fits_sip` argument |
| `gzip_level` | 1 | `L2GZIPLEVEL`'s default |
| `program_id` | -1 | the `SOCSIMS` program id |
| `[intake.nominal_zptmag]` | `dev`'s fallback zeropoints | used only when the file has no photometry metadata |
| `limmag_nsigma`, `limmag_clip_sigma` | 5.0, 3.0 | as `[import]` has them |
| `dq_mask_bits` | 0 | nothing masked, `dev`'s behaviour; a dataset's overlay names the bits whose pixels become NaN |
| `crpix_shift` | `[0.0, 0.0]` | the file's WCS unchanged; a dataset's measured translation, in pixels, added to `CRPIX1` and `CRPIX2` |
| `rederive_wcs` | false | the file's gWCS; true re-derives it from the file's `wcsinfo` and the distortion reference it names, before the SIP fit |
| `gaia_proper_motion` | false | the Gaia offset's stars at the catalog's `ref_epoch`, where the SOC simulations place them; true carries each star by its `pmra` and `pmdec` to the frame's mid-exposure (`MJD-OBS` plus half `EXPTIME`) with the packet stage's propagation, as flight data needs; `dev` has no such metric |

Each dataset's values, and the measurement behind each, are on the
[datasets](datasets) page. When the job names its dataset's Gaia
`catalogs` input, as the loop does once one is official, its metrics
record `gaia_dx_px`, `gaia_dy_px` and `n_gaia_stars`: the median offset
of the isolated Gaia stars on the frame, measured minus predicted
through the published WCS, a check of the WCS on every file. Under
`gaia_proper_motion` the stars are first carried to the frame's epoch,
so on flight data the offset no longer reads proper motion as WCS
(program 1049: dy −0.56 to −0.35 px at 2016.0, −0.060 to −0.038 px
propagated).

## What it measured

On one 204 MB F146 file, in a Batch container: the anonymous fetch
took 0.8 s, the conversion 2.7 s to a 421 MB FITS, gzip at level 1 5.5
s to 195 MB, the limiting magnitude 3.5 s, the rows 1.0 s, upload and
publish 1.5 s; the stage peaked at 906 MiB. On a host whose working
directory is network storage, conversion and gzip took about 4 s each.

Over the F146 ramp on SCA 8, 312 intakes ran in 17.1 to 24.6 s each,
median 20.8 s, at 910 MiB, writing 60.9 GB; their median queue wait was
144 s, because the compute environment scales up from nothing and every
job reserves the difference stage's 24 GiB. The 426 intakes of the run
all published on their first attempt.

## Not decided here

- Gzip is single-threaded and is the stage's largest step on Batch; a
  parallel compressor, or no compression, since the difference stage
  unpacks the file, would roughly halve the stage.
- Intake now asks Batch for 2 GiB, about twice its peak, and packs
  six to an instance, where it takes about twice as long as alone.
  Several files per job would cut the queue wait that dominates it.
- The `l2files` row and the PSF lookup are built by both `import` and
  `intake`; one helper would hold them once.
