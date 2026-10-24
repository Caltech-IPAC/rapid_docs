# Datasets

**Status: DRAFT**

A dataset is one body of input the pipeline takes in, with its own
live run and its own products, since dataset is in every scientific
key ([foundation](foundation)). This page states the simulations
the rebuild has read and the flight data it holds, what each one's data are, the quirks met in
them, and what each quirk became: a key in the dataset's settings
overlay, a reader, or a line recorded and moved past. A quirk is fixed
on the overlay and not debugged to its root in every dataset. The
overlays live in the pipeline repository under
`rapidpipe/settings/datasets/`, one TOML file per dataset with a
comment per key naming the measurement that earned it; the
[foundation](foundation) page states how a run resolves them.

| Dataset | Overlay | Survey | Read since |
|---|---|---|---|
| SOC simulation r00342, the High Latitude Wide Area Survey | `hlwas-r00342.toml` | HLWAS | 2026-10-22 |
| SOC simulation r00340, the Galactic Bulge Time Domain Survey | `gbtds-r00340.toml` | GBTDS | 2026-10-24 |
| OpenUniverse 2024, the time-domain set (TDS) | `openuniverse-tds.toml` | HLTDS | 2026-10-24 |
| RimTimSim, the 2026-06-22 delivery (one bulge field, SCA 2, F087 and F213) | `rimtimsim-260622.toml` | GBTDS | 2026-10-24 |
| RimTimSim, the 2026-06-22 delivery | `rimtimsim-260622.toml` | RimTimSims | 2026-10-24 |
| Flight, program 1049 | none | | held, not yet read |

## HLWAS, r00342

STScI's SOC simulation of the wide-area survey: 54 pointings on a grid
one SCA wide, seven filters, six passes, L2 ASDF files with a
Gaia-fitted WCS and no time-variable sources, so every difference is a
null test. The ramp, the breadth run over seven filters, the fixes and
the second iteration's proofs ran on it.

| Quirk | Disposition |
|---|---|
| The L2 data-quality flags mark defects the difference stage otherwise detects | the overlay: `dq_mask_bits = 0x2110C01`, commissioning's rule without SATURATED |
| The L2 WCS sits (+0.12, −0.99) px from the simulation's own input-catalog stars, on every file | the overlay: `crpix_shift = [0.12, -0.99]`; the intake's Gaia-offset metric reads +0.127 / −0.986 px without it and +0.007 / +0.003 with it |
| Each filter's passes differ in timing | the reference bound is the midpoint of the filter's third and fourth passes, set per run |
| The last two passes' exposures are 107.5 s against 294.1 s | recorded ([foundation](foundation), Not decided here) |

## GBTDS, r00340

STScI's SOC simulation of the bulge survey, in the wide-area
simulation's key grammar, with a preview and a thumbnail PNG and a
`_wcs.asdf` sidecar beside every L2 file.

| | r00340 |
|---|---|
| Span | 2027-10-01 to 2027-10-08, 7.8 days |
| Pointings | 6, at position angle 90.46 throughout |
| Passes | 5: the colour filters once, then F146 with F087 and F213 interleaved |
| Exposure | 66.41 s, 5 resultants, every file |
| Files per filter | F146 80,082; F213 3,348; F087 3,330; F062 432; F129, F158 and F184 216 each; F106 198 |
| Epochs per pointing and SCA | F146 738 to 744, every 13.7 min; F087 and F213 31; F062 4; the others 2 |
| Processing | romancal 0.22.0, CRDS context `roman_0046.pmap`, the same ePSF reference as HLWAS |

| Quirk | Disposition |
|---|---|
| The L2 gWCS is tweakreg's spurious crowded-field match, 9 to 50 px off and different on every epoch | the intake re-derives the WCS (`rederive_wcs = true`): on one file the input catalog's stars sit at +0.030 / −0.032 px through it, 9,993 matched, against chance through the L2 gWCS |
| Under today's CRDS context the WCS step takes a distortion reference that puts the frame about 1,770 px off | the re-derivation uses the distortion reference the file names, fetched by name |
| STScI's recipe reads the L1 header, but the L2 files carry the L1 values unchanged (12 of 12 sampled) | recorded; the L1 file is not read |
| The sidecar's `wcs_l1` is the L2 gWCS moved by the 4 px reference border | recorded |
| A pointing is the visit modulo 6, so a pointing selection does not bound the epochs | recorded; a sample is a source root of chosen files |
| The data-quality flags are HLWAS's | the overlay: HLWAS's mask |
| The bulge is confusion-limited, so the reference PSF cannot be measured from its stars (none passes) | the overlay: `[difference] reference_psf = "science"`, the science PSF for both images |
| With the science PSF on the reference, 346 to 418 core-and-ring residuals per epoch above S/N 20 | recorded with its gallery; this dataset's next measurement |
| The difference job takes 820 s, 3.5 times HLWAS's, on 9,000 candidates per epoch | recorded |
| The input-catalog tiles over the bulge are stars only, 700 MB and 7.7 million rows each | recorded |
| The Gaia archive returns at most 50,000 rows a job, silently | recorded; the cone is fetched in sub-boxes with the count checked (256,209 rows) |

