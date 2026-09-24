# The crossmatch stage

**Status: DRAFT**

What the `crossmatch` stage reads, what it writes into `astroobjects_<field>`
and `merges_<field>`, the association set it records, the settings it
takes and its exit codes. Written 2026-09-24 from the port on the
pipeline repository's `rebuild` branch (`rapidpipe/stages/crossmatch.py`,
`rapidpipe/science/crossmatch/catalog.py`,
`rapidpipe/settings/crossmatch.toml`, `rapidpipe/db/objects.py`,
migrations `20260924-03` to `-06`), ported from `dev`'s
`pipeline/crossMatchSources.py`. The port follows the lead's rule of
2026-09-22: minimise differences to `dev`, and design in, off by default,
anything that can be left unused. The [products](products) page fixes the
vocabulary; the rulings cited below are the supervisor's for step 1,
2026-09-24.

## In plain terms

For one field, a tile of the Roman sky tessellation, the stage decides
which astronomical object each newly loaded source belongs to. It walks
the field's exposures in time order. Each unflagged source is compared
with the field's known objects: a source within half a pixel of an object
is recorded as another sighting of it, and a source near no object
becomes a new object at its own position. A second pass then picks up
sources just across the field's edge, in the eight neighbouring tiles,
that sit on one of this field's objects. Everything one attempt writes is
one association set: a named group of rows that is either complete or
absent.

## Inputs

`--inputs` is a manifest naming what to match. It is either a `load`
completion manifest (one source set) or an input-set manifest composed
from several (ruling R2). The stage reads:

| Entry | Count | Used for |
|---|---|---|
| `source-set` | one or more | the sources to match. Each instance's `sources` child table is found through its difference image's `l2files` row (`objects.source_set_table`), never by date arithmetic; rows are read with `result_set` equal to the instance |
| `association-set` | none or one | the base: the field's prior catalog, frozen by whoever composed the inputs. Its `key.field` must be the unit's field |

The unit is the field's tessellation id (rtid) as a decimal string. The
stage filters sources by `field = <unit>` itself, so a manifest can name
source sets that also cover other fields; the launcher's per-field
fan-out needs no new manifest shape (ruling R2).

`inputs.result_sets` lists every source set and the base, sorted;
`inputs.products` is empty.

## What it runs

`dev`'s steps for one field, in `dev`'s order, in one transaction on one
connection. `dev` scans a processing date's jobs for their sources tables
and distinct fields (`util.lookup_source_tables_to_crossmatch_and_distinct_fields`)
and runs the fields in a process pool; the rebuild's unit is one field
and its input names the sets, so the scan and the pool are the
launcher's.

1. Take `pg_advisory_xact_lock(20260924, <field>)`, so two attempts on
   one field run one after the other. Without it, their CLUSTERs can
   deadlock on the lock upgrade (ruling R13).
2. Make `astroobjects_<field>` and `merges_<field>` if new (`dev`'s
   `main()` steps 3 to 5, lines 985-1091), through
   `create_field_object_tables`.
