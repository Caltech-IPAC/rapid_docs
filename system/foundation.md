# The foundation and the thin chain

**Status: DRAFT**

This page states how RAPID records what it made and which of it is
official, and the narrow chain of stages built on that record, from
stored images to alert packets. It is the design the `rebuild` branch
of the pipeline repository implements: `database/schema.sql`, the
package `rapidpipe.foundation`, the stages `intake`, `import`, `psf`,
`reference`, `difference` and `packet`, the loop, the quality gate, the
Kafka publication, the reader `scripts/read_packets.py`, the run
validation `scripts/validate_run.py`, the check script
`scripts/check_run.sh` and the queries in `database/queries.sql`.
The [stage contract](stage-contract) page states what a stage is under
it, and the [decisions](decisions) page records the rulings it rests
on. The chain has run end to end on SMDC's database and AWS Batch over
one field's whole night, 69 epochs, and then from SOC L2 ASDF files to
the Kafka topic over 426 epochs of a simulated wide-area survey, and
again after the housekeeping that made each epoch cheaper and gave the
reference a bound, and then over the simulation's six other filters,
each with PSFs the pipeline derives itself, and then with association
moved into the difference job, injected sources counted, Spot measured
and two more simulations taken in ([datasets](datasets)); the last
sections give the procedure, the checks they met and what they
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

`run create` resolves the body from three layers, low to high. The
shipped defaults, `rapidpipe/settings/foundation-thin.toml`, hold
`dev`'s values and `dev`'s behaviour, with the measured value and its
reason where a behaviour is new to the rebuild. A dataset's overlay,
`rapidpipe/settings/datasets/<dataset>.toml` (`--overlay`), holds only
the keys that differ for that dataset, each with a comment naming the
measurement that earned it; it is the recorded divergence from `dev`,
and what the next dataset copies and edits. Command-line overrides
(`--set TABLE.key=value`) carry one run's experiment. The run stores the
resolved body, its hash, and the name and hash of each layer, which
`run show` prints as `layers`. A middle layer per survey or instrument
waits until two datasets share a quirk. A setting exists only where a
measured case needed a different value; otherwise the code does one
thing. Datasets differ at intake in kind (a reader per input format, a
WCS correction, the data-quality mask) and downstream only in value. A
code divergence from `dev` where `dev` has no knob is one line on the
[decisions](decisions) page with its measurement. The overlays and what
earned each key are on the [datasets](datasets) page.

### Jobs

A job is one execution of one stage under a run. The `jobs` row holds
the stage, its scope, its state (`launched`, `running`, `published` or
`failed`), the image digest it ran under (none for a job run from a
checkout) and beside it the instance type, the Batch job id it was
last submitted as (none for a local job), the settings hash, the
attempt whose outputs were published, its manifest, the launched,
started and ended times, the exit code, and the reason an automatic
binding was refused, if one was, or the reason Batch gave for ending a
container that never recorded its own end. Local and Batch executions
both get a job row. A killed execution is a job row
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
| `objects` (the object catalog, not bound) | dataset, survey, field, object id, founding job | `objects`, with `memberships` declared beside each source set |
| `packets` (packet set) | dataset, expid, sca, fid | `packets`, with children `forced` and `external` |
| `catalogs` (reference catalog) | dataset, name, version | `catalogs` |

A source is identified by its set and its source id, an object by its
founding job and its object id, a packet by its set and its source.
Objects and memberships carry no binding of their own: a membership is
official when its source set is, and an object when one of its
memberships is. A set is
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

`job_inputs` holds, for each job, rows of two kinds. An `input` row
names a set the job reads, by product, key and the job that wrote it.
An `expects` row names, for one output key, the open binding the job
expects to replace, or none.

The launcher chooses these. For the live run it chooses the current
official sets; a campaign chooses its own previous sets, and none for
its first epoch. A stage reads the sets its rows name and never "the
current official" one, which is what lets a recipe that is not live,
or a correction of one downstream product, read sets that are not
official.

The one exception is the object catalog
({ref}`ruling <decision-association-in-difference>`). The difference
job reads the objects of its own run in each field its sources fall in
and those fields' neighbours, as they stand when it runs
({ref}`ruling <decision-association-by-source-field>`), and the packet job reads the trigger's objects, their official
members and the forced-photometry window the same way. Each records
exactly what it read, one `input` row per founding job or set seen,
written by the publisher from the manifest's `reads`. The run scope
keeps a recipe from reading another recipe's objects; the recorded read
gives the same rows again. The same night run in another order founds
some objects from a different epoch, so their ids differ, and a
comparison across recipes goes through source memberships.

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
is no stored flag. `memberships_official` holds the memberships whose
source set is official, so a superseded source set's memberships leave
with it, and `objects_official` holds every object with at least one
official membership, its statistics summed over them.

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
   binding is the one the job's `expects` row named, and each expected
   product's table loaded at least one row (or the manifest's `empty_ok`
   names it: a difference's `sources`, a packet set with no triggers), it
   closes those and opens the job's; otherwise it rolls back to the
   savepoint and records the refusal on the job;
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
For `packet` the input is a source set and the binding to replace is
the previous packet set of that image. Two jobs that both expect to
replace binding A: the first publishes and binds; the second publishes
and stays an unbound candidate. A late job from a run that is no longer
live stays unbound for the same reason.

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
mid-job, so the difference job matches in memory, and its parity with
the SQL matcher on the same field is a test in CI.

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

