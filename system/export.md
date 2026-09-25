# The export stage

**Status: STUB.** The stage is declared -- its contract, settings and
exit codes are fixed -- but not implemented. Every invocation that
passes validation exits 69, "declared but not implemented in this
build" ([stage-contract](stage-contract)); no science code runs and no
manifest is written.

Written 2026-09-24 from the rulings of supervisor step 8 (2026-09-24)
and the inventory of `dev`'s HATS export scripts, planned onto the
pipeline repository's `rebuild` branch as `rapidpipe/stages/export.py`
and `rapidpipe/settings/export.toml`. The [products](products) page
fixes the vocabulary; this page records the contract now and what is
left for the real port.

## In plain terms

`dev` builds HATS catalogs from three standalone scripts:
`pipeline/generateLightCurveHATSCatalog.py`, which dumps
`AstroObjects`/`Merges`/`Sources` columns into a HATS light-curve
catalog keyed by object (`aid, meanra, meandec, nsources, field`) with
per-source rows (`sid, pid, expid, field, sca, fid, mjdobs, fluxfit,
fluxerr`, and more); `pipeline/generateSourceHATSCatalog.py`, a
source-level catalog, not object- or light-curve-keyed; and
`scripts/convert_photutils_catalog_to_hats_catalog.py`, a small utility
converting one Photutils catalog to HATS format. None of the three has
a `ppid` row in `dev`'s pipeline table either, and the inventory found
no production entry point for them. The rebuild's `export` stage
declares the shape this catalog-building will take, reading named,
completed result sets and writing HATS files, without porting the
generators themselves this step (ruling R9, 2026-09-24).

## The declared contract

- **Unit:** `field`.
- **Consumes:** named, completed result sets from the input manifest --
  `association-set`, `statistics-set`, `source-set` -- read from the
  database, not from a producing stage's completion manifest.
- **Produces:** `catalog-export`.
- **Database access:** a database-reading stage, like `alerts`: it
  reads named result sets and writes files, with no rows of its own
  ([stage-contract](stage-contract)).
- **Settings:** `rapidpipe/settings/export.toml`, carrying the
  parameters `dev`'s three scripts take -- which HATS catalog type to
  build (light-curve, source, or a converted Photutils catalog) and the
  output format version.

## The stub

`main(argv)` validates its arguments, its settings and the input
manifest exactly as a real stage does: a bad argument, an invalid
setting or a malformed manifest exits 64 or 65 as
[stage-contract](stage-contract) already defines. `--dry-run` exits 0
and prints the planned inputs and outputs, the same as any other stage.
Past validation, the stub exits 69 with "stage `export` is declared but
not implemented in this build," and writes no manifest.
`rapidpipe selftest --stage export` asserts exit 69 and no manifest
against a fixture that names its input instances by id, with no
database.

## Not decided here

- Which HATS catalog types the stage builds, and how `dev`'s three
  scripts (light-curve, source, and the Photutils-to-HATS converter) map
  onto the one `catalog-export` product kind -- one instance per type,
  or several kinds.
- Delivery: where a `catalog-export` product is read from once made,
  since [products](products) marks it "none; exported."
