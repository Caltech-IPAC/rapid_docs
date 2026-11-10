# Where a run's hours go: the throughput report

**Status: current** (2026-11-09). Rapid PR 575 (throughput-metrics).

The question this page answers: for one run, where did the host-hours
go, and what is the next thing to make faster? Each successive
bottleneck can sit anywhere (a library, a stage, the lanes, Batch's
packing), so the answer comes from records every job writes, not from
a new run (Ben, 2026-11-09 21:21 UTC).

## The records

Every job writes its numbers into its manifest's `metrics`, so the
`job_metrics` view holds them permanently. The fields are on the
[stage contract](stage-contract): the steps' seconds (`step_<name>_s`,
each second counted once), the S3 reads and writes with their bytes,
`startup_s`, the container's CPU seconds against the same interval's
wall (`cgroup_cpu_s`, `cgroup_cpu_wall_s`), the host's CPUs
(`host_vcpus`) and the three memory peaks. The Batch attempt entry adds
the host's `instance_id` beside its `instance_type`. Batch's own record
of each job (`describe-jobs`: created, started, stopped, the container
instance, the vCPU it reserved) is joined by the report.

## The report

```sh
scripts/throughput_report.py --run <id> --batch-records <file> [--out <file>] [--hosts N]
```

Its inputs are `job_metrics`, the run's `jobs` rows and `job_inputs`,
and Batch's records. Batch forgets a job after a while, so the report
saves what it read to `--batch-records` the first time and reads that
file on every later call. It prints, in Markdown:

- **Job vCPU-hours by the stage timers.** This is the historical view,
  the exercise's ranking. Each job's `container_seconds` times its Batch
  vCPU, split by the difference timers (`rb_s`, `xsources_s`,
  `refpsf_s`, `gzip_s`, `pixel_columns_s`) and the packet timers
  (`packet_*_s`). The rest of each job is "untimed". Every row is a
  share of the run's total.
- **Job vCPU-hours by the steps.** The same, split by `step_<name>_s`
  where the jobs wrote steps, with the remainder stated. Absent on runs
  before PR 575.
- **CPU against wall, S3 bytes and memory** per stage.
- **Host-hours.** A host is a container instance. Its hours are the
  span from its first job's start to its last job's stop, over every
  job the records place on it, this run's and other runs'. Boot time and
  idle time outside that span are not in the records, so they are not
  counted. Inside the span, each moment is split equally among the jobs
  running on the host (time-weighted co-tenancy). Moments with no job
  are the host's idle share, and other runs' jobs are the coverage line.
  A job's host-hours are split across its steps, or before PR 575 its
  timers, in proportion to their seconds.
- **Co-tenancy** per instance type and for the longest-lived hosts: the
  mean and largest number of jobs at once while the host was occupied.
- **Queue wait** per stage, Batch's `createdAt` to `startedAt`.
- **Fixed cost against per-source cost.** A job's fixed seconds are its
  `startup_s` and its input reads and model and catalog loads. The rest
  of `container_seconds` is divided by its sources: the difference's
  scored candidates, the packet's packets. Absent before PR 575.