**The object catalog is append-only per run and field, and association
runs in the difference job**
({ref}`ruling <decision-association-in-difference>`). Observations do
not arrive in order, and an alert is the best information at the time.
The per-field chain it replaced, one `associate` job per epoch, each
waiting for its predecessor's set, assumed arrival in order and paid a
queue wait and a loop pass for three seconds of work; F158's
fourteen-deep chains took hours while the fan-out stages took minutes.
Now the difference job holds the epoch's sources in memory, reads each
touched field's objects as they stand, matches, founds an object for
each unmatched source, and publishes `objects.parquet` (founded here)
and `memberships.parquet` (each membership with its source's offsets
from the object's founding position and its flux) beside its sources.
An object's statistics are the sums of its official memberships'
shares, through `objects_official`: sufficient sums are additive, so
the order of arrival does not matter. Object ids are position hashes of
the founding source and never change after publication.

**A source belongs to its own field, whichever image detected it**
({ref}`ruling <decision-association-by-source-field>`). Every accepted
source is matched against the objects of the tessellation field it
falls in and that field's neighbours, and founds in its own field when
nothing matches. Under `dev`'s second pass a source outside its image's
own field could only join an object already there, so a field no image
is centred on founded nothing: on the injected SCA 8 footprint that
rule alerted 0.40 of the injected sources while 0.96 were detected.
Reading the neighbours keeps one star whose detections scatter either
side of a boundary from splitting into two objects.

**Two epochs in flight at once are reconciled at publish.** Both can
see no object at a new source and both found one. The publisher,
serialised by transaction-scoped locks on every (run, field) that
gained an object or a membership and on each such field's neighbours,
taken in ascending field order so two jobs founding either side of a
boundary share a lock and never deadlock, matches the job's founded
objects against those founded since its recorded read in those fields,
and attaches the duplicate's memberships to the existing object,
rebased to its origin, instead of inserting a second. `dev`'s route,
tolerate duplicates and merge later, changes object ids after alerts
have carried them, and is not taken.

**A superseded source set's memberships leave with it.** `dev`'s prune
deleted members whose difference image was no longer best. Here
official-ness of a membership is its source set's, so a re-differenced
epoch's old memberships drop out of `memberships_official` and its new
ones come in. Nothing is deleted.

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
recorded input can describe. Here a packet job reads its window's
images and the official `forced` rows that exist when it runs,
records that read, measures only the (object, image) pairs those do not
already hold, and publishes its own `forced.parquet` with `dev`'s row
id. Two packet sets in flight at once may each measure a pair neither
could read; the later of them copies one of the two.

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
| `rapidpipe run create --who --why --revision [--settings FILE] [--overlay FILE] [--set TABLE.key=VALUE ...] --survey --dataset` | resolves the three layers, records a run with its body and layers, and prints its id |
| `rapidpipe official change --group FILE --who --why` | applies a change group from a JSON list of `close` and `open` items; refuses naming the binding |
| `rapidpipe official undo <group> --who --why` | applies a group's inverse under the same rule |
| `rapidpipe run show <id>`, `rapidpipe job show <id>` | print a run with its live binding and jobs, or a job with its inputs and bindings, as JSON |
| `rapidpipe job local --run --stage --scope JSON [--inputs JSON] [--expects JSON]` | records a job and runs it in this process, then publishes |
| `rapidpipe job run --job <id>` | runs an existing job's next attempt, then publishes; stops at once if the job is published |
| `rapidpipe job submit ... --job-definition <name>` | records a job and submits one Batch job whose command is `job run`; with `--job <id>`, submits an existing job's next attempt instead |
| `rapidpipe job wait --job N [N ...] [--timeout S]` | blocks until every named job is published or failed, reconciling with Batch each check; exits 0 when all published, 1 when one failed, 2 at the timeout |
| `rapidpipe publish --run <id> [--settings FILE]` | the recovery sweep: produces the run's official packet sets that their own jobs did not send and the gate does not hold, and stamps each (Publication to Kafka, below) |
| `rapidpipe loop --run --filters --scas --pointings [--passes] --job-definition [--job-queue]` | carries a selection one stage forward per pass until it drains ([loop](loop)) |

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
where the stage wrote in place. Once `put` returns, the job removes its
working directory; a stage or an upload that raises leaves it for a
person to read. Before this, every `s3://` job run on a host left its
directory behind, 89 of them and 22 GiB on the fleet host. A stage reads every input through
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
database. The id Batch returns is written on the job row; a
resubmission replaces it, so the row names its latest Batch job, and
the loop reads Batch by it ([loop](loop), the reconcile).

Each submission asks Batch for its stage's memory, from the run's
settings table `[batch.memory_mib]`, one key per stage; a stage with no
key gets the job definition's. The values are about twice each stage's
measured peak, and the difference stage keeps the definition's 24 GiB:

| Stage | Asked, MiB | Peak measured on the ramp, MiB |
|---|---|---|
| `intake` | 2,048 | 910 |
| `psf` | 2,048 | 333, at breadth |
| `reference` | 6,144 | 2,831 |
| `difference` | 24,576 | 16,125 |
| `packet` | 2,048 | 867 |

With one reservation for every stage, the ramp ran every job on
r6i.8xlarge, about ten to an instance. With these, the compute
environment chose m6a.2xlarge and r6i.2xlarge or 4xlarge and packed 31
jobs onto six instances; every peak stayed under its ask. The container runs one attempt and publishes it, exactly as
`job run` does on a host. Batch retries exit 75 and nothing else
({ref}`ruling <decision-batch-retry>`): the job definition allows three
attempts, the first run and two retries, and its rules retry on exit
75, the stage contract's temporary dependency failure, and on a
container that failed to start (Batch's reason `Task failed to start`,
sixteen of them at breadth), and end the job on any other exit code or
on a failure with no exit code, such as a reclaimed instance. Exits 64,
65 and 70 are faults a retry would only repeat. The loop adds one
rerun of its own: a container Batch ended without `job run` recording
it is resubmitted once, and its rerun's death fails the loop. A retry after a late commit is safe because `job run` stops on
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
job records always name the code that ran. The new run, made live for
the same dataset, continues from the dataset's official rows, so a fix
in the middle of a drain resumes where the old run stopped. A Batch
stage reads only files in the inputs bucket, the run's public source
root and the CRDS server, and writes only under the scratch bucket's
root.

### Spot, a probe

Spot is a probe, never production
({ref}`ruling <decision-spot-probe>`). A run whose `[batch.spot]` table
names a Spot queue (`queue`, `backlog`, `hedge_factor`; the table is
absent by default, so every job runs on demand) is run under four
rules:

1. a stage's submission goes to the Spot queue while more than
   `backlog` of that stage's jobs remain to submit in the pass, and
   otherwise to the prompt queue the loop's `--job-queue` names, so a
   stage's last wave runs on demand;
2. a Spot submission has one attempt: it overrides the job
   definition's retry strategy;
3. a Spot job that ends unpublished, for any reason, is the job's one
   rerun, on the prompt queue, so nothing is retried on Spot;
4. a Spot job still running past `hedge_factor` times its stage's
   median `container_seconds` is terminated and rerun on the prompt
   queue.

`jobs.attempts` records every submission (queue, times, instance type,
zone, Batch's reason), each loop pass reports `queues` and `attempts`,
and `job_metrics` gains `container_seconds`, `batch_submissions`,
`reclaims`, `hedges` and `lost_seconds`. Capturing EventBridge's
two-minute interruption warning needs a CloudWatch Logs resource policy
not yet granted, so a reclaim is seen today only as a job that ended
unpublished. The first data points are under Measurements, below; the
infrastructure repository's job-shape page holds the series.

## The thin chain

One narrow path through every stage, the smallest working version of
each, run first on one field's two epochs with the brightest sources per
image. Each simplification keeps the shape of the full stage.

| Stage | Reads (named in `job_inputs`) | Writes (declared outputs) | Left out until breadth |
|---|---|---|---|
| `intake` | one SOC L2 `_cal.asdf` file under the run's source root; the science PSF of its filter and SCA | the gzipped 16-HDU FITS converted as `dev` converts it; `l2files`, and `exposures` when the job expects that key, with limiting magnitude, overlapping fields and sky indices computed | nothing for want of a PSF: every filter's is derived by `psf` |
| `import` | stored products for one field: L2 files, difference images, PSFs, the reference and its mosaic catalog, the Gaia copy; the cap on sources per image | copies of the image files; `exposures`, `l2files`, `diffimages`, `psfs`, `refimages`, `refimcatalogs`, `catalogs` and `sources` (the brightest N per difference image by flux over its error), with limiting magnitude, overlapping fields and sky indices computed; the source system's ids kept; provenance marked unknown | other fields and epochs; recovering provenance |
| `psf` | one SOC L2 file's metadata and the CRDS ePSF reference it names | the science and the reference PSF, one stamp twice; two `psfs` rows | a PSF per position on the detector; a reference PSF of the coadd's own |
| `reference` | the field's `l2files` rows for one filter and SCA, before the run's reference bound when it has one | the awaicgen mosaic with its coverage and uncertainty maps and SExtractor catalog; `refimages`, `refimimages` (one row per coadded L2 row) and `refimcatalogs` | `dev`'s later reference changes (infobits, status, the 9100-pixel mosaic); the Photutils catalog |
| `difference` | one epoch's `l2files` row, a `refimages` row with its mosaic catalog, and the science `psfs` row; the run's objects in the fields its sources fall in and their neighbours, read at execution and recorded | the gzipped ZOGY difference image, its uncertainty, the mask, the uncapped catalog and the files `packet` reads beside it, SFFT and naive run only for their outcome bits; `diffimages` and the `sources` set, mapped exactly as the import maps `dev`'s; `objects` founded here and this epoch's `memberships` | sumrat, real/bogus and the extra SFFT catalog columns; `dev`'s loader prefilter; `rubrat` |
| `packet` | the epoch's source set, the science PSF, the Gaia product, the reference and its mosaic catalog; read at execution and recorded: the triggers' objects and official members, the window's difference and science images and the official `forced` rows | `packets/<expid>-<sca>-<fid>.avro` at schema 00.06, the `packets.parquet` index, `forced.parquet`, `external.parquet`; as its last act, the set on the Kafka topic | NED, NED-LVS and solar-system matches |
| reader, outside the pipeline | a packet set's Avro and its official index and forced rows | a validation report | nothing |

Every stage reads its inputs the same way whoever made them, so
`packet` reads a Batch-made epoch exactly as an imported one, and `difference` never cares whether its reference was imported
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

### psf

The [psf](psf) page states `psf`: its scope (one file of the filter and
SCA it serves), the ePSF reference fetched by the name the file
carries, the fixed reduction to a 61-pixel stamp, the two `psfs` rows
it declares, and the `EPSFREF` keyword the intake checks against each
file's own reference. An OpenUniverse file names no ePSF reference, so
for `[intake] reader = "openuniverse"` the stage draws the stamp with
galsim.roman, the simulation's own model ([datasets](datasets)). The loop submits one for each filter and SCA that
lacks its PSFs, so a dataset needs no PSF imported.

### reference and difference

The [reference](reference) page states `reference`: its scope (field,
filter and SCA), the `l2files` rows it coadds in `dev`'s order, the
three tables it declares with the `rfid` it draws, and its settings.
The [difference](difference) page states `difference`: its scope (one
epoch's key), its four inputs (the L2 row, a reference, and one PSF of
each kind), the ZOGY image and source set it declares with the `pid` it
draws, the files it publishes and why each is kept, and its settings.
A run has one differencer, so only the ZOGY image is published as a
row; the SFFT and naive files are not uploaded at all.

### Association

The [difference](difference) page states the association the
difference job runs: the read of the objects in each field its
sources fall in and those fields' neighbours, `dev`'s first crossmatch
pass in memory over every accepted source (every object within the
match radius matches, not only the nearest, so a source may join
several objects; an unmatched source founds an object in its own
field, whose id is the `radec_index` of its position), and the
reconcile at publish. `dev`'s second pass, where a neighbouring field's
sources join objects only, is not taken
({ref}`ruling <decision-association-by-source-field>`). The `associate` stage it replaced, and with
it `crossmatch`, `statistics`, `prune` and `maintain`, is retired.

The sums are of offsets from the founding position, not of raw
degrees: at RA 268 an object spreads by about 1e-5 degrees, and a
variance from raw-degree sums would be lost to cancellation. The mean
is `ra0 + sumra / n`, and the standard deviation in RA carries one
cosine, of the mean declination. A membership attached by the
reconcile is rebased to the surviving object's origin.

### packet

`packet` is a port of `dev`'s alerts package at schema 00.06, one job
per official source set, in any order. Every source the run's
`[associate]` table accepts that is a member of an object triggers a
packet, and under association by the source's field every accepted
source is a member, so every accepted detection is alertable wherever
it falls on its image; a source in several objects takes the lowest object id, as
`dev` does, and `dev`'s cap per chip is not carried. Each packet
carries the best information at the time it is made
({ref}`ruling <decision-association-in-difference>`), what the job
read as it ran and recorded:

- `diaSource` from the source row;
- `prvDiaSources`, the object's official members at the read, with
  `mjdobs` before the trigger and within the history window, so a late
  epoch appears in packets issued after it arrives and never in those
  already sent;
- `diaObject` from the object's position and summed memberships,
  `nDiaSources` counting members up to and including the trigger;
- `prvDiaForcedSources`, `dev`'s PSF photometry at the object's founding
  position on every window image that holds it at the read, whichever
  field the image is centred on, difference
  and science image merged into one row per object and image, rows an
  official set already holds copied rather than measured;
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

(foundation-quality-gate)=
### The quality gate

The gate decides whether an official packet set goes to the topic.
`rapidpipe.foundation.gate.decide` is one query over `job_metrics`: it
holds the set when its difference job's `n_sources_snr_gt20` is above
`snr_gt20_factor` times the run's median, or `|core_fraction|` is above
`core_fraction_max_abs`, or `|ring_fraction|` above
`ring_fraction_max_abs`, once the run has `min_epochs` published
differences; otherwise it sends. The run's `[gate]` table holds 3.0,
0.025, 0.015 and 5, the healthy ranges the fixes measured across seven
filters: the worst epoch's count was 2.6 times its run's median, the
worst core 0.022. A held set is neither sent nor stamped, its reason
names the metric and the value, and each loop pass reports the run's
held sets as `held_sets`. Nothing is deleted, and there is no verb
that releases a held set. Every official set of the
fixes' seven runs, 55 of them, was sent at these values; the footprint
runs held one in 162 (ring fraction +0.016), and the 18 SCAs of one
pointing held seven, all on `core_fraction` +0.026 to +0.028, SCAs 16
and 17 entire.

### Publication to Kafka

The packet job sends its own set as its last act, once its publisher
has loaded and bound it. `rapidpipe.foundation.publish_kafka.deliver`
is the one send boundary: the gate answers first, and a held set goes
nowhere. Otherwise one message per packet goes to the topic, keyed by
the run's dataset, so a dataset's packets share a partition and keep
their order, with the set and the source id in the `rapid-set` and
`rapid-sid` headers. The value is a one-record Avro container, the
set's container header with the packet's own block, so each message
decodes on its own and carries its schema. There is no schema
registry. The producer waits for every acknowledgement from all in-sync
replicas, flushes once, and stamps the set's job with the time, the
partition and the first and last offsets
(`jobs.kafka_published_at`, `kafka_partition`, `kafka_first_offset`,
`kafka_last_offset`). The producer is idempotent, so the broker drops
a retried batch's duplicate within one send; a set sent again (a rerun,
the sweep) is a replay consumers tolerate, and nothing here is
exactly-once.

`rapidpipe publish --run <id>`, and the loop's publish in each pass,
is the recovery sweep and the verb that publishes again: it takes every
official, unstamped set whose job ended more than 300 s ago, through
the same boundary. A set inside that window is its container's to send,
is reported as `sets_waiting`, and holds the loop's drain. One call
opens one database connection and one producer and takes its sets one
at a time, each flushed within 120 s; a set with a failed
acknowledgement stays unstamped and the verb exits 70 naming it, and a
flush that does not finish in time leaves its set and every later one
unstamped and stops the call. A crash between the last acknowledgement
and the stamp offers the set again, so a consumer may see a packet
twice; replay is allowed. A job killed between its database publish and
its send, proven on a live run, is sent by the next pass. A set that
loses its binding before it is stamped is not offered.

The cluster's bootstrap servers, the topic and the largest request the
producer may send are named in the settings file's `[kafka]` table as
the deployment's parameter names, never their values. On Batch their
values, and the database's, are in the container's environment, so a
job reads no parameter store; the connection authenticates with the
caller's own cloud credentials. The transport is not part of a run's
recipe.

`scripts/consume_packets.py --run <id>` is the consumer check. It reads
only the offset ranges the run's stamped sets recorded, overlapping
ranges merged, with no consumer group; keeps a set's messages by key
and headers; requires every stamped packet to be seen; and decodes and
byte-compares against the outbox one set per field, the field's latest.
Zero kept is a failure, so a run with no stamped set fails. The
client's own record checksum is switched off, since it is pure Python
and held the read to about 50 messages a second. A run's check takes
about 4 s at one pointing and 388 s over 33,650 packets, whatever the
topic's size. It holds only within the topic's retention, seven days:
a run whose messages have aged out fails it as never read.

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
outputs root is the environment's. `[psf]` names the CRDS server and
the stamp's size ([psf](psf)). `[batch.memory_mib]` holds each
stage's memory ask (A job on Batch, above), `[batch.spot]` the Spot
probe's three values when a run names them, and `[gate]` the quality
gate's bounds. `[associate]` holds the association's values, which the
difference job reads. `[reference.selection]
before_mjd`, the reference bound, is documented in the shipped file and
absent there: a run sets it in its overlay, and a run without it
coadds every epoch of a field ([loop](loop), the reference bound).

## The queries

The official views answer eight queries without reading files:

- the current image and source set for a dataset, exposure, SCA and
  filter;
- a field's official objects and their members;
- an object's detection and forced history as a packet read it;
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
statement each. A query as a job read it reads base tables through
that job's recorded inputs; every other query reads the official views.

## The procedure proof

`tests/db/proof/test_steps.py` asserts the procedure proof's
observations on synthetic rows in CI, one test per step, read back
through the official views: a cutover as one group; its undo restoring
the first recipe; a publication interrupted before and after its
commit; two change groups on one binding at once; publication racing a
cutover; and an undo refused because a later group moved a binding.
Steps 1, 2 and 13 are the association's: two epochs of
one field differenced at once both publish and bind their own sources,
the second's founded objects attach to the first's, and a superseded
source set's memberships drop from the view. The steps that need the
real stages (3, 5, 7 and 9) are proven on SMDC's live runs instead. The real-data
script of the chain, `thin_proof.py`, is retired with `associate`.

## On SMDC

The SMDC database `rapid` holds the foundation in its `public` schema,
and the pipeline repository's `docs/foundation-smdc-step.md` is the
procedure, one command and then its check per step. It has eleven parts.

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
  check held, since it checks integrity and not order. The ruling that
  followed keeps one reference per dataset, field and filter and puts a
  field's chain in the loop's admission order, which is time order when
  the loop admits every SCA of an exposure together
  ({ref}`ruling <decision-chain-admission-order>`).

**Housekeeping.** The eighth part made each epoch cheaper before the
ramp grows, and gave the reference a bound. Every proof ran on Batch
under a throwaway dataset with its own live run, on the same pixels as
the wide-area run's first pointing, because the loop admits a file only
when no intake of its dataset has published it. The wide-area run and
the GBTDS run stayed live and untouched, and nothing was deleted.

- *Bytes.* The difference stage publishes the seven files its readers
  need, gzipped ([difference](difference)); a job removes its working
  directory after the upload; the intake writes an `exposures` row only
  when its job expects that key, so no unbound duplicates are left.
- *Batch.* Every job row carries its Batch job id; the loop's reconcile
  marked a container killed under it `failed` with Batch's reason in
  the next pass, and a rerun with `job submit --job` published; each
  stage asks for its own memory.
- *The pass.* The loop lists only the selection's observations;
  `publish` uses one connection and one flush per pass;
  `validate_run.py` works eight jobs or sets at a time, and the
  consumer check holds one set at a time.
- *The reference bound.* With the bound between the third and fourth
  passes, one pointing's reference coadded exactly the three epochs
  before it and the three after it were differenced, associated and
  published, chain depth three; `validate_run.py`, the reader and the
  consumer check were clean. A second dataset with the bound before
  every epoch took all six intakes in, reported the field held on every
  pass after, submitted no reference and no difference, and drained
  with exit 0.
- *The `catalogs` key.* The column, its unique constraint and the view
  were changed on SMDC in one transaction, and the open bindings and
  the recorded inputs naming a catalog gained their dataset; the bound
  products were unchanged.

**Breadth.** The ninth part ran the simulation's six other filters,
F087, F106, F129, F158, F184 and F213, without injection
({ref}`ruling <decision-breadth-before-injection>`), first on SCA 8 of
all 54 pointings and then on the 18 SCAs of the first pointing.

- *The PSF from each file's reference.* The [psf](psf) stage was proven
  on F146 first, under a dataset of its own with no PSF imported: the
  loop's first pass submitted one psf job and no intake, the next
  admitted the pointing's intakes, and the chain drained with every
  check clean. Every filter's PSFs were then derived by the loop, 109
  pairs over seven datasets, and every intake's check of its file's own
  reference held.
- *One dataset per filter.* Each filter ran as a dataset of its own
  with its own live run and its own reference bound, the midpoint of
  that filter's third and fourth passes, so every field has exactly
  three reference frames in every filter. A filter's chains, fixes and
  resumes are its own: three fixes resumed five filters while the
  sixth, already drained, stayed as it was. The shape avoids cross-band
  association by construction. A source seen in two filters is two
  objects in two datasets, and no packet carries forced photometry from
  another band; whether an object should span bands is open (Not
  decided here, below).
- *SCA 8 over the footprint.* The six loops drained 3,456 epochs: 324
  references, 2,484 differences, associates and packet sets, and
  503,964 packets on the topic. Three failures seen at this width were
  fixed in code and each resumed by a new live run of the same
  datasets: the parameter store throttled 3,400 jobs starting in one
  minute; one flush per publishing pass hung the producer (Publication
  to Kafka, above); and the loop's association rule read only its own
  run's jobs, so a resumed run associated every epoch a second time.
  That run was taken off live, the state before it restored in one
  change group with nothing deleted, and the rule now follows the
  field's official chain ([loop](loop)). A validation false failure on a
  source catalogued twice was a tolerance below the one-pass variance's
  rounding floor, and was corrected. Sixteen jobs that Batch failed to
  start were rerun by hand.
- *The 18 SCAs of one pointing.* The same six runs took 1,088 more
  epochs, with 102 psf jobs in the first pass, no code change, and one
  transient failure: the CRDS server answered 72 of 102 fetches at once
  with gateway timeouts, and the 72 published when rerun in waves.
- *The checks.* Every run of the six filters is clean by the check
  script, after the consumer check stopped reading the topic from its
  beginning (Validation, below).

**The fixes.** The tenth part removed the null test's two measured
artefact sources on the wide-area simulation's first pointing in all
seven filters (Measurements, The fixes, below).

**The second iteration.** The eleventh part, one unattended night,
changed the chain's shape and took it to two more simulations. Every
proof ran under a dataset of its own with its own live run, and nothing
was deleted.

- *Datasets.* The GBTDS simulation went through intake with its WCS
  re-derived, and one pointing through the chain under its own overlay;
  the OpenUniverse TDS set was read and one image taken in by a second
  intake reader, and on 2026-10-24 one filter and SCA of it ran through
  the chain. Their quirks and dispositions are on the
  [datasets](datasets) page.
- *The bright end flagged.* The bright-star footprint flag and the
  metrics the re-count asked for went into the difference job
  ([difference](difference)); a stamp twice the size changed nothing
  that matters.
- *The loop's operations.* The HLWAS WCS translation at intake with a
  Gaia-offset metric on every file, `--passes`, `job wait`, one
  automatic rerun and a submission cap per pass, the check scoped to a
  loop's SCAs, the quality gate, the ePSF from a copy and no parameter
  store read in a job ([loop](loop), The quality gate, above).
- *The producer.* The packet job sends its own set, offsets on the
  stamp; a job killed between its publish and its send was sent by the
  next pass (Publication to Kafka, above).
- *The guards.* A schema test that every bound product carries the
  dataset in its key and its view, and an import test that no import
  supplies an identity column but the three source-system ids kept.
- *Association.* Moved into the difference job and reconciled at
  publish; the chain's rows kept as `objects_chain` and
  `memberships_chain`. Two epochs of one field in flight at once, a
  replayed reconcile equal to the sequential result, a late epoch and a
  superseded set were each proven on run 69.
- *Spot.* The four rules proven on one pointing, then a twin of the
  injected footprint on Spot beside its on-demand run (Measurements,
  below).
- *Injection.* 200 constant sources per image, AB 21 to 27, injected
  into SCA 8's 162 epochs after the reference bound and the 18 SCAs of
  the first pointing, as datasets of their own
  ({ref}`ruling <decision-injection-outside>`); completeness and purity
  per magnitude are under Measurements, below. The footprint earned two
  fixes: the reference ePSF's centring where the secant step stalls,
  and the forced check under packet sets in flight at once.

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
3. **The catalog.** Every official membership is within the match
   radius of its object; every accepted source, wherever on its image it
   falls, is a member of an object in its own field or a neighbour, and
   every membership's object lies in its source's field or a neighbour;
   no two founders share one object, across field boundaries too; every
   official object's sums equal its official members'. (Until
   2026-10-24, the chain: `members_official` equal to the union of the
   predecessor chain's matches, less exclusions.)
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
8. **A replacement conserves membership**: the official memberships
   lose every membership of the old source set and gain the
   replacement's, row for row, and only the touched objects change.
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
check on every packet each time. The script now reads every job's
Parquet and decodes every packet set eight at a time, each worker on
its own connection, with the same assertions: on the wide-area run it
took 666 s against 1,512 s.

`scripts/check_run.sh --run <id>` runs a run's three checks in turn,
`validate_run.py`, the reader over the run's bound packet sets eight at
a time, and the consumer check, streams their output, and prints one
line, `Check run <id>: CLEAN|FAIL validate <passed>/<checks> <s> reader
<clean>/<sets> <s> consumer <seen>/<expected> <s>`, exiting non-zero
when any of the three fails. Every run of the breadth part was checked
with it, and every one was clean, as was every run of the second
iteration: the injected footprint's on-demand run validated in 475 s
and read 33,650 packets back in 388 s.

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
  artefact detections before the cap of 500, median 954, with 53 to 119
  above S/N 20, none of them variability. They sit at and around stars,
  the residual a PSF mismatch leaves, and on unmasked pixel defects.
  SCAs 4 and 5 leave three to four times the artefact residuals of the
  other SCAs. These counts are artefact counts: an image study found
  them to be the PSF mismatch and unmasked defects, and The fixes,
  below, measures them removed.

### Housekeeping

Measured 2026-10-23 on SMDC, each change proven on Batch over the
wide-area data's first pointing, against the wide-area run's figures for
the same pixels.

| | Before | After |
|---|---|---|
| A difference job's published bytes | 2,547 MB in 72 objects | 247 MB in 10 |
| The run's prefix per epoch | 2.83 GB | 0.53 to 0.57 GB |
| `difference` in the container, median | 227.0 s | 227.4 s, gzip 7 to 9 s of it |
| `packet` in the container, median | 26.7 s | 45.0 s on gzipped reads in the first proof, 27.5 to 35.9 s in the later two |
| Working directories left on the fleet host | 89, 22.2 GiB | none |
| Unbound duplicate `exposures` rows | 102 after the 18-SCA ramp | none, one row per exposure |
| Memory asked per job | 24 GiB, every stage | 1 to 24 GiB by stage |
| Instances | r6i.8xlarge, about ten jobs each | 2xlarge and 4xlarge sizes, 31 jobs on 6 |
| A container that ends unrecorded | stays `running` | `failed` with Batch's reason in the next pass, 0.1 s |
| An idle loop pass | 29.6 to 40.6 s | 3.8 to 5.8 s |
| Connections per publishing pass | one, plus three per set | two |
| `validate_run.py` on the wide-area run | 1,512 s, 579 MiB | 666 s, 1,086 MiB |
| The consumer check on the wide-area run | 2,397 s, 24.8 GiB | 2,740 s, 434 MiB |
| `reference` in the container | 76.4 s, 6 frames | 46.0 s, 3 frames |

- **The disjoint reference.** On one pointing's SCA 8, the three epochs
  of the fourth to sixth passes left 113, 114 and 128 artefact
  residuals above S/N 20, PSF mismatch and pixel defects rather than
  detections, against a three-frame reference made from the first three
  passes, against 72, 75 and 100 under the wide-area run's six-frame
  reference, which held each epoch; the same PSF and pixels, the
  reference the only change. The three epochs gave 551 packets
  against 447. The artefact fraction above S/N 20 rose from 0.144 to
  0.226. Every count here is of artefacts, not detections (The fixes,
  below).
  Whether depth or disjointness does it is not separated (Not decided
  here, below).
- **Packing has a cost in seconds.** An intake took 39 s with six
  sharing an 8-vCPU instance, against 21 s alone.
- **The read side of gzip.** Forced photometry opens three gzipped
  files per window image, about 2.1 s of decompression each, so a long
  chain pays it on every epoch.
- **The consumer check's time is the topic's.** It reads every
  partition from the earliest offset, so its time grows with the
  topic, whatever the run's size.

### Breadth

Measured 2026-10-23 on SMDC over the six other filters of the wide-area
simulation, one dataset each, SCA 8 of the 54 pointings and then the 18
SCAs of the first pointing, every PSF derived by the `psf` stage.

The residual counts below are artefact counts, not detections. The
simulation has no time-variable sources, and an image study of one F146
epoch found about three quarters of its packets on stars, where the
science PSF and the resampled reference's differ (the reference's stars
are about 15% wider, and the stage hands ZOGY one PSF for both), and
most of the brightest on unmasked pixel defects; noise accounted for
essentially none of them, and the pattern repeats from epoch to epoch.
The table gives the median per differenced epoch of these artefact
residuals above S/N 20 and their fraction of the 500 kept sources, for
the 294.1 s exposures, with the 107.5 s exposures of the last two passes
as "short":

| Filter | SCA 8, 54 pointings | 18 SCAs, first pointing | SCA 4 / SCA 5 | Packets | Run prefixes |
|---|---|---|---|---|---|
| F146 | 79 (0.158), one pointing's three epochs | 79 (0.158), the wide-area run, a reference holding the epoch and `dev`'s PSF | 352 / 256 | | |
| F087 | 110 (0.220) | 103 (0.207) | 401 / 324 | 27,644 | 154 GB |
| F106 | 97 (0.194); short 44 (0.088) | 97 (0.195); short 49 (0.098) | 393 / 229 | 180,389 | 534 GB |
| F129 | 92 (0.184); short 44 (0.088) | 118 (0.235); short 54 (0.108) | 500 / 180 | 183,535 | 535 GB |
| F158 | 148 (0.296); short 78 (0.156) | 161 (0.322); short 86 (0.172) | 500 / 270 | 203,892 | 571 GB |
| F184 | 333 (0.665) | 214 (0.428) | 500 / 500 | 31,913 | 155 GB |
| F213 | 33 (0.101), 333 kept | 44 (0.127), 394 kept | 66 / 166 | 14,631 | 148 GB |

- **What the table shows**, descriptively, since filter, depth and PSF
  change together across its rows: F087, F106 and F129 leave artefact
  fractions near F146's; F158 leaves more and F184 three to four times
  as many; F213 is the shallowest band and does not reach the cap. The
  short exposures halve the artefact fraction in each band that has
  them and carry about a quarter fewer packets per epoch. SCA 4 holds
  the most artefact residuals of the 18 in five of the six filters, and
  every kept source of SCA 4 is above S/N 20 in F129, F158 and F184.
  SCA 9, differenced against SCA 8's reference because the two share a
  field, leaves more artefact residuals than SCA 8 in five of the six,
  where in F146 the two were level.
- **In all**: 4,544 epochs ingested, 3,266 differenced, 643,004
  packets, 2.1 TB of run prefixes (0.45 to 0.46 GB per epoch), and a
  database of 2.74 GB.
- **Per stage on SCA 8**, medians across the six filters: intake 61 to
  79 s in the container after a 244 to 305 s queue wait, the six
  filters' 3,456 intakes submitted at once; reference 99 to 125 s on
  three frames; difference 181 to 289 s, longer with more containers
  sharing an instance; associate 4 to 9 s; packet 24 to 31 s at chain
  depth 2 and 128 to 141 s at depths 13 and 14, its memory flat at under
  900 MiB. Peak memory stayed within the F146 figures in every stage. The
  compute environment chose 2xlarge to 8xlarge instances of the m6a,
  r6i and r7i families.
- **Forced rows grow with the chain**: about 300 per epoch at depth 2
  and 1,400 at depth 13, 3.2 million over SCA 8.
- **Kafka**: about 30 packets a second per loop, one set at a time,
  with up to six loops publishing together. The topic keeps seven days,
  unbounded by size.
- **The checks.** The consumer check had read the topic from its
  beginning at about 40 messages a second, which made one run's check
  four hours and growing; the cause was the client's pure-Python record
  checksum. With the checksum off and the read starting at the run's
  first packet, a run's consumer check took 4 to 109 minutes, by how
  much of the topic followed its first packet. `validate_run.py` grows
  with the chain, 1,850 to 2,710 s at depths 13 and 14.

**Not measured, for want of data on the host that ran it**: the matcher
and the difference stage at the plan's density; a thirty-day window of real
cadence; completeness against the injected sources; and the rubrat,
NED and NED-LVS matches, whose model and catalog copies are in a bucket
this account cannot read. sumrat needs no new data, but no stage
computes it yet.

### The fixes

Measured 2026-10-24 on SMDC (brief `fixes-2026-10-23`), on the wide-area
simulation's first pointing, SCA 8, in all seven filters, each filter a
dataset of its own with a new live run: the L2 data-quality flags masked
at intake (commissioning's rule without SATURATED), the reference PSF
measured in the difference job from the resampled reference's stars, the
SWarp kernel left at `dev`'s BILINEAR by a paired comparison, and every
job's quality numbers in its manifest, exposed by the `job_metrics` view
and rendered per run by `scripts/inspect_run.py` before the checks. The
before is the same pixels' official products from the breadth runs and,
for F146, the image study's run, read from the database by lineage.

| Filter | Epochs | Above S/N 20 per epoch, before → after | Packets per epoch | Packets above S/N 20 | Core / ring of star flux after |
|---|---|---|---|---|---|
| F087 | 2 | 112 → 18 | 192 → 64 | 46 → 4 | -0.003 / +0.007 |
| F106 | 13 | 100 → 22 | 200 → 56 | 41 → 4 | +0.004 / +0.005 |
| F129 | 13 | 101 → 42 | 213 → 108 | 46 → 12 | +0.007 / +0.002 |
| F146 | 3 | 79 → 19 | 213 → 71 | 28 → 3 | +0.006 / -0.002, from +0.030 / -0.027 |
| F158 | 14 | 156 → 18 | 216 → 57 | 75 → 6 | +0.011 / -0.005 |
| F184 | 2 | 373 → 19 | 255 → 42 | 188 → 3 | +0.001 / +0.014 |
| F213 | 2 | 48 → 20 | 110 → 46 | 16 → 3 | +0.034 / +0.023 |

- **What is gone**: the defects (most of F184's bright end) and the
  core-and-ring residual the PSF mismatch left at every star. The share
  of sources on a reference source fell from 69% to 43% in F146.
- **What remains** above S/N 20 is bright stars, none of it a defect:
  on F146's SCA 8, 11 to 21 of 15 to 23 per epoch sit on a reference
  source of aperture S/N above 100, with the PSF's diffraction-spike
  pattern in the residual; F213 leaves a positive core and ring, a
  flux-scale residual. Turning off `dev`'s science extreme-pixel repair
  changed nothing, and the cause is open. SCAs 4 and 5 leave two to three
  times SCA 8's.
- **Two defects found by the re-count, fixed**: the reference PSF's star
  peak floor was F146's count rate and failed every F184 and F213
  difference (6 to 9 stars of 10 needed); it is now in units of the
  noise. The reference job's star width read the galaxies, since
  SExtractor's star classifier does not separate them on these mosaics;
  it now takes the narrowest population of widths (F087 0.91 to F213
  1.34 pixels).
- **Every run's checks** were clean: validation, the reader and the
  consumer, over 4,336 packets.

### The second iteration

Measured 2026-10-24 on SMDC (brief `night-2026-10-24`), on the
wide-area simulation's F146 data unless named; the runbook's part 11
holds the jobs, commands and raw tables.

**The null test, with the bright end flagged.** On pass 4 of the first
pointing, after the HLWAS WCS translation:

| | SCA 8 | SCA 5 | SCA 4 |
|---|---|---|---|
| Candidates / above S/N 20 | 802 / 29 | 884 / 69 | 640 / 36 |
| In a bright-star footprint, share of those above S/N 20 | 0.79 | 0.74 | 0.75 |
| Packets / above S/N 20 / flagged | 79 / 8 / 49 | 124 / 16 / 75 | 98 / 11 / 65 |
| Science stars' width over the ePSF's | 1.024 | 1.015 | 1.033 |
| Core / ring of star flux | +0.0001 / +0.0009 | +0.0114 / −0.0015 | +0.0058 / +0.0024 |

- **SCAs 4 and 5's excess is not a science-PSF width mismatch**: the
  science stars are 1.5 to 3.3% wider than the ePSF on all three, and
  SCA 5, with the most bright-star residuals, has the smallest
  mismatch.
- **The stamp size is not the residual's cause**: a 121-pixel reference
  PSF stamp against the 61-pixel one moved the ePSF flux held from
  0.971 to 0.979 and changed the counts by one.
- **F213's flux scale.** The zero-point table agrees with each filter's
  own file metadata to within 0.035 mag and is not corrected; the stored
  reference scale factor is 0.958 in F184 and 0.939 in F213 against
  0.99 to 1.01 in the others, which fits F213's positive core and ring.

**Association in the difference job.** On one pointing's SCA 8, the
last difference to the last packet took 31 s, against 5.2 min through
the chain of run 46; the read of a field's 200 objects took 0.9 ms
against 422 ms through the chain's view. Two epochs differenced at once
founded no duplicate, and a replayed reconcile from an empty read
attached its 105 memberships exactly as the sequential run had.

**Completeness and purity, injected.** 200 constant sources per image,
AB 21 to 27 uniform, in SCA 8's 162 epochs over the footprint after
the reference bound; matched within 0.3″ through the corrected WCS.
Every 0.5 mag bin is in the runbook; every other bin here:

| AB | Injected | Detected | Alerted | Alerted, of those detected in their image's own field | Purity, packets at this measured magnitude |
|---|---|---|---|---|---|
| 21.0 | 2,595 | 0.958 | 0.398 | 0.951 | 0.93 |
| 22.0 | 2,808 | 0.975 | 0.431 | 0.969 | 0.91 |
| 23.0 | 2,670 | 0.966 | 0.381 | 0.974 | 0.75 |
| 24.0 | 2,910 | 0.968 | 0.415 | 0.981 | 0.59 |
| 25.0 | 2,853 | 0.944 | 0.395 | 0.958 | 0.35 |
| 26.0 | 2,721 | 0.754 | 0.298 | 0.960 | 0.20 |
| 26.5 | 2,640 | 0.233 | 0.109 | 0.976 | 0.13 |

- **Detection is 0.94 to 0.98 to AB 25**, 0.75 at 26 and 0.23 at 26.5,
  with positions within 0.011″ and fluxes at 0.91 to 0.95 of the
  injected to that depth.
- **The alerted fraction, 0.40, is the association's field rule**, not
  the difference stage: a source outside its image's own field only
  joins an object already within the radius, and where none exists it
  never triggers. Of the unflagged detections inside their image's own
  field, 12,069 of 12,070 were alerted.
- **The purity floor.** Purity, packets on injected sources over all
  packets at that magnitude, is 0.91 to 0.93 at AB 21 to 22 and falls to
  0.20 at 26, where the artefacts and real faint residuals dominate.
  Per epoch the packets on anything but an injected source are a median
  95 (33 to 182): 52 on bright-footprint-flagged sources and 38 on
  others. The bright end of the flagged share is the null test's floor,
  about 20 per epoch above S/N 20 on SCA 8.
- **History.** Of 11,576 earlier alerted epochs the alerted injected
  sources' later packets should carry, 11,048 are present, 524 arrived
  after the packet's read, as the alert contract allows, and 4 are
  missing, where two epochs in flight founded one source's objects
  apart.
- **The 18 SCAs of the first pointing**: detection below AB 25 from
  0.67 (SCA 9) and 0.73 (SCA 7) to 0.99 (SCAs 8 and 17), with SCAs 4 and 5
  at 0.93 and 0.89; per-epoch false positives a median 153 against SCA
  8's 95; the gate held seven of the 51 sets.

**Spot, the first data points**
({ref}`ruling <decision-spot-probe>`). On one pointing (14 jobs, 7 on
Spot) there was no reclaim and no hedge, and Spot cost wall time: its
differences started 168 to 292 s after submission against 11 s on a
warm on-demand host. At footprint scale, the injected SCA 8 footprint
ran twice on the same bytes and truth, once on demand with 512 vCPU
held warm and once as a Spot twin:

| | On demand, warm | Spot twin |
|---|---|---|
| First submission to last job end | 28.1 min | 30.2 min |
| Batch submissions | 709 on demand | 589 Spot, 129 on demand |
| Reclaims / hedges | 0 / 0 | 0 / 0 |
| Median start wait, intake / difference | 65 s / 15 s | 160 s / 223 s |
| Job-hours | 17.4 | 13.4 Spot + 3.8 on demand |
| Priced by lane, Spot at Spot rates | $2.03 | $1.30 |
| Completeness | | the same to three detections |

The prices are each job's memory share of its host at published rates,
unverified against the bill; the warm capacity, up to about 59
instance-hours for the hour it was held, is not in them. Both runs lost
the same 13 minutes to the reference ePSF's centring failure, fixed in
the middle of the drain, so the spans compare like for like.

**GBTDS's one pointing**, with the science PSF on both images because
the bulge's reference stars cannot be measured, leaves 346 to 418
sources above S/N 20 per epoch, each bright one a core-and-ring
residual at a star, against about 19 on HLWAS; its difference job takes
820 s, 3.5 times HLWAS's ([datasets](datasets)).

### Association by the source's field

The injected SCA 8 footprint ran again under the field rule
({ref}`ruling <decision-association-by-source-field>`): the same 162
epochs, bytes and truth as the second iteration's on-demand run, on a
cold queue.

| SCA 8 footprint, 162 epochs | `dev`'s second pass | The source's field |
|---|---|---|
| Detected injected | 28,625 | 28,623 |
| Alerted, of those detected | 0.42 | 0.97 |
| Alerted at AB 21 / 23 / 25 / 26 | 0.40 / 0.38 / 0.40 / 0.30 | 0.92 / 0.94 / 0.92 / 0.72 |
| Purity at AB 21 / 23 / 25 / 26 | 0.93 / 0.75 / 0.35 / 0.20 | 0.93 / 0.75 / 0.34 / 0.20 |
| False positives per epoch, median | 95 | 224 |
| Objects | 20,575 in 70 fields | 37,800 in 290 fields, 21,573 in fields no image is centred on |
| First submission to last job end | 28.1 min, warm | 30.9 min, cold |
| Packet job, median | 37 s, 170 packets a set | 60 s, 393 packets a set |

- **Alerted approaches detected**: 27,750 of the 28,623 detected
  injected sources were alerted, at the same purity per magnitude. The
  alert volume is 2.3 times the second pass's, and the false positives
  per epoch rise with it, 130 of the 224 on bright-footprint-flagged
  sources.
- **The forced window holds**: no covering image published before a
  set started is missing from any of the 162 windows, and 249 of the
  571 window images read are centred on another field than the
  trigger's.
- **Splits at the edge**: 13 packets carry a source split over two
  objects, founders in flight whose positions fall just outside each
  other's radius, 0.05% of the expected history.

## Not decided here

- The false positives per epoch, a median 224 on the injected
  footprint once every accepted detection is alertable, 130 of them on
  bright-footprint-flagged sources. Purity per magnitude is unchanged
  by the field rule; the volume is the next science question.
- Whether an object's statistics are materialised per field. The view
  read a field's 200 objects in 0.9 ms; at GBTDS depth it is unmeasured.
- A source that a job in flight founded nearby is not added to an
  object the other job read, as a sequential run would have. On the
  footprint, 4 of 11,576 expected history entries were missing where
  two epochs in flight founded one source's objects apart, and under
  the field rule 13 packets carried a source split that way.
- Forced photometry's cost at scale. It is about 3.6 s per window
  image, dominated by opening the images. A set's `forced` rows are its
  packets times the window images on the trigger's SCA, so a field's
  total grows as the square of its epochs inside one window; F158 at
  14 epochs held about 14 rows per packet and its packet job about
  300 s.
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
- Whether the disjoint reference's extra bright residuals come from
  its depth, three frames against six, or from its disjointness. A
  three-frame reference that holds the epoch would separate them; the
  simulation has six F146 epochs per pointing, too few for a six-frame
  reference disjoint from three. The PSF mismatch at stars is under
  both.
- Where the reference bound goes in general. On the HLWAS simulation
  each filter's bound is the midpoint of its own third and fourth
  passes, which leaves three reference epochs before it in every filter;
  a survey without passes needs another rule.
- Exactly-once delivery. The producer is idempotent since the job
  role's idempotent-write grant (2026-10-24), which covers one send; a
  set sent twice reaches the topic twice.
- The Spot interruption warning's capture, which waits on a logs
  resource policy, and what a reclaim costs, since none has been seen.
- Cross-band association. Each filter is a dataset of its own, so a
  source seen in two filters is two objects. Whether an object is per
  band or across bands is open, and with it forced photometry in the
  other bands at a source's position.
- The cause of the bright-star residual (about 20 per epoch above S/N
  20 on SCA 8, two to three times that on SCAs 4 and 5), now flagged
  and not fixed; neither the science PSF's width nor the stamp size is
  it. F213's flux-scale residual fits its references' scale factor of
  0.94.
- The 107.5 s exposures of the last two passes are differenced against
  a 294.1 s reference. Whether a short exposure gets a reference of its
  own exposure time, or is differenced at all, is open.
- Completeness on real hosts and light curves past AB 25. The
  OpenUniverse TDS chain runs end to end and its transients are
  detected at 1.0 to AB 24 and 0.5 at 25, but every difference fills
  `dev`'s cap of 500 sources, so the cap ends the count
  ([datasets](datasets)).
- GBTDS's core-and-ring residual with the science PSF on both images,
  346 to 418 per epoch above S/N 20.
- Whether SFFT and the naive subtraction keep running now that only
  their outcome bits remain ([difference](difference)).
- Packets after a replacement stay as published with the old
  detections in their history; whether a loop should ever rebuild
  them is open. A campaign reruns from the replaced epoch.
- Packet counts per chip in a dense field: GBTDS's 9,000 candidates
  per epoch kept 500 sources and 169 to 173 packets.
- The meaning of `nDiaSources` in the 00.06 schema's own documentation,
  which is `dev`'s; changing it is a schema change for the team.
- `packet.edge_pixels` is in the thin run's settings and read by no
  stage, since no two-pixel edge rule exists in `dev`'s alerts code.
