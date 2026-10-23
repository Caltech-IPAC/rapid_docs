# The loop

**Status: DRAFT**

`rapidpipe loop` carries a selection of a live run's data from the
source root to the Kafka topic. Each pass admits what is new, moves
every ready epoch one stage forward, and ends by publishing what became
official. It is one verb run under a timeout from a host, not a service
and not a scheduler of its own. The [foundation](foundation) page
states the records it reads and writes, and the
[intake](intake) page the stage it starts with.

This page replaces the processing-date loop of the retired run model,
with its operations-registry trigger, loop spec, per-date runs and
promotion. Where an older page still points at that loop's discovery,
classification or commands, this page governs.

## In plain terms

The loop looks at the run's source root and at the database, decides
what can run now, submits it to Batch without waiting, and goes to
sleep. Two minutes later it looks again. A file nobody has taken in
gets an intake job; a field with all its images taken in gets a
reference; an image with a reference gets a difference; and each
field's association and packets advance one epoch at a time, oldest
first. At the end of every pass, whatever packet sets became official
go to the topic. When a pass finds nothing new, nothing running and
nothing to submit, the selection is drained and the loop exits.

## The selection

```
rapidpipe loop --run <id> --filters F146 --scas 8 --pointings all \
    --job-definition <name:revision> [--max-intake 100] [--interval 120] [--once]
```

The selection is three arguments: filters, SCAs, and pointings, either
`all` or a list of `VVV_EEEE`, a visit and an exposure. A pointing is
the same (visit, exposure) pair in every pass of a filter; the
observation number is not part of it, since it can change between
passes of one filter. The selection is the operator's instruction for
this invocation and is recorded in every pass's summary. It is not part
of the run's recipe: widening it changes nothing in the run's settings,
and the same run can be drained one pointing, one SCA or one footprint
at a time.

The loop is for the live run of a survey and dataset. The run's
settings name its source root, and the run holds exactly one open Gaia
catalog binding, which every packet job names. The job definition is an
argument because the run records a code revision, not a job
definition. The loop changes no stage code, so it may run from a newer
checkout than the run's revision while the jobs run the run's image.

## One pass

A pass first asks Batch about the jobs it holds pending, then reads the
source root's listing and one snapshot of the run's tables, decides
every submission from them in a pure function, submits each through
`job submit`'s path without waiting, and publishes.

The listing covers only the selection. A source key's first seventeen
characters name one observation, and an observation is one filter, but
a filter's observation number can differ between passes. So the loop
reads one key of each observation in the source root, keeps the
observations whose filter the selection names, and lists only those in
full. Over the HLWAS simulation that is 23,398 keys instead of 272,160.

Its order:

1. **intake**: one job per listed file the selection admits that no
   published intake of the dataset and no intake job of this run has
   taken, at most `--max-intake` per pass. Each names its filter's and
   SCA's science PSF. The first intake of an exposure expects the
   shared `exposures` key; the others leave it out.