One pointing's SCA 8, nine F146 epochs, ran through the whole chain:
the reference from the first six, three epochs differenced, 515
packets on the topic, every check clean.

## OpenUniverse TDS

The OpenUniverse 2024 time-domain simulation, romanisim's
`simple_model` images. STScI's copy is ASDF, 13,256 files over seven
filters in one patch of about 0.27 deg²; IRSA's public release holds the
whole sequence as FITS, 2.06 million files.

- **The pointing is a row of the observing sequence**, whose date is
  the file's exposure start. A visit runs all seven filters over 2.7
  days; visits come every 5 days. A point in the patch has 106 images
  per filter at the median.
- **The truth is in every file**: galaxies, point sources and
  transients (one SCA held 164 transients, 113 core-collapse, 30 SN Ia,
  20 SN Iax, at redshift 0.7 to 2.8). IRSA's index per image gives each
  object's pixel position and realised flux, so completeness is a join
  of each difference image's candidates to its file's transient rows.
  It complements injection: real hosts, light curves and cadence,
  where injection keeps dense control. It comes after HLWAS injection.

| Quirk | Disposition |
|---|---|
| The tree is a plain mapping, not a data model; `data` is float64 counts per exposure, `dq` all zero | a reader of its own: `[intake] reader = "openuniverse"`, an adapter onto the SOC reader's conversion |
| The WCS takes one-based pixels: stars sit at (−1.16, −1.06) px through it | the overlay: `crpix_shift = [-1, -1]`; the truth then sits within 0.0016 px |
| The file's zero point is photons to counts, not AB | the overlay: the AB zero points for counts per second per filter |
| `err` equals `data` on 90% of pixels | recorded; nothing reads it |
| The gWCS cannot be inverted by today's gwcs | recorded; only the forward transform is used, matched by the SIP fit to 1.5e-9″ |
| No ePSF reference is named | the psf stage draws the science PSF with galsim.roman, the simulation's own model, for the file's filter and SCA (`[intake] reader` dispatches it); its centroid sits (−0.16, −0.13) px from the stamp's centre in H158 |
| The file names a pointing, not a visit, exposure and pass | the loop lists `<filter>/` in the legacy spelling for the pipeline's filter name; a pointing is the observing sequence's row, the `expid`; no passes |
| Transients live through the first visits: 348 of 761 lit transient rows in the sample have light in a reference frame | the reference stays the first visits under `before_mjd`; the count judges only transients that start after its last frame with no light in it, and reports the rest apart |
| No Gaia stars in the simulation, and the packet stage needs a catalog | the run's catalog is the truth's star rows on Gaia's schema; the intake's WCS metric reads them, (−0.08, −0.07) px |
| Every difference fills dev's cap of 500 sources (2,077 to 3,682 candidates, 261 to 500 kept above S/N 20) | recorded; it sets the faint end of the count, the next measurement |
| The gain match scales the reference by 2.2 (HLWAS 0.99) | recorded; the flux of the subtracted transients is right to 0.95 |

The chain runs end to end under the reader. The sample is H158 on one
SCA, whose live transients are the brightest of the seven filters, in
one field 27 in-season images share: a reference from the first six
visits and ten epochs across the season and the late visits, every job
published on its first attempt. Counted against the truth per image, the
evaluated transients are detected at 1.0 to AB 24, 0.8 at 24.5 and 0.5
at 25, then the source cap ends the count. The run predates
association by the source's field, so every alerted one is in its
image's own field and 16 of the 35 detections, outside it, were not
alerted; the field rule makes such a detection alertable. The chain
has been rerun under it only with SFFT's raw catalog published (24 of
the 410 detected, every one alerted; [difference](difference),
Measured), so ZOGY under the field rule is not measured here. It is a different test from HLWAS injection, which
detects 0.94 to 0.98 to AB 25 on sources placed at will. The runbook's
part 12 step 3 holds the numbers.

## RimTimSim, 2026-06-22

TRExS's RimTimSim simulator, one Galactic-bulge field (`dev`'s field
4682737) on SCA 2 in F087 and F213, 263 files read as `dev`'s converted
`_lite.fits.gz` files: F087 132 and F213 131, every exposure 54.72 s,
the dithers within 0.69 by 0.61 arcsec and the rotation 29.098° on
every file.

