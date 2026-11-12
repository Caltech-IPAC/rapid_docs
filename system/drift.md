# The nightly drift gate

**Status: current**

Once a day the rebuilt pipeline runs one injected HLWAS epoch from start to
finish at the newest `rapid-rebuild` revision. It checks the run and compares
six numbers with a spread, a tolerance for each. When a number falls
outside its spread, the gate is red, and the alert topic says so. It exists
because the 2026-10-24 SFFT regression (core fraction +0.252 against
+0.003, false positives 385 against 228 an epoch) merged without anyone
seeing it: the science-drift workflow is a report, and nothing ran
`check_run.sh` on a schedule.

## What runs

The run is epoch 4040101 of the injected footprint `r00342-inj1` (pointing
`001_0001`, SCA 8, F146, 200 injected sources from AB 21 to 27), with the
reference built from passes 1 to 3. That is runs 170 and 172's shape: the
HLWAS overlay with the injected source root, the reference bound 61591.4056,
and the NED and NED-LVS matches off. Each night gets a dataset and run of its
own, `nightly-drift-<UTC stamp>`, and follows [Starting a night](loop) step
for step: the run, made live, the Gaia import of the team's mirror, the
loop, the check, the compare, and the live binding closed.

The revision is the highest ACTIVE `rapid-rebuild` revision when the night
starts. The night checks out the rapid commit that revision records
(`RAPID_RELEASE_IDENTITY`), so the run, its image and the gate's code are one
commit.

The schedule is rapid_systems' operations registry: the `nightly-drift` row,
daily at 06:00 UTC on rapid-admin, running `cloudformation/op-nightly-drift.sh`.
A failed step, a check that does not read CLEAN, or a red column fails the
row. A failed row publishes "RAPID operation nightly-drift FAILED" to the
alert topic, and the night's log on rapid-admin
(`/var/log/rapid/nightly-drift-<stamp>.log`) holds the check line and the
gate's table.

## The columns

`scripts/compare_runs.py --run-a <the previous night> --run-b <tonight>
--spread scripts/drift-spread.toml` prints both runs' rows beside the spread
and judges tonight's. Before the first night, the previous night is run 172.

| Column | What it is |
|---|---|
| packets | the epoch's official packets |
| core | the difference job's `core_fraction` |
| ring | the difference job's `ring_fraction` |
| detected at the threshold | injected sources matched within 0.3 arcsec by an official source whose RuBR-AT score is at least `[packet] rb_threshold` (0.5134) |
| false positives | packets on sources not in the truth, bright-flagged or not (`completeness.py`'s count) |
| difference s | the difference job's `container_seconds` |

A value outside its spread is red, and so is a column the run could not give.
A spread whose two ends are equal is compared for equality.

## The spread

The spread is a tolerance for each column, set while the code changes daily
(Ben, 2026-11-12). It is centred on the nights of 2026-11-11 and 2026-11-12
(runs 230 and 236, `rapid-rebuild:127` and `:131`) and sized to pass
numerical noise while staying far inside the regression the gate exists for.

| Column | Runs 230 and 236 | Spread | Rule |
|---|---|---|---|
| packets | 339 | 266 to 407 | 20 % above the nights, the earlier floor kept |
| core | −0.0000335 | −0.01 to +0.01 | the 2026-10-24 regression read +0.252 |
| ring | −0.009193 | −0.0111 to −0.0074 | 20 % either side |
| detected at the threshold | 159 | 99 to 200 | the earlier floor, to all 200 injected sources |
| false positives | 150 | 95 to 180 | 20 % above the nights, the regression was 70 % up |
| difference s | 152.7 to 167.9 | 0 to 450 | a faster job is never red |

Before this, the spread was the lowest and highest value over runs 152, 167,
168 and 170 (read from SMDC on 2026-11-08), so core and ring were held to
the sixth decimal place. That turned the gate red on three nights running:

| Night (UTC) | Run | Revision | Red columns | What moved |
|---|---|---|---|---|
| 2026-11-10 | 220 | `:123` | core, ring | core −0.0000256 to −0.0000267, ring −0.009220 to −0.009218 |
| 2026-11-11 | 230 | `:127` | packets, core, ring, false positives, difference s | core to −0.0000335, ring to −0.009193, packets 338 to 339, false positives 149 to 150, difference 257 to 168 s |
| 2026-11-12 | 236 | `:131` | the same five | nothing; equal to run 230 but the seconds |

Every check read CLEAN and the detected count stayed at 159. The first step
has rapid PRs 568 to 581 between its revisions, and the second has PRs 582
to 586. Neither step is attributed to one PR: no bisect was run.

The values are in `scripts/drift-spread.toml`. The gate reads the file from
the commit the night's revision records, so an edit takes effect at the
first night after a `rapid-rebuild` revision is registered from a commit
that holds it.

## The first nights

Before the first scheduled night, the row's own runbook was started by hand
on rapid-admin (2026-11-08, 08:39 to 08:51 UTC). It resolved
`rapid-rebuild:109` (rebuild `7cfb6df7`, the commit that added the gate) and
made run 181 under dataset `nightly-drift-20261108T0839`. The Gaia import and
the loop exited 0, and the check read `CLEAN validate 6/6 reader 1/1
consumer 338/338`. Against run 172 the gate was green:

| Column | Run 172 | Run 181 | Spread |
|---|---|---|---|
| packets | 338 | 338 | 266 to 338 |
| core | −0.0000256 | −0.0000256 | −0.0000260 to −0.0000256 |
| ring | −0.00922022 | −0.00922022 | −0.00922022 to −0.00922018 |
| detected at the threshold | 159 | 159 | 99 to 171 |
| false positives | 149 | 149 | 95 to 149 |
| difference s | 252.4 | 261.4 | 226.1 to 350.5 |

The live binding was closed after the compare. The first scheduled night is
2026-11-09 06:00 UTC, and it compares itself with run 181.

The queue item also named a line in Ben's own list beside the topic. That
list is not reachable from AWS, so the topic is the one place a red night is
raised.

## Not yet decided

- A spread from same-revision nights, once the code settles. A week of
  nightly rows would give one, much narrower than the tolerances.
