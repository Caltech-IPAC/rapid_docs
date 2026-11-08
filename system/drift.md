# The nightly drift gate

**Status: current**

Once a day the rebuilt pipeline runs one injected HLWAS epoch from start to
finish at the newest `rapid-rebuild` revision. It checks the run and compares
six numbers with a spread recorded from earlier runs. When a number falls
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

The spread is the lowest and highest value of each column over runs 152,
167, 168 and 170, read from SMDC on 2026-11-08. Run 167 stopped before the
packet stage, so its packets and false positives are absent rather than zero.

| Column | 152 (`:94`) | 167 (`:105`) | 168 (`:106`) | 170 (`:107`) | Spread |
|---|---|---|---|---|---|
| packets | 266 | | 338 | 338 | 266 to 338 |
| core | −0.0000260 | −0.0000256 | −0.0000256 | −0.0000256 | −0.0000260 to −0.0000256 |
| ring | −0.00922018 | −0.00922022 | −0.00922022 | −0.00922022 | −0.00922022 to −0.00922018 |
| detected at the threshold | 99 | 171 | 159 | 159 | 99 to 171 |
| false positives | 95 | | 149 | 149 | 95 to 149 |
| difference s | 226.1 | 350.5 | 241.0 | 252.7 | 226.1 to 350.5 |

The four runs span three states of the code. Run 152 predates the uncapped
sources and `max_alerts` 2000 (rapid PRs 529 and 531), and run 167's packets
would have come from `sources` while 168's and 170's come from `xsources`. So
the spread is this sample's range, not one revision's repeatability: runs
168, 170 and 172 agree on every column but the seconds (241.0 to 252.7). The
exact values are in `scripts/drift-spread.toml`. Widening a range is an edit
there, reviewed like any other.

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

- A spread from same-revision nights. A week of nightly rows would give one,
  much narrower than the four runs' range.
