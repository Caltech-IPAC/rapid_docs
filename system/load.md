# The load stage

**Status: DRAFT**

The `load` stage reads the two Photutils PSF-fit catalogs, positive and
negative, made by the difference stage for one registered difference
image. It joins each to its finder catalog, rejects sources fitted
outside the image, and loads the rest into `sources`, exactly as `dev`
does. SExtractor catalogs are not loaded, as in `dev`. The rows form
one source set: a named group that is either
complete or absent. They go into a child table for the image's
observation date and detector, created with `dev`'s indexes if needed.

The stage lands on the pipeline repository's `rebuild` branch
(`rapidpipe/stages/load.py`,
`rapidpipe/science/load/catalogs.py`, `rapidpipe/settings/load.toml`,
`rapidpipe/db/sources.py`, `rapidpipe/products/psf.py`,
`rapidpipe/db/psfs.py`, migrations `20260923-04` to `-07`), ported from
`dev`'s `pipeline/loadPSFCatIntoDBSourcesTable.py`. Every ported stage
minimises differences from `dev` and designs in, off by default,
anything that could be left unused. The [products](products) page fixes
the vocabulary used here. The `psf` registration block landed beside
the stage and is described below.

## Inputs

`--inputs` is the difference attempt's output location, containing its
completion manifest and files. The stage reads:

| Entry | Members | Used for |
|---|---|---|
| the `difference-image` of the `[load] differencer` setting | none read | its instance names the `diffimages` row: `pid`, and through `rid` the `l2files` row |
| its `source-catalog` with catalog type `photutils`, sign `positive` | `catalog`, `finder` | the positive rows |
| its `source-catalog` with catalog type `photutils`, sign `negative` | `catalog`, `finder` | the negative rows |

Every member read is checked for size and SHA-256. The difference
instance must already be registered: `pid`, `expid`, `sca`, `fid`,
`mjdobs` and the observation date come from the rows `register` wrote,
never from the files.

If any of the four catalog files is missing, the stage skips the image,
as `dev` does: exit 0, no rows or source set, and the reason in the
execution record's `notes`.

## What it runs

The stage follows `dev`'s per-job order:

1. Read each PSF-fit catalog and its finder catalog as text tables and
   inner-join them on `id`; a source missing from either is dropped.
2. Compute each source's level-6 and level-9 HEALPix index (NSIDE 64
   and 512, nested) from its RA and Dec.
3. Reject sources whose fitted position lies outside
   `[xy_fit_min, naxis - xy_fit_max_offset]` in either axis. As in `dev`,
   naxis is the science image's axis plus one row or column; a NaN
   position is rejected.
4. Look up each source's Roman tessellation tile, the `field` column.
   The rebuild uses the certified closed-form tessellation already in
   the tree, which agrees with `dev`'s SQLite lookup on every tile.
5. Write one CSV: `dev`'s 28 columns, positive rows then negative, and
   the three run columns.
6. Make `sources_<yyyymmdd>_<sca>` if it does not exist, register the
   source set, and COPY the CSV into the child table, all in one
   transaction. Read back the loaded row count and check that it matches.

## The child tables

`sources` has one child table per observation date and detector,
`sources_<yyyymmdd>_<sca>`, as `dev`'s current loader names it. The date
is the UT date of the image's `dateobs`.

Some of `dev`'s production tables predate that rule. The control image
(`dev` pid 1105, `dateobs` 2027-10-01) was loaded on 2026-08-09 by an
earlier loader and sits in `sources_20260809_1`, named by the date it was
processed, with every row stamped the image's own field (4711398). The
rebuild follows `dev`'s current code: the child is named by `dateobs`,
and each source's field is its own tessellation tile. The team approved
this departure from `dev`'s older data.

Nothing in the rebuild derives a table name from a date: crossmatch and
the other readers resolve a source set's child table through the set's
own record.

`dev`'s loader creates a child as a login holding `rapidporole`, which
owns `sources`. The rebuild's service login holds table grants only,
so two functions do the work as `rapidporole` (migration `20260923-05`,
EXECUTE granted by `-06`):

