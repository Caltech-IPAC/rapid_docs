# The alerts stage

**Status: DRAFT**

What the `alerts` stage reads, what it writes, the outbox row it keeps
for each alert, and its settings and exit codes. Written 2026-09-24 from
the port landing on the pipeline repository's `rebuild` branch
(`rapidpipe/stages/alerts.py`, `rapidpipe/science/alerts/`,
`rapidpipe/db/alerts.py`, `rapidpipe/products/alertcontainer.py`,
`rapidpipe/settings/alerts.toml`, migration
`20260924-07-alert-outbox.sql`), ported from `dev`'s
`pipeline/produceAlertsForProcDate.py` and `alerts/` (schema
`rapid.v00_04`). The port follows the lead's rule of 2026-09-22:
minimise differences to `dev`, and design in, off by default, anything
that can be left unused. The [products](products) page fixes the
vocabulary; this page records how the stage meets it, and amends two of
its paragraphs (below).

## In plain terms

For one finalized difference image, the stage reads the image's sources
from a named source set. It reads their objects from one or more named
association sets, one per field the image touches, and those objects'
statistics from whichever statistics sets describe them. It builds one
Avro alert per unflagged, associated source, as `dev` does, and writes
them all into one Avro container file with `dev`'s summary JSON. It
keeps one outbox row per alert, naming the container, the Avro block
that alert's record lives in, and the record's position in the block and
in the container as a whole. `dev` writes files only, with no database
row anywhere naming an alert; the rebuild needs one, so the stage
registers the container and the outbox's row set as its own products, in
the same transaction that writes the rows. Kafka publication, alert
naming and two of the three cutout images are ported as designed-in,
off-by-default mechanism, as `dev` itself leaves them: `dev` never calls
its own naming procedures or its own Kafka publisher from the pipeline
path.

## Inputs

Unit: detector-image. `--inputs` is an input-set manifest, stage
`input-set`, not a producing stage's completion manifest:

| Part | Content | Used for |
|---|---|---|
| `outputs[]` `difference-image`, exactly one | the finalized instance; its key `differencer` must equal `[alerts] diff_flavor`; member role `difference`, size and SHA-256 verified | `cutoutDifference`; the `diffimages` row (`pid`), looked up through `diffimages.instance` |
| `outputs[]` `reference-catalog`, at most one | its primary member, a SExtractor catalog; this kind's registration block is not fixed yet, so none is required | `refStarMatches`/`refGalaxyMatches` when `[alerts] refcat` is set; absent means both stay null |
| `inputs.result_sets` | instance ids, classified by looking up each one's kind in `product_instances`: exactly one `source-set`, one or more `association-set`, any number of `statistics-set`, each complete | the source, association and statistics rows, and each association set's lineage (below) |

A statistics set must describe exactly one of the named association
sets, and at most one statistics set may describe any one association
set; either violation exits 65. What "describes" means is not fixed
anywhere else on rebuild: the rule is that one of the values in the
statistics set's `product_instances.logical_key` equals that association
set's instance id, and the fixture uses the key `{"membership": <set>}`.
An association set with no describing statistics set falls back to
`dev`'s own path when statistics have not run for an object: null
sigmas, and a count of `merges` rows for `nDiaSources`.

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

Here the image touches two fields, 5321 and 5322, each with its own
association set and the statistics set that describes it. The five
`result_sets` entries carry no role of their own; the stage tells them
apart by the kind and, for a statistics set, the association set each
instance is registered under, never by their position in the list.

## What it reads

Sources come from `sources`, still read through its parent table: unlike
the per-field object tables below, `sources`' per-date, per-detector
children inherit it, so a `result_set` filter on the parent already
covers every row. Objects and their merges come from step 1's per-field
tables instead, `merges_<field>` and `astroobjects_<field>`, and their
statistics from `astroobjectsmeta_<field>`: these are standalone tables,
never children of a shared parent, so the stage reads each one by its
built name (`rapidpipe.db.objects.field_table_names`), not through
inheritance. A named association set's field comes from its logical
key's `field`, which must be a non-negative integer or a decimal string
of one, else exit 65; a field with no such table also exits 65.

