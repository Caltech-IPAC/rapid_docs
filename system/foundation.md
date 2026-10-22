# The foundation and the thin chain

**Status: DRAFT**

This page states how RAPID records what it made and which of it is
official, and the narrow chain of stages built on that record, from
stored images to alert packets. It is the design the `rebuild` branch
of the pipeline repository implements: `database/schema.sql`, the
package `rapidpipe.foundation`, the stages `intake`, `import`,
`reference`, `difference`, `associate` and `packet`, the loop, the
Kafka publication, the reader `scripts/read_packets.py`, the run
validation `scripts/validate_run.py` and the queries in
`database/queries.sql`.
The [stage contract](stage-contract) page states what a stage is under
it, and the [decisions](decisions) page records the rulings it rests
on. The chain has run end to end on SMDC's database and AWS Batch over
one field's whole night, 69 epochs, and then from SOC L2 ASDF files to
the Kafka topic over 426 epochs of a simulated wide-area survey; the
last sections give the procedure, the checks both met and what they
measured.

## In plain terms

A run is a recipe: who launched it, why, from which code, with which
settings, for which survey and dataset. A job is one execution of one
stage under a run. Every catalog row the pipeline publishes names the
job that wrote it, and nothing published is ever changed.

Which rows are official is a separate record. One table holds, for
each product key, the binding that says which job's rows are official,
and for each survey and dataset, which run is live. Bindings change
only in recorded groups, and every group can be undone. Each product
table has a view that shows its official rows.

A stage reads what its job was given at launch, computes in memory,
writes files under a prefix that names the job and attempt, and stops.
The publisher then loads the declared rows in one short transaction
and, when the run is live and nothing has moved in the meantime, makes
them official. A retry is a new attempt of the same job; once a job is
published, a retry does nothing.

## The foundation

Six statements define it. Each is one mechanism.

### Runs

A run is a recipe someone launched for a reason. The `runs` row holds
who, when, why, the code revision, the full settings body inline, and
the one survey and dataset the run is for. There is no settings table
and no resolution of settings at run time: a stage reads its own table
from the run's body.

### Jobs

A job is one execution of one stage under a run. The `jobs` row holds
the stage, its scope, its state (`launched`, `running`, `published` or
`failed`), the image digest it ran under (none for a job run from a
checkout) and beside it the instance type, the settings hash, the attempt whose outputs were published,
its manifest, the launched, started and ended times, the exit code, and
the reason an automatic binding was refused, if one was. Local and
Batch executions both get a job row. A killed execution is a job row
that never reached `published`.

### Published rows name their job

Every product row carries `job`, never null, and each scientific key is
unique per job. Two executions over the same input therefore coexist
and neither overwrites the other. A row reaches its run through its
job, and the official views expose both.

Each product has one scientific key, and dataset is in every key, so a
source-injected variant and its original are distinct products with
distinct live streams:

| Product | Scientific key | Rows |
|---|---|---|
| `exposures` | dataset, expid | `exposures` |
| `l2files` | dataset, expid, sca, fid | `l2files` |
| `diffimages` | dataset, expid, sca, fid | `diffimages` |
| `psfs` | dataset, fid, sca, kind | `psfs` |
| `refimages` | dataset, field, fid | `refimages`, with children `refimimages` (members) and `refimcatalogs` (mosaic catalogs) |
| `sources` (source set) | dataset, expid, sca, fid | `sources` |
| `objects` (object set) | dataset, survey, field | `objects`, with child `memberships` |
| `packets` (packet set) | dataset, expid, sca, fid | `packets`, with children `forced` and `external` |
| `catalogs` (reference catalog) | name, version | `catalogs` |

A source is identified by its set and its source id, an object by its
set and its object id, a packet by its set and its source. A set is
identified by the job that wrote it, so a job that writes a set binds
exactly one key of that set's product.

The pipeline id that `dev` carries in nearly every image query is not
in any key: a run has one differencer, and a second differencer is
another run. A PSF's kind is in its key, `science` or `reference`
({ref}`ruling <decision-psf-kind>`): the science image's PSF and the
reference image's PSF of one filter and SCA are different products,
which the key without the kind merged. `dev`'s `psfs` has no such
column; this is the identity rule applied.

### Inputs are chosen at launch and recorded

`job_inputs` holds, for each job, rows of three kinds. An `input` row
names a set the job reads, by product, key and the job that wrote it;
an object-set job's predecessor is its `input` row of product
`objects`. An `expects` row names, for one output key, the open binding
the job expects to replace, or none. An `excludes` row, for `associate`
only, names a source set of the predecessor's chain that is no longer
official, whose members the job drops.

The launcher chooses these. For the live run it chooses the current
official sets; a campaign chooses its own previous sets, and none for
its first epoch. A stage reads the sets its rows name and never "the
current official" one, which is what lets a recipe that is not live,
or a correction of one downstream product, read sets that are not
official.

### One table of official bindings

`official` holds two kinds of binding. A product binding points a
(product, key) at one job's rows; a partial unique index allows at most
one open binding per key. A live binding points a (survey, dataset) at
one run, again at most one open. Every binding row records who opened
it, when, why and in which change group, and once closed, who closed
it, when, why and in which group. A group's full effect is read from
the rows it opened and the rows it closed.

One operation, `change`, applies a group in one transaction: it closes
bindings, then opens them, and refuses the whole group if a binding it
expected to close is no longer open. `undo` reads a group's two sides,
builds the inverse (close what it opened, reopen as new rows what it
closed) and applies it under the same rule; it never reopens a closed
row.

Each product table has a view `<table>_official`: its rows joined to
their open bindings, with the `binding` and `run` columns added. There
is no stored flag. `members_official` follows an official object set's
predecessor chain and returns its memberships, except those whose
source set any set in the chain excluded.

### Publish last

A stage computes, writes its files and its declared Parquet outputs
under an immutable prefix, `<outputs root>/<run>/<stage>/<job>/<attempt>/`,
and returns. The publisher then, serialised on the job's row:

1. stops at once, before reading any file, if the job is already
   published;
2. verifies every declared file against its checksum;
3. loads the attempt's declared rows, and writes the job's state,
   published attempt and manifest;
