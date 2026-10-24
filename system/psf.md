# The psf stage

**Status: DRAFT**

`psf` derives the PSF the difference stage reads for one filter and SCA
of a dataset, from the CRDS ePSF reference the dataset's own L2 file
names, and declares it as the science PSF. The reference image's PSF is
not this stage's: the difference job measures it from the resampled
reference it makes ({ref}`ruling <decision-reference-psf-measured>`).
Each image's PSF comes from that reference because it is
the calibration's PSF and what flight data will carry
({ref}`ruling <decision-psf-from-epsf>`); a simulation's rendering PSF
is not a product. The reduction from the ePSF to a pipeline PSF is new
science with no `dev` original. The stage is `rapidpipe/stages/psf.py`
on the pipeline repository's `rebuild` branch. The
[foundation](foundation) page states the records it works within, the
[stage contract](stage-contract) page what a stage is, and the
[loop](loop) page when a job of it is submitted.

## Scope and inputs

The scope is `{"dataset": ..., "file": <stem>}`, where the stem is any
one SOC calibrated file of the filter and SCA the job serves; the loop
names the first new stem of the pair. The job names no `input` rows.
It reads two things from outside the record:

- the calibrated file, from the run's `[intake] source_root`, anonymously
  when `[intake] unsigned` is true, as the [intake](intake) stage reads
  it. Only its metadata is read: the filter, the detector, the CRDS
  context it was calibrated under, and `meta.ref_file.epsf`, the ePSF
  reference it names (`crds://roman_wfi_epsf_0276.asdf` for F146 on SCA
  8 of the HLWAS simulation, under context `roman_0046.pmap`);
- that reference, fetched **by the name the file carries** (a RimTimSim
  file names none, so for `[intake] reader = "rimtimsim"` the name is the
  dataset overlay's `[psf.epsf]` entry for the filter, and the file is
  not read) from the
  CRDS server in `[psf] crds_server`, at
  `<server>/unchecked_get/references/roman/<name>`. There is no rmap
  match, no context lookup and no `crds` package: the file has already
  chosen its reference, and the stage takes that choice as given.

The reference is one ASDF file per filter and SCA, 178.6 MB. Its
`roman.psf` array has shape (3 defocus values, 3 spectral types, 9
positions, 361, 361): a 3 x 3 grid of positions on the detector,
oversampled four times, made with stpsf 2.0.0. The stage refuses the
job before a manifest when the reference's `meta.instrument.detector`
or `optical_element` is not the calibrated file's.

The reference is fetched into a temporary directory beside the job's
working directory, not into it, because everything in the working
directory is uploaded and nothing downstream reads the reference. It is
removed when the stage returns. Nothing caches it between jobs.

## The reduction

The conversion is fixed, not configured. The stage takes the in-focus
plane for a G2V star, `psf[focus 0, G2V]`, as a photutils
`GriddedPSFModel` over the reference's nine positions, the recipe
romanisim 0.14.0 uses, built directly so that romanisim is not a
dependency. It evaluates the model at the detector centre, (2048, 2048),
on `oversample x size` points per axis at sub-pixel centres, offset by
`(j + 0.5) / oversample - size / 2` from the centre, so the PSF's centre
is the stamp's centre: the central pixel for an odd `size`, the central
corner for an even one. Each `oversample x oversample` block is summed
into one pixel, and the stamp is normalised to unit sum. `oversample` is
the reference's own `meta.oversample`, 4; `size` is the one setting.

The block sum is right for these files because the stored grid holds
flux per oversampled sample, not a surface brightness. In the F146 SCA
8 reference the in-focus G2V image at the centre sums to 0.979 over its
361 x 361 samples, and the same model sampled once per detector pixel
sums to 0.066, about one sixteenth. Summing a pixel's sixteen samples
gives that pixel's flux; sampling at pixel centres would not.

The centroid is kept where the reference puts it. At the detector
centre of the F146 SCA 8 reference it sits 0.027 and 0.043 pixel from
the stamp's centre, and the stage does not re-centre it.

## Declared outputs

One FITS file under the attempt's prefix:

| File | `PSFKIND` | `psfs` key |
|---|---|---|
| `sciimage_psf_<filter>_sca<NN>.fits` | `sciimage_psf` | (dataset, fid, sca, `science`) |

and `psfs.parquet` with its row, keyed as an imported PSF is
keyed, so the difference stage reads a derived PSF exactly as it reads
a copied one. The `psfid` is drawn from the table's identity, and the
`import` stage now draws its own the same way rather than writing a
source system's id, so a derived PSF never meets an id an import wrote.

