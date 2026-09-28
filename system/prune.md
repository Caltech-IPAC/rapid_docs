# The prune stage

**Status: DRAFT**

For one field, `prune` excludes association pairs whose sources came
from difference images that are not best for their positions. It records
the excluded pairs in a new table, `prunedmerges`. The resulting
`pruned-set` is its base association set minus those pairs; the base is
never mutated, and a stage never drops a table. The [products](products)
page fixes this vocabulary and rule: "A pruned set is its base association
set minus an explicit list of excluded pairs ... the base is never mutated".

The stage is ported from `dev`'s `pipeline/pruneNotBestMerges.py` onto
the pipeline repository's `rebuild` branch: `rapidpipe/stages/prune.py`,
`rapidpipe/settings/prune.toml`, migration `20260924-05-prunedmerges.sql`,
and `rapidpipe/db/objects.py`'s `insert_pruned_merges` and association-chain
helpers. `dev`'s `pruneNotBestMerges` uses `vbest = 0` to select pairs,
then runs `DELETE FROM merges_<field>`, drops any emptied `merges_<field>`
table and vacuums the rest. The rebuild ports the exclusion rule; the
deletion, table drop and VACUUM pass are not ported. Nor is
`dev`'s `pruneNotBestSources`, a separate script that deletes `sources`
rows by a global flag: it would delete rows another run's science still
depends on, breaking "science rows only by their own run".

## Inputs

`--inputs` is `crossmatch`'s completion manifest, read directly rather
than through an accumulated input set. `crossmatch` and `prune` share
the `field` unit. The manifest must contain exactly one `association-set`
output entry whose key names this field; zero or more than one is a
rejected input. `inputs.result_sets` names that instance.

## The exclusion rule

A pair is excluded when its source's difference image meets neither
condition for being best:

- `diffimages.vbest > 0`, maintained by promotion.
- The image was made by this run: `diffimages.run` equals this run's id.
  These images are registered with `vbest` 0 and promoted, if at all,
  after the loop.

`dev` also sets `vbest = 0` at registration and promotes later
(`updatePSF`'s pattern, mirrored for difference images), but its images
are already `vbest = 1` when it prunes. In the rebuild, a bare
`vbest = 0` check would exclude every pair a first pass produces because
nothing is promoted within that pass. The own-run clause therefore makes
the first pass exclude nothing, matching `dev`'s first pass. It also
excludes nothing for a production run's own, not-yet-promoted images.

A later `prune` attempt excludes pairs whose sources' difference images
have since been superseded (reassigned to another run, still `vbest = 0`),
as `dev`'s `vbest = 0` does once a newer image is promoted current.
Promotion maintains `vbest` as a current-membership flag ([runs](runs)
page), so both clauses are exercised now: the own-run clause keeps this
run's images, and the `vbest` clause excludes a pair once another run's
promotion supersedes its difference image.

## What it runs

The stage runs one transaction, following `dev`'s per-field exclusion
(`pruneNotBestMerges.py`) with the run model's base-plus-delta reads in
place of `dev`'s date scan:

1. Follow the association set's base chain (`objects.association_chain`:
   the instance and its bases, recursively, "base plus delta") and every
   chain member's own named source sets (`product_instances.logical_key
   ->> 'source_sets'`, resolved to their `sources` child tables with
   `objects.source_set_table`). A crossmatch pass may have read source
   sets its base did not, so the not-best set below is built over the
   whole chain's sources, not just this attempt's own.
2. Build `dev`'s not-best `sid` set, one temporary table for the whole
   field, one `UNION`ed `SELECT` per (source-set instance, its table)
   pair. As `dev`'s own comment explains, `UNION` removes duplicate `sid`
   values across source-set tables; with `UNION ALL`, those duplicates
   would violate the temporary table's primary key. The exclusion rule above
   replaces `dev`'s bare `vbest = 0`.
3. Select the chain's `merges_<field>` pairs (`result_set = ANY(chain)`)
   whose `sid` is in the not-best set, deduplicated.
4. Register the new `pruned-set` result set (below), then insert the
   excluded pairs into `prunedmerges` with `objects.insert_pruned_merges`
   before committing. Registration comes first because `prunedmerges`
   rows carry foreign keys to the new set's `result_sets` row, as
   [load](load) registers before it COPYs.

## What lands in `prunedmerges`

One row per excluded pair, `database/migrations/20260924-05-prunedmerges.sql`:

| Column | Source |
|---|---|
| `result_set` | the new pruned-set instance |
| `base_set` | the association-set instance this pruned set excludes pairs from |
| `aid`, `sid` | the excluded pair, from `merges_<field>` |
| `run`, `attempt` | the run and the prune attempt that wrote the row |

`PRIMARY KEY (result_set, aid, sid)` allows each pair at most once per
pruned set. `insert_pruned_merges` uses `ON CONFLICT DO
NOTHING`, so a retried insert within one attempt is a no-op. All fields
share one table because the base set's logical key already names its
field and the rows are few.

## The pruned set

Each prune attempt produces one `pruned-set` result set (products page),
unit field. Its logical key, `{base, settings_hash}`, names the base
association-set instance and the resolved settings' hash. It has no
`field` of its own because the base already names one. The manifest
entry has no members and carries this `registration` block:

| Field | Meaning |
|---|---|
| `row_count` | pairs excluded, as in `result_sets.row_count` -- 0 for an empty exclusion, still a complete set |
| `base_row_count` | `merges_<field>` rows over the whole base chain, before exclusion |
| `table` | `prunedmerges` |
| `rule` | `not-best`, the only rule (`[prune] rule`) |

The loop names each field's pruned set in every alerts input set touching
that field. Alerts history omits the listed pairs; the base's
`merges_<field>` rows remain unchanged. The [alerts](alerts) page has
the binding. Alerts is the only consumer named for `prunedmerges` so far.

## Reuse and retries

With `[prune] done_check` on (the default), the stage reuses a complete,
retained pruned set already written in this run with the same key
(same base and settings hash) and writes nothing. Reuse requires the
producing attempt to be the calling attempt or to have disposition
`succeeded` (`db/objects.find_complete_result_set`, joining `attempts`;
the [runs](runs) page has the general rule).

A set left by an attempt that committed rows and then failed, or by
another attempt still without a disposition, is not reused. A retry
after a failed commit therefore writes a fresh set instead of adopting
the orphaned one. `[prune] done_check = false` forces a fresh attempt,
as needed when retrying after the association set's sources' promotion
state has changed. `dev` has no done file for this stage:
`pruneNotBestMerges` always re-derives and re-deletes.

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