4. inside a savepoint, attempts the automatic binding: if the job's run
   is live for its survey and dataset, and for each output key the open
   binding is the one the job's `expects` row named, it closes those and
   opens the job's; otherwise it rolls back to the savepoint and records
   the refusal on the job;
5. commits, all of the above in one short transaction, then runs
   `ANALYZE` on the tables it loaded, and on `official` when its
   binding wrote there.

A refused job's rows stay published as an unbound candidate, visibly,
and a later change group can bind them. A retry finds its job published
and stops; a retry after a failed attempt writes a new attempt, so a
published prefix is never rewritten.

## Why it is this way

**`dev`'s shapes are prior art, not a constraint.** The rule that the
rebuild coexist with `dev`'s schema is revoked
({ref}`ruling <decision-foundation-dev-prior-art>`). The per-SCA row
shape and the scientific column names stay because they are the
instrument's shape and cost nothing. The columns kept per table are
the ones the team's queries read. The static tables (filters, SCAs,
surveys, fields) stay plain tables. The sky tessellation is computed in
closed form by `roman_tessellation.py` and is not a table. `dev`'s
`pipelines` and `swversions` are not carried, because the run's
revision and settings record what they recorded.

**There is no `vbest`.** It was a second, mutable copy of the truth
with its own write path, on four tables. The binding replaces it, and
an explicit change group with a reason is the recorded act that `dev`'s
human lock (`vbest = 2`) stood for.

**Joins between products are on scientific keys, never on another
product's row id.** `dev` joins a difference image to its L2 row by row
id, and under coexistence that row may not be the official one. "L2
images with no official difference image" is an anti-join of two
official views on (dataset, expid, sca, fid).

**A source is official when its set is.** `dev` has no flag on sources;
association, export and light curves were correct only because prune
deleted superseded rows first. Here `sources_official` joins source
sets to the open bindings of their image key, and no catalog row is
deleted.

**Spatial queries stay in SQL where the team runs them.** Cone
searches on image centres, containment on overlapping fields and the
forced-photometry image search are most of the team's query shapes.
The base tables keep q3c indexes on image and object centres and a GIN
index on `overlapfields`, and every official view is a plain join so
the planner reaches them. A failed execution publishes nothing, so
`status` is a column a query filters on, not part of a view.

**Columns `dev` backfills are computed before publish.** `dev` fills
limiting magnitude, overlapping fields and sky indices into published
L2 rows in place. Here the stage that publishes a row computes them; a
later correction is a new job's row, rebound.

**One live run per survey and dataset, for every stage.** A retune is a
new run, which becomes live for every stage; stages whose values did
not change behave as before. A live pointer per stage would buy only a
patchwork of recipes nothing asked for. A correction run that touches
only downstream products is either not made live, its results bound by
an explicit group, or made live for everything.

**Automatic binding compares the expected binding, not the input.**
For `associate` the set it read and the binding it replaces coincide;
for `packet` the input is an object set and the binding to replace is
the previous packet set of that image. Two jobs that both read set A:
the first publishes B and binds; the second publishes C and stays an
unbound candidate. A late job from a run that is no longer live stays
unbound for the same reason.

**Concurrency is the unique index and the row lock.** Two groups that
close the same binding: the second blocks on the row, finds it closed,
and refuses. Two groups that open a binding on the same key: the
partial unique index refuses the second. There is no table lock and no
lock table. The publisher's live check is a plain read: a cutover that
does not touch a job's expected bindings is equivalent to one committed
after the job, and one that does is caught by the row lock on the
binding.

**Stages read, compute in memory, and the publisher writes.** A stage
holds no connection while it computes and writes no catalog row. The
old crossmatch matched each exposure against rows it had itself written
for the previous one, inside one transaction under an advisory lock;
with outputs going to Parquet there is nothing for SQL to query
mid-job, so `associate` matches in memory, and its parity with the SQL
matcher on the same field is a test in CI.

**Declared outputs, not every file.** A stage's manifest names which of
its files are catalog rows, and the publisher loads those and only
those. Parquet is the row format because the stages, the publisher and
an archive export all read it without conversion.

**The database is authoritative for bookkeeping.** Runs, failed jobs
and official changes with their reasons live only in the database, and
its backups are what protect them. Catalog rows can be reloaded from a
job's Parquet; the bookkeeping cannot.

**A cutover is one change group.** It rebinds the affected products and
the live binding together. A campaign that carries live results forward
names them in its group; nothing is inherited. A live epoch that lands
while a cutover is being prepared moves a binding the group expects to
close, and the group refuses.

**Bytes are immutable.** Published rows reference files whose paths
contain the job id and the attempt, with their checksums. A retry
writes new files and never overwrites a referenced one.

**Association products are sets, and sets are deltas.** An object set
is one job's output for one field. `objects.parquet` holds every object
of the field with its founding position and its statistics as
sufficient sums (count, and the sum and sum of squares of position and
flux), so the next epoch updates statistics from the predecessor's
objects and this epoch's sources without reading history.
`matches.parquet` holds only this epoch's new memberships. A full
membership snapshot per epoch would grow with the square of the epoch
count, and a GBTDS field has tens of thousands of epochs. Object ids
are position hashes of the founding source, so the same founding source
gives the same id under any recipe, and a join on object id works
across recipes for most objects.

**The object set is the pruned set.** `dev`'s prune deleted members
whose difference image was no longer best. Here an `associate` job
learns at launch which of the predecessor's source sets are no longer
official, records them as exclusions, and drops their members from its
sums; `members_official` omits them. Nothing is deleted, and exclusions
are rare because a superseded source set is rare.

**A packet set is per difference image.** The alert unit is one
difference image, so a packet set's key is its image key, never the
field. The current-packet view keeps every epoch, and a correction of
one epoch replaces only that epoch's set. The packet stage writes Avro
and a `packets.parquet` index that locates each record by file, offset
and length; an object's alert history is a query over the index, and a
packet's lineage is its job's recorded inputs.

**A packet's history is bounded by its trigger.** Previous detections
are those before the trigger, and the detection count is the count as
of the trigger, so a packet rebuilt for epoch 1 after epoch 2 is loaded
carries nothing from epoch 2.

**Forced photometry is a packet-set output with named inputs.** `dev`
caches forced rows in a per-object store that every job rewrites and no
recorded input can describe. Here a packet job names its window's
images and its predecessor packet sets' `forced.parquet` as inputs,
measures only the (object, image) pairs those do not already hold, and
publishes its own `forced.parquet` with `dev`'s row id.

