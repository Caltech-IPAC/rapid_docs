# The statistics stage

**Status: DRAFT**

This page covers what the `statistics` stage reads and what it computes.
It also records what lands in `astroobjectsmeta`, the result set the
stage records, its settings and its exit codes. Written 2026-09-24 from
the port on the pipeline repository's `rebuild` branch:

- `rapidpipe/stages/statistics.py`;
- `rapidpipe/science/statistics/lightcurve.py`;
- `rapidpipe/settings/statistics.toml`;
- `rapidpipe/db/objects.py`;
- migrations `20260924-03` to `-06`.

The port is of `dev`'s `pipeline/computeStatisticsForAstroObjects.py`.
It follows the lead's rule of 2026-09-22: minimise differences to
`dev`, and design in, off by default, anything that can be left unused.
The [products](products) page fixes the vocabulary; this page records
how the stage meets it.

## In plain terms

`crossmatch` groups a field's sources into objects: each object is a
row of `astroobjects_<field>`, and each `merges_<field>` row links an
object to one of its sources. For one field's association set, the
`statistics` stage gathers every source of every object. From them it
computes the object's mean position and flux, their spread, and how
many sources there are, exactly as `dev` does. It writes one row per
object into `astroobjectsmeta_<field>`. Everything the stage writes for
one association set is one statistics set: a named group of rows that
is either complete or absent. The stage never changes the association
set it reads.

## Inputs

`--inputs` is `crossmatch`'s completion manifest (supervisor step 1,
ruling R2, 2026-09-24). The stage reads its one `association-set` entry:

| Field | Used for |
|---|---|
| `instance` | the association set whose objects are described; named in `inputs.result_sets` |
| `key.field` | must equal the unit, the field's rtid |
| `key.base` | read from the database, not the manifest: the base the set extends |
| `key.source_sets` | read from the database, not the manifest: the source sets the set was made from |

The stage does not require the input manifest's own `stage` to be
`crossmatch`, only that it carries exactly one `association-set` entry
for the unit's field. The association set must already be registered:
the stage resolves everything else through the database by instance id.

### The membership

An association set is **base plus delta** (supervisor step 1, ruling
R3, 2026-09-24): its membership is its own rows plus the membership of
its base, recursively. The stage takes the chain of instances from
`objects.association_chain`, the input set first, and requires every
set in it to be a complete, retained `association-set`.

The sources an object's statistics are drawn from are the rows of the
source sets named in the `source_sets` key of every set in the chain.
Each source set resolves to its `sources_<yyyymmdd>_<sca>` child table by
instance (`objects.source_set_table`).

This one rule replaces three steps in `dev`: its `l2files` overlap lookup
of candidate child tables, its `pg_class` check that they exist, and its
`diffimages.vbest > 0` join. An association set names exactly the source
sets it was made from, so "best" is already decided upstream, by the
launcher's input selection (supervisor step 1, ruling R7, 2026-09-24).

## What it runs

The stage runs `dev`'s per-field steps, in `dev`'s order, and states
which are ported:

| `dev` step | In the rebuild |
|---|---|
| delete repeated `aid` rows of `astroobjects_<field>`, keeping the highest `ctid` (line 214) | not ported: a stage never mutates another set's rows, and `UNIQUE (result_set, aid)` makes the repeat impossible within a set |
| delete `astroobjects_<field>` rows with no `merges` row | not ported: same reason; such an object has no sources and gets no statistics row either way |
| find candidate `sources` child tables from `l2files`, keep those that exist | replaced by the membership above |
| one UNION ALL query, one SELECT per child table, filtered to `diffimages.vbest > 0` | ported; one SELECT per source set, filtered by the membership instead of `vbest` |
| delete `astroobjects_<field>` rows of objects with no best source | not ported: a stage never mutates another set's rows |
| per object, `compute_radec_statistics`, flux mean and standard deviation, source count | ported verbatim |
| one CSV, COPY into `astroobjectsmeta_<field>` | ported, with the run columns and through a temporary table with `ON CONFLICT DO NOTHING` (ruling R4) |
| drop and recreate `astroobjectsmeta_<field>` before, index and CLUSTER it after, VACUUM ANALYZE or drop it if empty | not ported: the table is made once, with its indexes, and appended to; each attempt writes a new set beside the old ones |

In order, inside one transaction:

1. Resolve the chain, the source sets and their child tables. When the
   chain names no source sets at all, exit 65; `dev` exits 7 when it
   finds no source tables.
2. With `[statistics] done_check` on, reuse a complete statistics set
   with the same key already written in this run (ruling R14).
3. Make `astroobjectsmeta_<field>` if it does not exist, through
   `create_astroobjectsmeta_child_table`. The function applies `dev`'s
   fillfactor 70, unlogged storage, its `nsources` and Q3C `meanradec`
   indexes and its grants, plus the rebuild's set-scoped UNIQUE and the
   `run` and `result_set` indexes.
4. Query the membership:

   ```sql
   SELECT a.aid, b.sid, b.ra, b.dec, b.fluxfit
   FROM merges_<field> AS a JOIN <sources child> AS b ON a.sid = b.sid
   WHERE a.result_set = ANY(<chain>) AND b.result_set = <source set>
   UNION ALL ...   -- one SELECT per source set
   ```

5. Group the rows by `aid`, as `dev` does. An `(aid, sid)` pair that
   appears under two sets of the chain counts once; the count of such
   repeats goes in the execution record.
