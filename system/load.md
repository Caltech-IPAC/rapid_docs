# The load stage

**Status: DRAFT**

What the `load` stage reads, what it writes into `sources`, the result
set it records, the settings it takes, and the `psf` registration block
that landed beside it. Written 2026-09-23 from the port that landed on
the pipeline repository's `rebuild` branch (`rapidpipe/stages/load.py`,
`rapidpipe/science/load/catalogs.py`, `rapidpipe/settings/load.toml`,
`rapidpipe/db/sources.py`, `rapidpipe/products/psf.py`,
`rapidpipe/db/psfs.py`, migrations `20260923-04` to `-07`), ported from
`dev`'s `pipeline/loadPSFCatIntoDBSourcesTable.py`. The port follows the
lead's rule of 2026-09-22: minimise differences to `dev`, and design in,
off by default, anything that can be left unused. The
[products](products) page fixes the vocabulary; this page records how
the stage meets it.

## In plain terms

For one registered difference image, the stage reads the two Photutils
PSF-fit catalogs the difference stage made, positive and negative, joins
each to its finder catalog, drops sources fitted outside the image, and
loads the rest as rows of the `sources` table, exactly as `dev` does.
The rows land in the child table for the image's observation date and
detector, which the stage makes, with `dev`'s indexes, if it is new.
Everything the stage writes for one image is one source set: a named
group of rows that is either complete or absent. SExtractor catalogs are
not loaded, as in `dev`.

## Inputs

`--inputs` is the difference attempt's output location: its completion
manifest and files. The stage reads:

| Entry | Members | Used for |
|---|---|---|
| the `difference-image` of the `[load] differencer` setting | none read | its instance names the `diffimages` row: `pid`, and through `rid` the `l2files` row |
| its `source-catalog` with catalog type `photutils`, sign `positive` | `catalog`, `finder` | the positive rows |
| its `source-catalog` with catalog type `photutils`, sign `negative` | `catalog`, `finder` | the negative rows |

Every member read is checked for size and SHA-256. The difference
instance must already be registered: `pid`, `expid`, `sca`, `fid`,
`mjdobs` and the observation date come from the rows `register` wrote,
never from the files.

If any of the four catalog files is missing, the stage does what `dev`
does and skips the image: exit 0, no rows, no source set, and the reason
in the execution record's `notes`.

## What it runs

`dev`'s per-job steps, in `dev`'s order:

1. Read each PSF-fit catalog and its finder catalog as text tables and
   inner-join them on `id`; a source missing from either is dropped.
2. Compute each source's level-6 and level-9 HEALPix index (NSIDE 64
   and 512, nested) from its RA and Dec.
3. Reject sources whose fitted position lies outside
   `[xy_fit_min, naxis - xy_fit_max_offset]` in either axis, with naxis
   the science image's axis plus one row or column, as `dev` sets it; a
   NaN position is rejected.
4. Look up each source's Roman tessellation tile, the `field` column.
   The rebuild uses the certified closed-form tessellation already in
   the tree, which agrees with `dev`'s SQLite lookup on every tile.
5. Write one CSV: `dev`'s 28 columns, positive rows then negative, and
   the three run columns.
6. Make `sources_<yyyymmdd>_<sca>` if it does not exist, register the
   source set, and COPY the CSV into the child table, all in one
   transaction; the loaded row count is read back and must match.

`load` never clusters or analyzes per image: `dev`'s once-per-processing-date
CLUSTER and ANALYZE is its own `maintain` stage instead, described below
under the child tables (lead, 2026-09-23).

## The child tables

`sources` is the parent of one child table per observation date and
detector, `sources_<yyyymmdd>_<sca>`, as in `dev`; the date is the UT
date of the image's `dateobs`. `dev`'s loader makes a child as a login
holding `rapidporole`, which owns `sources`. The rebuild's service
login holds table grants only, so two functions do the same work as
`rapidporole` (migration `20260923-05`, EXECUTE granted by `-06`):