**Reference catalogs are products.** Gaia, NED, NED-LVS and the
solar-system predictions are copies whose version no packet recorded.
Each is a product keyed by (name, version), and a job names the one it
read.

**One schema file, applied fresh.** `schema.sql` holds every table,
view and operation, with the q3c extension and its indexes in a block
that continues where q3c is absent, as on a developer's container. The
apply is one `psql -f`. There is no migration machinery: the PSF kind
was the first change after real data, and it and every later change
are incremental SQL run once.

Immutability is of published rows and their bytes, not of every field:
bindings close and job state changes. Retention is deferred, and its
rule when it comes is that a row that was ever official keeps its whole
input closure. Stacked inputs fit the identity model as a product with
its own key and a membership table, on the reference-image pattern.

Given up on purpose: scratch and production custody, releases before
delivery, check policies, plan files, custom retries (Batch retries,
and publish-last makes a retry safe), a sharing rule, catalog copies,
expiry, reconstruction from storage alone, a uniform file-only stage
interface, a stored `vbest`, a live pointer per stage, a lock on the
official table, the branch's `alert_outbox` table and `maintain` stage,
and `dev`'s per-object forced-photometry store.

## The verbs

| Verb | Does |
|---|---|
| `rapidpipe run create --who --why --revision --settings FILE --survey --dataset` | records a run and prints its id |
| `rapidpipe official change --group FILE --who --why` | applies a change group from a JSON list of `close` and `open` items; refuses naming the binding |
| `rapidpipe official undo <group> --who --why` | applies a group's inverse under the same rule |
| `rapidpipe run show <id>`, `rapidpipe job show <id>` | print a run with its live binding and jobs, or a job with its inputs and bindings, as JSON |
| `rapidpipe job local --run --stage --scope JSON [--inputs JSON] [--expects JSON] [--excludes JSON]` | records a job and runs it in this process, then publishes |
| `rapidpipe job run --job <id>` | runs an existing job's next attempt, then publishes; stops at once if the job is published |
| `rapidpipe job submit ... --job-definition <name>` | records a job and submits one Batch job whose command is `job run` |
| `rapidpipe publish --run <id> [--settings FILE]` | produces the run's official, unstamped packet sets to the Kafka topic and stamps each (Publication to Kafka, below) |
| `rapidpipe loop --run --filters --scas --pointings --job-definition` | carries a selection one stage forward per pass until it drains ([loop](loop)) |

A refusal exits 1 with the binding named. The exception is a refusal
because the job's run is not live: the job is published and its rows
are an unbound candidate, which is what a run that is not live is for,
so the job exits 0 and the refusal is on its row and on standard
error. A missing row or unreadable file exits 64.

### Where outputs live

The outputs root comes from `RAPIDPIPE_OUTPUTS_ROOT`, a `file://` or
`s3://` URL, and every prefix is under it. Two functions in
`rapidpipe.foundation.prefix` are the only way a file crosses a prefix.
`get(url)` returns a local path for a file URL: the file itself for
`file://`, or a download, once per object per process, for `s3://`.
`put(directory, prefix)` uploads a stage's working directory to its
attempt's prefix, `manifest.json` last, and does nothing for `file://`,
where the stage wrote in place. A stage reads every input through
`get`, writes under its job's local path, and records each file as the
prefix's URL plus its relative path. The publisher reads the manifest
and the declared files through `get` too, so it verifies checksums on
what the bucket holds. An attempt number under `s3://` is one more than
the highest already in the bucket, so an attempt that uploaded and then
failed to publish is never rewritten.

### A job on Batch

`job submit` takes `job local`'s arguments and a job definition. It
records the job, then submits one Batch job whose command is `job run
--job <id>`, with the outputs root (which must be `s3://`) in the
container's environment; the job definition's parameter tree names the
database. The container runs one attempt and publishes it, exactly as
`job run` does on a host. Batch retries exit 75 and nothing else
({ref}`ruling <decision-batch-retry>`): the job definition allows three
attempts, the first run and two retries, and its rules retry on exit
75, the stage contract's temporary dependency failure, and end the job
on any other exit code or on a failure with no exit code, such as a
reclaimed instance. Exits 64, 65 and 70 are faults a retry would only
repeat. A retry after a late commit is safe because `job run` stops on
a published job and otherwise takes the next attempt. Batch places a
retry within seconds, with no backoff, so the three attempts ride out a
database outage only as long as the connection's own retries inside
each attempt, about 8 s each. A job can still be resubmitted by hand,
the same Batch request again. Running the job records the job
definition's image digest on the job row and beside it the instance
type, read from the instance's metadata service when the attempt
starts (none when the service does not answer, as on a developer's
machine), so a re-execution can be compared with the instance it ran
on ({ref}`ruling <decision-instance-type>`). The compute environment is
not pinned to one instance family. The job's printed result carries the peak resident memory
of the stage's process and of its largest child, which is how a
toolkit binary's memory is seen; Batch itself reports no memory figure.

Each commit that runs on Batch has its own image, tagged
`rebuild-<sha>`, and its own `rapid-rebuild` job definition revision,
registered by the infrastructure repository's release hooks. A run's
revision names the commit; a fix to the code is a new commit, a new
image, and a new run whose jobs are submitted afresh, so the run and
job records always name the code that ran. A Batch stage names only
files in the inputs bucket and outputs under the scratch bucket's root,
the two places the job role can read.

## The thin chain

One narrow path through every stage, the smallest working version of
each, run first on one field's two epochs with the brightest sources per
image. Each simplification keeps the shape of the full stage.