- **Flagged sources**: `sources` where `result_set` is the source set
  and `pid` is the finalized instance's `diffimages` row, `flags <> 0`.
  Counted and listed in the summary as dropped, reason `flagged`, never
  assembled, as `dev`'s `iter_sources` does.
- **Alertable sources**: the same with `flags = 0`, joined to `filters`
  for `band` and `exposures` for `exptime`, ordered by `sid`.
- **Lineage**: crossmatch can write an association set that extends an
  earlier one, recorded as `base` in the extending set's logical key. An
  extending set's `merges`/`astroobjects` rows hold only its new
  detections and the objects it newly created; a known object's own
  `astroobjects` row stays in whichever set first made it. Each named
  association set is therefore resolved to its full chain, newest first
  (`rapidpipe.db.objects.association_chain`); a broken chain exits 65.
  The base sets a chain pulls in are appended to `inputs.result_sets` and
  become dependencies of this attempt, the same as any set named
  directly. Statistics sets need no such chain: `statistics` computes a
  set over the whole membership, base sets included, keyed to it
  directly.
- **Associations**: for each alertable source, its object is taken from
  a `merges` row in any set in any named association set's chain, joined
  to that set's `astroobjects`, picking the newest set in the chain that
  has the row when more than one does. `nDiaSources` is the describing
  statistics set's `nsources` where one exists, else a count of the
  object's `merges` rows across the whole chain, `dev`'s fallback before
  statistics have run for an object. A source with no `merges` row in
  any set of any chain is dropped, reason `unassociated`; a `merges` row
  with no matching `astroobjects` row anywhere in its chain is an
  orphan, dropped with reason `orphan`, `dev`'s `AssociationError` case.
  Where one source has more than one `merges` row, the lowest `aid`
  wins.
- **History**, `prvDiaSources`: the object's other `merges` rows across
  its association set's chain, joined back to `sources` in any result
  set, since those rows are the association set's own frozen
  dependencies, not this attempt's. `dev` bounds history by time, not by
  count: a source counts as previous history down to
  `[alerts] prv_window_days` before its own `mjdobs`, with no upper
  bound, so a later detection of the same object also counts as
  previous to it.

An input product with no `product_instances` row, such as a reference
catalog `dev` registered, is still read and cross-matched, but is left
out of `inputs.products` and gets no dependency edge; it is named
instead in the execution record's `notes.unregistered_inputs`. This
follows the same rule `difference` uses for a `dev`-registered
reference.

## What it writes

One Avro object container per unit, `dev`'s schema `rapid.v00_04`, codec
`deflate` at compression level 1 with `dev`'s own 16,000-byte sync
interval kept, plus a summary JSON of the same shape as `dev`'s
`BatchStats.as_dict()`, extended with the flagged count and the full
dropped list with reasons.

The stage registers two products itself, in the transaction that writes
the outbox rows: an `alert-container` file product (the container and
its summary as members) and an `alert-set` result set (no members, its
key the container's, `complete` true, `row_count` the outbox rows
written). This makes `alerts` the producer and the initial registrar of
both outputs, unlike every other stage, which writes a manifest for a
separate `register` run to record. `register` still validates and can
replay the same manifest: given the same `alert-container` and
`alert-set` entries again, it checks them, including every member's
role, path, size and SHA-256, against what `alerts` already wrote and
adds nothing, the same no-op replay any other kind gets; both kinds have
to be known to `register` for the replay to succeed, not the container
alone. This amends the products page's "Alert names are not a file
product" paragraph, which said `register` records the container; the
stage does, and standalone `register` is the replay path, not the first
writer (supervisor step 2, 2026-09-24).

Within the transaction, registration happens before the outbox insert:
the outbox rows carry immediate foreign keys to `product_instances` and
to `result_sets`, so those rows must exist first. This reverses the
order named when the outbox was specified; both still commit together,
in one transaction, so nothing is visible half-written.