3. List the field's exposures: per source set, `SELECT DISTINCT expid,
   mjdobs ... WHERE field = <field> AND flags = 0`, merged and sorted by
   `mjdobs` ascending exactly as `dev` sorts its dict (lines 219-257).
4. Stage 1, per exposure in that order, per source set holding it
   (lines 267-547):
   - Query A: the exposure's unflagged sources in the field joined to
     the catalog with `q3c_join(a.ra, a.dec, b.ra0, b.dec0,
     match_radius)`. Each (source, object) pair becomes a merges row. A
     source near two objects gets two rows, as in `dev`.
   - Query B: the same sources again. Each source Query A did not match
     becomes a new object, `aid = radec_index(ra, dec)` (`dev`'s
     `util.radec_index`, ported into `rapidpipe.science.spatial`), with
     one astroobjects row and one merges row.
   - After the exposure, COPY the astroobjects file, then the merges
     file. The next exposure's Query A therefore sees this exposure's new
     objects, as in `dev`.
5. CLUSTER `astroobjects_<field>` on its position index and ANALYZE both
   tables (`dev`'s `main()` step 7, lines 1156-1186), through
   `cluster_field_object_tables`, when `[crossmatch]
   cluster_between_passes` is on (ruling R5).
6. Stage 2, per neighbouring field, per source set (lines 581-889). The
   neighbours come from the certified closed-form tessellation already in
   the tree; `dev` reads them from its SQLite tessellation file. For a tile with eight neighbours,
   `dev` first draws an inclusion cone around the field's centre: the
   largest centre-to-corner separation plus `match_radius` (lines
   673-703), and the query adds `q3c_radial_query(a.ra, a.dec, ra0,
   dec0, cone)`. A tile with any other count, near a pole, is queried
   without the cone. The neighbour's unflagged sources are joined to this
   field's catalog; each pair becomes a merges row. No objects are made:
   an unmatched neighbour source gets its object when its own field runs.
   One COPY of the merges file follows the loop.
7. Count the new set's rows in both tables; each count must equal the
   rows the copies inserted, or the stage stops with exit 70.
8. Register the association set, then commit.

The registration comes after the passes. `load` registers its set before
the COPY; here `register_manifest` writes the set's `row_count` when it
inserts the `result_sets` row, and the count is known only after both
passes. The per-field tables carry no foreign keys, so nothing needs the
instance row first; rows and registration still commit together.

One difference changes the work and leaves the rows alone. `dev` runs Query A and B
against every sources table for every exposure. The rebuild queries only
the sets whose exposure list holds that exposure, which returns the same
rows.

## The child tables

`astroobjects_<field>` and `merges_<field>` are made `LIKE` the
`astroobjects` and `merges` prototypes, one pair per field, as in `dev`.
`dev`'s crossmatch makes them as a login holding `rapidporole`; the
rebuild's service login holds table grants only, so three SECURITY
DEFINER functions owned by `rapidporole` do that work (migration
`20260924-04`, EXECUTE granted by `-06`):

- `create_field_object_tables(field)`: `dev`'s creation, unlogged,
  owner `rapidporole`, its four indexes (`aid` on both, the Q3C position
  index on `astroobjects`, `sid` on `merges`) and its grants, plus the
  rebuild's run columns, set-scoped keys and `result_set`/`run` indexes.
  An advisory lock serialises two stages making the same pair. A table
  `dev` already made is adopted in place.
- `create_astroobjectsmeta_child_table(field)`: `statistics`' table, not
  used here.
- `cluster_field_object_tables(field)`: `dev`'s CLUSTER on the position
  index and ANALYZE of both tables.

**Uniqueness (ruling R4).** `merges_<field>` has `UNIQUE (result_set,
aid, sid)` and `astroobjects_<field>` has `UNIQUE (result_set, aid)`. The
keys are scoped to the set: two scratch runs over the same sources
make the same `aid`s under different sets, and the products page scopes
keys to their set. Each COPY loads a temporary table and inserts with
`ON CONFLICT DO NOTHING`, counting the rows inserted. `dev`'s children
carry no key at all (`LIKE ... INCLUDING CONSTRAINTS` does not copy the
prototype's primary key), so `dev` keeps every repeated row: two
unmatched sources at one position in one exposure give it two objects
with one `aid`, and its `statistics` step later deletes all but the last.
The rebuild keeps the first row inserted and never writes the second.
`dev`'s `pruneRedundantMerges` is folded into the same insert.

**The catalog a pass reads (ruling R3).** An association set's rows are
its own plus its base's, recursively (`objects.association_chain`, which
follows `logical_key->>'base'`). Both passes read `astroobjects` rows
whose `result_set` is in the base's chain or is this attempt's own new
set: "base plus delta". Nothing is selected by custody, so a set's
result depends only on its named inputs. With no base, the catalog is
the attempt's own objects only, and a second attempt over the same
sources makes the same objects again under its own set.

**Rows without a run.** Rows `dev` wrote before the run model have
`run IS NULL` and belong to no set, so no chain includes them.
`[crossmatch] legacy_catalog` reads them as catalog too
(`b.result_set = ANY(...) OR b.run IS NULL`). It is for the cutover onto
production `rapid`, where `dev`'s per-field tables exist; `rapid_rebuild`
has no such rows, and the setting is off by default. Adopting a `dev`
table adds the run columns but no rows to any set.

## What lands in `astroobjects` and `merges`

`dev`'s columns keep their meaning; the last three are added by
migration `20260924-03`, nullable, all set or all null, and set on every
row the rebuild writes.

`astroobjects_<field>`, one row per new object:

| Column | Source |
|---|---|
| `aid` | `radec_index(ra, dec)` of the source that made the object: RA and Dec each in 1/3300-arcsecond units, packed into one integer |
| `ra0`, `dec0` | that source's `ra`, `dec` |
| `flux0` | that source's `fluxfit` |
| `run` | the run |
| `attempt` | the crossmatch attempt |
| `result_set` | the association set's instance |

`merges_<field>`, one row per (object, source) pairing:

| Column | Source |
|---|---|
| `aid` | the object |
| `sid` | the source's `sid` in its `sources` child table |
| `run`, `attempt`, `result_set` | as above |

The CSV lines are `dev`'s: each value's Python `str()`, comma-joined,
unquoted, with the three run columns appended.

## The association set

One `association-set` result set per attempt, unit field. The stage
writes its `product_instances` row (kind `association-set`, stage
`crossmatch`, this attempt as producer and registrar, custody by run
kind), its `result_sets` row (`complete` true, `row_count` the merges
rows written) and dependency edges to every source set and the base, in
the same transaction as the rows (ruling R10).

Logical key:

| Field | Value |
|---|---|
| `field` | the unit's rtid, an integer |
| `base` | the base association set's instance, or null |
| `source_sets` | the source-set instances read, sorted |
| `settings_hash` | the attempt's resolved settings hash |

The manifest entry has no members. Its `registration` block:

| Field | Meaning |
|---|---|
| `astroobjects_table`, `merges_table` | `astroobjects_<field>`, `merges_<field>` |
| `row_counts.astroobjects` | objects inserted |
| `row_counts.merges` | merges rows inserted, as in `result_sets.row_count` |
| `row_counts.merges_pass1`, `merges_pass2` | the same, by pass |
| `row_counts.new_objects` | unmatched sources given an object, counted before ON CONFLICT; larger than `astroobjects` when sources repeat a position |

A retry is a new attempt with a new instance. `[crossmatch] done_check`
is the rebuild's form of a done file (ruling R14). A complete set with the
same logical key already written in the same run is reused, nothing is
written, and the manifest names that instance. Its `row_counts` then
carries `astroobjects` and `merges` only. A retry can follow a failure
after the rows committed but before the manifest was published. The done
check then names the existing set instead of writing a second one. The
gap itself is a stage-contract matter and is not closed here.

## Settings

`rapidpipe/settings/crossmatch.toml`. `dev` reads its `.ini`
(`cdf/awsBatchSubmitJobs_launchSingleSciencePipeline.ini`) for two
values; the rest of the section it loads is unused (ruling R11).

| Setting | Default | `dev` |
|---|---|---|
| `[source_matching] match_radius` | 0.00001528 | `[SOURCE_MATCHING] match_radius`, degrees, "half of 0.11 arcsec (a Roman WFI pixel)" |
| `[crossmatch] source_flags` | 0 | `flags = 0`, hard-coded in every sources query |
| `[crossmatch] cluster_between_passes` | true | `main()` step 7, always run |
| `[crossmatch] legacy_catalog` | false | none: `dev` reads the whole table; see "Rows without a run" |
| `[crossmatch] done_check` | true | none: `dev` has no done file for crossmatch |

`dev`'s `[SCI_IMAGE] ppid` served only the processing-date job scan,
which the input manifest replaces, so it is not carried. `NUM_CORES` is
the launcher's fan-out.

## Exit codes

| Code | When |
|---|---|
| 0 | the set was written, or reused under `done_check` |
| 64 | the unit is not a decimal rtid, an unknown or invalid setting, or a bad `RAPIDPIPE_CROSSMATCH_DATABASE` |
| 65 | no `source-set` entry, two `association-set` entries, a base for another field, or a source set or base that is unregistered, incomplete, not retained, or has a broken chain |
| 70 | a table's row count for the new set differs from the rows inserted, or any unclassified error |
| 75 | the database cannot be reached, or the connection is lost mid-transaction |

## Local execution

`make stage-crossmatch` runs the stage fixture (`tests/fixtures/crossmatch/`)
against a fake database. The fixture uses field 4662268, an interior tile
with eight neighbours, and two source sets whose time order is the
reverse of their exposure-id order. It checks both passes, a flagged
source, a repeated position and a match across the north edge.
`rapidpipe selftest --stage crossmatch` runs the same fixture inside the
pipeline image. The PostgreSQL path, with Q3C, is
`tests/db/test_crossmatch.py`, which loads a synthetic source set
through the real difference, register and load chain first.
