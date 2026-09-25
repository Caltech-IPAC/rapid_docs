# The photometry stage

**Status: STUB.** The stage is declared -- its contract, settings and
exit codes are fixed -- but not implemented. Every invocation that
passes validation exits 69, "declared but not implemented in this
build" ([stage-contract](stage-contract)); no science code runs and no
manifest is written.

Written 2026-09-24 from the rulings of supervisor step 8 (2026-09-24)
and the inventory of `dev`'s forced-photometry pipeline, planned onto
the pipeline repository's `rebuild` branch as
`rapidpipe/stages/photometry.py` and `rapidpipe/settings/photometry.toml`.
The [products](products) page fixes the vocabulary; this page records
the contract now and what is left for the real port.

## In plain terms

`dev` runs forced photometry from a standalone script,
`pipeline/forcedPhotometryForField.py`: given a field and a CSV of
`reqid, ra, dec` sky positions, it measures a flux at each position on
every difference image touching it, using the difference image's own
SFFT PSF and falling back to the reference image's PSF when SFFT's is
not available. No `ppid` row exists for it in `dev`'s pipeline table,
and it is not wired into `dev`'s AWS Batch dispatch the way reference,
science and post-processing are; the inventory did not find where or
how it is actually scheduled in production. The rebuild's `photometry`
stage declares the shape this measurement will take as a run-model
transform stage, producing a `light-curve` product, without porting the
measurement itself this step (ruling R9, 2026-09-24).

## The declared contract

- **Unit:** `field`.
- **Consumes:** one `difference-image`, one `psf`, and a named object
  set given in the input manifest -- a `statistics-set` or an
  `association-set` instance, the set of positions to measure.
- **Produces:** `light-curve`.
- **Database access:** none; `photometry` is a transform stage, the
  same category `reference`, `difference` and `finalize` already
  declare ([stage-contract](stage-contract)).
- **Settings:** `rapidpipe/settings/photometry.toml`, carrying the
  parameters `dev`'s `forcedPhotometryForField.py` takes -- aperture or
  PSF-fit choice among them -- and `dev`'s own documented exit-code map
  for photometry-quality conditions (codes 52, 54 to 58, and 60 to 62
  in `dev`'s script; recorded here for the future port, not given
  individual meanings, since this build does not run the measurement
  they describe).

## The stub

`main(argv)` validates its arguments, its settings and the input
manifest exactly as a real stage does: a bad argument, an invalid
setting or a malformed manifest exits 64 or 65 as
[stage-contract](stage-contract) already defines. `--dry-run` exits 0
and prints the planned inputs and outputs, the same as any other stage.
Past validation, the stub exits 69 with "stage `photometry` is declared
but not implemented in this build," and writes no manifest.
`rapidpipe selftest --stage photometry` asserts exit 69 and no manifest
against a fixture that names its input instances by id, with no
database.

## Not decided here

- How object positions reach a database-less photometry stage, when
  `dev`'s script reads them from a CSV built by hand: whether the input
  manifest's named object set carries positions directly, or whether the
  stage needs a database read after all.
- Which HATS catalog types the light curves this stage measures feed
  into; see [export](export).
- Delivery: where a `light-curve` product is read from once made, since
  [products](products) marks it "none; exported."