2. **reference**: one job per field and filter with at least
   `[reference.selection] min_frames` official L2 rows, no official
   reference and none pending or failed, and only while no intake of
   the run is pending, so a reference coadds every epoch the drain
   admits rather than the first two to land. The rows are one SCA's,
   the first in order with enough frames; the job's scope records which.
   With a reference bound set, the rules change as described under
   [The reference bound](#the-reference-bound).
3. **difference**: one job per official L2 row whose field has an
   official reference and whose key has no official difference and no
   difference job of the run pending or failed. With a bound, only rows
   at or after it.
4. **associate**: per field, one job for the earliest official source
   set, by `mjdobs`, that no associate of the run has named, with the
   field's open object set as its predecessor. It waits while an
   associate of the field is pending, while an earlier selected L2 row
   of the field lacks its source set, and while any intake of the run
   is pending, since an intake's field is known only once it publishes.
5. **packet**: per field, one job for the earliest associated epoch
   without a packet set, once every earlier epoch's packet set is
   official, because a packet set reuses its predecessors' forced rows.
   It names the reference, the run's Gaia catalog, the science PSF, the
   object set, the epoch's source set, the field's earlier packet sets,
   and the field's difference images and L2 rows within the stage's
   forced window.
6. **Kafka**: `publish` over the run's official, unstamped packet sets
   ([foundation](foundation), Publication to Kafka), on one connection
   with one flush for every set the pass made official. An idle pass
   opens no producer.

Fields advance independently, so one pass can carry many fields at
different depths, and a packet job for epoch *n* goes out beside the
associate for epoch *n + 1*.

**Pending and failed.** A job is pending while it is `launched` or
`running`. A failed job is reported and never resubmitted: its key
counts as taken until a person reruns it, with `job run --job <id>` on
the host or `job submit --job <id>` on Batch, and the loop then carries
on from it.

**The reconcile.** Every job row records the Batch job id it was last
submitted as. At the start of each pass the loop describes the run's
unpublished Batch jobs, a hundred ids a call, and reads the answer two
ways. A Batch job that has ended while its row still says `launched` or
`running` is a container that ended without `job run` recording it: the
row is marked `failed`, with Batch's exit code and its status reason in
the row's `refusal`, and the pass reports it like any failed job. A row
marked `failed` whose Batch job is still queued or running is Batch's
own retry of exit 75 in flight, and the pass holds it pending rather
than exiting. Once Batch has ended a job, the job's own record is the
authority; a local job, or one Batch no longer describes, is left
alone. The whole reconcile took 0.1 s a pass.

**Drained.** A pass is drained when it found no new file, has nothing
pending and submitted nothing. The verb then exits 0. It exits 0 after
one pass with `--once`, 2 after a pass that reports a failed job, and
64 when the run's dataset has no single Gaia catalog. Each pass prints
one JSON line: submitted and pending per stage, failed, held, new,
admitted, listed, packets and sets produced, the reconcile's counts,
drained, its time and the selection. The next pass starts `--interval`
seconds after the last one started, or at once if the pass ran longer.

## The reference bound

A run may set `[reference.selection] before_mjd`, a modified Julian
date. With it set, a field's reference is built only from the field's
epochs before the bound, and only the epochs at or after it are
differenced, so no epoch is subtracted from a reference that holds it.
The bound is a date rather than a list of passes because a survey such
as GBTDS has no passes ({ref}`decision-reference-bound`). Absent, every
epoch may build the reference and every epoch is differenced, as
before.

With the bound set, a reference job names only the field's official L2
rows with `mjdobs` before it, and waits until the selection's intake has
drained: every listed file the selection admits is published and no
intake of the run is pending. No intake pending is not enough on its
own, because a pass admits at most `--max-intake` files and a field's
next epoch can still be listed and unadmitted. The rows before the
bound get no difference, association or packet; the field's chain
starts at the bound.

A field that, once the intake has drained, has fewer than `min_frames`
official rows before the bound, none at all included, gets no
reference. The pass reports it under `held`, with the field and the
reason, on every pass. A held field does not keep the loop from
draining, and the verb exits 0: the gap is recorded, with no timeout.

## The per-field chain

A field's object sets form one chain, one `associate` per epoch, each
naming the last as its predecessor; its packet sets form a second chain
behind it. The chain is in the loop's admission order, and the loop
admits in `mjdobs` order across every SCA of its selection
({ref}`decision-chain-admission-order`). The loop holds a field's
association while any earlier epoch of the field is still upstream.
When two SCAs cover one field, as adjacent pointings do on a grid one
SCA wide, both SCAs' epochs share one reference, since a reference is
per dataset, field and filter, and the SCA is in the PSF key the
difference stage reads per epoch. A loop over every SCA admits each
exposure's SCAs together, so their epochs join the chain in time order;
the HLWAS ramp, which drained SCA 8 before the other SCAs, chained one
such field out of order. An earlier epoch that arrives after later ones
is a rerun from that epoch; the loop never re-associates.

## What it measured

On SMDC, 2026-10-22, over the HLWAS simulation's F146 data:

| Selection | Epochs | Passes | Loop start to drained | Jobs | Failed |
|---|---|---|---|---|---|
| one pointing, SCA 8 | 6 | 18 | 34.7 min | 25 | 0 |
| every pointing, SCA 8 | 312 | 15 | 42.8 min | 1,300 | 0 |
| one pointing, all 18 SCAs | 102 | 18 | 34.6 min | 424 | 0 |

- **An idle pass** took 29 to 35 seconds on the ramp, about 30 of them
  the listing of the whole source root, 272,160 keys in 273 pages.
  Listing only the selection's observations brought it to 3.8 to
  5.8 s; the listing itself is 95 requests and about 4 s.
- **Submission** takes 0.17 to 0.3 s a job, two short transactions and
  one Batch request; 200 intakes went out in 34 s.
- **A pass that publishes** about 52 packet sets took 251 to 274 s on
  the ramp, about 4.3 s a set and three connections a set, more than
  twice the interval. One connection and one flush per pass brings a
  publishing pass to two connections in all.
- **A chain's span is the pass interval times its depth**: a depth-6
  chain took 20 minutes for about 21 seconds of associate containers,
  and the same across 52 fields at once.

## Not decided here

- Where the loop runs on a schedule, and at what cadence, once real
  deliveries exist. Today a person starts it under a timeout on a host.
- A chain that advances faster than one link per pass, by passing again
  as soon as chain work ends or by running `associate` and `packet` in
  one Batch job. At GBTDS depth this is the loop's latency.
- An unbounded run's field with fewer than `min_frames` rows still
  waits without a `held` report; only a bounded run reports it.
- Where the bound goes for each filter of a footprint, and whether
  a reference disjoint from its epochs costs residuals by its depth
  or by its disjointness ([foundation](foundation), Not decided here).
- A reconcile of a Batch job that Batch no longer describes is
  unit-tested only; it has not been seen live.
- The mission's own delivery layout and manifest, once the interface is
  defined; today the source root is a directory of SOC files.
- Lanes or resource profiles dedicated to the loop.
