# The alerts stage

**Status: DRAFT**

The `alerts` stage builds an Avro container for one finalized difference
image and records each alert in an outbox. It lands on the pipeline
repository's `rebuild` branch
(`rapidpipe/stages/alerts.py`, `rapidpipe/science/alerts/`,
`rapidpipe/db/alerts.py`, `rapidpipe/products/alertcontainer.py`,
`rapidpipe/settings/alerts.toml`, migration
`20260924-07-alert-outbox.sql`), ported from `dev`'s
`pipeline/produceAlertsForProcDate.py` and `alerts/` (schema
`rapid.v00_04`). Every ported stage minimises differences from `dev` and
leaves optional features designed in but off by default. The
[products](products) page fixes the vocabulary; this page states how
the stage meets it and amends two of its paragraphs below.

## In plain terms

The stage reads the image's sources from a named source set, their
objects from named association sets (one per field the image touches),
and the objects' statistics from the sets that describe them. As `dev`
does, it builds one Avro alert per unflagged, associated source and
writes them into one container with `dev`'s summary JSON.

Each outbox row names the alert's container, Avro block and record
position within both. `dev` writes files only, with no database row
naming an alert. The rebuild needs that row, so the stage registers the
container and outbox row set as its own products in the transaction
that writes the rows.

Kafka publication, alert naming and two of the three cutout images are
ported as designed-in, off-by-default mechanisms, as `dev` leaves them.
`dev` never calls its naming procedures or Kafka publisher from the
pipeline path.

## Inputs

Unit: detector-image. `--inputs` is an input-set manifest, stage
`input-set`, not a producing stage's completion manifest:

| Part | Content | Used for |
|---|---|---|
| `outputs[]` `difference-image`, exactly one | the finalized instance; its key `differencer` must equal `[alerts] diff_flavor`; member role `difference`, size and SHA-256 verified | `cutoutDifference`; the `diffimages` row (`pid`), looked up through `diffimages.instance` |
| `outputs[]` `reference-catalog`, at most one | its primary member, a SExtractor catalog; this kind's registration block is not fixed yet, so none is required | `refStarMatches`/`refGalaxyMatches` when `[alerts] refcat` is set; absent means both stay null |
| `inputs.result_sets` | instance ids, classified by looking up each one's kind in `product_instances`: exactly one `source-set`, one or more `association-set`, any number of `statistics-set`, and any number of `pruned-set`, each complete | the source, association and statistics rows, each association set's lineage (below), and, where named, the pairs each pruned set excludes from history |

A statistics set must describe exactly one named association set, and
each association set may have at most one describing statistics set;
either violation exits 65. Here, "describes" means that a value in the
statistics set's `product_instances.logical_key` equals the association
set's instance id. This rule is not fixed elsewhere on rebuild; the
fixture uses `{"membership": <set>}`. Without a describing statistics
set, the stage uses `dev`'s fallback for objects whose statistics have
not run: null sigmas and a count of `merges` rows for `nDiaSources`.

A pruned set's logical-key base must equal a named association set's
instance id, and each association set may have at most one pruned set;
either violation exits 65. Every read of the base association set's
chain excludes the pairs listed in the pruned set: a `merges` row whose
`(aid, sid)` appears in `prunedmerges` supplies no association and is
excluded from the `nDiaSources` fallback and history. A trigger whose only
`merges` rows are excluded is dropped as unassociated.

Without a named pruned set, the stage reads every pair as before and
records `"none"` in the execution record's `notes.pruned_sets`.
Otherwise, that note lists the applied pruned sets. They appear in
`inputs.result_sets` and become dependencies of the alert container.

A worked example, with two fields:

```json
{
  "schema_version": "1",
  "run": "01J8Y6QZ3M00000000000000RN",
  "unit": {"kind": "detector-image", "id": "e20260821001234/SCA07"},
  "stage": "input-set",
  "attempt": "01J8Y6QZ3M00000000000000AT",
  "execution_record": "exec/01J8Y6QZ3M00000000000000AT.json",
  "inputs": {
    "manifest": "inputs/manifest.json",
    "products": {},
    "result_sets": [
      "01J8Y6QZ3M00000000000SRCS1",
      "01J8Y6QZ3M00000000000ASSC1", "01J8Y6QZ3M00000000000STAT1",
      "01J8Y6QZ3M00000000000ASSC2", "01J8Y6QZ3M00000000000STAT2"
    ]
  },
  "outputs": [
    {
      "kind": "difference-image", "format_version": "1",
      "instance": "01J8Y6QZ3M0000000000000D1F",
      "key": {"l2": "01J8Y6QZ3M00000000000000L2",
              "reference": "01J8Y6QZ3M0000000000000REF",
              "differencer": "zogy", "settings_hash": "sha256:0000...0000"},
      "primary": "diff/zogy_diffimage_masked.fits",
      "members": [{"role": "difference", "path": "diff/zogy_diffimage_masked.fits",
                   "bytes": 164160, "sha256": "sha256:..."}],
      "registration": {}
    },
    {
      "kind": "reference-catalog", "format_version": "1",
      "instance": "01J8Y6QZ3M00000000000RCAT1",
      "key": {"reference": "01J8Y6QZ3M0000000000000REF", "catalog_type": "sextractor"},
      "primary": "ref/refimage_sexcat.txt",
      "members": [{"role": "catalog", "path": "ref/refimage_sexcat.txt",
                   "bytes": 1234, "sha256": "sha256:..."}],
      "registration": {}
    }
  ]
}
```

