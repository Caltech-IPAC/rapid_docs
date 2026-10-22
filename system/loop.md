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

A pass reads the source root's listing and one snapshot of the run's
tables, decides every submission from them in a pure function, submits
each through `job submit`'s path without waiting, and publishes. Its
order:

1. **intake**: one job per listed file the selection admits that no
   published intake of the dataset and no intake job of this run has
   taken, at most `--max-intake` per pass. Each names its filter's and
   SCA's science PSF. The first intake of an exposure expects the
   shared `exposures` key; the others leave it out.
2. **reference**: one job per field, filter and SCA with at least
   `[reference.selection] min_frames` official L2 rows, no official
   reference and none pending or failed, and only while no intake of
   the run is pending, so a reference coadds every epoch the drain
   admits rather than the first two to land.
3. **difference**: one job per official L2 row whose field has an
   official reference and whose key has no official difference and no
   difference job of the run pending or failed.
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
   ([foundation](foundation), Publication to Kafka).

Fields advance independently, so one pass can carry many fields at
different depths, and a packet job for epoch *n* goes out beside the
associate for epoch *n + 1*.

**Pending and failed.** A job is pending while it is `launched` or
`running`. A failed job is reported and never resubmitted: its key
counts as taken until a person reruns it with `job run --job <id>`, and
the loop then carries on from it.

**Drained.** A pass is drained when it found no new file, has nothing
pending and submitted nothing. The verb then exits 0. It exits 0 after
one pass with `--once`, 2 after a pass that reports a failed job, and
64 when the run has no single Gaia catalog. Each pass prints one JSON
line: submitted and pending per stage, failed, new, admitted, listed,
packets and sets produced, drained, its time and the selection. The
next pass starts `--interval` seconds after the last one started, or at
once if the pass ran longer.

## The per-field chain

A field's object sets form one chain, in `mjdobs` order, one
`associate` per epoch, each naming the last as its predecessor; its
packet sets form a second chain behind it. The loop keeps each chain
chronological by holding a field's association while any earlier epoch
of the field is still upstream. One case it cannot hold: when two SCAs
cover one field, as adjacent pointings do on a grid one SCA wide, the
second SCA's epochs share the first SCA's reference, since the
reference key has no SCA, and join the chain after the epochs already
in it even when they are earlier in time. That is open
([foundation](foundation), Not decided here).

## What it measured

On SMDC, 2026-10-22, over the HLWAS simulation's F146 data:

| Selection | Epochs | Passes | Loop start to drained | Jobs | Failed |
|---|---|---|---|---|---|
| one pointing, SCA 8 | 6 | 18 | 34.7 min | 25 | 0 |
| every pointing, SCA 8 | 312 | 15 | 42.8 min | 1,300 | 0 |
| one pointing, all 18 SCAs | 102 | 18 | 34.6 min | 424 | 0 |

- **An idle pass** takes 29 to 35 seconds, about 30 of them the listing
  of the whole source root, 272,160 keys in 273 pages.
- **Submission** takes 0.17 to 0.3 s a job, two short transactions and
  one Batch request; 200 intakes went out in 34 s.
- **A pass that publishes** about 52 packet sets takes 251 to 274 s,
  about 4.3 s a set, more than twice the interval.
- **A chain's span is the pass interval times its depth**: a depth-6
  chain took 20 minutes for about 21 seconds of associate containers,
  and the same across 52 fields at once.

## Not decided here

- Where the loop runs on a schedule, and at what cadence, once real
  deliveries exist. Today a person starts it under a timeout on a host.
- A chain that advances faster than one link per pass, by passing again
  as soon as chain work ends or by running `associate` and `packet` in
  one Batch job. At GBTDS depth this is the loop's latency.
- Listing only the selection's prefixes instead of the whole source
  root, which would cut an idle pass to a few seconds.
- Producing every set of a pass under one connection and one flush,
  which would remove most of the publish step's time.
- A Batch job that dies without `job run` recording it stays `running`
  in `jobs`, so the loop never drains and runs to its timeout. Recording
  the Batch job id on the row would let a pass see it. Not yet seen.
- A job marked `failed` between Batch's retries of exit 75 makes the
  loop exit 2 though the retry may succeed. Not yet seen.
- The mission's own delivery layout and manifest, once the interface is
  defined; today the source root is a directory of SOC files.
- Lanes or resource profiles dedicated to the loop.