| Stage | Reads (named in `job_inputs`) | Writes (declared outputs) | Left out until breadth |
|---|---|---|---|
| `intake` | one SOC L2 `_cal.asdf` file under the run's source root; the science PSF of its filter and SCA | the gzipped 16-HDU FITS converted as `dev` converts it; `exposures` and `l2files`, with limiting magnitude, overlapping fields and sky indices computed | other filters, for want of their PSFs |
| `import` | stored products for one field: L2 files, difference images, PSFs, the reference and its mosaic catalog, the Gaia copy; the cap on sources per image | copies of the image files; `exposures`, `l2files`, `diffimages`, `psfs`, `refimages`, `refimcatalogs`, `catalogs` and `sources` (the brightest N per difference image by flux over its error), with limiting magnitude, overlapping fields and sky indices computed; the source system's ids kept; provenance marked unknown | other fields and epochs; recovering provenance |
| `reference` | the field's `l2files` rows for one filter and SCA | the awaicgen mosaic with its coverage and uncertainty maps and SExtractor catalog; `refimages`, `refimimages` (one row per coadded L2 row) and `refimcatalogs` | `dev`'s later reference changes (infobits, status, the 9100-pixel mosaic); the Photutils catalog |
| `difference` | one epoch's `l2files` row, a `refimages` row with its mosaic catalog, and one `psfs` row of each kind, `science` and `reference`; the cap on sources | the ZOGY difference image and the files `packet` reads beside it, SFFT and naive as `dev` runs them; `diffimages` and the `sources` set, mapped exactly as the import maps `dev`'s | sumrat, real/bogus and the extra SFFT catalog columns; `dev`'s loader prefilter |
| `associate` | the epoch's source sets for the field and its eight neighbours; the predecessor object set, or none; the exclusions | `objects.parquet` (every object of the field, id carried forward or position-hashed, founding position, sufficient sums) and `matches.parquet` (this epoch's memberships) | `rubrat`, `sumrat`; field parallelism |
| `packet` | the epoch's source set; the object set to use, and through it its chain and exclusions; the window's difference and science images with their PSFs; the predecessor packet sets; the Gaia product; the reference and its mosaic catalog | `packets/<expid>-<sca>-<fid>.avro` at schema 00.06, the `packets.parquet` index, `forced.parquet`, `external.parquet` | NED, NED-LVS and solar-system matches |
| reader, outside the pipeline | a packet set's Avro and its official index and forced rows | a validation report | nothing |

Every stage reads its inputs the same way whoever made them, so
`associate` and `packet` read a Batch-made epoch exactly as an imported
one, and `difference` never cares whether its reference was imported
or coadded.

### import

The import stage takes stored products into the record. One job
imports the shared products (the reference with its mosaic catalog, the
science PSF and the Gaia copy) and one job imports each epoch, because
a source set's job binds one key. The kept sources are mapped onto the
`sources` columns with the old load stage's join, and their HEALPix and
tessellation columns are computed. A row's `filename` is the URL of the
copy under the job's prefix; every file is reached through its row.
A PSF's `psf` scope declares its kind; the stage reads the file's
`PSFKIND` (`dev` writes `sciimage_psf` and `refimage_psf`) and fails
before any manifest if it names the other kind. A file with no keyword
imports under the declared kind, and the manifest says so.

### intake

The [intake](intake) page states `intake`: its scope (one file of a
dataset), the science PSF it names, the conversion ported from `dev`,
the `exposures` and `l2files` rows it declares with the `expid` packed
from the file's name, and its settings. Where `import` copies products
another system made, `intake` makes the L2 product from the raw file,
so a run that starts from intake owns its data from the first stage.

### reference and difference

The [reference](reference) page states `reference`: its scope (field,
filter and SCA), the `l2files` rows it coadds in `dev`'s order, the
three tables it declares with the `rfid` it draws, and its settings.
The [difference](difference) page states `difference`: its scope (one
epoch's key), its four inputs (the L2 row, a reference, and one PSF of
each kind), the ZOGY image and source set it declares with the `pid` it
draws, and its settings. A run has one differencer, so only the ZOGY
image is published; the SFFT and naive files stay under the prefix.

### associate

`associate` replaces `crossmatch`, `statistics`, `prune` and
`maintain`. It accepts sources whose `flags` and signal-to-noise meet
the run's `[associate]` settings, then matches them in memory with the
semantics of the SQL matcher it replaces: every object within the match
radius matches, not only the nearest, so a source may join several
objects; an unmatched source founds an object whose id is the
`radec_index` of its position, and coincident founders share one
object. Exposures are taken in ascending MJD, and objects founded by
one exposure are seen by the next, not by their own. A second pass over
the eight neighbouring fields' sources adds memberships only.

The sums are of offsets from the founding position, not of raw
degrees: at RA 268 an object spreads by about 1e-5 degrees, and a
variance from raw-degree sums would be lost to cancellation. The mean
is `ra0 + sumra / n`, and the standard deviation in RA carries one
cosine, of the mean declination. An excluded source set's members are
subtracted once; an object left with no members stays with
`nsources = 0`.

### packet

`packet` is a port of `dev`'s alerts package at schema 00.06, one job
per difference image. Every `flags = 0` source the named object set
holds triggers a packet; a source in several objects takes the lowest
object id, as `dev` does, and `dev`'s cap per chip is not carried. Each
packet carries:

- `diaSource` from the source row;
- `prvDiaSources`, the object's members through the chain, less
  exclusions, with `mjdobs` before the trigger and within the history
  window;
- `diaObject` from the set's position and sums, `nDiaSources` counting
  members up to and including the trigger;
- `prvDiaForcedSources`, `dev`'s PSF photometry at the object's founding
  position on every window image that holds it, difference and science
  image merged into one row per object and image, rows a predecessor
  set holds copied rather than measured;
- `gaiaMatches` with proper motion propagated to the trigger, and
  `refStarMatches` and `refGalaxyMatches` from the reference's mosaic
  catalog;
- `cutoutDifference`, `cutoutScience` and `cutoutReference`, each 129
  pixels square, pixels off the chip filled with 0.0.

`ssMatches`, `nedMatches` and `lvsMatches` are null: in the schema's
contract null means the match did not run, and these are deferred. The
difference image is measured with its own PSF and uncertainty map,
where `dev` measures the SFFT difference image whatever the named
flavour.

### The reader

`scripts/read_packets.py` reads what `packet` published and exits
non-zero on any failure. It checks that every record is valid against
the schema its index row names; that every cutout opens as FITS at the
stated size with the stated fill; that every forced value equals the
`forced_official` row with its id; that every previous detection
precedes its trigger; and that every index row decodes to its record
and names the job's recorded inputs.

### Publication to Kafka

