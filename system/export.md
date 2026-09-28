# The export stage

**Status: DRAFT**

The `export` stage builds a HATS (Hierarchical Adaptive Tiling Scheme)
source catalog from named, completed source sets and publishes it as one
`catalog-export` instance through the manifest, like other stages'
products. The [products](products) page fixes the vocabulary.

The stage lands on the pipeline repository's `rebuild` branch
(`rapidpipe/stages/export.py`, `rapidpipe/settings/export.toml`,
`rapidpipe/products/catalogexport.py`), ported from `dev`'s
`pipeline/generateSourceHATSCatalog.py`. That script dumps the whole
`sources` table to CSV in `sid`-range chunks, builds the catalog with
`hats-import` and syncs it to S3 by hand. The rebuild keeps the CSV dump
and `hats-import` build, but reads only the named source sets and
publishes through the manifest.

The stage reads the database and writes no rows of its own
(`database_access = "read"`). `register` records the output instance,
as it does for `source-catalog` and `alert-container`.

`dev`'s light-curve catalog (`pipeline/generateLightCurveHATSCatalog.py`)
has one row per object, joining `AstroObjects`, `Merges` and `Sources`.
It is not ported; `[export] catalog_type = "light-curves"` exits 64.

## Inputs

The unit kind is `field`. `--inputs` is an input-set manifest
(stage `input-set`) whose `inputs.result_sets` names, by instance id,
one or more `source-set` instances and, optionally, `association-set`
instances. Each must be registered, complete and retained (not deleted).
A `statistics-set` or any kind other than those two exits 65, as does a
set that fails any of those three checks. A manifest naming only
association sets also exits 65 because it supplies no sources to export.

Association sets are checked and recorded in the manifest's
`result_sets_read` and execution notes, but never read or otherwise
touched: the source catalog does not use them. Neither kind's field is
checked against the unit id. A source set's key names its difference
instance, not a field; the `sources` rows carry their own `field` column.

## What it runs

1. **Classify the named sets.** Look up each entry in `inputs.result_sets`
   and split them into source sets and association sets, applying the
   input checks above (exit 65).
2. **Read the rows.** `SELECT <columns> FROM sources WHERE result_set =
   ANY(<named source sets>) [AND flags = 0] ORDER BY sid`, through the
   `sources` parent table, as `alerts` reads named source sets. A
   server-side (named) cursor streams batches within the stage's one
   read-only transaction. `[export] flags_zero_only` restricts the read
   to `flags = 0` rows; it defaults to false because `dev`'s `SELECT`
   has no flags filter.
3. **Dump to CSV.** Write the streamed rows to `sources_<n>.csv` files
   under a per-attempt work directory, with one header row and
   `[export] csv_rows_per_file` rows per file (`dev`: 100000, hard-coded).
   Reading zero rows, with or without the flags filter, exits 65.
   `hats-import` cannot build an empty catalog; `dev` never ran on an
   empty table either.
4. **Build the HATS catalog.** Pass `hats-import`'s `ImportArguments` to
   `pipeline_with_client` on a local Dask `Client`: `ra_column`,
   `dec_column`, the healpix order range, `pixel_threshold`,
   `catalog_type`, the dumped CSV files as a `CsvReader`, output artifact
   name and path, a scratch `tmp_dir`, `resume=False`, and no progress
   bar. Settings control the worker count and thread-versus-process
   mode. No dashboard port is bound, and Dask's scratch directory is
   under the attempt's work directory. Missing `hats`, `hats-import` or
   `dask` exits 64; any other failure inside `hats-import` exits 70.

## Output

The output is one `catalog-export` file product
(`rapidpipe.products.catalogexport`). Every file `hats-import` writes
under `<outputs>/hats/<catalog_name>/` is a member with one of three roles:

- `hats`: the catalog's root `properties` (or `hats.properties`) file.
- `partition`: each `Norder=*/Dir=*/Npix=*.parquet` leaf.
- `metadata`: everything else (`partition_info.csv`, `skymap*.fits`,
  `point_map.fits`, `dataset/_metadata`, `dataset/_common_metadata`).

The primary member is the root `properties` file.

Key: `{"field": <rtid>, "export_type": "sources", "selection": <selection
digest>, "settings_hash": <resolved settings hash>}`. The selection
digest is the full SHA-256 hex digest of the sorted, distinct named
`source-set` instance ids joined by newlines, the same rule as the
reference-image's selection digest. Rebuilding the same set of source
sets in any input order makes another instance of the same logical
product; a different set makes a new product. The earlier "result_set"
key component named only the first source set, allowing exports of
different sets with the same first element to collide.

The registration block records `row_count` (rows dumped, checked against
the catalog's `properties` file), `export_type` (must equal the key's),
`hats_version` (installed `hats` package version), `healpix_order`
(highest partition order `hats-import` wrote), `partition_count` (number
of `partition` members) and `md5` (of the primary member). Its
`source_sets` preserves every named source set in input order for
provenance, even though the key's `selection` sorts them.

