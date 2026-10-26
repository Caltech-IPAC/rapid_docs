# Measurements

**Status: current**

The pipeline's code and settings carry constants that were set by a
measurement made by hand on one image or one run. This page states each
of those measurements once, with its sample, its date and the numbers
it found, so a comment in the code can point here rather than to a
working file no repository holds. A constant's current value is the
code's; where the code chose a value other than the measurement's, the
section says so. A later measurement that changes a constant replaces
its section's text and names the change.

Every section below was measured on the SOC HLWAS simulation r00342,
filter F146, SCA 8, pointing `001_0001` (pass 4 is exposure `4040101`),
unless it says otherwise. Pixels are 0-based, x along columns, and
offsets are measured minus predicted.

(measurement-difference-images)=
## What run 17's difference detections were

Measured 2026-10-23 on run 17 (dataset `r00342-ep1`), pass 4 (difference
job 2455) and pass 5 (job 2456), by reading the products directly. It
is the measurement the difference job's quality numbers
(`rapidpipe/science/difference/metrics.py`) and the run inspector's
pictures (`scripts/inspect_run.py`) were written to make by code on
every job.

- **The detections were not noise.** Of pass 4's 500 kept sources (the
  cap, from 1,035 candidates, the faintest at S/N 5.98), 367 sat on a
  reference source and 74% lay within 3 px of a star found on the
  reference (40 to 90 px shifted controls: 0.3%). Gaussian noise gives
  about 0.02 of them. The difference's noise was right: robust sigma
  0.0545 against the uncertainty image's median 0.0550, difference over
  uncertainty 0.989.
- **Registration was not the cause.** Over 584 isolated stars,
  science minus reference was −0.015, +0.016 px with no rotation or scale
  term above 0.003 px across the frame.
- **The residual was a PSF mismatch.** The reference's stars were 15%
  wider than the science's (second-moment sigma 1.108 against 0.959 px,
  peak over flux 0.158 against 0.293), while ZOGY was given one PSF for
  both. Every compact star left a positive core inside a negative ring.
- **Pixel defects dominated the bright end.** Of the 80 sources above
  S/N 20, 30 were high-uncertainty clusters, 5 single-pixel spikes and
  12 on holes in the reference. Four of the 30 brightest "stars" on the
  reference were single-pixel spikes with nothing in the science.
- **The pattern repeated per epoch.** 56% of pass 5's sources lay within
  3 px of a pass 4 source.

The star measurement behind the residual and registration numbers, and
the constants of `metrics.py` it set:

| Constant | Value | The measurement |
|---|---|---|
| `LIST_STARS` | 2000 | DAOStarFinder at 8 sigma, FWHM 2.6 px, on the resampled reference found 3,881; the 2,000 brightest by flux were kept |
| `TOP_STARS` | 30 | the brightest 30 of those |
| `ISOLATION_PX` | 12.0 | no other of the 2,000 within 12 px |
| `MARGIN_PX` | 40 | 40 px from every edge |
| `CORE_RADIUS_PX`, `RING_RADIUS_PX` | 2.5, 6.0 | core r < 2.5 px; ring 2.5 to 6 px |
| `APERTURE_PX`, `SKY_ANNULUS_PX` | 5.0, (8.0, 12.0) | star flux in 5 px, local background from 8 to 12 px |
| `CENTROID_SIGMA_PX`, `CENTROID_HALF` | 1.5, 7 | Gaussian-weighted iterative centroid, sigma 1.5 px, 15 × 15 window, on both images |
| `ON_STAR_PX` | 3.0 | "on a star": within 3 px of a reference source |
| `BRIGHT_SNR` | 20.0 | the bright end: fit S/N above 20 |
| `DEFECT_SIGMA_PX` | 0.8 | not measured here: the code's floor that sets aside the single-pixel spikes found among the top 30 |

Over the 26 real stars of the top 30, pass 4: core fraction +0.030 and
ring fraction −0.027 of the star's flux, science minus reference centroid
−0.017, +0.014 px (MAD 0.010, 0.013), flux ratio 1.011. The bright
footprint's constants come from run 46 and are stated in `metrics.py`
itself.

