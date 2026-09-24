# The prune stage

**Status: DRAFT**

What the `prune` stage reads, the exclusion rule it runs, what lands in
`prunedmerges`, the pruned set it records, its settings and exit codes.
Written 2026-09-24 from the port that landed on the pipeline repository's
`rebuild` branch (`rapidpipe/stages/prune.py`, `rapidpipe/settings/prune.toml`,
migration `20260924-05-prunedmerges.sql`, `rapidpipe/db/objects.py`'s
`insert_pruned_merges` and the association-chain helpers), ported from
`dev`'s `pipeline/pruneNotBestMerges.py` (supervisor step 1, ruling R6,
2026-09-24). The [products](products) page fixes the vocabulary; this
page records how the stage meets it.

## In plain terms

For one field, `dev`'s `pruneNotBestMerges` deletes every `merges_<field>`
pair whose source came from a difference image that is not the best one
for its position (`vbest = 0`), then drops any `merges_<field>` table it
emptied and vacuums the rest. The rebuild ports the exclusion rule but not
the deletion: `prune` records the excluded pairs in a new table,
`prunedmerges`, as a `pruned-set` result set -- its base association set
minus those pairs. The base is never mutated, and a stage never drops a
table (products page, "A pruned set is its base association set minus an
explicit list of excluded pairs ... the base is never mutated").

## Inputs

`--inputs` is `crossmatch`'s completion manifest. The stage
reads its one `association-set` output entry whose key names this field
(step 1 ruling R2: `crossmatch` and `prune` share the `field` unit, and
`prune` reads `crossmatch`'s manifest directly, not an accumulated
input set). Exactly one such entry is required; zero or more than one is
a rejected input. `inputs.result_sets` names that instance.

## What it runs

One transaction, following `dev`'s per-field exclusion (`pruneNotBestMerges.py`)
with the run model's own base-plus-delta reads (ruling R3) in place of
`dev`'s date scan:

1. Follow the association set's base chain (`objects.association_chain`:
   the instance and its bases, recursively -- "base plus delta") and every
   chain member's own named source sets (`product_instances.logical_key
   ->> 'source_sets'`, resolved to their `sources` child tables with
   `objects.source_set_table`). A crossmatch pass may have read source
   sets its base did not, so the not-best set below is built over the
   whole chain's sources, not just this attempt's own.
2. Build `dev`'s not-best `sid` set, one temporary table for the whole
   field, one `UNION`ed `SELECT` per (source-set instance, its table)
   pair -- `UNION`, not `UNION ALL`, as `dev`'s own comment explains: a
   `sid` occurring in more than one source-set table would otherwise
   violate the temporary table's primary key. Ruling R6's exclusion rule,
   below, replaces `dev`'s bare `vbest = 0`.
3. Select the chain's `merges_<field>` pairs (`result_set = ANY(chain)`)
   whose `sid` is in the not-best set, deduplicated.
4. Register the new `pruned-set` result set (below), then insert the
   excluded pairs into `prunedmerges` with `objects.insert_pruned_merges`
   -- registration first, since `prunedmerges`' rows carry foreign keys to
   its own `result_sets` row, as [load](load) registers before it COPYs.
   Commit.

`dev`'s `DELETE FROM merges_<field>` of the excluded pairs, its drop of an
emptied `merges_<field>` table, and its VACUUM pass are not ported: a
pruned set records exclusions instead of mutating its base, and a stage
never drops a table (ruling R6). `dev`'s `pruneNotBestSources` -- a
separate script that deletes `sources` rows by a global flag -- is not
ported either: it would delete rows another run's science still depends
on, breaking "science rows only by their own run".

## The exclusion rule

Ruling R6 (supervisor step 1, 2026-09-24): a pair is excluded when its
source's difference image is not best, where best means
`diffimages.vbest > 0` (maintained by promotion) **or** the difference
image was made by this run (`diffimages.run` equals this run's id, whose
rows are registered with `vbest` 0 and promoted, if at all, after the
loop). `dev` sets `vbest = 0` at registration and promotes it later
(`updatePSF`'s pattern, mirrored for difference images); a bare
`vbest = 0` check would therefore exclude every pair a first pass ever
produces, since nothing is promoted yet within one pass. The own-run
clause is what makes a first pass exclude nothing, as `dev`'s first pass
does -- `dev` reaches the same result because its own images are already
`vbest = 1` by the time it prunes, this run's own images are not yet
promoted at all. A later `prune` attempt, pruning an association set
whose sources' difference images were since superseded (reassigned to
another run, still `vbest = 0`), excludes them, as `dev`'s `vbest = 0`
does once a newer image is promoted current. Ruling R6 depends on
promotion maintaining `vbest` for difference images, not yet built (step
1 Codex plan review; recorded there as a step 3/6 prerequisite) -- until
then, only the own-run clause is exercised.

## What lands in `prunedmerges`

One row per excluded pair, `database/migrations/20260924-05-prunedmerges.sql`:

| Column | Source |
|---|---|
| `result_set` | the new pruned-set instance |
| `base_set` | the association-set instance this pruned set excludes pairs from |
| `aid`, `sid` | the excluded pair, from `merges_<field>` |
| `run`, `attempt` | the run and the prune attempt that wrote the row |

`PRIMARY KEY (result_set, aid, sid)`: a pair is excluded from one pruned
set at most once; `insert_pruned_merges` inserts with `ON CONFLICT DO
NOTHING`, so a retried insert within one attempt is a no-op (ruling R4's
pattern). One table for every field, not a per-field table: the base set
already names its field through its own logical key, and the rows are
few.

## The pruned set

One `pruned-set` result set per prune attempt (products page): unit
field, logical key `{base, settings_hash}` -- the base association-set
instance and the resolved settings' hash, no `field` of its own (the
base already names one). The manifest entry has no members; its
`registration` block:

| Field | Meaning |
|---|---|
| `row_count` | pairs excluded, as in `result_sets.row_count` -- 0 for an empty exclusion, still a complete set |
| `base_row_count` | `merges_<field>` rows over the whole base chain, before exclusion |
| `table` | `prunedmerges` |
| `rule` | `not-best`, the only rule (`[prune] rule`) |

`inputs.result_sets` names the association-set instance `prune` read.

With `[prune] done_check` on (ruling R14, the default), a complete pruned
set with the same key -- same base, same settings hash -- already written
in this run is reused and nothing is written; `[prune] done_check = false`
forces a fresh attempt, as a retry after the association set's sources'
promotion state has changed needs. `dev` has no done file for this stage
at all: `pruneNotBestMerges` always re-derives and re-deletes.

## Settings

`rapidpipe/settings/prune.toml`:

| Setting | Default | `dev` |
|---|---|---|
| `[prune] rule` | `not-best` | the only rule `dev`'s script runs; any other value is a usage error, since nothing else exists to route it to yet |
| `[prune] done_check` | true | `dev` has no done file for this stage |

## Exit codes

| Code | When |
|---|---|
| 0 | pruned, or reused under `done_check` (an empty exclusion is still a complete set) |
| 64 | the unit id is not a non-negative field (rtid) integer, an unknown `[prune] rule`, or an invalid `[prune] done_check` |
| 65 | the input manifest does not have exactly one `association-set` entry naming this field |
| 70 | the rows inserted into `prunedmerges` differ from the pairs written, or any unclassified error |
| 75 | the database cannot be reached, or the connection is lost mid-transaction |

## Local execution

`make stage-prune` runs the stage fixture (`tests/fixtures/prune/`)
against a fake database and checks the excluded pairs across all three
`vbest`/`run` cases; the same path against PostgreSQL is
`tests/db/test_prune.py`.