- **The critical path of one exposure.** The packet job of median
  end-to-end time, walked back through each job's gating upstream job:
  of its inputs' jobs that stopped before it was submitted, the last to
  stop. Each hop shows the gap (the loop's cadence), the queue wait and
  the run.
- **Leads, ranked.** The largest host-hour items, then what the numbers
  say about CPU left on the hosts, idle hosts, other runs and queue wait.

A field a run's jobs never wrote prints "absent", never zero. A
published job whose row has no `ended`, and so no `container_seconds`,
is named in the header and left out of the sums. Run 188 has 30
differences and 88 packets like that, each reclaimed by Spot after its
publish committed and before the job wrote its `ended`. Since rapid PR
578 the publisher writes `ended` with the published state, so runs from
then on have none.

## Run 187: the throughput baseline

Run 187 drained the 10/21 window on `rapid-queue-prompt`, on
`rapid-rebuild:112`, before PR 575. The report reproduces the
exercise's ranking from the records: `rb_s` 37.5 %, `xsources_s`
28.5 % and the difference's untimed part 22.8 % of 2,961.5 vCPU-hours.
By host-hours the same three take 39.8 %, 29.6 % and 24.3 % of 313.4
host-hours: a difference job shared its r6i.8xlarge with 9.5 jobs on
average, the intakes their m6a hosts with 12.8 to 20, so a difference
second carries more of a host. The hosts' vCPU-hours were 3.4 times
the jobs' reservations.

The report, `--batch-records` read from the outputs root's `throughput-report/batch-187.json`:

Dataset `baseline-fakesrc-1021b`, survey GBTDS, revision `41d671e7e421eb20931e687bbbc50fe1aae2b0cd`. Published jobs with `container_seconds`: difference 1980, import 2, intake 4529, packet 1980, psf 18, reference 109.

### Job vCPU-hours, by the stage timers (the historical view)

Denominator: 2,961.5 vCPU-h, every published job's `container_seconds` times its Batch vCPU.

| Rank | Item | vCPU-h | Share |
|---|---|---|---|
| 1 | difference: rb_s | 1,111.3 | 37.5 % |
| 2 | difference: xsources_s | 844.1 | 28.5 % |
| 3 | difference: untimed | 674.2 | 22.8 % |
| 4 | packet: untimed | 165.4 | 5.6 % |
| 5 | packet: packet_forced_s | 54.1 | 1.8 % |
| 6 | packet: packet_cutouts_s | 38.7 | 1.3 % |
| 7 | intake | 25.4 | 0.9 % |
| 8 | reference | 12.2 | 0.4 % |
| 9 | packet: packet_read_s | 11.2 | 0.4 % |
| 10 | packet: packet_assembly_s | 10.4 | 0.4 % |
| 11 | difference: gzip_s | 6.8 | 0.2 % |
| 12 | difference: pixel_columns_s | 5.1 | 0.2 % |
| 13 | packet: packet_matching_s | 2.4 | 0.1 % |
| 14 | psf | 0.0 | 0.0 % |
| 15 | difference: refpsf_s | 0.0 | 0.0 % |
| 16 | import | 0.0 | 0.0 % |

### Job vCPU-hours, by the steps

absent: no job of this run wrote `step_*_s` metrics (before throughput-metrics).

### Per stage: CPU against wall, S3 bytes, memory

| Stage | Jobs | CPU s / wall s | S3 read GB | S3 write GB | anon peak median MiB |
|---|---|---|---|---|---|
| difference | 1980 | absent | absent | absent | absent |
| import | 2 | absent | absent | absent | absent |
| intake | 4529 | absent | absent | absent | absent |
| packet | 1980 | absent | absent | absent | absent |
| psf | 18 | absent | absent | absent | absent |
| reference | 109 | absent | absent | absent | absent |

### Host-hours

Hosts: 215 container instances. Denominator: their span, first job's start to last job's stop, 314.0 host-h (10,032.8 host vCPU-h). Inside it, time is split equally among the jobs running at each moment: this run's published jobs 313.4 host-h (99.8 %), its unpublished attempts 0.0, other runs' jobs (coverage) 0.0 (0.0 %), idle 0.6 (0.2 %). Boot and idle time outside the span is not in the records and not counted. A job's share is split across its steps (or, before throughput-metrics, its timers) in proportion to their seconds.

| Rank | Item | Host-h | Share of the run's |
|---|---|---|---|
| 1 | difference: rb_s | 124.58 | 39.8 % |
| 2 | difference: xsources_s | 92.62 | 29.6 % |
| 3 | difference: untimed | 76.23 | 24.3 % |
| 4 | packet: untimed | 9.08 | 2.9 % |
| 5 | packet: packet_forced_s | 3.20 | 1.0 % |
| 6 | packet: packet_cutouts_s | 2.26 | 0.7 % |
| 7 | intake | 1.83 | 0.6 % |
| 8 | reference | 0.82 | 0.3 % |
| 9 | difference: gzip_s | 0.74 | 0.2 % |
| 10 | packet: packet_read_s | 0.65 | 0.2 % |
| 11 | packet: packet_assembly_s | 0.61 | 0.2 % |
| 12 | difference: pixel_columns_s | 0.57 | 0.2 % |
| 13 | packet: packet_matching_s | 0.14 | 0.0 % |
| 14 | psf | 0.01 | 0.0 % |
| 15 | difference: refpsf_s | 0.00 | 0.0 % |

### Co-tenancy

| Instance type | vCPU | Hosts | Jobs | Span host-h | Idle host-h | Mean jobs at once | Largest |
|---|---|---|---|---|---|---|---|
| m6a.2xlarge | 8 | 2 | 56 | 0.1 | 0.0 | 7.5 | 8 |
| m6a.4xlarge | 16 | 6 | 1142 | 0.8 | 0.2 | 12.8 | 16 |
| m6a.8xlarge | 32 | 9 | 3349 | 1.6 | 0.4 | 20.0 | 32 |
| r6i.8xlarge | 32 | 198 | 4069 | 311.5 | 0.0 | 9.5 | 32 |

<details><summary>Per host, the 20 longest spans of 215</summary>

| Host | Type | Jobs (this run) | Span h | Idle h | Mean | Largest |
|---|---|---|---|---|---|---|
| 07cfa835ce3a | r6i.8xlarge | 21 (21) | 1.97 | 0.00 | 9.3 | 11 |
| d225d4fc712f | r6i.8xlarge | 36 (36) | 1.91 | 0.00 | 11.4 | 26 |
| bf13b0322d23 | r6i.8xlarge | 61 (61) | 1.89 | 0.00 | 13.4 | 32 |
| 5dbb11b48bdb | r6i.8xlarge | 55 (55) | 1.85 | 0.00 | 13.2 | 30 |
| ff6fcb7b056c | r6i.8xlarge | 37 (37) | 1.84 | 0.00 | 11.7 | 26 |
| f581dd721fa8 | r6i.8xlarge | 27 (27) | 1.83 | 0.00 | 10.9 | 17 |
| ff86110c48e2 | r6i.8xlarge | 59 (59) | 1.83 | 0.00 | 13.1 | 32 |
| 82e3f07460f2 | r6i.8xlarge | 32 (32) | 1.83 | 0.00 | 10.9 | 24 |
| 0593939580e6 | r6i.8xlarge | 58 (58) | 1.82 | 0.00 | 12.8 | 32 |
| 057ae1610912 | r6i.8xlarge | 24 (24) | 1.82 | 0.00 | 10.5 | 15 |
| 0eb2bdb57e5b | r6i.8xlarge | 118 (118) | 1.82 | 0.00 | 15.8 | 32 |
| 1f330e6da294 | r6i.8xlarge | 131 (131) | 1.82 | 0.00 | 16.7 | 32 |
| af141fa925d8 | r6i.8xlarge | 77 (77) | 1.81 | 0.00 | 13.6 | 32 |
| 1e2a308a1ede | r6i.8xlarge | 63 (63) | 1.81 | 0.00 | 13.4 | 32 |
| f219c0699ee5 | r6i.8xlarge | 42 (42) | 1.81 | 0.00 | 11.8 | 27 |
| fb3e0f86ec67 | r6i.8xlarge | 24 (24) | 1.80 | 0.00 | 10.7 | 15 |
| 587aebe36235 | r6i.8xlarge | 76 (76) | 1.80 | 0.00 | 13.4 | 32 |
| 201d56084f3e | r6i.8xlarge | 18 (18) | 1.80 | 0.00 | 10.4 | 15 |
| c8caedcf0ae9 | r6i.8xlarge | 29 (29) | 1.79 | 0.00 | 11.4 | 22 |
| 4c79bc0d3e88 | r6i.8xlarge | 58 (58) | 1.79 | 0.00 | 13.1 | 32 |

</details>

### Queue wait, Batch's createdAt to startedAt

| Stage | Submissions | Median s | p90 s | Max s |
|---|---|---|---|---|
| difference | 1980 | 179 | 187 | 221 |
| intake | 4529 | 9 | 43 | 167 |
| packet | 1980 | 7 | 11 | 113 |
| psf | 18 | 125 | 127 | 129 |
| reference | 109 | 169 | 181 | 184 |

### Fixed cost per job against per-source cost

Fixed: `startup_s` (the process's start to the job's, outside `container_seconds`) and `step_read_inputs_s`, `step_rb_model_load_s`, `step_stage_inputs_s`, `step_read_s`, `step_s3_read_s`, `step_catalog_mirror_s`, `step_crds_fetch_s`, `step_distortion_s`. Per source: the rest of `container_seconds` over the difference's scored candidates or the packet's packets; medians over the jobs that wrote steps.

| Stage | Jobs (with steps) | container s | startup s | fixed s | s per source |
|---|---|---|---|---|---|
| difference | 1980 (0) | 4,736.0 | absent | absent | absent |
| import | 2 (0) | 1.0 | absent | absent | absent |
| intake | 4529 (0) | 18.9 | absent | absent | absent |
| packet | 1980 (0) | 541.2 | absent | absent | absent |
| psf | 18 (0) | 9.4 | absent | absent | absent |
| reference | 109 (0) | 413.7 | absent | absent | absent |

### The critical path of one exposure

The exposure of median end-to-end time, 9,074 s from its first job's submission to its packet job's stop. Gap: the upstream job's stop to this job's submission (the loop's cadence).

| Job | Stage | Gap s | Queue wait s | Run s |
|---|---|---|---|---|
| 42059 | psf | 0 | 127 | 15 |
| 44589 | intake | 1,540 | 7 | 25 |
| 46634 | reference | 1,231 | 170 | 393 |
| 47585 | difference | 131 | 186 | 4,212 |
| 49359 | packet | 1 | 13 | 195 |
| 49692 | packet | 111 | 8 | 709 |

### Leads, ranked

1. difference: rb_s: 124.6 host-h, 39.8 % of the run's
2. difference: xsources_s: 92.6 host-h, 29.6 % of the run's
3. difference: untimed: 76.2 host-h, 24.3 % of the run's
4. packet: untimed: 9.1 host-h, 2.9 % of the run's
5. packet: packet_forced_s: 3.2 host-h, 1.0 % of the run's
6. the hosts' vCPU-h are 3.4 times the jobs' vCPU reservation: memory, not CPU, sets the packing, so CPU is left on the hosts
7. idle host time inside the span: 0.6 host-h (0.2 %) - packing and scale-in, not code
8. queue wait: difference jobs waited a median 179 s for a host


## Run 188: the Spot arm

Run 188 drained the same window on `rapid-queue-bulk` (Spot). There the
difference's untimed part leads with 52.4 % of 2,420.5 vCPU-hours,
followed by `rb_s` at 14.5 %, the packet's untimed part at 13.8 % and
`xsources_s` at 13.4 %. Its 1,179 hosts were mostly 2xlarge types, with
1.2 to 2.2 jobs at once, against run 187's 9.5 on r6i.8xlarge. `rb_s`
fell to a third of run 187's. That is consistent with, not shown to be
caused by, the shipped thread pool's gain alone and loss when packed
(the onnxruntime settings section of the
[exercise page](../log/2026-11-08-exercise-2026-11.md)).

The report, `--batch-records` read from the outputs root's `throughput-report/batch-188.json`:

Dataset `spot-fakesrc-1021`, survey GBTDS, revision `41d671e7e421eb20931e687bbbc50fe1aae2b0cd`. Published jobs with `container_seconds`: difference 1950, import 1, intake 4529, packet 1892, psf 18, reference 109. Published without it (left out): difference 30, packet 88.

### Job vCPU-hours, by the stage timers (the historical view)

Denominator: 2,420.5 vCPU-h, every published job's `container_seconds` times its Batch vCPU.

| Rank | Item | vCPU-h | Share |
|---|---|---|---|
| 1 | difference: untimed | 1,268.1 | 52.4 % |
| 2 | difference: rb_s | 350.7 | 14.5 % |
| 3 | packet: untimed | 333.4 | 13.8 % |
| 4 | difference: xsources_s | 324.9 | 13.4 % |
| 5 | packet: packet_forced_s | 39.5 | 1.6 % |
| 6 | packet: packet_cutouts_s | 30.4 | 1.3 % |
| 7 | intake | 25.7 | 1.1 % |
| 8 | packet: packet_read_s | 20.9 | 0.9 % |
| 9 | reference | 8.5 | 0.4 % |
| 10 | packet: packet_assembly_s | 7.8 | 0.3 % |
| 11 | difference: gzip_s | 5.2 | 0.2 % |
| 12 | difference: pixel_columns_s | 3.5 | 0.1 % |
| 13 | packet: packet_matching_s | 1.7 | 0.1 % |
| 14 | psf | 0.0 | 0.0 % |
| 15 | difference: refpsf_s | 0.0 | 0.0 % |
| 16 | import | 0.0 | 0.0 % |

### Job vCPU-hours, by the steps

absent: no job of this run wrote `step_*_s` metrics (before throughput-metrics).

### Per stage: CPU against wall, S3 bytes, memory

| Stage | Jobs | CPU s / wall s | S3 read GB | S3 write GB | anon peak median MiB |
|---|---|---|---|---|---|
| difference | 1950 | absent | absent | absent | absent |
| import | 1 | absent | absent | absent | absent |
| intake | 4529 | absent | absent | absent | absent |
| packet | 1892 | absent | absent | absent | absent |
| psf | 18 | absent | absent | absent | absent |
| reference | 109 | absent | absent | absent | absent |

### Host-hours

Hosts: 1179 container instances. Denominator: their span, first job's start to last job's stop, 977.6 host-h (15,123.6 host vCPU-h). Inside it, time is split equally among the jobs running at each moment: this run's published jobs 954.6 host-h (97.6 %), its unpublished attempts 20.1, other runs' jobs (coverage) 0.0 (0.0 %), idle 3.0 (0.3 %). Boot and idle time outside the span is not in the records and not counted. A job's share is split across its steps (or, before throughput-metrics, its timers) in proportion to their seconds.

| Rank | Item | Host-h | Share of the run's |
|---|---|---|---|
| 1 | difference: untimed | 542.51 | 56.8 % |
| 2 | difference: xsources_s | 141.78 | 14.9 % |
| 3 | difference: rb_s | 138.29 | 14.5 % |
| 4 | packet: untimed | 94.12 | 9.9 % |
| 5 | packet: packet_cutouts_s | 9.43 | 1.0 % |
| 6 | packet: packet_forced_s | 9.31 | 1.0 % |
| 7 | packet: packet_read_s | 4.75 | 0.5 % |
| 8 | intake | 4.00 | 0.4 % |
| 9 | reference | 3.03 | 0.3 % |
| 10 | difference: gzip_s | 2.65 | 0.3 % |
| 11 | packet: packet_assembly_s | 2.41 | 0.3 % |
| 12 | difference: pixel_columns_s | 1.75 | 0.2 % |
| 13 | packet: packet_matching_s | 0.54 | 0.1 % |
| 14 | psf | 0.01 | 0.0 % |
| 15 | difference: refpsf_s | 0.00 | 0.0 % |

### Co-tenancy

| Instance type | vCPU | Hosts | Jobs | Span host-h | Idle host-h | Mean jobs at once | Largest |
|---|---|---|---|---|---|---|---|
| m6a.2xlarge | 8 | 409 | 3689 | 352.4 | 1.3 | 1.7 | 8 |
| m6a.4xlarge | 16 | 113 | 642 | 119.7 | 0.1 | 2.2 | 16 |
| m6a.8xlarge | 32 | 133 | 1660 | 207.1 | 0.8 | 4.4 | 32 |
| m6i.2xlarge | 8 | 228 | 867 | 138.9 | 0.2 | 1.3 | 8 |
| m7a.2xlarge | 8 | 108 | 588 | 44.5 | 0.3 | 1.2 | 8 |
| m7a.4xlarge | 16 | 1 | 16 | 0.0 | 0.0 | 13.4 | 16 |
| m7i.2xlarge | 8 | 4 | 278 | 0.5 | 0.2 | 5.9 | 8 |
| m7i.4xlarge | 16 | 165 | 475 | 79.9 | 0.0 | 1.8 | 16 |
| r6i.4xlarge | 16 | 4 | 74 | 5.8 | 0.0 | 6.8 | 16 |
| r6i.8xlarge | 32 | 14 | 385 | 28.8 | 0.0 | 10.4 | 32 |

<details><summary>Per host, the 20 longest spans of 1179</summary>

| Host | Type | Jobs (this run) | Span h | Idle h | Mean | Largest |
|---|---|---|---|---|---|---|
| d614b73a6c01 | r6i.8xlarge | 33 (33) | 2.33 | 0.00 | 10.3 | 16 |
| bac17677965d | r6i.8xlarge | 26 (26) | 2.32 | 0.00 | 10.4 | 15 |
| 8f14862f8cd7 | r6i.8xlarge | 22 (22) | 2.26 | 0.00 | 9.9 | 14 |
| 74f55cd1ea8c | r6i.8xlarge | 17 (17) | 2.25 | 0.00 | 9.9 | 11 |
| 79d94a1be534 | r6i.4xlarge | 21 (21) | 2.20 | 0.00 | 6.2 | 16 |
| 6e2d2e7a3d9d | r6i.8xlarge | 17 (17) | 2.15 | 0.00 | 10.2 | 11 |
| ce1aa5188ef8 | m6a.2xlarge | 18 (18) | 2.13 | 0.00 | 2.7 | 6 |
| b08459a93195 | r6i.8xlarge | 17 (17) | 2.11 | 0.00 | 10.1 | 11 |
| 4e003c4b37db | r6i.8xlarge | 17 (17) | 2.11 | 0.00 | 10.1 | 11 |
| 4deaec1aa0e3 | r6i.8xlarge | 18 (17) | 2.11 | 0.00 | 10.2 | 12 |
| a553d1b6f460 | r6i.8xlarge | 16 (16) | 2.10 | 0.00 | 10.0 | 11 |
| bb5f90218d34 | m6a.8xlarge | 10 (10) | 2.10 | 0.00 | 5.1 | 9 |
| 537d4db52976 | m6a.4xlarge | 14 (14) | 2.10 | 0.00 | 3.3 | 12 |
| 0d7e2ca5c472 | m6a.4xlarge | 9 (9) | 2.08 | 0.00 | 2.4 | 8 |
| a46188b09543 | m6a.4xlarge | 14 (14) | 2.07 | 0.00 | 3.8 | 12 |
| b5712759af94 | m6a.4xlarge | 14 (14) | 2.07 | 0.00 | 3.5 | 12 |
| 34d9d907f094 | m6a.4xlarge | 9 (9) | 2.07 | 0.00 | 2.6 | 8 |
| b5fbb906fc0c | m6a.4xlarge | 14 (14) | 2.07 | 0.00 | 3.4 | 12 |
| 62ef02f480c1 | m6a.8xlarge | 5 (5) | 2.06 | 0.00 | 4.8 | 5 |
| 82790cc70e87 | m6a.2xlarge | 16 (16) | 2.06 | 0.01 | 2.9 | 6 |

</details>

### Queue wait, Batch's createdAt to startedAt

| Stage | Submissions | Median s | p90 s | Max s |
|---|---|---|---|---|
| difference | 2024 | 469 | 713 | 1,057 |
| intake | 4529 | 7 | 66 | 204 |
| packet | 1992 | 7 | 53 | 171 |
| psf | 18 | 191 | 192 | 200 |
| reference | 109 | 215 | 459 | 463 |

### Fixed cost per job against per-source cost

Fixed: `startup_s` (the process's start to the job's, outside `container_seconds`) and `step_read_inputs_s`, `step_rb_model_load_s`, `step_stage_inputs_s`, `step_read_s`, `step_s3_read_s`, `step_catalog_mirror_s`, `step_crds_fetch_s`, `step_distortion_s`. Per source: the rest of `container_seconds` over the difference's scored candidates or the packet's packets; medians over the jobs that wrote steps.

| Stage | Jobs (with steps) | container s | startup s | fixed s | s per source |
|---|---|---|---|---|---|
| difference | 1950 (0) | 3,063.0 | absent | absent | absent |
| import | 1 (0) | 1.3 | absent | absent | absent |
| intake | 4529 (0) | 18.3 | absent | absent | absent |
| packet | 1892 (0) | 892.5 | absent | absent | absent |
| psf | 18 (0) | 9.0 | absent | absent | absent |
| reference | 109 (0) | 260.9 | absent | absent | absent |

### The critical path of one exposure

The exposure of median end-to-end time, 8,077 s from its first job's submission to its packet job's stop. Gap: the upstream job's stop to this job's submission (the loop's cadence).

| Job | Stage | Gap s | Queue wait s | Run s |
|---|---|---|---|---|
| 50678 | psf | 0 | 191 | 15 |
| 53143 | intake | 1,481 | 19 | 22 |
| 55304 | reference | 1,288 | 462 | 257 |
| 57110 | difference | 54 | 722 | 3,119 |
| 58297 | packet | 80 | 3 | 364 |

### Leads, ranked

1. difference: untimed: 542.5 host-h, 56.8 % of the run's
2. difference: xsources_s: 141.8 host-h, 14.9 % of the run's
3. difference: rb_s: 138.3 host-h, 14.5 % of the run's
4. packet: untimed: 94.1 host-h, 9.9 % of the run's
5. packet: packet_cutouts_s: 9.4 host-h, 1.0 % of the run's
6. the hosts' vCPU-h are 6.2 times the jobs' vCPU reservation: memory, not CPU, sets the packing, so CPU is left on the hosts
7. idle host time inside the span: 3.0 host-h (0.3 %) - packing and scale-in, not code
8. queue wait: difference jobs waited a median 469 s for a host


## Run 216: the first run with every field

Run 216 (`throughput-metrics-sca3`) ran run 212's inputs, run 187's SCA 3
(261 intakes, 6 references, 110 differences, 110 packet sets), on
`rapid-rebuild:119` (rapid `e7d7155a`, the PR's branch) on
`rapid-queue-prompt`, every setting as shipped. The loop drained at
00:36 UTC 2026-11-10, exit 0, nothing failed. All 489 published jobs
wrote every field. Per expid the scored, kept, xsource and packet counts
and the gate's decision equal run 212's on all 110 expids. Only
`n_memberships` and `n_xmemberships` differ, and they differ as much
between runs 212 and 190: association depends on the order the
differences finish.

What the steps add to the timers' view:

- **Real/bogus scoring is 58.3 % of the job vCPU-hours, not 36.2 %.**
  `rb_s` times only the PSF-fit catalogs' scoring. The `rb` step also
  counts the xsources' scoring, which sits inside `xsources_s`. The
  xsources' fit itself (`step_xsources_fit_s`) is 2.4 %.
- **The difference's untimed 24.1 % is now named.** SFFT's catalogs
  9.7 %, ZOGY's catalogs 8.3 %, `naive` 1.3 %, the SFFT solve 2.0 %,
  ZOGY 0.7 %. ZOGY and the naive difference run on every job though SFFT
  is the published differencer. The remainder is 0.6 %.
- **The difference job uses 2.8 CPU seconds per wall second** against
  its one-vCPU reservation. Intake and packet are near 0.9.
- **The intake's remainder** (median 91 s of a 105 s job, against 17 s
  on run 212) falls after the manifest's upload, so it is the publish.
  It ran while run 215 (memory-shape-15g) was publishing its 1,998
  intakes. That cause is inferred from the timing, not probed.
- **Host-hours:** 53 container instances (42 r7i.4xlarge, 11
  r7i.2xlarge), 27.7 host-hours in their span. Run 216 took 66.1 %,
  other runs on the same hosts 26.1 % and idle 7.8 %.

The report, `--batch-records` read from the outputs root's `throughput-report/batch-216.json`:

Dataset `throughput-metrics-sca3`, survey GBTDS, revision `e7d7155acf62c152e6d8431d7b0343a5edcc0941`. Published jobs with `container_seconds`: difference 110, import 1, intake 261, packet 110, psf 1, reference 6.

### Job vCPU-hours, by the stage timers (the historical view)

Denominator: 88.5 vCPU-h, every published job's `container_seconds` times its Batch vCPU.

| Rank | Item | vCPU-h | Share |
|---|---|---|---|
| 1 | difference: rb_s | 32.0 | 36.2 % |
| 2 | difference: xsources_s | 21.9 | 24.8 % |
| 3 | difference: untimed | 21.3 | 24.1 % |
| 4 | intake | 7.9 | 8.9 % |
| 5 | packet: packet_forced_s | 1.9 | 2.2 % |
| 6 | packet: packet_cutouts_s | 1.3 | 1.5 % |
| 7 | packet: packet_read_s | 0.5 | 0.5 % |
| 8 | packet: packet_assembly_s | 0.4 | 0.5 % |
| 9 | reference | 0.4 | 0.4 % |
| 10 | difference: gzip_s | 0.3 | 0.3 % |
| 11 | packet: untimed | 0.2 | 0.2 % |
| 12 | difference: pixel_columns_s | 0.2 | 0.2 % |
| 13 | packet: packet_matching_s | 0.1 | 0.1 % |
| 14 | psf | 0.0 | 0.0 % |
| 15 | import | 0.0 | 0.0 % |
| 16 | difference: refpsf_s | 0.0 | 0.0 % |

### Job vCPU-hours, by the steps

489 of 489 published jobs wrote steps; 88.5 vCPU-h. The remainder is `container_seconds` less the job's steps.

| Rank | Item | vCPU-h | Share |
|---|---|---|---|
| 1 | difference: step_rb_s | 51.61 | 58.3 % |
| 2 | difference: step_sfft_catalogs_s | 8.59 | 9.7 % |
| 3 | difference: step_zogy_catalogs_s | 7.31 | 8.3 % |
| 4 | intake: remainder | 6.98 | 7.9 % |
| 5 | difference: step_xsources_fit_s | 2.12 | 2.4 % |
| 6 | packet: step_forced_s | 1.91 | 2.2 % |
| 7 | difference: step_sfft_solve_s | 1.76 | 2.0 % |
| 8 | packet: step_cutouts_s | 1.31 | 1.5 % |
| 9 | difference: step_naive_s | 1.18 | 1.3 % |
| 10 | difference: step_zogy_s | 0.66 | 0.7 % |
| 11 | difference: remainder | 0.50 | 0.6 % |
| 12 | packet: step_assembly_s | 0.44 | 0.5 % |
| 13 | intake: step_limmag_s | 0.34 | 0.4 % |
| 14 | packet: step_s3_read_s | 0.30 | 0.3 % |
| 15 | difference: step_trim_s | 0.30 | 0.3 % |
| 16 | reference: step_awaicgen_s | 0.28 | 0.3 % |
| 17 | intake: step_gaia_s | 0.24 | 0.3 % |
| 18 | difference: step_gainmatch_s | 0.22 | 0.2 % |
| 19 | difference: step_pixel_columns_s | 0.21 | 0.2 % |
| 20 | difference: step_resample_s | 0.18 | 0.2 % |
| 21 | packet: step_read_s | 0.17 | 0.2 % |
| 22 | intake: step_gzip_s | 0.16 | 0.2 % |
| 23 | difference: step_background_s | 0.16 | 0.2 % |
| 24 | difference: step_science_catalog_s | 0.15 | 0.2 % |
| 25 | difference: step_s3_read_s | 0.14 | 0.2 % |
| 26 | difference: step_sfft_inputs_s | 0.12 | 0.1 % |
| 27 | packet: step_matching_s | 0.10 | 0.1 % |
| 28 | difference: step_s3_write_s | 0.10 | 0.1 % |
| 29 | packet: remainder | 0.10 | 0.1 % |
| 30 | difference: step_source_set_s | 0.09 | 0.1 % |
| 31 | difference: step_sfft_mask_s | 0.08 | 0.1 % |
| 32 | difference: step_quality_metrics_s | 0.08 | 0.1 % |
| 33 | intake: step_convert_s | 0.07 | 0.1 % |
| 34 | packet: step_index_s | 0.07 | 0.1 % |
| 35 | difference: step_reformat_s | 0.07 | 0.1 % |
| 36 | difference: step_associate_s | 0.07 | 0.1 % |
| 37 | packet: step_s3_write_s | 0.04 | 0.0 % |
| 38 | intake: step_s3_write_s | 0.04 | 0.0 % |
| 39 | intake: step_s3_read_s | 0.04 | 0.0 % |
| 40 | difference: step_stage_inputs_s | 0.04 | 0.0 % |
| 41 | reference: step_prepare_s | 0.04 | 0.0 % |
| 42 | reference: step_measure_s | 0.02 | 0.0 % |
| 43 | reference: step_read_inputs_s | 0.02 | 0.0 % |
| 44 | reference: step_s3_read_s | 0.01 | 0.0 % |
| 45 | difference: step_rb_model_load_s | 0.01 | 0.0 % |
| 46 | reference: step_catalog_s | 0.01 | 0.0 % |
| 47 | reference: remainder | 0.01 | 0.0 % |
| 48 | reference: step_s3_write_s | 0.00 | 0.0 % |
| 49 | difference: step_registration_s | 0.00 | 0.0 % |
| 50 | difference: step_read_inputs_s | 0.00 | 0.0 % |
| 51 | psf: remainder | 0.00 | 0.0 % |
| 52 | packet: step_write_set_s | 0.00 | 0.0 % |
| 53 | difference: step_xsources_set_s | 0.00 | 0.0 % |
| 54 | import: remainder | 0.00 | 0.0 % |
| 55 | difference: step_manifest_s | 0.00 | 0.0 % |
| 56 | psf: step_s3_read_s | 0.00 | 0.0 % |
| 57 | import: step_catalog_mirror_s | 0.00 | 0.0 % |
| 58 | difference: step_refpsf_s | 0.00 | 0.0 % |
| 59 | packet: step_manifest_s | 0.00 | 0.0 % |
| 60 | psf: step_s3_write_s | 0.00 | 0.0 % |
| 61 | psf: step_reduce_s | 0.00 | 0.0 % |
| 62 | import: step_s3_write_s | 0.00 | 0.0 % |

### Per stage: CPU against wall, S3 bytes, memory

| Stage | Jobs | CPU s / wall s | S3 read GB | S3 write GB | anon peak median MiB |
|---|---|---|---|---|---|
| difference | 110 | 2.81 | 117.34 | 29.47 | 14,801 |
| import | 1 | 1.69 | absent | 0.00 | 3,899 |
| intake | 261 | 0.89 | 15.50 | 15.60 | 894 |
| packet | 110 | 0.93 | 129.14 | 42.39 | 1,730 |
| psf | 1 | 1.00 | 0.18 | 0.00 | 233 |
| reference | 6 | 1.58 | 9.02 | 6.02 | 2,447 |

### Host-hours

Hosts: 53 container instances. Denominator: their span, first job's start to last job's stop, 27.7 host-h (419.2 host vCPU-h). Inside it, time is split equally among the jobs running at each moment: this run's published jobs 18.3 host-h (66.1 %), its unpublished attempts 0.0, other runs' jobs (coverage) 7.2 (26.1 %), idle 2.2 (7.8 %). Boot and idle time outside the span is not in the records and not counted. A job's share is split across its steps (or, before throughput-metrics, its timers) in proportion to their seconds.

| Rank | Item | Host-h | Share of the run's |
|---|---|---|---|
| 1 | difference: step_rb_s | 10.46 | 57.1 % |
| 2 | difference: step_sfft_catalogs_s | 1.80 | 9.8 % |
| 3 | difference: step_zogy_catalogs_s | 1.50 | 8.2 % |
| 4 | packet: step_forced_s | 0.88 | 4.8 % |
| 5 | packet: step_cutouts_s | 0.62 | 3.4 % |
| 6 | intake: remainder | 0.60 | 3.3 % |
| 7 | difference: step_xsources_fit_s | 0.44 | 2.4 % |
| 8 | difference: step_sfft_solve_s | 0.36 | 2.0 % |
| 9 | difference: step_naive_s | 0.24 | 1.3 % |
| 10 | packet: step_assembly_s | 0.22 | 1.2 % |
| 11 | packet: step_s3_read_s | 0.14 | 0.8 % |
| 12 | difference: step_zogy_s | 0.14 | 0.7 % |
| 13 | difference: remainder | 0.10 | 0.6 % |
| 14 | packet: step_read_s | 0.08 | 0.5 % |
| 15 | reference: step_awaicgen_s | 0.07 | 0.4 % |
| 16 | difference: step_trim_s | 0.06 | 0.3 % |
| 17 | packet: step_matching_s | 0.05 | 0.3 % |
| 18 | packet: remainder | 0.05 | 0.3 % |
| 19 | difference: step_gainmatch_s | 0.05 | 0.3 % |
| 20 | difference: step_pixel_columns_s | 0.04 | 0.2 % |
| 21 | difference: step_resample_s | 0.04 | 0.2 % |
| 22 | packet: step_index_s | 0.04 | 0.2 % |
| 23 | difference: step_background_s | 0.03 | 0.2 % |
| 24 | difference: step_science_catalog_s | 0.03 | 0.2 % |
| 25 | difference: step_s3_read_s | 0.03 | 0.2 % |
| 26 | intake: step_limmag_s | 0.03 | 0.2 % |
| 27 | difference: step_sfft_inputs_s | 0.03 | 0.1 % |
| 28 | difference: step_s3_write_s | 0.02 | 0.1 % |
| 29 | packet: step_s3_write_s | 0.02 | 0.1 % |
| 30 | intake: step_gaia_s | 0.02 | 0.1 % |
| 31 | difference: step_source_set_s | 0.02 | 0.1 % |
| 32 | difference: step_sfft_mask_s | 0.02 | 0.1 % |
| 33 | difference: step_quality_metrics_s | 0.02 | 0.1 % |
| 34 | difference: step_reformat_s | 0.01 | 0.1 % |
| 35 | intake: step_gzip_s | 0.01 | 0.1 % |
| 36 | difference: step_associate_s | 0.01 | 0.1 % |
| 37 | reference: step_prepare_s | 0.01 | 0.0 % |
| 38 | difference: step_stage_inputs_s | 0.01 | 0.0 % |
| 39 | intake: step_convert_s | 0.01 | 0.0 % |
| 40 | reference: step_measure_s | 0.00 | 0.0 % |
| 41 | reference: step_read_inputs_s | 0.00 | 0.0 % |
| 42 | reference: step_s3_read_s | 0.00 | 0.0 % |
| 43 | intake: step_s3_write_s | 0.00 | 0.0 % |
| 44 | intake: step_s3_read_s | 0.00 | 0.0 % |
| 45 | difference: step_rb_model_load_s | 0.00 | 0.0 % |
| 46 | reference: step_catalog_s | 0.00 | 0.0 % |
| 47 | reference: remainder | 0.00 | 0.0 % |
| 48 | reference: step_s3_write_s | 0.00 | 0.0 % |
| 49 | difference: step_registration_s | 0.00 | 0.0 % |
| 50 | difference: step_read_inputs_s | 0.00 | 0.0 % |
| 51 | packet: step_write_set_s | 0.00 | 0.0 % |
| 52 | psf: remainder | 0.00 | 0.0 % |
| 53 | difference: step_xsources_set_s | 0.00 | 0.0 % |
| 54 | difference: step_manifest_s | 0.00 | 0.0 % |
| 55 | packet: step_manifest_s | 0.00 | 0.0 % |
| 56 | psf: step_s3_read_s | 0.00 | 0.0 % |
| 57 | difference: step_refpsf_s | 0.00 | 0.0 % |
| 58 | psf: step_s3_write_s | 0.00 | 0.0 % |
| 59 | psf: step_reduce_s | 0.00 | 0.0 % |

### Co-tenancy

| Instance type | vCPU | Hosts | Jobs | Span host-h | Idle host-h | Mean jobs at once | Largest |
|---|---|---|---|---|---|---|---|
| r7i.2xlarge | 8 | 11 | 80 | 3.1 | 1.2 | 1.6 | 2 |
| r7i.4xlarge | 16 | 42 | 3967 | 24.7 | 1.0 | 5.3 | 16 |

<details><summary>Per host, the 20 longest spans of 53</summary>

| Host | Type | Jobs (this run) | Span h | Idle h | Mean | Largest |
|---|---|---|---|---|---|---|
| d63907df4770 | r7i.4xlarge | 120 (19) | 1.13 | 0.03 | 5.0 | 16 |
| 0c7cccb69e8f | r7i.4xlarge | 342 (3) | 1.01 | 0.00 | 4.4 | 16 |
| cbc0401f376c | r7i.4xlarge | 332 (1) | 0.98 | 0.00 | 5.3 | 16 |
| 878910112eec | r7i.4xlarge | 33 (6) | 0.98 | 0.00 | 4.2 | 6 |
| 08d82c6dabb0 | r7i.4xlarge | 31 (5) | 0.98 | 0.00 | 4.6 | 6 |
| 32573fef45f4 | r7i.4xlarge | 143 (20) | 0.92 | 0.03 | 5.9 | 16 |
| e77fdd217647 | r7i.4xlarge | 35 (5) | 0.92 | 0.00 | 4.3 | 6 |
| fea5539e6f4d | r7i.4xlarge | 35 (5) | 0.90 | 0.00 | 4.2 | 6 |
| 4810cfa822ce | r7i.4xlarge | 143 (18) | 0.89 | 0.03 | 6.0 | 16 |
| 55474bf17373 | r7i.4xlarge | 60 (30) | 0.87 | 0.00 | 5.3 | 9 |
| 5ddf28a47b6a | r7i.4xlarge | 30 (6) | 0.86 | 0.00 | 4.7 | 6 |
| cb2667e5793a | r7i.4xlarge | 108 (20) | 0.85 | 0.04 | 5.8 | 16 |
| 043ea8e4ed60 | r7i.4xlarge | 118 (19) | 0.84 | 0.04 | 5.9 | 16 |
| b460a14f41c6 | r7i.4xlarge | 35 (6) | 0.80 | 0.00 | 4.8 | 6 |
| c9ace606d4d9 | r7i.4xlarge | 100 (21) | 0.79 | 0.00 | 5.7 | 16 |
| 89e6c6e05c42 | r7i.4xlarge | 32 (5) | 0.79 | 0.00 | 4.9 | 6 |
| 4474fb3e9f83 | r7i.4xlarge | 32 (5) | 0.78 | 0.00 | 4.9 | 6 |
| 900e63d20132 | r7i.4xlarge | 32 (5) | 0.78 | 0.00 | 4.9 | 6 |
| 1ca0f7205d15 | r7i.4xlarge | 116 (13) | 0.77 | 0.00 | 5.5 | 16 |
| fa9d9806b3bc | r7i.4xlarge | 297 (4) | 0.77 | 0.00 | 6.7 | 16 |

</details>

### Queue wait, Batch's createdAt to startedAt

| Stage | Submissions | Median s | p90 s | Max s |
|---|---|---|---|---|
| difference | 110 | 134 | 179 | 183 |
| intake | 261 | 21 | 67 | 82 |
| packet | 110 | 10 | 145 | 176 |
| psf | 1 | 5 | 5 | 5 |
| reference | 6 | 8 | 9 | 9 |

### Fixed cost per job against per-source cost

Fixed: `startup_s` (the process's start to the job's, outside `container_seconds`) and `step_read_inputs_s`, `step_rb_model_load_s`, `step_stage_inputs_s`, `step_read_s`, `step_s3_read_s`, `step_catalog_mirror_s`, `step_crds_fetch_s`, `step_distortion_s`. Per source: the rest of `container_seconds` over the difference's scored candidates or the packet's packets; medians over the jobs that wrote steps.

| Stage | Jobs (with steps) | container s | startup s | fixed s | s per source |
|---|---|---|---|---|---|
| difference | 110 (110) | 2,494.9 | 1.3 | 7.4 | 0.0813 |
| import | 1 (1) | 1.8 | 1.0 | 1.6 | absent |
| intake | 261 (261) | 104.9 | 1.1 | 1.5 | absent |
| packet | 110 (110) | 137.2 | 1.8 | 15.2 | 0.0627 |
| psf | 1 (1) | 4.9 | 1.0 | 1.6 | absent |
| reference | 6 (6) | 231.1 | 0.9 | 19.0 | absent |

### The critical path of one exposure

The exposure of median end-to-end time, 3,322 s from its first job's submission to its packet job's stop. Gap: the upstream job's stop to this job's submission (the loop's cadence).

| Job | Stage | Gap s | Queue wait s | Run s |
|---|---|---|---|---|
| 68665 | psf | 0 | 5 | 7 |
| 69016 | intake | 73 | 22 | 105 |
| 69332 | reference | 28 | 8 | 238 |
| 69934 | difference | 62 | 138 | 2,494 |
| 75280 | packet | 2 | 7 | 133 |

### Leads, ranked

1. difference: step_rb_s: 10.5 host-h, 57.1 % of the run's
2. difference: step_sfft_catalogs_s: 1.8 host-h, 9.8 % of the run's
3. difference: step_zogy_catalogs_s: 1.5 host-h, 8.2 % of the run's
4. packet: step_forced_s: 0.9 host-h, 4.8 % of the run's
5. packet: step_cutouts_s: 0.6 host-h, 3.4 % of the run's
6. the hosts' vCPU-h are 4.7 times the jobs' vCPU reservation: memory, not CPU, sets the packing, so CPU is left on the hosts
7. idle host time inside the span: 2.2 host-h (7.8 %) - packing and scale-in, not code
8. other runs' jobs on the same hosts: 7.2 host-h (26.1 %)
9. queue wait: difference jobs waited a median 134 s for a host