`rapidpipe publish --run <id>` takes every packet set of the run that is
official and not yet stamped, and produces one message per packet to the
topic. The key is the packet set's job and the packet's source id; the
value is a one-record Avro container, the set's container header with
the packet's own block, so each message decodes on its own and carries
its schema. There is no schema registry. The producer waits for every
acknowledgement from all in-sync replicas, then stamps the set's job
with the time (`jobs.kafka_published_at`). A producer error leaves the
set unstamped and the verb exits 70. A crash between the last
acknowledgement and the stamp offers the set again on the next call, so
a consumer may see a packet twice; replay is allowed and there is no
exactly-once delivery. A set that loses its binding before it is
stamped is not offered.

The cluster's bootstrap servers, the topic and the largest request the
producer may send are named in the settings file's `[kafka]` table as
the deployment's parameter names, never their values, and the
connection authenticates with the caller's own cloud credentials. The
transport is not part of a run's recipe: `publish` reads the table from
the shipped settings file or the one `--settings` names, not from the
run's body.

`scripts/consume_packets.py --run <id>` is the consumer check. It reads
every partition from its earliest offset to the end offset at its
start, with no consumer group; keeps the messages whose key names one
of the run's stamped sets; and requires each to decode as one record
valid against its index row's schema, to equal the outbox bytes for its
key, and every stamped packet to be seen at least once. Zero kept is a
failure.

Today the producer runs where the loop runs, on a host, after the
packet stage has published. Producing from the packet stage's own Batch
job, as its last act, is not decided (Not decided here, below).

### Settings of the thin run

The run's body is `rapidpipe/settings/foundation-thin.toml`, one table
per stage, with `dev`'s values where `dev` hard-codes them: the import
cap `max_sources` (500); `associate.match_radius` (1.528e-05 degrees),
`source_flags` (0) and `min_snr` (5); `packet.stamp_half_width` (64),
`prv_window_days` (365.25), `forced_window_days` (30),
`gaia_radius_arcsec` (1) with `gaia_max_matches` (3), and
`refcat_radius_arcsec` (5) with `refcat_max_matches` (3). `[reference]`
and `[difference]` carry `dev`'s ini sections as subtables, one per
section, with `dev`'s values (`min_frames` 2 and `max_frames` 25 among
them); `[difference]` adds `max_sources` (500) with the import's
meaning, and `[difference.statistics] clip_correction_seed` (0) makes
the stage's output the same on the same inputs. The paths in those tables are the pipeline image's; a run
outside the image overrides them in its own body. Data locations are
never in the shipped file: the import's source directory is its job's
scope, the intake's source root is the run's own `[intake]
source_root`, given in the settings overlay at `run create`, and the
outputs root is the environment's.

## The queries

The official views answer eight queries without reading files:

- the current image and source set for a dataset, exposure, SCA and
  filter;
- the current object set of a field and its members;
- an object's detection and forced history within a named set;
- packet history by observation, by source and by versioned object;
- a candidate set against the official one, with unmatched detections
  shown;
- the ancestors of a packet set, and the descendants of a bad
  reference;
- failed and unbound jobs;
- the bindings before and after a named change group.

The first four have precedent in the team's code; the other four are
new with this design. Beside them, the team's twelve spatial and status
shapes run on the views with the q3c and GIN indexes used: a cone over
difference images, L2 images in a cone overlapping a field, difference
images in a cone with their reference, overlap of `overlapfields`,
objects in a cone, a chip's unflagged sources, the usable reference,
the L2 time-window work list, L2 images without a difference image,
frame counts, a difference image by its product id, and L2 images with
a usable reference. All of them are `database/queries.sql`, one named
statement each. A query within a named set reads base tables through
that set's recorded chain; every other query reads the official views.

## The procedure proof

`tests/db/proof/thin_proof.py` runs the thirteen observations of the
procedure proof on the thin field's real data, through the verbs and
`job local` only, from an empty database. They cover the object binding
moved by the publisher alone; two jobs racing for one binding; a recipe
that is not live beside the live one; a cutover group and its undo; a
job launched before a cutover and published after it; a correction run
of one epoch's packets; a job killed before and after its commit; two
recipes from two commits at once, joined on scientific key and on
object id; two change groups on one binding; publication racing a
cutover; an undo refused because a binding moved; and a replacement
source set excluded downstream. The first passing run took about two
minutes. The same observations on synthetic rows run in CI under
`tests/db/proof/`.

## On SMDC

The SMDC database `rapid` holds the foundation in its `public` schema,
and the pipeline repository's `docs/foundation-smdc-step.md` is the
procedure, one command and then its check per step. It has seven parts.

**The schema.** `public` is dropped and recreated from `schema.sql` in
one transaction, through the pooler, as the database owner. Everything
else in the database stays: the operations schema, the pooler's lookup
schema and every role. The pipeline's role then gets read, write and
`MAINTAIN` on every table and sequence, and the same by default on
anything created later. SMDC is a prototype that nothing else writes
to ({ref}`ruling <decision-smdc-prototype>`), so there is no backup
before the replace and no fence on the pooler around it; the rollback
is the previous schema in git. The check that the pipeline's own path
works is `rapidpipe run show 1` exiting 64, "run 1 does not exist".

**The inputs.** The field's files are copied into the inputs bucket
under `foundation/`. That bucket is write-once: its policy refuses an
upload without a create-only condition and refuses every delete.

**The baseline.** The milestone 1 to 3 jobs (import, associate,
packet) run again under run 1, which is made live, with the outputs
root on the scratch bucket. Their products are bound by the publisher
as they land. Every Batch stage later reads them, and the Batch job
role cannot read the products bucket, which is why the baseline writes
to scratch too.

**Batch.** A run that is not live names the commit whose image the job
definition pins. Under it, `reference` coadds the baseline's two L2
images, `difference` subtracts each epoch from that reference, and
`associate` and `packet` follow, every one of them submitted with `job
submit`. Their products publish unbound, because the run is not live.
One change group then replaces the imported reference, difference
images, source sets, object set and packet sets with the Batch-made
ones. The reference is in the group because the official difference
images must be the ones subtracted against the official reference. The
exposures, L2 files, PSFs and Gaia copy stay on the baseline's jobs.
The undo of that group restores every official view, and every table's
row count is unchanged except `official`'s, so nothing is deleted.

**Uncapped.** The same chain at `max_sources = 0`, against the same
reference, measured per stage, then its own change group and undo.