- `create_sources_child_table(obs_date, sca)`: `dev`'s creation (`LIKE
  sources INCLUDING DEFAULTS INCLUDING CONSTRAINTS`, owner `rapidporole`,
  unlogged, `INHERIT sources`), its eight indexes (`pid`, `expid`, `sca`,
  `field`, `flags`, `mjdobs`, `sid`, and the Q3C position index), and its
  grants to `rapidreadrole` and `rapidadminrole`, plus the rebuild's
  service login and `rapid_read` where those roles exist. An advisory
  lock serialises two loads making the same table. The function also
  creates b-tree indexes on `result_set` and `run` (migration
  `20260923-09`), matching the naming pattern of the other eight: run
  deletion reads rows by `run` and crossmatch reads a result set by
  `result_set`, both scans. There is no per-child UNIQUE on `(pid, id,
  isdiffpos)`: scratch runs coexist over the same logical inputs by
  design, and the done check in `load`'s inputs guards uniqueness within
  one run (lead, 2026-09-23).
- `cluster_sources_child_table(obs_date, sca)`: `dev`'s CLUSTER on the
  position index and ANALYZE. Called by the `maintain` stage below, not
  by `load`.

Three things differ from `dev`: the tablespace lines are omitted, as the
baseline omits them; the grants run when the table is made rather than
after loading; and `dev`'s `REVOKE ALL ... FROM rapidporole` with its
re-grant list is omitted, because on PostgreSQL 17 and later that pair
takes away the owner's `MAINTAIN` privilege and CLUSTER is then refused.

`dev` runs its CLUSTER and ANALYZE once per processing date, after every
image for that date has loaded; running it per image would recluster
the table on every load. The rebuild keeps that timing but moves it out
of `load` into its own stage, `maintain`, unit (observation date,
detector), scheduled after the date's last `load` unit and before
`crossmatch`, calling `cluster_sources_child_table`. It is built with
the crossmatch port, crossmatch being the first stage that reads a
clustered child table (lead, 2026-09-23).

## What lands in `sources`

One row per loaded source. `dev`'s columns keep their meaning; the last
three are added by migration `20260923-04`, nullable, all set or all
null, and are set on every row the rebuild writes.

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

One `source-set` result set per load, the products page's database
result set: unit detector image, logical key (difference instance,
catalog type `photutils`). The stage writes its `product_instances` row
(kind `source-set`, stage `load`, this attempt as producer and
registrar, custody by run kind), its `result_sets` row (`complete` true,
`row_count` the rows loaded) and dependency edges to the difference
instance and both catalog instances, in the same transaction as the
rows. An image whose sources are all rejected gives an empty set, still
complete.

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
rebuild's form is `[load] done_check`: a complete source set with the same
key already loaded in the same run is reused, nothing is written, and
the manifest names that instance.

## Settings

`rapidpipe/settings/load.toml`: every knob `dev`'s loader reads, with
`dev`'s value, except its S3, job-query and process-pool knobs, which the
launcher and the manifests replace.

| Setting | Default | `dev` |
|---|---|---|
| `[load] differencer` | `zogy` | ZOGY stays the default: it is the only differencer whose catalogs exist to load. `dev` loads SFFT's catalogs (`output_sfft_psfcat_filename`) against the ZOGY image's `pid` (`[SCI_IMAGE] ppid = 15`); once SFFT registers as its own `difference-image` instance (`[sfft] register_sfft` on, a `pipelines` row for SFFT), setting `differencer=sfft` loads SFFT's catalogs against SFFT's own `pid` instead, a stated departure from `dev` accepted as a correctness gain (lead, 2026-09-23) |
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

The products page's `psf` kind (filter, detector, version; registered
by `psf-import`, the [runs](runs) page's import-run pattern; table
`psfs`) now has its field list, and `register` records it. Nothing
emits a `psf` entry yet: `psf-import` is not built, and the difference
stage's input `psf` entries are consumed, not registered. The block is
designed in and unused.

A psf instance's `version` is logical and equals the allocated legacy
number: the manifest key's `version` and the `psfs.version` column hold
the same value, there is no separate delivered-version column, and the
psf's delivered identity is its checksum, not its version (lead,
2026-09-23).

`applies_to` (`science` or `reference`) is a role in the difference
stage's input set, not a field of the `psf` kind's key: an input-set
entry carries a product key and a role side by side, so the same `psf`
instance can be named with either role without changing its key (lead,
2026-09-23).

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

`psfs`'s key `(fid, sca, version)` is kept unwidened, table-wide through
`dev`'s `addPSF`: it allocates across the whole table, so two runs never
hold the same version. This is a deliberate exception to the run
model's per-run versioning; the difference image keeps within-run
numbering instead, because its `version` is allocated per run for
`(rid, ppid)`, and its key carries the run through that allocation
(lead, 2026-09-23).

## Local execution

`make stage-load` runs the stage fixture (`tests/fixtures/load/`)
against a fake database and checks the rows and the manifest; the same
path against PostgreSQL is `tests/db/test_load.py`.