The image touches fields 5321 and 5322, each with its own association
set and describing statistics set. The five `result_sets` entries carry
no roles. The stage identifies them by kind and, for statistics sets,
the association set each instance is registered under, never by its
position in the list.

## What it reads

Sources are read through the `sources` parent table. Its per-date,
per-detector children inherit from `sources`, so a `result_set` filter
on the parent covers every row. Objects and merges come from step 1's
per-field tables, `astroobjects_<field>` and `merges_<field>`, and
statistics from `astroobjectsmeta_<field>`. These standalone tables
have no shared parent; the stage builds each name with
`rapidpipe.db.objects.field_table_names`. A named association set's
logical-key `field` must be a non-negative integer or its decimal
string. An invalid field or a missing field table exits 65.

### Lineage

Crossmatch can extend an earlier association set, named by `base` in
the extending set's logical key. The extending set's
`merges`/`astroobjects` rows hold only new detections and newly created
objects; a known object's `astroobjects` row stays in the set that
created it. The stage resolves each named association set's full chain,
newest first, with `rapidpipe.db.objects.association_chain`; a broken
chain exits 65. Base sets are appended to `inputs.result_sets` and
become dependencies of this attempt, just like directly named sets.
Statistics sets need no chain: `statistics` computes each set over the
whole membership, including bases, and keys it directly to that
membership.

### Sources, associations and history

The stage reads `sources` whose `result_set` is the source set and
whose `pid` is the finalized instance's `diffimages` row. Sources with
`flags <> 0` are counted and listed as dropped in the summary, reason
`flagged`, and never assembled, following `dev`'s `iter_sources`.
Alertable sources have `flags = 0`; they are joined to `filters` for
`band` and `exposures` for `exptime`, then ordered by `sid`.

For each alertable source, the stage finds a `merges` row in any named
association set's chain and joins it to that set's `astroobjects`.
When several sets in a chain have the row, the newest wins. When a
source has several `merges` rows, the lowest `aid` wins.
`nDiaSources` comes from the describing statistics set's `nsources`
where one exists; otherwise it counts the object's `merges` rows
across the whole chain, `dev`'s fallback before an object's statistics
have run. A source with no `merges` row in any chain is dropped as
`unassociated`. A `merges` row with no matching `astroobjects` row
anywhere in its chain is dropped as `orphan`, `dev`'s
`AssociationError` case.

History, `prvDiaSources`, consists of the object's other `merges` rows
across its association set's chain, joined back to `sources` in any
result set. Those rows are the association set's frozen dependencies,
not this attempt's. As in `dev`, history is bounded by time, with no
count limit: it reaches back `[alerts] prv_window_days` before the
source's `mjdobs` and has no upper bound. A later detection of the same
object therefore also counts as previous history. Named pruned sets'
excluded pairs are removed before applying the time window, under the
pruned-set rule above.