The pictures: the whole difference image downsampled by keeping the
largest-magnitude pixel of each 8 × 8 block (so noise looks stronger than
block means), stretched to ±5 sigma with the packets overplotted; and a
gallery of the 30 brightest reference stars, science, reference and
difference side by side. `inspect_run.py` makes both for the first and
last epoch and every epoch whose bright count is twice the run's median.

(measurement-wcs-offset)=
## The WCS against the stars

Measured 2026-10-24 on the pass 4 calibrated file
(`r0034201004001004001_0001_wfi08_f146_cal`). The L2 file's WCS places
stars a constant offset from where they are. It is the measurement behind
the HLWAS overlay's `[intake] crpix_shift = [0.12, -0.99]` and the
intake's Gaia offset metric (`rapidpipe/science/astrometry.py`).

- The simulation's own input catalog (its point sources, Gaia DR3
  positions at epoch 2016.0 with no proper motion) through the file's
  gWCS against 61 measured centroids: 30 matched, offset +0.116, −0.989 px,
  scatter 0.029 and 0.023 px, the same at match radii 1.5, 3 and 5 px;
  shifted controls matched none. A linear fit leaves slopes under 0.01 px
  per 1,000 px, so it is a translation, not a rotation or scale.
- The same through the intake FITS file's SIP WCS: +0.116, −0.990 px. The
  SIP WCS matches the gWCS to about 1e-6 px over the frame, so the intake
  adds nothing.
- Gaia DR3 against the same centroids: +0.108, −0.982 px (4 stars);
  2026-10-23 on run 17's science image, +0.127 ± 0.035, −0.988 ± 0.023 px
  (38 stars). Applying proper motion made it worse, so the simulation
  placed stars at catalog positions.

The measurement's star selection, beside `astrometry.py`'s constants:

| Constant | Code | The measurement |
|---|---|---|
| `ISOLATION_PX` | 10.0 | nearest neighbour over 10 px |
| `MARGIN_PX` | 20 | 15 px from the edge |
| `PEAK_SIGMA` | 50.0 | peak 20 to 3,500 DN/s (background sigma 0.0533 DN/s) |
| `MAX_MOVE_PX` | 3.0 | centroid moved under 1.5 px |
| `_HALF` | 7 | Gaussian-weighted iterative centroid, sigma 1.5 px, 15 × 15 window |

The code reads +0.127, −0.986 over 34 stars on the same file. What is
not measured: other SCAs and pointings, and the centroid's own bias,
which could move either number by a few hundredths of a pixel.

(measurement-reference-psf)=
## The reference image's PSF

Measured 2026-10-23 on run 17's pass 4 reference after the difference
job's resample onto the science grid. It is the measurement behind the
reference PSF the difference job measures for itself
(`rapidpipe/science/difference/refpsf.py`) and the noise-correlation
number (`noise.py`).

Both resamplings widen the PSF; the stars' second-moment sigma (r ≤ 4 px,
28 compact stars):

| Stage | star sigma, px | added variance |
|---|---|---|
| science image | 0.952 | |
| awaicgen mosaic, 0.11" north-up | 1.039 | 0.173 |
| after SWarp BILINEAR onto the science grid | 1.100 | 0.131 |
| the same mosaic, SWarp LANCZOS3 | 1.020 | |

An empirical ePSF built from the resampled reference's own stars:
DAOStarFinder at 8 sigma, peak 20 to 3,500 DN/s, sharpness and roundness
cuts, no neighbour within 14 px: 73 stars on the SCA. At oversample 4 on
31 px stamps it gives sigma 1.064 to 1.091 px from 10 to 100 stars,
stable from 10; oversample 1 gives a phase-averaged PSF with half the
peak (0.131) and is not used. The built ePSF's centroid sat 0.01 to
0.2 px off the central pixel and had to be re-centred to under 0.01 px,
since a 0.02 px shift between the PSFs is 0.3% of a star's flux as a
dipole. The whole chain took 4.7 s on the 4089² frame.

