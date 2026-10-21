# The foundation and the thin chain

**Status: DRAFT**

This page states how RAPID records what it made and which of it is
official, and the narrow chain of stages built on that record, from
stored images to alert packets. It is the design the `rebuild` branch
of the pipeline repository implements: `database/schema.sql`, the
package `rapidpipe.foundation`, the stages `import`, `reference`,
`difference`, `associate` and `packet`, the reader
`scripts/read_packets.py` and the queries in `database/queries.sql`.
The [stage contract](stage-contract) page states what a stage is under
it, and the [decisions](decisions) page records the rulings it rests
on. The chain has run end to end on SMDC's database and AWS Batch; the
last two sections give the procedure and what it measured.

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
checkout), the settings hash, the attempt whose outputs were published,
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
| `psfs` | dataset, fid, sca | `psfs` |
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
another run.

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
   `ANALYZE` on the tables it loaded.

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
apply is one `psql -f`. There is no migration machinery until the first
change after real data; from then on changes are incremental SQL.

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

A refusal exits 1 with the binding named; a missing row or unreadable
file exits 64.

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
`job run` does on a host. A retry is the same Batch request submitted
again: `job run` stops on a published job and otherwise takes the next
attempt. Running the job records the job definition's image digest on
the job row, and its printed result carries the peak resident memory
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
| `import` | stored products for one field: L2 files, difference images, PSFs, the reference and its mosaic catalog, the Gaia copy; the cap on sources per image | copies of the image files; `exposures`, `l2files`, `diffimages`, `psfs`, `refimages`, `refimcatalogs`, `catalogs` and `sources` (the brightest N per difference image by flux over its error), with limiting magnitude, overlapping fields and sky indices computed; the source system's ids kept; provenance marked unknown | other fields and epochs; recovering provenance |
| `reference` | the field's `l2files` rows for one filter and SCA | the awaicgen mosaic with its coverage and uncertainty maps and SExtractor catalog; `refimages`, `refimimages` (one row per coadded L2 row) and `refimcatalogs` | `dev`'s later reference changes (infobits, status, the 9100-pixel mosaic); the Photutils catalog |
| `difference` | one epoch's `l2files` row, a `refimages` row with its mosaic catalog, the science PSF and the reference PSF; the cap on sources | the ZOGY difference image and the files `packet` reads beside it, SFFT and naive as `dev` runs them; `diffimages` and the `sources` set, mapped exactly as the import maps `dev`'s | sumrat, real/bogus and the extra SFFT catalog columns; `dev`'s loader prefilter |
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

### reference

`reference` coadds the L2 images its job names into one reference for
a field, filter and SCA, with `dev`'s steps in `dev`'s order: each
frame reformatted and scaled to the filter's zero point, the awaicgen
mosaic with its coverage and uncertainty maps, the coverage and image
measurements `dev` keeps, SExtractor on the mosaic, and a header stamp
naming the run, job, attempt and stage. Frames are coadded in order of
observation time; fewer than `min_frames` fails the job, and frames
past `max_frames` are left out and named in the manifest.

The stage draws the reference's `rfid` from the table's own sequence
while it reads its inputs, so the member and catalog rows carry it
before publication. That `rfid` is the foundation's; an imported
reference keeps the source system's id as an import-only value. The
mosaic carries the filter's zero point as `MAGZP` (26.863 for W146),
where the imported reference from `dev`'s August run carries the scalar
fallback, 17.0.

### difference

`difference` subtracts one epoch's L2 image from the reference its job
names, with ZOGY, and runs SFFT and the naive subtraction beside it as
`dev` does. The science was refreshed from `dev` before the port: the
image FWHM from point sources, the reference background subtracted by
the science image's background estimator, the detection overrides of
the SFFT and naive catalogs, SFFT's coverage mask, and `dev`'s current
SExtractor tables. Gain matching reads the reference's zero point from
its own `MAGZP`, so an imported and a coadded reference both work.

ZOGY needs two PSFs, the science image's and the reference image's.
Both are `psfs` rows under the same key, and the stage tells them apart
by the `PSFKIND` keyword in each file, failing unless there is exactly
one of each. A run has one differencer, so only the ZOGY image is
published as a `diffimages` row; the SFFT and naive files stay under
the prefix for diagnosis. The `sources` set is the ZOGY positive PSF-fit
catalog, capped at `max_sources` by flux over its error (0 keeps every
source), through the same mapping the import uses. A missing catalog
publishes an empty set with its outcome bit set in `infobitssci`.

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
meaning. The paths in those tables are the pipeline image's; a run
outside the image overrides them in its own body. Data locations are
never settings: the import's source directory is its job's scope and
the outputs root is the environment's.

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
procedure, one command and then its check per step. It has five parts.

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

## Measurements

Measured 2026-10-21 on SMDC, two epochs (expid 84613 and 84624) of
field 4658155, SCA 8, filter W146, every stage on Batch with one vCPU
and 15 GiB per job. The pipeline repository's runbook carries the full
tables, ids and commands; these are its results. They are observations,
not gates.