"Any result set" is restricted here to the source sets named by the
association chains (each key's `source_sets`). Every history and
association read must satisfy the [products](products) page's reading
rule: the source set must be complete, retained, and either the alerts
run's own or `candidate`/`current` from a selected attempt. A chain
naming a scratch or unselected source set exits 65. Only the named sets
and their bases get dependency edges on the alert container; the chain
source sets do not (open item).

An input product without a `product_instances` row, such as a reference
catalog registered by `dev`, is still read and cross-matched. It gets
no dependency edge and is recorded in the execution record's
`notes.unregistered_inputs` rather than `inputs.products`, following
`difference`'s rule for a `dev`-registered reference.

## What it writes

The stage writes one Avro object container per unit using `dev`'s
schema `rapid.v00_04`, codec `deflate` at compression level 1, and
16,000-byte sync interval. Its summary JSON keeps the shape of `dev`'s
`BatchStats.as_dict()`, adding the flagged count and full dropped list
with reasons. A unit with no alertable sources still produces a
zero-record container and a complete, empty `alert-set`.

### Registration: `alert-container` and `alert-set`

In the transaction that writes the outbox rows, the stage registers an
`alert-container` file product (container and summary members) and an
`alert-set` result set (no members, the container's key, `complete`
true, and `row_count` equal to the outbox rows written). `alerts` both
produces and initially registers these outputs; every other stage
writes a manifest for a separate `register` run.

`register` can validate and replay the same manifest. It checks the
`alert-container` and `alert-set` entries, including every member's
role, path, size and SHA-256, against what `alerts` wrote and adds
nothing. This is the same no-op replay other kinds get, and requires
`register` to know both kinds. This amends the products page's "Alert
names are not a file product" paragraph, which said `register` records
the container. The stage initially records it; standalone `register`
replays it.

Registration precedes the outbox insert because outbox rows have
immediate foreign keys to `product_instances` and `result_sets`.
This reverses the originally specified order. Both still commit in one
transaction, with nothing visible half-written.

`register` learns both kinds. The `alert-container` validator requires
the `container` and `summary` member roles and the registration fields
below. `alert-set` is validated as a result set with registration
`{row_count, table: "alert_outbox"}`. Registering either writes only its
own instance row, as for a `source-catalog` entry today. The outbox rows
and container bytes are the science content; both are durable when
either manifest is registered.

The container's registration block contains `alert_count`,
`dropped_count`, `schema_version`, the finalized
`difference` instance, the registered reference-catalog instance when
one was read, and the sets it read, as both lists and, for convenience,
the first of each list: `association_sets` and `association_set`,
`statistics_sets` and `statistics_set`. A singular value is null only
when its list is empty. Dependencies are recorded for the difference
instance, a registered reference-catalog instance, every named
association and statistics set, every base set a lineage chain pulled
in, and every named pruned set; an unregistered reference catalog gets
no edge, per "What it reads" above.

On success, the stage sets `diffimages.nalertpackets = 1` on the
finalized instance's `diffimages` row. Matching both `instance` and
`run` limits the update to the row this run's `register` created. An
instance belonging to another run matches no row; the stage logs a
warning and records the count in the execution record's notes without
failing.

### Recovery

Rerunning an attempt whose commit landed recovers the existing result
without duplication. The stage regenerates the container and summary
from the same inputs, with the same records in the same order and
deflate at level 1. It derives the sync marker from the SHA-256 of the
attempt id instead of using `dev`'s random marker. Embedded schema
field keys are sorted because `fastavro` otherwise orders them by the
process's hash seed. Every alert shares one `timeProcessedMjd`, reused
from the outbox rows; `dev` uses a separate timestamp per alert.

The stage checks regenerated bytes, members and locators against the
registered and written result; any difference exits 70. The live
service `NED` is the one input that can change a rerun's bytes.

### The alert outbox

`alert_outbox` is a new table, one row per alert, written by the stage
alongside its two registrations:

| Column | Meaning |
|---|---|
| `id` | the row's own id |
| `run`, `attempt` | this alerts attempt |
| `instance` | the registered `alert-container` instance |
| `result_set` | the registered `alert-set` instance |
| `alert_name` | null (below) |
| `candidate` | the source's `sid`, the alert's `diaSourceId` |
| `object` | the associated object's `aid`, the alert's `diaObjectId` |
| `pid` | the finalized difference instance's `diffimages` row |
| `first_seen_mjd` | `diaObject.firstDiaSourceMjd`: the minimum `mjdobs` over the trigger and its previous detections |
| `ra`, `dec` | the trigger source's `ra`, `dec` |
| `record_ordinal` | the record's 0-based position in the whole container; `UNIQUE (instance, record_ordinal)` |
| `block_offset`, `block_length` | the byte offset and size (sync marker included) of the Avro block holding this record, read back with `fastavro.block_reader` once the container is closed |
| `record_index` | the record's 0-based position within that block |
| `time_processed_mjd` | the one `timeProcessedMjd` stamped on every alert in this container |
| `schema_version` | `00.04` |
| `written_at` | when the row was written |
| `published_at`, `topic`, `publication_ref` | null: set by a publisher this port does not build (below) |

Packing follows `dev`, so a block ordinarily holds several records.
Only the compressed block has a byte range; individual records do not.
`block_offset` and `block_length` identify the block, which decodes
independently against the container header. `record_index` selects the
alert from that decoded block; `record_ordinal` locates it in the whole
container, independent of block boundaries. With the default 129x129
cutout, each alert (about 67 kB) usually fills its own block because
`dev`'s sync interval is 16,000 bytes. Only records without a filled
cutout are small enough to share a block.
`UNIQUE (instance, candidate)` is the row's own idempotency key, the
same pair a rerun's recovery reads back.

This amends the general locator description in [runs.md](runs)'s
storage-layout paragraph: the locator is an Avro block plus the record's
position within it and within the container.

## Kafka

`[publish] kafka` defaults to `false`. Setting it `true` exits 64,
"Kafka publication is not enabled in this build": the same refusal
`dev`'s own pipeline path takes, since `dev` never constructs a Kafka
producer for its pipeline stage either, only for the standalone
`alerts.cli --kafka` flag this port does not carry. No Kafka client
library is imported anywhere in the stage. The outbox's `published_at`,
`topic` and `publication_ref` columns are the publication hook: designed
in, and off, for whichever later stage or process reads unpublished
outbox rows and publishes them.

## Alert naming

`alert_name` stays null. `dev` declares an `alertnames` table and
`addAlertName`/`computeAlertName` procedures for a base-26 name scheme,
but no path in `dev`'s pipeline or CLI calls them; naming is unused
legacy machinery there too. The rebuild ports nothing of it and leaves
naming for the team to decide.

## Cutouts

Only the difference cutout is populated: a 129x129 pixel stamp cut from
the finalized difference instance's `difference` member with astropy
(`dev` uses fitsio through a temporary file; the rebuild reads the FITS
data directly), centered on the source's fitted position plus one pixel
(`xfit+1`, `yfit+1`, `dev`'s 1-based FITS convention), off-chip pixels
filled with 0.0. The science and reference cutouts are null in this
port: `dev` cuts them from the background-subtracted science image and
the resampled, gain-matched reference, neither of which is an input-set
member the stage can name yet. They stay null until those roles exist in
the input set, a choice left to the team.

## Cross-matches

`ssMatch` runs only when `[alerts] kona_file` names a file; the default
is empty, and an empty setting skips the KONA prediction import
entirely, so nothing imports `rapid_kona` in the default path. `NED`
cross-matching runs only when `[alerts] ned = true`; the default is
`false`, where `dev`'s own `ned_match` defaults on, and a test run never
sets it, since the cross-match calls an external web service
(`astroquery`, the reader `dev` used before its move to a local HATS
mirror, which is not ported here). The reference-catalog
cross-match (`refMatch`) runs when `[alerts] refcat` is set and the
input set's `reference-catalog` entry is present.

## Settings

`rapidpipe/settings/alerts.toml`:

| Setting | Default | `dev` |
|---|---|---|
| `[alerts] diff_flavor` | `zogy` | `dev` defaults to `sfft`; `zogy` was ruled. Must equal the input set's `difference-image` key. |
| `[alerts] stamp_half_width` | 64 | `STAMP_HALF_WIDTH`, giving 129x129 stamps |
| `[alerts] kona_file` | empty | `dev`'s `kona_file`; empty skips `ssMatch` and its import |
| `[alerts] ned` | false | `dev`'s `ned_match` defaults on; off was ruled, and it is never on in a test run |
| `[alerts] refcat` | true | `dev`'s `refcat_match` |
| `[alerts] prv_window_days` | 365.25 | `dev`'s `PRV_WINDOW_DAYS` |
| `[archive] codec` | `deflate` | `dev`'s `archive_codec` |
| `[archive] compression_level` | 1 | `dev`'s `open_alert_archive` level |
| `[publish] kafka` | false | Kafka publication; `true` exits 64 |
| `[publish] topic` | empty | unused while `kafka` is false |

## Exit codes

| Code | When |
|---|---|
| 0 | the container, summary, outbox rows and both registrations were written, including an empty container for zero alertable sources, a recovered rerun that regenerates identical bytes, and `--dry-run` |
| 64 | an unknown or invalid setting, `[publish] kafka = true`, an unreadable `kona_file`, or a bad `RAPIDPIPE_ALERTS_DATABASE` |
| 65 | the input manifest is not an `input-set` manifest or its unit is not `detector-image`; the difference-image entry is absent, duplicated, or its differencer is not `diff_flavor`; a member fails its size or SHA-256 check, or the difference image is unreadable; a named result set is unregistered, of an unknown kind, or incomplete; the input set does not name exactly one source set or no association set; a statistics set describes no named association set, or two describe one; a pruned set names a base association set not among the input's own association sets, or two pruned sets name the same base; a named association set's field is not a non-negative integer or has no field tables; a lineage chain is broken; the source set was loaded from a different difference instance; or the difference instance has no `diffimages` row |
| 70 | a recovered rerun whose regenerated bytes or locators differ from what was registered, for example because `NED` is live and on; a registered record that reads back differently from what was written; or any unclassified error |
| 75 | the database cannot be reached, or the connection is lost mid-transaction |

## Local execution

`make stage-alerts` runs the stage fixture against a fake database
(`rapidpipe/selftest/support/fakealertsdb.py`, `load`'s fake-database
pattern) seeded with two fields, each with its own association and
statistics sets, and a mix of sources: flagged, orphaned, unassociated,
associated with history, and one only reachable through a lineage base
set; the fixture decodes the container with fastavro and checks each
record, its block locator and its outbox row against the seed. The same
path against PostgreSQL is `tests/db/test_alerts.py`.