The registration block the stage writes for the container:
`alert_count`, `dropped_count`, `schema_version`, the finalized
`difference` instance, the registered reference-catalog instance when
one was read, and the sets it read, as both lists and, for convenience,
the first of each list: `association_sets` and `association_set`,
`statistics_sets` and `statistics_set`, the singular form null only
when its list is empty. Dependencies are recorded for the difference
instance, a registered reference-catalog instance, every named
association and statistics set, and every base set a lineage chain
pulled in; an unregistered reference catalog gets no edge, per "What it
reads" above.

On success the stage also sets `diffimages.nalertpackets = 1` on the
run's own `diffimages` row for the finalized difference instance,
matching on `instance` and `run` together, so it touches only the row
this run's own `register` created. If the difference instance belongs to
another run, no row matches; the stage logs a warning and records the
count in the execution record's notes rather than failing.

A unit with no alertable sources still produces a container, with zero
records, and a complete, empty `alert-set`. On a rerun of an attempt
whose commit already landed, the stage recovers rather than duplicates:
it regenerates the container and summary from the same inputs (the same
records in the same order; deflate at level 1; the sync marker derived
from the SHA-256 of the attempt id rather than `dev`'s random one; the
embedded schema's field keys sorted, since `fastavro`'s own ordering
otherwise follows the process's hash seed; and one `timeProcessedMjd`
for every alert in the container, reused from the outbox rows rather
than `dev`'s separate timestamp per alert) and checks the regenerated
bytes, members and locators against what was registered and written; a
difference exits 70. `NED`, a live service, is the one input that can
make a rerun's bytes differ from the first attempt's.

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

`dev`'s own packing is kept, so a block ordinarily holds several
records: a single record has no byte range of its own inside a
compressed block, only the block does. `block_offset` and
`block_length` name that block exactly, and it decodes on its own
against the container's header; `record_index` then picks the alert out
of the decoded block, and `record_ordinal` gives its place in the
container as a whole, independent of block boundaries. With the default
129x129 cutout, each alert (about 67 kB) usually fills a block on its
own, since `dev`'s sync interval is 16,000 bytes; only a record with no
filled cutout is small enough to share a block with its neighbours.
`UNIQUE (instance, candidate)` is the row's own idempotency key, the
same pair a rerun's recovery reads back.

This amends [runs.md](runs)'s storage-layout paragraph, which described
the outbox row's locator in general terms; the exact mechanism is this
one, an Avro block plus the record's position within it and within the
container (supervisor step 2, 2026-09-24).

## Registration: `alert-container` and `alert-set`

`register` learns both kinds. A validator for `alert-container` requires
the `container` and `summary` member roles and the registration fields
above; `alert-set` is validated as a result set, its registration
`{row_count, table: "alert_outbox"}`. Registering either writes nothing
beyond its own instance row, the same as a `source-catalog` entry today;
the science content is the outbox rows and the container bytes, both
already durable by the time either manifest is registered.

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
naming for the lead to decide.

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
the input set, a choice left to the lead.

## Cross-matches

`ssMatch` runs only when `[alerts] kona_file` names a file; the default
is empty, and an empty setting skips the KONA prediction import
entirely, so nothing imports `rapid_kona` in the default path. `NED`
cross-matching runs only when `[alerts] ned = true`; the default is
`false`, where `dev`'s own `ned_match` defaults on, and a test run never
sets it, since the cross-match calls an external web service
(`astroquery`, the reader `dev` used before its 2026-09-23 move to a
local HATS mirror, which is not ported here). The reference-catalog
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
| 65 | the input manifest is not an `input-set` manifest or its unit is not `detector-image`; the difference-image entry is absent, duplicated, or its differencer is not `diff_flavor`; a member fails its size or SHA-256 check, or the difference image is unreadable; a named result set is unregistered, of an unknown kind, or incomplete; the input set does not name exactly one source set or no association set; a statistics set describes no named association set, or two describe one; a named association set's field is not a non-negative integer or has no field tables; a lineage chain is broken; the source set was loaded from a different difference instance; or the difference instance has no `diffimages` row |
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