| Stage | Epoch | In container, cap 500 | In container, uncapped | Peak memory, process / largest child | Outputs |
|---|---|---|---|---|---|
| `reference` | both | 36.8 s | (the same reference) | not recorded | three 196 MB images, an 8.3 MB catalog |
| `difference` | 84613 | 1,348 s | 1,369 s | 1.37 GiB / 14.35 GiB | 72 files, 2.82 GB |
| `difference` | 84624 | 1,324 s | 1,353 s | 1.31 GiB / 14.35 GiB | 72 files, 2.82 GB |
| `associate` | 1 | 2.8 s | 3.2 s | 227 MiB | 10.3 KB |
| `associate` | 2 | 2.7 s | 2.9 s | 228 MiB | 13.5 KB |
| `packet` | 84613 | 21.5 s | 14.1 s | 844 MiB | 15.7 MB |
| `packet` | 84624 | 17.8 s | 18.5 s | 845 MiB | 14.1 MB |

Peak memory is from the uncapped run, the first to report it. A cold
queue added about two minutes before the first job of each run; jobs
that found an instance running waited under ten seconds. The baseline's
`job local` jobs on a host took 1 to 10 s each, and the schema replace
took 1 s.

- **Sources per image before the cap**: 5,703 and 5,544, against 5,450
  and 5,586 in `dev`'s own catalogs of the same images. The same code on
  the same inputs counted 5,539 for 84624 in the capped run, so the
  stage is not reproducible run to run by a few sources; the cause is
  not established. The plan's figure of 16 to 43 thousand sources per
  image is not reproduced on these two images, by the port or by `dev`.
- **Objects, memberships and packets**: 155 objects (82 founded by the
  first epoch, 73 by the second), 82 and 73 memberships, 82 and 73
  packets, all read CLEAN by the reader. Removing the cap changes none
  of these: `associate` accepts 199 and 158 sources by flags and
  signal-to-noise, all inside the brightest 500.
- **The matcher** took about 1 s per epoch at 227 MiB on those sources.
- **The member chain** is two sets deep on this field. A synthetic
  chain on a local database, with 1,000 memberships per set, measured
  the packet stage's reads: at 10,000 sets and 10 million memberships
  the chain walk took 9.9 ms, the trigger lookup 12 ms, and 500
  objects' history 0.92 s for 1.58 million rows. The history read grows
  with the rows it returns, not the depth.
- **A change group** of eight keys took 19.3 ms through the pooler and
  its undo 15.3 ms; the command around each took 0.40 s, mostly
  start-up. The local curve's 0.14 ms per key predicts 1.1 ms; the rest
  is round trips to the pooler.
- **The Batch-made sources against `dev`'s**: 1 to 2% of the capped 500
  match `dev`'s within the match radius, and the difference images
  correlate at 0.71 to 0.73. The Batch reference coadds the two epochs
  being differenced, so each subtraction removes half of itself; `dev`'s
  reference is 25 other frames. Against `dev`'s reference, the port's
  host difference image correlates with `dev`'s at 0.99989. With two
  epochs the Batch result proves the chain, not the science.

**Against the hour per image.** The provisional requirement is an alert
current within an hour of an image's delivery
({ref}`ruling <decision-latency>`). On this chip, one image's chain on
Batch took about 25 minutes: two of cold queue, 22.5 to 23 of
difference, and under half a minute for `associate` and `packet`. The
difference stage is 95% of it, the cap does not change its cost, and
its largest child process peaked 0.65 GiB under the job definition's
15 GiB. These figures cover two epochs and one chip, with a reference
that includes the images it is subtracted from.

**Not measured, for want of data on the host that ran it**: the field's
other epochs and a second field; the matcher and the difference stage
at the plan's density; a night's fan-out across 18 chips; packets with
a thirty-day window; a reference built from other frames; completeness
against the injected sources; and the rubrat, NED and NED-LVS matches,
whose model and catalog copies are in a bucket this account cannot
read. sumrat needs no new data, but no stage computes it yet.

## Not decided here

- The cost of following an object set's predecessor chain when a field
  has tens of thousands of sets. The synthetic measurement above finds
  no need for compaction at ten thousand; if it bites later, a periodic
  set holding the full membership compacts the chain, a job like any
  other.
- Forced photometry's cost at scale. On the thin field it is two to
  four seconds per window image, dominated by opening the images, not
  by the fits.
- Dense-field memory for `associate` and packet counts per chip.
- The cost of a large change group. The operation is linear at about
  0.14 ms per key on a local database and dominated by round trips
  through the pooler; a set-based close and open would remove most of
  it. On an `official` table never analysed, the planner picks the
  wrong partial index, and the publisher analyses only the tables it
  loads.
- Whether the PSF key needs a kind. The science and reference PSFs of
  one filter and SCA share a key today, and `difference` tells them
  apart by a keyword in the file.
- Whether the team's read role reads the foundation's tables, or only
  the official views. It has `USAGE` on the schema and no `SELECT`.
- The meaning of `nDiaSources` in the 00.06 schema's own documentation,
  which is `dev`'s; changing it is a schema change for the team.
- `packet.edge_pixels` is in the thin run's settings and read by no
  stage, since no two-pixel edge rule exists in `dev`'s alerts code.
- The imported reference has no `refimimages` rows, since the source
  system's rows do not name its members; a reference `reference` makes
  has them.