6. Per object, in ascending `aid` order: `compute_radec_statistics`
   (`dev`'s `rapid_pipeline_subs.py`, verbatim), `np.mean` and `np.std`
   of the fluxes, and the source count. Then one CSV line in `dev`'s
   column order, then the run columns.
7. Register the statistics set, COPY the CSV, read back the row count
   for the set (it must equal the lines written, else exit 70), and
   commit.

`compute_radec_statistics` averages the sources' unit vectors, so the
0/360 RA wrap and the poles are handled. The RA spread is the standard
deviation of the shortest signed RA difference scaled by cos(Dec). Its
fifth value, the RMS angular spread, is only logged by `dev`:
`astroobjectsmeta` has no column for it. Two consequences, both as in
`dev`:

- A one-source object has standard deviations 0.0, not NaN, because
  `np.std` is the population standard deviation.
- A mean position a hair below RA 0 can come out as `meanra` exactly
  360.0, because a tiny negative angle modulo 360 rounds up.

`dev` writes objects in a set's iteration order, which is arbitrary.
The rebuild writes them in `aid` order; the table's contents are the
same.

## What lands in `astroobjectsmeta`

One row per object with at least one source in the membership, in
`astroobjectsmeta_<field>`. `dev`'s columns keep their meaning; the last
three are added by migration `20260924-03`, nullable, all set or all
null, and are set on every row the rebuild writes.

| Column | Source |
|---|---|
| `aid` | the object |
| `meanra`, `meandec` | the mean position, degrees |
| `stdevra`, `stdevdec` | the per-axis spread, degrees; RA's scaled by cos(Dec) |
| `meanflux`, `stdevflux` | mean and population standard deviation of the sources' `fluxfit` |
| `nsources` | the number of sources |
| `run` | the run |
| `attempt` | the statistics attempt that wrote the row |
| `result_set` | the statistics set's instance |

Keys are set-scoped (products page): `UNIQUE (result_set, aid)`.
Statistics for one object under two sets are two rows. `dev`'s
table-wide primary key on `aid` is not copied onto the rebuild's
per-field tables.

## The statistics set

One `statistics-set` result set per attempt, the products page's
database result set. Its unit is the field and its logical key is
`{"membership": <association-set instance>}`, which names the exact
membership it describes. The stage writes three things in the same
transaction as the rows:

- its `product_instances` row: kind `statistics-set`, stage
  `statistics`, this attempt as producer and registrar, custody by run
  kind;
- its `result_sets` row: `complete` true, `row_count` the objects with
  statistics;
- a dependency edge to the association set.

An association set whose membership has no `merges` rows gives an empty
set, still complete.

The manifest entry has no members; its `registration` block is
informational:

| Field | Meaning |
|---|---|
| `table` | `astroobjectsmeta_<field>` |
| `row_count` | objects with statistics, as in `result_sets.row_count` |
| `objects_in_set` | distinct `aid` among the membership's `merges` rows; equal to `row_count` unless a `merges` row names a source outside the chain's source sets |

`inputs.result_sets` names the association set; `inputs.products` is
empty. The execution record's `notes` carry the chain read and the
source sets resolved.

## Settings

`rapidpipe/settings/statistics.toml`. `dev`'s script reads no
load-bearing setting: its `.ini` reads serve its processing-date scan
or are never used. The rebuild's unit and input replace them.

| Setting | Default | Meaning |
|---|---|---|
| `[statistics] done_check` | true | reuse a complete statistics set with the same key already written in this run (ruling R14) |
| `[statistics] membership` | `association` | what the statistics describe; `pruned` is refused with 64 |

Delivered statistics describe the association set, as `dev` computes
them: `dev` runs crossmatch, then statistics, then prune. The pruned
set as a statistics input is designed in, since the key already names
either kind of set, and left unused (products page, lead, 2026-09-22).
The setting names that choice so turning it on later is a settings
change plus the code behind it.

## Exit codes

| Code | When |
|---|---|
| 0 | a statistics set was written, possibly empty, or reused under `done_check` |
| 64 | the unit id is not a non-negative decimal rtid, `membership` is not `association`, an invalid setting, or a bad `RAPIDPIPE_STATISTICS_DATABASE` |
| 65 | the input manifest carries no or several `association-set` entries, or one for another field. Also 65 when a set in the chain is unregistered, incomplete or not retained, or the chain names no source sets. Also 65 when a source set cannot be resolved to its child table, or `merges_<field>` does not exist |
| 70 | the loaded row count differs from the rows written, or any unclassified error |
| 75 | the database cannot be reached, or the connection is lost mid-transaction |

## Local execution

`make stage-statistics` runs the stage fixture
(`tests/fixtures/statistics/`) against a fake database. The fixture is a
two-set chain with an object spanning the RA wrap, a single-source
object, and a set outside the chain. It checks the manifest, the chain
read and each object's statistics against the ported function.
`rapidpipe selftest --stage statistics` runs the same fixture inside the
pipeline image. The same stage against PostgreSQL is
`tests/db/test_statistics.py`: it covers the rows, the instance,
`result_sets` and dependency rows, reuse on a second attempt, a second
set with the done check off, and base plus delta.

## Open

- `dev`'s aid self-dedupe (`computeStatisticsForAstroObjects.py:214`)
  deletes repeated `aid` rows of `astroobjects_<field>`, keeping the
  last written. How repeats arose in `dev`, and whether the rebuild's
  keep-the-first `ON CONFLICT` choice matches what `dev` intended,
  remains a question for Russ (supervisor step 1, ruling R7,
  2026-09-24).
