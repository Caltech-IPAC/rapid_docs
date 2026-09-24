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
from a named source set, their objects from a named association set, and
those objects' statistics from a named statistics set when one is named.
It builds one Avro alert per unflagged, associated source, as `dev`
does, and writes them all into one Avro container file with `dev`'s
summary JSON. It keeps one outbox row per alert, naming the container and
the exact byte range of the one Avro block that alert's record lives in.
`dev` writes files only, with no database row anywhere naming an alert;
the rebuild needs one, so the stage registers the container and the
outbox's row set as its own products, in the same transaction that
writes the rows. Kafka publication, alert naming and two of the three
cutout images are ported as designed-in, off-by-default mechanism, as
`dev` itself leaves them: `dev` never calls its own naming procedures or
its own Kafka publisher from the pipeline path.

## Inputs

Unit: detector-image. `--inputs` is an input-set manifest, stage
`input-set`, not a producing stage's completion manifest:

| Part | Content | Used for |
|---|---|---|
| `outputs[]` `difference-image`, exactly one | the finalized instance; its key `differencer` must equal `[alerts] diff_flavor`; member role `difference`, size and SHA-256 verified | `cutoutDifference`; the `diffimages` row (`pid`), looked up through `diffimages.instance` |
| `outputs[]` `reference-catalog`, at most one | its primary member, a SExtractor catalog; this kind's registration block is not fixed yet, so none is required | `refStarMatches`/`refGalaxyMatches` when `[alerts] refcat` is set; absent means both stay null |
| `inputs.result_sets` | instance ids, classified by looking up each one's kind in `product_instances`: exactly one `source-set`, exactly one `association-set`, at most one `statistics-set`, each complete | the source, association and statistics rows |

A worked example:

```json
{
  "schema_version": "1",
  "run": "01J8Y6QZ3M00000000000000RN",
  "unit": {"kind": "detector-image", "id": "e20260821001234/SCA07"},
  "stage": "input-set",
  "attempt": "01J8Y6QZ3M00000000000000AT",
  "inputs": {
    "products": {},
    "result_sets": [
      "01J8Y6QZ3M00000000000SRCS1",
      "01J8Y6QZ3M00000000000ASSC1",
      "01J8Y6QZ3M00000000000STAT1"
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

The three `result_sets` entries carry no role of their own; the stage
tells them apart by the kind each instance was registered under, never
by their position in the list.

## What it reads

Every read names its result set explicitly and reads the parent table
(`sources`, `merges`, `astroobjects`, `astroobjectsmeta`), never a
per-date, per-detector or per-field child table by name:

- **Flagged sources**: `sources` where `result_set` is the source set
  and `pid` is the finalized instance's `diffimages` row, `flags <> 0`.
  Counted and listed in the summary as dropped, reason `flagged`, never
  assembled, as `dev`'s `iter_sources` does.
- **Alertable sources**: the same with `flags = 0`, joined to `filters`
  for `band` and `exposures` for `exptime`, ordered by `sid`.
- **Associations**: `merges` of the source set's sources left joined to
  `astroobjects` of the association set on `aid`, left joined to
  `astroobjectsmeta` of the statistics set on `aid` when one is named.
  `nDiaSources` is the statistics row's `nsources` where one exists,
  else the count of that object's `merges` rows in the association set,
  `dev`'s fallback before statistics have run for an object. A source
  with no `merges` row at all is dropped, reason `unassociated`; a
  `merges` row with no matching `astroobjects` row is an orphan, dropped
  with reason `orphan`, `dev`'s `AssociationError` case. Where one
  source has more than one `merges` row, the lowest `aid` wins.
- **History**, `prvDiaSources`: the object's other `merges` rows in the
  same association set, joined back to `sources` in any result set,
  since those rows are the association set's own frozen dependencies,
  not this attempt's. `dev` bounds history by time, not by count: a
  source counts as previous history down to `[alerts] prv_window_days`
  before its own `mjdobs`, with no upper bound, so a later detection of
  the same object also counts as previous to it.

## What it writes

One Avro object container per unit, `dev`'s schema `rapid.v00_04`, codec
`deflate` at compression level 1, plus a summary JSON of the same shape
as `dev`'s `BatchStats.as_dict()`, extended with the flagged count and
the full dropped list with reasons.

The stage registers two products itself, in the transaction that writes
the outbox rows: an `alert-container` file product (the container and
its summary as members) and an `alert-set` result set (no members, its
key the container's, `complete` true, `row_count` the outbox rows
written). This makes `alerts` the producer and the initial registrar of
both outputs, unlike every other stage, which writes a manifest for a
separate `register` run to record. `register` still validates and can
replay the same manifest: given the same `alert-container` and
`alert-set` entries again, it checks them against what `alerts` already
wrote and adds nothing, the same no-op replay any other kind gets; both
kinds have to be known to `register` for the replay to succeed, not the
container alone. This amends the products page's "Alert names are not a
file product" paragraph, which said `register` records the container;
the stage does, and standalone `register` is the replay path, not the
first writer (supervisor step 2, 2026-09-24).

Within the transaction, registration happens before the outbox insert:
the outbox rows carry immediate foreign keys to `product_instances` and
to `result_sets`, so those rows must exist first. This reverses the
order named when the outbox was specified; both still commit together,
in one transaction, so nothing is visible half-written.

The registration block the stage writes for the container: `alert_count`,
`dropped_count`, `schema_version`, the finalized `difference` instance,
and the three result-set instances it read (`source_set`,
`association_set`, `statistics_set`, the last null when no statistics
set was named).

On success the stage also sets `diffimages.nalertpackets = 1` on the
run's own `diffimages` row for the finalized difference instance,
matching on `instance` and `run` together, so it touches only the row
this run's own `register` created. If the difference instance belongs to
another run, no row matches; the stage logs a warning and records the
count in the execution record's notes rather than failing.

A unit with no alertable sources still produces a container, with zero
records, and a complete, empty `alert-set`. On a rerun of an attempt
whose commit already landed, the stage recovers rather than duplicates:
it looks up this attempt's registered `alert-container` and `alert-set`
instances, rebuilds their entries from the registered members' local
files, and checks each against its registered SHA-256; a mismatch exits
70. A full rerun with the same inputs and settings produces the same
records and the same outbox rows, since nothing in the read or the
assembly depends on wall-clock time or on anything the manifest does not
name.

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
| `record_index` | the record's 0-based position in the container |
| `block_offset`, `block_length` | the byte offset and length, in the container, of the one Avro block holding this record |
| `schema_version` | `00.04` |
| `written_at` | when the row was written |
| `published_at`, `topic`, `publication_ref` | null: set by a publisher this port does not build (below) |

Avro's object container compresses each block of records together, so a
single record ordinarily has no byte range of its own inside a shared,
compressed block. The stage sidesteps that by flushing the container
writer after every record, so each alert's record is the sole record in
its own block; `block_offset` and `block_length` name that block
exactly, and it decodes on its own against the container's header. This
differs from `dev` only for a record with no filled cutout, small enough
that `dev`'s own writer would have packed it into a shared block with
its neighbours; every alert `dev` writes with a difference cutout
already fills a block on its own, at `dev`'s sync interval. `UNIQUE
(instance, candidate)` is the row's own idempotency key, the same pair a
rerun's recovery reads back.

This amends [runs.md](runs)'s storage-layout paragraph, which said the
outbox row carries "each alert's byte range" in general; it is exact for
every record this port writes, by construction, not merely as a
fallback locator (supervisor step 2, 2026-09-24).

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
| 0 | the container, summary, outbox rows and both registrations were written, including an empty container for zero alertable sources, a recovered rerun, and `--dry-run` |
| 64 | an unknown or invalid setting, `[publish] kafka = true`, an unreadable `kona_file`, or a bad `RAPIDPIPE_ALERTS_DATABASE` |
| 65 | the input manifest is not an `input-set` manifest or its unit is not `detector-image`; the difference-image entry is absent, duplicated, or its differencer is not `diff_flavor`; a member fails its size or SHA-256 check, or the difference image is unreadable; a named result set is unregistered, of an unknown kind, incomplete, duplicated or missing; the source set was loaded from a different difference instance; or the difference instance has no `diffimages` row |
| 70 | a recovered rerun whose registered files are missing or changed, or any unclassified error |
| 75 | the database cannot be reached, or the connection is lost mid-transaction |

## Local execution

`make stage-alerts` runs the stage fixture against a fake database
(`rapidpipe/selftest/support/fakealertsdb.py`, `load`'s fake-database
pattern) seeded with a small mix of sources: flagged, orphaned,
unassociated, and associated with history; the fixture decodes the
container with fastavro and checks each record, its block locator and
its outbox row against the seed. The same path against PostgreSQL is
`tests/db/test_alerts.py`.