`register` validates the entry and writes only the instance row. There
is no `catalog-export`-specific table, as with `source-catalog` and
`alert-container`.

## Settings

`rapidpipe/settings/export.toml` holds every `dev` parameter the stage
reads, taken from the `[HATS_CATALOGS]` section of
`awsBatchSubmitJobs_launchSingleSciencePipeline.ini` on `dev`:

| Setting | Default | Meaning |
|---|---|---|
| `[export] catalog_type` | `sources` | which catalog this attempt exports; only `sources` is built. `light-curves` (`dev`'s `generateLightCurveHATSCatalog.py`) is not ported and exits 64 here |
| `[export] flags_zero_only` | false | restrict the export to `flags = 0` rows; `dev`'s own `SELECT` has no such filter |
| `[export] csv_rows_per_file` | 100000 | rows per dumped CSV file (`dev`: `nrows_per_file`, hard-coded) |
| `[hats] format_version` | `1` | the `catalog-export` entry's format version |
| `[hats] catalog_name` | `sources_hats_catalog` | the output directory name under `<outputs>/hats/` (`dev`: `sources_catalog_name`) |
| `[hats] hats_catalog_type` | `object` | `hats-import`'s `ImportArguments.catalog_type`; `dev` passes none, so `hats-import`'s own default applies |
| `[hats] lowest_healpix_order`, `highest_healpix_order` | 2, 9 | `hats-import`'s healpix order range (`dev`'s values) |
| `[hats] pixel_threshold` | 1000000 | `hats-import`'s rows-per-partition ceiling; `dev` passes none, so `hats-import`'s own default applies |
| `[hats] sort_columns` | empty | `hats-import`'s `sort_columns`, joined with `,`; `dev` passes none |
| `[hats] n_workers` | 1 | the local Dask cluster's worker count (`dev`'s value) |
| `[hats] dask_processes` | true | workers are processes, Dask's own default, as `dev`; false runs threads in this process instead, which the selftest overlay uses to keep the fixture fast |
| `[hats] ra_col`, `dec_col` | `ra`, `dec` | the RA/Dec column names among the dumped columns (`dev`: `sources_ra_col`, `sources_dec_col`) |
| `[hats] columns` | `dev`'s `sources_cols`, verbatim | the `sources` columns dumped, in order: `sid`, `id`, `pid`, `ra`, `dec`, `xfit`, `yfit`, `fluxfit`, `xerr`, `yerr`, `fluxerr`, `npixfit`, `qfit`, `cfit`, `flags`, `sharpness`, `roundness1`, `roundness2`, `npix`, `peak`, `field`, `hp6`, `hp9`, `expid`, `fid`, `sca`, `mjdobs`, `isdiffpos` |

## Exit codes

| Code | When |
|---|---|
| 0 | exported: the CSV dump, the HATS catalog and the manifest were all written |
| 64 | a setting is missing, empty or invalid, `[export] catalog_type` names the designed-in `light-curves`, or `hats`/`hats-import`/`dask` are not installed in this environment |
| 65 | a named result set is unknown, incomplete, deleted, or of a kind this stage does not read (anything but `source-set` and `association-set`), no `source-set` is named at all, or the named source sets together have no rows to export |
| 70 | `hats-import` raised, or the catalog it wrote does not check out against the row count |
| 75 | the database cannot be reached, or the connection is lost mid-read |

## Local execution

```
rapidpipe stage export --run <run-id> --unit <rtid> --attempt <attempt-id> \
    --inputs <dir-or-s3-prefix> --outputs <dir-or-s3-prefix> \
    [--settings <toml>] [--dry-run]
```

`make stage-export` runs `rapidpipe selftest --stage export` against a
fake database (`rapidpipe.selftest.support.fakeexport`) instead of
PostgreSQL. The fixture has two named source sets of 120 and 80 rows,
an unnamed source set of 50 rows that must not be read, and one named
association set, recorded but unused. With `flags_zero_only` off, all
200 named rows are exported.

`hats-import` runs for real with or without `--real-tools`: it is pure
Python and needs no C tool the fixture would otherwise fake. Both modes
use one `expected.json`. The checks validate the `catalog-export` entry
and verify its key, row count, source sets and partition count. They
also check that its `properties` file agrees on the row count and that
the fake database records reads of only the two named source sets,
never the unnamed set or the association set.

## Not decided here

- The light-curve HATS catalog: `dev`'s
  `pipeline/generateLightCurveHATSCatalog.py`, not ported;
  `[export] catalog_type = "light-curves"` exits 64.
- Delivery: where a `catalog-export` product is read from once made,
  since [products](products) marks it "none; exported."
- Catalog naming: `[hats] catalog_name` fixes one directory name per
  settings profile; how two exports of the same field and export type,
  or a real deployment serving several catalogs, would be named apart is
  not decided.
- Field validation: a catalog labelled by the unit's field can hold rows
  with a different `field`. The stage deliberately restricts reads only
  by named source sets, which a manifest can name regardless of their
  rows' fields. Whether to check the field is left open.
