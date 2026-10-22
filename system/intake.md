# The intake stage

**Status: DRAFT**

The `intake` stage turns one SOC L2 file, a calibrated Roman image in
ASDF, into the L2 product the rest of the chain reads: a gzipped FITS
file in `dev`'s layout, one `l2files` row and one `exposures` row. It is
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
of the file's filter and SCA, used for the limiting magnitude. The
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
5. Measure the limiting magnitude with the science PSF, as `import`
   does.
6. Derive the image centre, corners, tessellation field, overlapping
   fields and HEALPix indexes, as `import` does.
7. Write the rows and the manifest.

The fitted SIP reproduces the gWCS to well under the fit's own 0.1
pixel bound: on a real file, to below 1e-5 arcsec at the corners and
the centre. The difference stage reformats the science image itself,
so intake does not.

## Declared outputs

| Output | Key | Notes |
|---|---|---|
| the gzipped FITS | | under the attempt's prefix; the `l2files` row's `filename` is its URL |
| `l2files` | dataset, expid, sca, fid | the file's footprint, field, overlapping fields, HEALPix indexes, WCS columns and limiting magnitude |
| `exposures` | dataset, expid | one per exposure |

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
intake of that exposure leave it out of its expects. Every intake still
writes the row, so 17 of each exposure's 18 rows are unbound
candidates.

The `SWVERS` keyword is `job <id>`: the job names its run, and the run
its code revision.

## Settings

The run's `[intake]` table, with `dev`'s hard-coded values as keys:

| Key | Value | `dev` |
|---|---|---|
| `source_root` | the run's overlay only | |
| `unsigned` | false | |
| `sip_degree` | 5 | `SIPDISTORTIONDEGREE`'s default |
| `sip_max_pix_error` | 0.1 | the `to_fits_sip` argument |
| `gzip_level` | 1 | `L2GZIPLEVEL`'s default |
| `program_id` | -1 | the `SOCSIMS` program id |
| `[intake.nominal_zptmag]` | `dev`'s fallback zeropoints | used only when the file has no photometry metadata |
| `limmag_nsigma`, `limmag_clip_sigma` | 5.0, 3.0 | as `[import]` has them |

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
- Intake peaks at under a twentieth of what its job definition
  reserves. A smaller reservation for intake would pack many more per
  instance, and several files per job would cut the queue wait that
  dominates it.
- Whether an intake that does not expect the `exposures` key should
  write the row at all.
- The `l2files` row and the PSF lookup are built by both `import` and
  `intake`; one helper would hold them once.