| Quirk | Disposition |
|---|---|
| The files are FITS, the image in DN with a TAN-SIP WCS and a zero point (`ZPTMAG`, 25.8573 in F213 and 26.2982 in F087), no uncertainty and no DQ | a reader of its own: `[intake] reader = "rimtimsim"` writes the SOC layout with `dev`'s converter's headers; a DQ mask is refused, NaN stay NaN; a file not in DN, without `ZPTMAG`, or whose filter or SCA contradicts its name is refused |
| The file name is the exposure, with no visit or pass | the loop lists the flat prefix; a pointing is the exposure number, the `expid`; no passes |
| The WCS sits (+0.052, +0.060) px from 588 Gaia DR3 stars | recorded; no `crpix_shift` |
| No ePSF reference is named; `dev` uses a WebbPSF library file this account cannot read | the overlay's `[psf.epsf]`: the CRDS references context `roman_0077` answers for WFI02 at the field's start, `roman_wfi_epsf_0280` (F213) and `0266` (F087); F213's leaves a residual 0.024 of the peak inside 8 px on 60 isolated stars |
| `dev` transposes the science PSF for this dataset | not built: the F213 stamp is within 0.0017 of its own transpose, and the residual moves from 0.024 to 0.022 transposed |
| Written at gain 1, read noise 11, rate saturation 1.1e6 DN, no cosmic rays or bad pixels | the overlay: `dev`'s rimtimsims values, and the artefact repair off, since its threshold is below the stars' cores |
| The reference stars measure (100 used of 160 passing, σ 1.32 px) | `reference_psf` stays `"measured"` |

The reader is proven on one file; the chain has not yet run on this
dataset.

## Flight data, program 1049

The first flight images held are program 1049, "RAPID CAR-198
Implementation" (observed 2026-10-24 10:40 to 11:10 UTC, F062 and F158,
288 L2 rows at MAST): four dithered F158 epochs of WFI02, observation 2
visit 1, about 208 MB each, copied once into the inputs bucket under
`flight-1049/` with a manifest. They are SOC L2 ASDF files and open as
such; WFI02 was taken because every WFI01 row of the program names a
placeholder guide star. No run has read them yet.

## RimTimSim, the 2026-06-22 delivery

TRExS's Roman time-domain image simulator: one Galactic-bulge field
(`dev`'s 4682737, one tessellation field), SCA 2 only, F087 (132
exposures) and F213 (131) from 2027-02-14 to 2027-04-24, 54.72 s each,
dithers within 0.7″ and one roll angle. The rebuild reads `dev`'s
converted `lite` files, `rimtimsim_WFI_<filter>_SCA02_<exposure>_lite.fits.gz`
(the source prefix is the run's `intake.source_root`), the exposure
number GBTDS's. The only truth delivered is the 2025-05-13 delivery's
metadata: an input catalog of 4.97 million stars, injected-parameter
tables and time series per filter.

| Quirk | Disposition |
|---|---|
| A FITS file, not ASDF: the image in DN at gain 1, no ERR or DQ, NaN present | a reader of its own: `[intake] reader = "rimtimsim"`, `dev`'s header builders onto the SOC layout |
| The file names no ePSF reference | the overlay's `[psf.epsf]`: CRDS's answer under `roman_0077` for WFI02 per filter ({ref}`decisions <decision-rimtimsim-epsf>`) |
| `dev` transposes the science PSF for this simulation | measured on one epoch: core −0.0694 → −0.0688, ring −0.0339 → −0.0385; not taken |
| `dev`'s artefact repair threshold (10,000 DN/s) is below the stars' cores | the overlay: off, with `dev`'s rimtimsims gain, read noise and saturation |
| The WCS | right as converted: Gaia DR3 at +0.03 to +0.12 / −0.01 to +0.08 px; no `crpix_shift` |
| F213's differences over-subtract star cores (core −0.050 to −0.075, 10k to 13k negative candidates above S/N 20 per epoch) | recorded; the quality gate holds those sets; the next measurement for this dataset |
| Every epoch fills the 500-source cap, and a difference takes 28 to 72 min | recorded |
| The 2025-05-13 truth's times and star positions match the images, its injected signal does not; its dim-EB time series carry the blended-EB ids | recorded; no completeness until a truth for this delivery exists |

The sample is the first ten frames of each filter as the reference
(`before_mjd = 61455.3`, `dev`'s bound) and the next five epochs. Both
filters ran end to end, every job on its first attempt and every check
clean: F087 1,818 packets on the topic, F213 1,499 with one set held by
the gate. The runbook's part 13 step rimtimsim-reader holds the numbers.