**The night.** The sixth part takes one field's whole simulated night,
69 epochs of one SCA in one filter, through the chain twice: once in
the shape of the live loop and once as a campaign, then makes the
campaign official and exercises the operations on it.

- *The PSF kind and the read role* went in as the first incremental
  SQL, in one transaction as the database owner: the `kind` column,
  each existing row's kind read from its file's keyword, the check
  constraint, the unique key and the view replaced, and the kind
  backfilled into the stored keys of `official` and `job_inputs`, which
  compare a key as a whole. The reference PSF, unbound until then
  because its key collided with the science PSF's, was bound by one
  group. The team's read role gained `SELECT` on every table and view
  of `public`, and the same by default on anything created later
  ({ref}`ruling <decision-read-role>`).
- *The cutover* was one change group of two rows: it closed the
  baseline run's live binding and opened one for a new run, created
  not live a moment before. Every product binding stayed on the
  baseline's jobs, because a cutover carries only what it names.
- *The live loop* imported the night's 67 further epochs under the new
  live run, one host job per epoch in order of `mjdobs`, each bound by
  the publisher as it landed. `associate` and `packet` then ran on
  Batch for each epoch in turn: each `associate` named the current
  official object set as its predecessor, and each `packet` named the
  earlier packet sets' `forced.parquet` among its inputs, since a set's
  forced rows cover only the objects that triggered in it. All 134 jobs
  succeeded on their first attempt and were bound automatically. The
  night's last object set holds 1,504 objects with 2,547 memberships
  across 69 sets, and 69 packet sets hold 2,488 packets, all read clean
  by the reader.
- *The campaign*, a run that is not live and keeps every source,
  coadded a reference from the night's first 25 epochs (none of the
  25 frames of `dev`'s reference is in the night), differenced all 69
  epochs on Batch at once and one epoch a second time, and ran
  `associate` and `packet` over the first five epochs. Everything
  published unbound.
- *One change group made the campaign official*: it opened 145
  bindings, the reference, 69 difference images, 69 source sets, the
  last object set and five packet sets, and closed the 209 it replaced,
  including the live loop's packet sets for epochs 6 to 69 with nothing
  opened in their place. Exposures, L2 files, PSFs, the Gaia copy and
  the live binding did not move. Of the two executions of one epoch,
  the group bound the first; the other stays a visible candidate.
- *A mid-night epoch was replaced*: the third epoch of the campaign's
  chain was differenced again, an `associate` job named the new source
  set, the night's last object set as predecessor and the old source
  set as an exclusion, a `packet` job followed for that epoch, and one
  group bound the four keys together, so there was no moment when the
  sources had moved and the objects had not. The packets of epochs 4
  and 5 stay as published, and three of them carry an epoch-3 detection
  of the old set in their history; they are valid against their
  recorded inputs. A loop does nothing about them, since a packet is a
  record at its trigger time; a campaign that wants them consistent
  reruns from the replaced epoch.
- *Undo* of the replacement group restored the open bindings row for
  row. The undo of the night's group then refused, because the first
  undo had reopened four of its keys as new rows and an undo never
  reopens a closed row; an explicit group that closed the current
  binding on each key the night's group opened and reopened what it
  closed restored the earlier state row for row. The night's group was
  then applied again, so the campaign's products are official and the
  live run is unchanged.
- *Two change groups closing the same binding at once, through the
  pooler*: the second blocked on the row lock, then refused naming the
  binding, and nothing was half-applied.

**The wide-area survey.** The seventh part takes the chain from raw
SOC L2 files to the Kafka topic, with every byte inside SMDC and
nothing imported from another centre. Its data are STScI's SOC
simulation r00342 of the High Latitude Wide Area Survey, read from a
public bucket: 54 pointings on a grid one SCA wide, revisited to within
a few arcseconds in every pass, with a Gaia-fitted WCS and no
time-variable sources, so every difference is a null test. It uses F146
only, the one filter with PSFs on SMDC.

- *Fixes first.* The instance type went onto the job row, a refusal
  because the run is not live stopped being a Batch failure, the
  download cache is removed when the process exits, and the reference
  stage's seed is pinned as the difference stage's is. One proof job on
  each of two Intel sizes reproduced its epoch's earlier Intel rows bit
  for bit; the one earlier AMD execution of the same epoch differs from
  all of them in a few thousand rows, by at most half an arcsecond and a
  few percent in flux.
- *The endpoint before breadth.* The GBTDS night's official packets
  were produced to the topic from the fleet host and read back by the
  consumer check, every one byte-equal to the outbox; a second publish
  produced nothing.
- *A live run beside the GBTDS one.* The HLWAS dataset has its own run,
  live for its survey and dataset while the GBTDS run stays live for
  its own, as the one-live-run rule allows. Its 36 F146 PSFs, one of
  each kind per SCA, were imported under the dataset, and a Gaia DR3
  copy covering the whole footprint was fetched from the ESA archive
  and imported under its own catalog name, since the `catalogs` key has
  no dataset and the GBTDS copy holds the plain name.
- *One pointing.* The six F146 epochs of one SCA's pointing went through
  intake, reference, difference, associate and packet on Batch, then to
  the topic, with the validation checks now a script run over the whole
  run.
- *The loop.* `rapidpipe loop` took a second pointing from ASDF to the
  topic in 18 passes with no hand on it.
- *The ramp.* The loop's selection widened to every F146 pointing on
  SCA 8, 312 more epochs on 52 more fields, drained in 15 passes and
  42.8 minutes with no failed job; then to all 18 SCAs of the first
  pointing, 102 more epochs, drained in 18 passes and 34.6 minutes. The
  run ended with 426 epochs on 70 fields, 70 references, 70 per-field
  chains and 55,436 packets on the topic, every job published and bound.
- *A field shared by two SCAs.* The pointing grid's step is one SCA
  width, so SCA 9 of one pointing lands on the field SCA 8 of the next
  pointing covers. The reference key has no SCA, so SCA 9's epochs were
  differenced against SCA 8's reference, each naming its own SCA's
  reference PSF, and were appended to that field's chain after SCA 8's
  epochs although each was taken earlier. Nothing failed and the chain
  check held, since it checks integrity and not order; the question is
  open (Not decided here, below).

## Validation