| Constant (`refpsf.py`) | Value | The measurement |
|---|---|---|
| `THRESHOLD_SIGMA` | 8.0 | 8 sigma |
| `FWHM_PX` | 2.6 | the resampled reference's sigma 1.10 × 2.355 |
| `ISOLATION_PX` | 14.0 | no neighbour within 14 px |
| `OVERSAMPLE`, `STAMP_PX` | 4, 31 | oversample 4, 31 px |
| `MIN_STARS`, `MAX_STARS` | 10, 100 | stable from 10 stars; 100 the most used |
| `CENTRING_TOLERANCE_PX` | 0.01 | re-centred to under 0.01 px |

The measurement's sharpness and roundness values were not recorded.
Two constants were set later, on the same image: the width cut
`WIDTH_EXCESS_MAX_PX` 0.4 (2026-10-24: stars 1.06 to 1.14 px, defect
pixels 0.48 to 0.66, galaxies 1.55 to 1.84, against the science PSF's
0.947), and the peak floor in sigma (2026-10-24, runs 51 and 52: the
original 20 DN/s floor left F184 and F213 with 8 and 6 stars).

The caveat `noise.py` measures: LANCZOS3 was not tested for ringing
around spikes and NaN holes, or for correlating the reference's noise.
An interpolating kernel correlates noise across neighbouring pixels, and
correlated noise raises detections at a fixed per-pixel threshold.

(measurement-dq-mask)=
## The DQ mask at intake

Measured 2026-10-23 on pass 4's L2 data quality array (4088², 1.52% of
pixels with a bit) and the three reference frames. It is the measurement
behind the HLWAS overlay's `[intake] dq_mask_bits = 0x2110C01`.

- The four reference-only spikes are wild values in all three reference
  frames, every one flagged UNRELIABLE_FLAT (0x2000000), so no median or
  clip over three frames rejects them; the mask does.
- Isolated pixels above 1,000 DN/s: 70 in pass 4 (63 to 70 in passes 1
  to 3), every one with a bit of commissioning PR 238's default mask
  0x2110C03; above 10,000 DN/s, 21, all UNRELIABLE_FLAT.
- SATURATED (0x2) is set on the core of every star with a reference peak
  above about 100 DN/s. With it in the mask, 15 of 30 compact stars kept
  0.23 to 0.83 of their aperture flux, so the overlay's mask is PR 238's
  without SATURATED.
- Within a 7 × 7 box, PR 238's mask touched 65 of the 500 sources and 34
  of the 80 above S/N 20; at 5,000 random positions, 0.7%.

(measurement-association)=
## The association's match semantics

Read 2026-10-23 from `dev`'s association code (`pipeline/crossMatchSources.py`
at the fork) and the rebuild's SQL matcher, which the in-memory matcher
(`rapidpipe/science/crossmatch/memory.py`) replaced with the same
semantics:

- A new object's id is `radec_index(ra, dec)` of the first unmatched
  source, a deterministic packing of position at 1/3300 arcsecond, as in
  `dev`: no sequence and no database round trip. Two sources at one
  position in one exposure share the one id.
- A source matches every object within the match radius, not the
  nearest, so a source can join several objects.
- Objects founded by one SCA of an exposure are not visible to another
  SCA of the same exposure: `dev` copies them in after the per-SCA loop.

(measurement-query-shapes)=
## The team's query shapes

Read 2026-10-23 from `dev` (54fd7ea) and `commissioning` (8a636ea): every
read the team's code makes of the database, numbered R1 onward. The
twelve spatial and status shapes in the pipeline repository's
`database/queries.sql` cite these numbers:

| Shape | What `dev` reads | Where |
|---|---|---|
| R2 | the unflagged sources of one chip, with filter and exposure time | `alerts/providers.py` |
| R6 | usable difference images in a cone, one filter, an MJD window | `alerts/forced_phot.py` |
| R9 | the best reference image for a field and filter | `rapid_db.py` |
| R13 | L2 work lists by date range, exposure, or field and filter | `rapid_db.py` |
| R14 | L2 images in a cone that overlap a field | `rapid_db.py` |
| R16 | difference images in a cone with their reference | `rapid_db.py` |
| R17 | frame counts per field and filter | `rapid_db.py` |
| R19 | L2 images overlapping a field's tiles | `rapid_pipeline_subs.py` |
| R22 | usable L2 images with no difference image | `rapid_db.py` |
| R25 | the association match of sources to a field's objects | `pipeline/crossMatchSources.py` |
