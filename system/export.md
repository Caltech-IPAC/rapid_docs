# The export stage

**Status: DRAFT**

What the `export` stage reads, what it runs, what it publishes, and its
settings and exit codes. Written 2026-09-24 from the port that landed on
the pipeline repository's `rebuild` branch
(`rapidpipe/stages/export.py`, `rapidpipe/settings/export.toml`,
`rapidpipe/products/catalogexport.py`), ported from `dev`'s
`pipeline/generateSourceHATSCatalog.py` (supervisor step 8, ruling R12,
2026-09-24). The [products](products) page fixes the vocabulary; this
page records how the stage meets it.

## In plain terms

`dev` dumps the whole `sources` table to CSV in `sid`-range chunks, then
builds a HATS (Hierarchical Adaptive Tiling Scheme) catalog from those
files with `hats-import` and syncs the result to S3. The rebuild's
`export` reads named, completed source sets instead of the whole table,
dumps their rows to CSV the same way, and runs the same `hats-import`
build; the result is published as one `catalog-export` instance through
the manifest, like every other stage's products, rather than synced by
hand. The stage reads the database and writes no rows of its own
(`database_access = "read"`); `register` records the instance it
produces, the way it already does for `source-catalog` and
`alert-container`. `dev`'s light-curve catalog
(`pipeline/generateLightCurveHATSCatalog.py`, one row per object joining
`AstroObjects`, `Merges` and `Sources`) is not ported this step:
requesting it, `[export] catalog_type = "light-curves"`, exits 64. It
remains on the [photometry](photometry) page, unported alongside forced
photometry.

## Inputs

Stage `export`, unit kind `field`. `--inputs` is an input-set manifest
(stage `input-set`) whose `inputs.result_sets` names, by instance id,
one or more `source-set` instances and, optionally, `association-set`
instances. Every named set must be registered, complete and retained
(not deleted); a `statistics-set` or any other kind, or a set that fails
any of those three checks, exits 65. At least one `source-set` must be
named; a manifest naming only association sets exits 65 too, since there
would be no sources to export.

An association set is checked but never read: it is recorded in the
manifest's `result_sets_read` and in the execution notes, and nothing
else touches it, since the source catalog does not use it. Neither
source sets' nor association sets' field is checked against the unit id:
a source set's key names its difference instance, not a field, and the
`sources` rows carry their own `field` column.

## What it runs

1. **Classify the named sets.** Split `inputs.result_sets` into source
   sets and association sets by looking each one up; a source set with
   no matching row, an incomplete one, or one no longer retained fails
   the same way (exit 65).
2. **Read the rows.** `SELECT <columns> FROM sources WHERE result_set =
   ANY(<named source sets>) [AND flags = 0] ORDER BY sid`, through the
   `sources` parent table, the way `alerts` reads named source sets --
   not `dev`'s whole-table `sid`-range chunking. A server-side (named)
   cursor streams the rows in batches inside the stage's one read-only
   transaction. `[export] flags_zero_only` (default false, since `dev`'s
   own `SELECT` carries no flags filter) restricts the read to `flags =
   0` rows.
3. **Dump to CSV.** The streamed rows are written to `sources_<n>.csv`
   files under a per-attempt work directory, one header row per file,
   `[export] csv_rows_per_file` rows each (`dev`: 100000, hard-coded).
   Zero rows read, with or without the flags filter, exits 65:
   `hats-import` cannot build an empty catalog, and `dev` never ran on
   an empty table either.
4. **Build the HATS catalog.** `hats-import`'s `ImportArguments` --
   `ra_column`, `dec_column`, the healpix order range, `pixel_threshold`,
   `catalog_type`, the dumped CSV files as a `CsvReader`, output artifact
   name and path, a scratch `tmp_dir`, `resume=False`, no progress bar --
   run by `pipeline_with_client` on a local Dask `Client` (worker count
   and thread-versus-process mode from settings, no dashboard port bound,
   its scratch directory under the attempt's work directory). Missing
   `hats`, `hats-import` or `dask` in the environment exits 64; any other
   failure inside `hats-import` exits 70.

## Output

One `catalog-export` file product (`rapidpipe.products.catalogexport`):
members are every file `hats-import` wrote under
`<outputs>/hats/<catalog_name>/`, with one of three roles -- `hats` for
the catalog's root `properties` (or `hats.properties`) file, `partition`
for each `Norder=*/Dir=*/Npix=*.parquet` leaf, `metadata` for everything
else (`partition_info.csv`, `skymap*.fits`, `point_map.fits`,
`dataset/_metadata`, `dataset/_common_metadata`). The primary member is
the root `properties` file.

Key: `{"field": <rtid>, "export_type": "sources", "result_set": <the
first named source set>, "settings_hash": <resolved settings hash>}`.
Registration block: `row_count` (the rows dumped, checked against the
catalog's own `properties` file), `export_type` (must equal the key's),
`hats_version` (the installed `hats` package version), `source_sets`
(every named source set, in input order, the first equal to the key's
`result_set`), `healpix_order` (the highest partition order
`hats-import` actually wrote), `partition_count` (the number of
`partition` members), `md5` (of the primary member). `register`
validates the entry and writes nothing beyond the instance row: no
`catalog-export`-specific table exists, the same treatment
`source-catalog` and `alert-container` get.

## Settings

`rapidpipe/settings/export.toml` holds every `dev` parameter the stage
reads, taken from the `[HATS_CATALOGS]` section of
`awsBatchSubmitJobs_launchSingleSciencePipeline.ini` on `dev`:

| Setting | Default | Meaning |
|---|---|---|
| `[export] catalog_type` | `sources` | which catalog this attempt exports; only `sources` is built. `light-curves` (`dev`'s `generateLightCurveHATSCatalog.py`) is the next port and exits 64 here |
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
PostgreSQL: two named source sets, 120 and 80 rows, one unnamed source
set of 50 rows that must not be read, and one named association set,
recorded but unused. `flags_zero_only` is off, so all 200 named rows are
exported. `hats-import` itself runs for real either side of
`--real-tools`, since it is pure Python and needs no C tool the fixture
would otherwise fake; there is one `expected.json`, not a fake-tools and
a real-tools variant. The checks: the `catalog-export` entry validates,
its key, row count, source sets and partition count are right, its own
`properties` file agrees on the row count, and the fake database's
record of what was read names only the two named source sets, never the
unnamed one or the association set.

## Not decided here

- The light-curve HATS catalog: `dev`'s
  `pipeline/generateLightCurveHATSCatalog.py`, the next port, named on
  the [photometry](photometry) page alongside forced photometry.
- Delivery: where a `catalog-export` product is read from once made,
  since [products](products) marks it "none; exported."
- Catalog naming: `[hats] catalog_name` fixes one directory name per
  settings profile; how two exports of the same field and export type,
  or a real deployment serving several catalogs, would be named apart is
  not decided.
