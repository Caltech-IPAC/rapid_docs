# The maintain stage

**Status: DRAFT**

What the `maintain` stage reads, what it runs, its unit, its manifest,
and its exit codes. Written 2026-09-24 from the port that landed on the
pipeline repository's `rebuild` branch (`rapidpipe/stages/maintain.py`,
`rapidpipe/db/sources.py`'s `cluster_and_analyze`, migration
`20260924-02`), following the timing the [load](load) page already
described and the lead's ruling of 2026-09-23 that created the stage.
The [products](products) page fixes the vocabulary; this page records
how the stage meets it.

## In plain terms

`dev` runs its CLUSTER and ANALYZE of a `sources` child table once per
processing date, after every image for that date has loaded; running it
per image would recluster the table on every load. The rebuild keeps
that timing in a stage of its own: for one observation date and
detector, `maintain` clusters the child table on its position index and
analyzes it, once, after the date's last `load` unit and before
`crossmatch` reads the table (supervisor step 1, ruling R1,
2026-09-24). It writes no rows and no result set; it only makes the
table `crossmatch` reads efficient to scan.

## Inputs

`--inputs` is a manifest carrying one or more `source-set` output
entries: either a `load` completion manifest naming one, or a stage
input-set manifest composed from several `load` attempts for the same
date and detector. The stage does not require any particular `stage` or
`unit.kind` on the input manifest itself -- a `load` completion manifest
carries unit kind `detector-image`, an input-set manifest may carry this
stage's own `detector-date` -- only that every entry it reads is a
`source-set` for the unit's own table.

Each entry's `registration.table` must equal the unit's child table,
`sources_<yyyymmdd>_<sca>`; an entry naming a different table is a
rejected input, as is an input manifest with no `source-set` entries at
all. The child table itself must already exist -- `maintain` never
creates one, only `load` does.

## What it runs

1. Parse the unit id into an observation date and detector, and build
   the expected child table name from them.
2. Read every `source-set` entry in the input manifest, and check each
   one's `registration.table` against that table.
3. Check the table exists.
4. Call `cluster_sources_child_table(obs_date, sca)` -- `dev`'s CLUSTER
   on the position index and ANALYZE, the same SQL function `load` may
   call inline (off by default there) -- and commit.

An image whose sources are all rejected by `load` still gives a complete,
empty source set (`load`'s page): `maintain` clusters and analyzes its
table exactly as it would a table with rows, since an empty table is
still `dev`'s once-per-date maintenance target.

## Unit

Unit kind `detector-date`, unit id `<yyyymmdd>/SCA<nn>` -- the
observation date and detector a run's `load` units for that date and
detector share, and the same pair the child table's own name is built
from (supervisor step 1, ruling R2, 2026-09-24). This is a new kind
because none of the contract's other four fits the lead's ruling of
2026-09-23 that `maintain`'s unit is "(observation date, detector)":
`detector-image` is one image, one attempt; `processing-date` carries no
detector; `field` is a tessellation tile; `exposure` an admitted image
before any detector-level product exists. `rapidpipe.stages.contract.UNIT_KINDS`
and `rapidpipe.products.manifest.UNIT_KINDS` both carry the fifth value,
and migration `20260924-02` widens the `units.unit_kind` CHECK
constraint to match, so a run can record a `maintain` unit at all
(supervisor step 1, 2026-09-24).

## The manifest

`maintain` writes no output: its manifest's `outputs` list is always
empty. `inputs.result_sets` names every `source-set` instance the input
manifest listed -- the stage contract's field for the stages that read
named, completed database result sets (`maintain`, `crossmatch`,
`statistics`, `prune`), extended to `maintain` in this port. The
execution record's `notes` carry `table` (the child table clustered) and
`clustered` (`true`), so a run's history shows which table each
`maintain` attempt maintained without a result set to look it up by.

## Exit codes

| Code | When |
|---|---|
| 0 | the table was clustered and analyzed |
| 64 | the unit id is not `<yyyymmdd>/SCA<nn>`, or the settings overlay is invalid (the stage takes none, so any overlay key is unknown) |
| 65 | the input manifest has no `source-set` entries, an entry's `registration.table` does not match the unit's table, or the table does not exist |
| 70 | any unclassified error |
| 75 | the database cannot be reached, or the connection is lost mid-transaction |

## Local execution

`make stage-maintain` runs the stage fixture
(`tests/fixtures/maintain/`) against a fake database and checks the
manifest and the fake database's recorded CLUSTER; the same path
against PostgreSQL, checking `pg_index.indisclustered` on the child
table's position index, is `tests/db/test_maintain.py`.