- `create_sources_child_table(obs_date, sca)`: `dev`'s creation (`LIKE
  sources INCLUDING DEFAULTS INCLUDING CONSTRAINTS`, owner `rapidporole`,
  unlogged, `INHERIT sources`), its eight indexes (`pid`, `expid`, `sca`,
  `field`, `flags`, `mjdobs`, `sid`, and the Q3C position index), and its
  grants to `rapidreadrole` and `rapidadminrole`, plus the rebuild's
  service login and `rapid_read` where those roles exist. An advisory
  lock serialises two loads making the same table. The function also
  creates b-tree indexes on `result_set` and `run` (migration
  `20260923-09`), named like the other eight. These support scans by
  `run` for run deletion and by `result_set` for crossmatch. There is no
  per-child UNIQUE on `(pid, id, isdiffpos)`: scratch runs coexist over
  the same logical inputs by design, and the done check in `load`'s
  inputs guards uniqueness within one run.
- `cluster_sources_child_table(obs_date, sca)`: `dev`'s CLUSTER on the
  position index and ANALYZE. The `maintain` stage calls it by default;
  `load` can call it per image through `[child_tables]
  cluster_and_analyze`, which is off by default.

Three things differ from `dev`: tablespace lines are omitted, as in the
baseline; grants run when the table is made rather than after loading;
and `dev`'s `REVOKE ALL ... FROM rapidporole` and re-grant list are
omitted. On PostgreSQL 17 and later, that pair removes the owner's
`MAINTAIN` privilege, causing CLUSTER to be refused.

`dev` runs its CLUSTER and ANALYZE once per processing date, after every
image for that date has loaded; running it per image would recluster
the table on every load. The rebuild keeps that timing by default in
[maintain](maintain), unit kind
`detector-date` (observation date, detector), scheduled after the
date's last `load` unit and before `crossmatch`, calling
`cluster_sources_child_table` (see [maintain](maintain), "Unit").

## What lands in `sources`

Each loaded source gets one row. `dev`'s columns keep their meaning.
Migration `20260923-04` adds the last three, nullable and either all set
or all null; the rebuild sets them on every row it writes.

| Column | Source |
|---|---|
| `id` | the catalog's `id` (not unique across images) |
| `ra`, `dec` | the PSF-fit catalog's `ra`, `dec` |
| `xfit`, `yfit`, `fluxfit` | `x_fit`, `y_fit`, `flux_fit` |
| `xerr`, `yerr`, `fluxerr` | `x_err`, `y_err`, `flux_err` |
| `npixfit`, `qfit`, `cfit`, `redchi`, `flags` | `n_pixels_fit`, `qfit`, `cfit`, `reduced_chi2`, `flags` |
| `sharpness`, `roundness1`, `roundness2`, `npix`, `peak` | the finder catalog's `sharpness`, `roundness1`, `roundness2`, `n_pixels`, `peak` |
| `pid` | the difference instance's `diffimages` row |
| `isdiffpos` | true for the positive catalog, false for the negative |
| `field` | the tessellation tile of (`ra`, `dec`) |
| `hp6`, `hp9` | HEALPix NSIDE 64 and 512, nested, of (`ra`, `dec`) |
| `expid`, `fid`, `sca`, `mjdobs` | that `diffimages` row's `l2files` row |
| `run` | the run |
| `attempt` | the load attempt that wrote the row |
| `result_set` | the source set's instance |
| `sid` | allocated by the table's sequence |
| `rb` | null: real-bogus is not run |

## The source set

Each load produces one `source-set`, the products page's database
result set. Its unit is a detector image and its logical key is
(difference instance, catalog type `photutils`). In the same
transaction as the source rows, the stage writes:

- A `product_instances` row: kind `source-set`, stage `load`, this
  attempt as producer and registrar, and custody by run kind.
- A `result_sets` row: `complete` true and `row_count` the rows loaded.
- Dependency edges to the difference instance and both catalog instances.

An image whose sources are all rejected gives an empty, complete set.

The manifest entry has no members; its `registration` block is
informational:

| Field | Meaning |
|---|---|
| `row_count` | rows loaded, as in `result_sets.row_count` |
| `table` | the child table, `sources_<yyyymmdd>_<sca>` |
| `rows_by_sign` | `{positive, negative}` row counts |

`inputs.products` names `difference-image` and the two catalogs as
`source-catalog/positive` and `source-catalog/negative`.

`dev` skips a job whose `source_dbload_jid<jid>.done` file exists. The
rebuild's `[load] done_check` reuses a complete, retained source set of
this run with the same key only if its producing attempt is the calling
attempt or has disposition `succeeded`. Nothing is written; the
manifest names the reused instance.

A retry loads a fresh set under its own instance if the earlier attempt
committed rows and then failed, or if another attempt still has no
disposition. The earlier rows remain the run's own but are unreachable:
no later stage selects an unsucceeded attempt's output.
`db/sources.find_complete_source_set` enforces this by joining
`attempts`; the [runs](runs) page has the general rule.

## Settings

`rapidpipe/settings/load.toml` holds every setting `dev`'s loader reads,
with `dev`'s value, except the S3, job-query and process-pool settings
replaced by the launcher and manifests.

| Setting | Default | `dev` |
|---|---|---|
| `[load] differencer` | `zogy` | ZOGY stays the default: it is the only differencer whose catalogs exist to load. `dev` loads SFFT's catalogs (`output_sfft_psfcat_filename`) against the ZOGY image's `pid` (`[SCI_IMAGE] ppid = 15`); once SFFT registers as its own `difference-image` instance (`[sfft] register_sfft` on, a `pipelines` row for SFFT), setting `differencer=sfft` loads SFFT's catalogs against SFFT's own `pid` instead, a stated departure from `dev` accepted as a correctness gain |
| `[load] done_check` | true | `DONTCHECKDONEFILE` unset |
| `[load] skip_loading` | false | `SKIPLOADING` unset: when true, no table is made and no rows load |
| `[instrument] naxis1_sciimage`, `naxis2_sciimage` | 4088, 4088 | `[INSTRUMENT]`; one is added, as `dev` adds it |
| `[psf_fit_bounds] xy_fit_min` | -0.5 | module constant |
| `[psf_fit_bounds] xy_fit_max_offset` | 0.5 | module constant |

## Exit codes

| Code | When |
|---|---|
| 0 | loaded, reused under `done_check`, skipped for a missing catalog, or `skip_loading` |
| 64 | an unknown or invalid setting, or a bad `RAPIDPIPE_LOAD_DATABASE` |
| 65 | the input manifest is not a difference stage's, the differencer's instance is absent or unregistered, a member fails its size or SHA-256, or a catalog cannot be read |
| 70 | the loaded row count differs from the rows written, or any unclassified error |
| 75 | the database cannot be reached, or the connection is lost mid-transaction |

## The psf registration block

`register` records the field list below for the products page's `psf`
kind (filter, detector, version) in `psfs`. Registration is through
`psf-import`, the [runs](runs) page's import-run pattern. The block is
designed in and unused: `psf-import` is not built, nothing emits a
`psf` entry yet, and the difference stage consumes its input `psf`
entries without registering them.

A psf instance's logical `version` equals the allocated legacy number.
The manifest key's `version` and `psfs.version` hold the same value;
there is no separate delivered-version column. The psf's delivered
identity is its checksum, not its version.

`applies_to` (`science` or `reference`) is a role in the difference
stage's input set, not a field of the `psf` kind's key: an input-set
entry carries a product key and a role side by side, so the same `psf`
instance can be named with either role without changing its key.

| Field | Source | Column |
|---|---|---|
| filter | manifest key `filter` | `fid`: lookup in `filters` |
| detector | manifest key `detector`, SCA 1 to 18 | `sca` |
| version | manifest key `version`, equal to the allocated legacy version | the key, and `psfs.version` |
| legacy version | allocated by `dev`'s own `addPSF`: the next number for (`fid`, `sca`) across the table | `version` |
| file path | manifest primary member, the one member, role `psf`, under the attempt's output location | `filename` |
| checksum | registration block `md5` | `checksum` |
| verification | registration block `status`: 1 when the maker verified the file | `status` |
| current flag | 0 at registration; made current afterwards as `dev`'s `updatePSF` does | `vbest` |
| run, attempt, instance | the manifest and the registering attempt; migration `20260923-07` | `run`, `attempt`, `instance` |

`psfs` keeps its unwidened key `(fid, sca, version)`. `dev`'s `addPSF`
allocates across the whole table, so two runs never hold the same
version. This is a deliberate exception to the run model's per-run
versioning. The difference image keeps within-run numbering: its
`version` is allocated per run for `(rid, ppid)`, and its key carries
the run through that allocation.

## Local execution

`make stage-load` runs the stage fixture (`tests/fixtures/load/`)
against a fake database and checks the rows and the manifest; the same
path against PostgreSQL is `tests/db/test_load.py`.