A night is one coherent account when it meets ten checks. Each is a
function over the views, the tables, the Parquet under the prefixes and
the Avro read with the reader's own functions, and prints a pass line
or its first counter-example. Checks 1 to 6 run on a whole run's
products; 7 to 10 on the operations.

1. **Lineage closes.** Every published row names a published job and
   every job a run; every `job_inputs` row resolves to a published row
   of its product and key; every binding, open or closed, names a
   published job's rows. No orphans either way.
2. **Parquet and tables agree.** Each declared output's row count is
   the table's count for that job, and the manifest's checksums match
   the bytes in the prefix.
3. **The chain.** `members_official` equals the union of
   `matches.parquet` over the object set's predecessor chain, less
   exclusions, row for row; every object's sums reproduce its members'
   mean and standard deviation; every object of a set is in the next.
4. **Packets.** Against the packet job's own recorded inputs, never the
   current official sets: every history detection precedes the
   trigger, `nDiaSources` counts the memberships up to the trigger, the
   three cutouts open, every forced row equals the row of the
   `forced.parquet` its inputs name, and every index row resolves to
   its Avro record. The reader passes on every set.
5. **Forced photometry is measured once.** Each (object, image) pair is
   measured in one packet set; a set that carries a reused row carries
   the same measurement, value for value.
6. **Two executions of one key** both publish with equal rows, and at
   most one is official while the other is a visible candidate.
7. **One group makes a night official**: every view the group names
   moves to the new jobs, nothing it does not name moves, and every
   table's row count is unchanged except `official`'s.
8. **A replacement conserves membership**: the official members are
   the predecessor's, less every membership of the old source set,
   plus the replacement's matches, row for row, and only the touched
   objects change.
9. **Undo restores** the open bindings row for row, deleting nothing.
10. **Two concurrent groups on one binding**: one commits, the other
    refuses naming the binding, and nothing is half-applied.

On 2026-10-21 the night met all ten. Checks 1 to 6 held on the live
loop's run, 69 sets deep, and again on the campaign's after it became
official, five sets deep; 7 to 10 held on the campaign. Check 9 held
by the rule's own refusal: after a later group has moved one of its
keys, an undo refuses and an explicit group restores.

Checks 1 to 6 are now one script, `scripts/validate_run.py --run <id>`,
each a function scoped to one run's jobs. Two are restated for that
scope: the chain check covers every object set of the run that is bound
or is the last of its chain, and the forced check requires that a
packet set's row for an (object, image) pair a recorded predecessor set
also holds is that predecessor's measurement. Checks 7 to 10 are
operations with no read-only form over a run, checked as they run. The
script passed on both GBTDS runs, and on the wide-area run after its
first pointing, after its second, after the SCA 8 ramp and after the
18-SCA ramp. The reader was clean on every packet set and the consumer
check on every packet each time.

## Measurements

Measured 2026-10-21 on SMDC, field 4658155, SCA 8, filter W146, every
Batch job with one vCPU. The pipeline repository's runbook carries the
full tables, ids and commands; these are its results. They are
observations, not gates: latency and performance are a later task
({ref}`ruling <decision-latency-later>`).

| Stage | Jobs | In container | Queue wait | Peak memory, process / largest child | Output per job |
|---|---|---|---|---|---|
| `import`, on a host | 67 | 5.9 to 7.1 s, mean 6.4 s | | | about 327 MB |
| `reference`, 25 frames | 1 | 227 s | 115 s, from a cold queue | 1.35 / 1.41 GiB | 595 MB |
| `difference` | 71 | 1,091 to 1,181 s, median 1,124 s | 2.4 to 222 s, median 166 s | at most 1.39 / 14.54 GiB | 72 files, about 2.8 GB |
| `associate`, live loop | 67 | 2.4 to 10.0 s, mean 2.7 s | median 6.9 s | 227 to 243 MiB | a few KB |
| `packet`, live loop | 67 | 28 s at 3 window images to 362 s at 69, mean 189 s | median 7.1 s | 844 to 1,036 MiB | 469 MB of Avro in all |
| `associate`, campaign | 5 | 2.7 to 3.0 s | | 224 to 230 MiB | a few KB |
| `packet`, campaign | 5 | 12.7 to 37.8 s | | 844 to 848 MiB | 61 MB in all |

- **The fan-out.** All 70 difference jobs of the campaign started within
  240 s of the first submit and ran at once; the last published 23 min
  19 s after the first was submitted. The largest child process peaked
  at 14.54 GiB, against the job definition's 24 GiB.
- **The live loop's chain**, first submit to last packet, took 3 h 53
  min. The `associate` chain alone took 27 min; the `packet` chain is
  the critical path, because each packet job waits for the one before
  in order to reuse its forced rows. Forced photometry is 69% of the
  packet stage's time, about 3.6 s per window image, and a newly
  triggering object is measured on every earlier image of the night.
  The night produced 87,404 forced rows, 62,427 of them measured.
- **Chain depth.** At 69 sets the chain walk took 1.8 ms and
  `members_official` 32 ms; at 5 sets, 1.8 ms and 5.1 ms.
- **Change groups.** The cutover, two rows, took 4.1 ms. The night's
  group, 145 opens and 209 closes, took 257 ms in the operation, 1.23
  ms per key, and 0.58 s with process start-up; eight keys had taken
  2.4 ms per key, and a local database 0.14 ms. The replacement's
  group of four keys took 12.1 ms, its undo 8.9 ms.
- **The ten checks** took 255 s on the live loop's run and 145 s on the
  campaign's, mostly reading S3.
- **The database** is 239 MB: `sources` 102 MB, `objects` 19 MB,
  `forced` 19 MB, and every other table under 2 MB. `official` holds
  961 rows. All 23 statements of `database/queries.sql` run under 30 ms
  at this size.
- **Storage.** The live loop's run holds 22.4 GB under the scratch root,
  almost all the imported images; the campaign's holds 201 GB, 197 GB
  of it the difference stage's working files.
- **The retry.** A job that could not reach the database exited 75 on
  each of three attempts, 33 s from the first start to the last stop; a
  job with a bad parameter tree exited 64 once.
- The source counts and the comparison with `dev`'s night are on the
  [difference](difference) and [reference](reference) pages.