Each file's header names the reference (`EPSFREF`, the keyword `dev`'s
copied F146 files already carry), the calibrated file's CRDS context
(`CRDSCTX`), the position (`PSFX`, `PSFY`), the oversampling
(`EPSFOVS`) and the block (`EPSFBIN`). The manifest adds the focus, the
spectral type, the size, the reference's bytes, the flux the stamp held
before normalising, the centroid offset and the time of each step.

`EPSFREF` is a contract with the [intake](intake) stage: an intake
refuses a file, before a manifest, whose own `meta.ref_file.epsf` is
not the reference its science PSF names. So "each file's own
reference" is checked on every file. A PSF that names no
reference, or a file that names none, is accepted.

## Settings

| Setting | Value | Meaning |
|---|---|---|
| `[psf] crds_server` | `https://roman-crds.stsci.edu` | the CRDS server the reference is fetched from, the public server by default |
| `[psf] size` | 61 | the stamp's side in detector pixels, the `NAXIS1` of `dev`'s copied F146 science PSF |
| `[batch.memory_mib] psf` | 2,048 | the stage's memory ask on Batch |

The focus, the spectral type, the position and the block are not
settings: they are the conversion, and changing one is a change of
science.

## What it measured

On SMDC on 2026-10-23, over the HLWAS simulation.

**The stamp.** For F146 on SCA 8 the 61 x 61 stamp holds 0.9710 of the
model's flux before normalising; the reference's own 361-sample grid
holds 0.979, and a 181-pixel stamp 0.9793, so 61 pixels hold 99.15% of
what the model holds. Beside `dev`'s copied F146 PSF, which is an
ensemble over twelve sub-pixel phases:

| | Peak | Centroid offset x, y (pixel) | Encircled within 1, 2, 3, 5 pixels |
|---|---|---|---|
| derived by this stage | 0.344 | -0.027, -0.043 | 0.569, 0.719, 0.820, 0.874 |
| `dev`'s copied PSF | 0.240 | +0.094, +0.081 | 0.534, 0.711, 0.816, 0.874 |

The derived core is sharper and the wings agree.

**The F146 comparison.** Two runs differenced the same three epochs of
one pointing's SCA 8, passes four to six, against the same three-frame
reference of passes one to three under the same bound, one with `dev`'s
copied PSF and one with the derived PSF, the PSF the only change. The
residuals above S/N 20 per epoch fell from 113, 114 and 128 to 80, 79
and 75, and the fraction of the 500 kept rows above S/N 20 from 0.23 to
0.26 to 0.15 to 0.16; every kept row now clears S/N 5 (500 of 500,
against 414 to 454), and the three epochs gave 628 packets against 551.
These are artefact counts, not detections: the simulation has no
time-variable sources, and an image study of one of these epochs found
about three quarters of its packets on stars, where the science image's
PSF and the resampled reference's differ, and most of the brightest on
unmasked pixel defects, with noise accounting for essentially none. The
derived PSF's lower count is a smaller PSF mismatch at the stars, not a
cleaner image. It is within the factor of two the comparison allowed.

**The job.** Alone on Batch: the reference fetched in 3.18 s, the
calibrated file's metadata read in 2.05 s, the model built in 2.93 s,
the reduction 0.12 s and the rows 0.26 s, 10.9 s in the container
after a 186 s queue wait, at a peak of 302 MiB. The prefix holds 43.7
KB. With six fetching at once the container took 38 to 40 s; with 102
at once, 53 to 118 s, and 72 of the 102 failed on the CRDS server's
gateway timeouts (70 HTTP 504, two read timeouts) and published when
rerun in waves of 12 and 24. Over seven datasets, 109 jobs derived 109
pairs, and every intake's `EPSFREF` check held: the simulation names one
reference per filter and SCA.

## Not decided here

- **The position.** Every image's PSF is the reference's model at the
  detector centre. The reference holds a 3 x 3 grid of positions, so a
  PSF per quadrant, or one evaluated per source, is possible; which the
  difference stage should read is the plan's question.
- **The reference PSF.** Until 2026-10-24 this stage also wrote the
  science stamp as the `reference` kind. The resampled coadd's stars are
  wider than that (second-moment width 1.10 pixels against the science
  image's 0.96 on F146 SCA 8), which left the core-and-ring residual at
  every star, so the difference job now measures the reference PSF
  itself ([difference](difference)).
- **A reference-file part in the `psfs` key.** The key is (dataset,
  fid, sca, kind), with no reference name, because the simulation names
  one ePSF per filter and SCA. A dataset whose files name two
  references for one filter and SCA would see its first intake refused
  on `EPSFREF`, and that refusal is what would earn the key change.
- **The fetch.** Each job fetches the whole 178.6 MB reference for a
  42 MB array of which it reads one plane, and every dataset fetches
  its references again. A server error under a wide fan-out fails the
  job; mapping it to exit 75, which Batch retries, or reading the
  reference once per reference rather than once per job, is open.
