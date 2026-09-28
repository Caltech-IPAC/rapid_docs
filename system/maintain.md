# The maintain stage

**Status: DRAFT**

For one observation date and detector, `maintain` clusters the `sources`
child table on its position index and analyzes it. It runs once, after
the date's last `load` unit and before `crossmatch` reads the table, to
make that scan efficient. It writes no rows or result set.

`dev` runs CLUSTER and ANALYZE once per processing date, after every
image for that date has loaded. The rebuild keeps that timing in a
separate stage, following the [load](load) page's timing and the team's
ruling that created the stage. Running it per image would
recluster the table on every load.

The implementation is on the pipeline repository's `rebuild` branch:
`rapidpipe/stages/maintain.py`, `rapidpipe/db/sources.py`'s
`cluster_and_analyze`, and migration `20260924-02`. The
[products](products) page fixes the vocabulary.

## Unit

The new unit kind is `detector-date`, with id `<yyyymmdd>/SCA<nn>`: the
observation date and detector shared by a run's `load` units and used
to name their child table, `sources_<yyyymmdd>_<sca>`.

The team's ruling fixes `maintain`'s unit as "(observation date,
detector)". None of the contract's other four kinds fits:
`detector-image` is one image, one attempt; `processing-date` carries no
detector; `field` is a tessellation tile; `exposure` is an admitted image
before any detector-level product exists.
`rapidpipe.stages.contract.UNIT_KINDS` and
`rapidpipe.products.manifest.UNIT_KINDS` both carry the fifth value.
Migration `20260924-02` widens the `units.unit_kind` CHECK constraint
to match, allowing a run to record a `maintain` unit.

## Inputs

`--inputs` carries one or more `source-set` output entries: either a
`load` completion manifest naming one, or a stage input-set manifest
composed from several `load` attempts for the same date and detector.
Every entry the stage reads must be a `source-set` whose
`registration.table` equals the unit's child table. A different table
or no `source-set` entries makes the input invalid. The table must
already exist; only `load` creates it.

The input manifest needs no particular `stage` or `unit.kind`. A
`load` completion manifest carries `detector-image`; an input-set
manifest may carry `detector-date`.

## What it runs

1. Parse the unit id into an observation date and detector, and build
   the expected child table name from them.
2. Read every `source-set` entry in the input manifest, and check each
   one's `registration.table` against that table.
3. Check the table exists.
4. Call `cluster_sources_child_table(obs_date, sca)` and commit. This
   SQL function runs `dev`'s CLUSTER on the position index and ANALYZE;
   `load` may also call it inline, but that option is off by default.

An image whose sources are all rejected by `load` still gives a
complete, empty source set (`load`'s page). `maintain` clusters and
analyzes its table just as it would a table with rows: an empty table
is still `dev`'s once-per-date maintenance target.

## The manifest

The manifest's `outputs` list is always empty. `inputs.result_sets`
names every `source-set` instance listed in the input manifest. The
stage contract uses this field for stages that read named, completed
database result sets (`maintain`, `crossmatch`, `statistics`, `prune`);
this port extends it to `maintain`.

The execution record's `notes` carry `table` (the child table clustered)
and `clustered` (`true`). With no result set to look up, these notes
identify the table each attempt maintained in the run's history.

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
manifest and the recorded CLUSTER. `tests/db/test_maintain.py` runs the
same path against PostgreSQL, checking `pg_index.indisclustered` on the
child table's position index.