**Against the hour per image.** The provisional requirement is an alert
current within an hour of an image's delivery
({ref}`ruling <decision-latency>`). On this chip one epoch's chain on
Batch takes about 19 minutes of difference, seconds of `associate`, and
a packet job that grows with the window, from under a minute to six
minutes over one night; the difference stage dominates until the
window is long. Shortening either is the later task the latency
ruling names.

### The wide-area ramp

Measured 2026-10-22 on SMDC over the F146 ramp on SCA 8, 312 epochs on
52 fields, all driven by the loop. The compute environment chose
r6i.8xlarge for nearly every job, because one job definition reserves
the difference stage's 24 GiB for every stage.

| Stage | Jobs | Queue wait, min / median / max | In container, min / median / max | Peak memory | Output, median per job |
|---|---|---|---|---|---|
| `intake` | 312 | 54 / 144 / 158 s | 17.1 / 20.8 / 24.6 s | 910 MiB | 195 MB |
| `reference`, 6 frames | 52 | 5.0 / 6.5 / 9.2 s | 77 / 98 / 102 s | 2,831 MiB | 596 MB |
| `difference` | 312 | 7 / 154 / 228 s | 206 / 246 / 327 s | 16,125 MiB | 2.55 GB |
| `associate` | 312 | 4.6 / 11.5 / 191 s | 2.4 / 3.5 / 11.8 s | 238 MiB | a few KB |
| `packet` | 312 | 3.0 / 48 / 189 s | 13.0 / 30.2 / 60.5 s | 867 MiB | 26 MB |

- **The drain.** First intake submitted to last packet produced, 42.3
  minutes. The stages' spans, first launched to last ended: intake 3.5
  minutes, reference 1.9, difference 9.0, associate 23.8, packet 29.7.
  At most 290 containers ran at once, the differences.
- **The chains.** Each field's six associates took 20 minutes end to
  end for about 21 seconds of containers: a chain advances one link per
  loop pass ([loop](loop)).
- **One intake on Batch**: fetch of the 204 MB file 0.8 s, conversion
  2.7 s, gzip 5.5 s, limiting magnitude 3.5 s, rows 1.0 s, upload and
  publish 1.5 s.
- **Kafka.** 43,725 packets in 324 sets, 8.43 GB of Avro, at about 4.3
  s and 31 packets a second per set; the largest message is 1.5% of the
  request limit, and every message repeats the 35 KB container header.
- **The checks.** `validate_run.py` took 20.5 minutes over the 324
  epochs, the reader two minutes eight sets at a time, and the consumer
  check 32 minutes at 20 GB of memory.
- **The database** is 365 MB after the SCA 8 ramp: `sources` 133 MB,
  `forced` 49 MB, `objects` 48 MB. After the 18-SCA ramp it is 396 MB
  and `official` holds 3,523 rows.
- **Storage.** The run's prefix holds 1.2 TB after both ramps; the
  difference stage's working files are 89% of it, 42 uncompressed FITS
  files per epoch.
- **The 18-SCA ramp**: 102 epochs, first intake to last packet 34.0
  minutes, at most 99 containers at once, 11,711 packets, median queue
  waits 86 s for intake and 98 s for difference.
- **The null test.** Per epoch the difference stage found 798 to 1,207
  detections before the cap of 500, median 954, with 53 to 119 above
  S/N 20. They sit at and around stars, the residual a PSF made for
  another simulation leaves; none is variability. SCAs 4 and 5 leave
  three to four times the bright residuals of the other SCAs.

**Not measured, for want of data on the host that ran it**: the matcher
and the difference stage at the plan's density; a thirty-day window of real
cadence; completeness against the injected sources; and the rubrat,
NED and NED-LVS matches, whose model and catalog copies are in a bucket
this account cannot read. sumrat needs no new data, but no stage
computes it yet.

## Not decided here

- The cost of following an object set's predecessor chain when a field
  has tens of thousands of sets. A synthetic chain of ten thousand sets
  walked in 9.9 ms and the night's 69 in 1.8 ms; if it bites later, a
  periodic set holding the full membership compacts the chain, a job
  like any other.
- Forced photometry's cost at scale. It is about 3.6 s per window
  image, dominated by opening the images, and it orders the packet
  jobs into one chain. Measuring a night's new objects per image across
  jobs, or naming predecessor sets for reuse without waiting on them,
  would change both.
- The cost of a large change group, about three round trips per item
  through the pooler: 1.23 ms per key at 145 keys. A set-based close
  and open would remove most of it.
- Whether an undo after a later group has moved one of its keys should
  have a verb. Today it refuses, which is the safety the design asks
  for, and an explicit group restores.
- The difference stage's rows differ in some columns between CPU
  families on the same inputs, by unverified cause: two Intel sizes
  agree bit for bit and one AMD execution does not. The instance type
  is now on every job row, so a comparison can be filtered; whether a
  run should hold to one family is open, and today it does not.
- Whether a reference is per field and filter, as its key is today, or
  per field, filter and SCA; and what a field's chain does with an
  epoch that arrives after later ones. An SCA landing on a field
  another SCA referenced is differenced against that stack and joins
  its chain out of order.
- A reference disjoint from the epochs it is subtracted from. Today a
  field's reference coadds the same epochs that are then differenced,
  which suits a null test and would suppress a real transient.
- The `catalogs` key, (name, version), is the one key without the
  dataset. A second footprint's Gaia copy takes its own name today;
  the key gaining the dataset, as every other key has, would make it
  one product per dataset.
- Producing packets to Kafka from the packet stage's own Batch job, as
  its last act, in place of a host process after the fact. It needs a
  grant on the Batch job role and a path from the compute environment
  to the brokers, neither tested.
- PSFs for the other filters. Only F146's exist on SMDC, so only F146
  has been run.
- **Source injection is the next scientific step.** The chain has the
  right shape and functions on a static simulated sky; whether it
  finds what is there is the next question, asked by injecting sources
  into the same data, before more breadth.
- Packets after a replacement stay as published with the old
  detections in their history; whether a loop should ever rebuild
  them is open. A campaign reruns from the replaced epoch.
- Dense-field memory for `associate` and packet counts per chip.
- The meaning of `nDiaSources` in the 00.06 schema's own documentation,
  which is `dev`'s; changing it is a schema change for the team.
- `packet.edge_pixels` is in the thin run's settings and read by no
  stage, since no two-pixel edge rule exists in `dev`'s alerts code.
