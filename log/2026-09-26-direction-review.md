---
blogpost: true
date: 2026-09-26
author: rebuild direction pass
category: log
---

# Direction review of the rebuild: findings

The rebuild prototype was complete on 2026-09-25. On 2026-09-26 the lead
asked for a consistency and direction review of the three repositories,
with one test above the others: the system should be designed and
understandable, not evolved and complex. A mechanism the team cannot say
in one plain sentence is a finding, and where two ways of doing one job
exist, the review proposes keeping one. This post records what the
review found, ranked, and what it changed. Mechanical fixes landed as
pull requests; anything that renames, drops or changes behaviour a
caller could depend on is a proposal here, with its cost, for the lead.

The pages this review produced are [operations](../system/operations.md)
(live processing, reprocessing and development together, a proposal) and
[observability](../system/observability.md) (logging, monitoring and job
timing). A read-only Codex review of the combined merged changes found
five code defects and three test or wording faults; all were fixed in one
round (rapid #157, rapid_systems #88).

The review read `rapid` at `rebuild` 31bd8a39, `rapid_docs` at b3ce2b2
and `rapid_systems` at 227ffb1. Codex Astra co-reviewed the
consolidation candidates; its answers are folded in below and attributed
where they changed a finding.

## Ranked findings

| Rank | Finding | Where | Disposition |
|---|---|---|---|
| 1 | Four exit-code vocabularies in one binary: the stage contract's, the tool page's, `release`'s (usage is 2), and a private tuple in `launch/loop.py`; and `argparse` exits 2 on any parse failure from the top-level CLI, where `run status` also uses 2 for "still running" | `stages/contract.py`, `release/hooks.py`, `launch/loop.py`, `cli/main.py` `main()` | Documented as they are ([tool](../system/tool.md)); one vocabulary proposed below |
| 2 | Two input-set binding implementations with the same subtle invariant (bind, commit, then write the manifest last) and different binding rules: the CLI composer binds a manifest's outputs only, the loop's binds outputs and result sets | `cli/runctl.py` `compose_inputs`, `launch/loop.py` `_bind_and_write` | Proposal below |
| 3 | Logs go to stdout, so `run local` interleaves a stage's log lines with its one data line | `log.py` | Fixed: logs on stderr (rapid #154) |
| 4 | Three drifting copies of "find the host, start it, wait for SSM" and two of the account guard, each with bugs the others fixed; `lib.sh`'s `resolve_and_wake` reported success when the host never came online | `rapid_systems` `bin/rapid`, `cloudformation/lib.sh` | Bug fixed with a fixture (rapid_systems #87); one source proposed below |
| 5 | Machine-readable output has three regimes: `loop show --json`, `release` always JSON, everything else text only | the CLI | Proposal below |
| 6 | Flags spelling one concept several ways: `--check-policy` and `--policy`; `--settings` (a location) beside `--settings-overlay-ref` (a record reference); `--stages a,b` beside repeatable `--inputs STAGE=LOC` | the CLI | `check run --check-policy` added as an alias (rapid #153); the rest proposed below |
| 7 | Environment variables with two prefixes for one value (`RAPIDPIPE_IMAGE_DIGEST` then `RAPID_IMAGE_DIGEST`; `RAPIDPIPE_RELEASE` then `RAPID_RELEASE_IDENTITY`), and eleven the code reads that the README did not name | `stages/contract.py`, `db/connection.py`, the stages | Documented in the README (rapid #153); one rule proposed below |
| 8 | Three log-line shapes across the operations scripts (`lib.sh` on stdout with timestamps; thirteen copies of `fail()` in the `op-*.sh` scripts; release hooks on stderr as `<script>: message`) | `rapid_systems` `cloudformation/` | Proposal below |
| 9 | A dead compatibility branch in the loop's promotion (an `inspect.signature` test that is always false) | `launch/loop.py` | Removed (rapid #153) |
| 10 | Page claims that no longer match the code: `load.md` on `dev`'s child-table naming and on clustering; `loop.md` on `--retry-failed`; a production-variable name in `rapid_systems`' workstation page that `rapidpipe` never reads | the pages named | Fixed (rapid_docs #36, rapid_systems #87) |
| 11 | Nothing checks that the image-registry lifecycle rules cannot expire an image an ACTIVE rebuild job-definition revision pins; today none can | `rapid_systems` `rapid-ecr.yaml`, `rapid-batch.yaml` | Static check added (rapid_systems #87) |
| 12 | The house rule against em dashes holds in two repositories and not the third, and 31 of them remain on four system pages | `rapid_docs` system pages, `rapid_systems` | Removed from the four pages (rapid_docs #39); the cross-repository rule proposed below |

## Proposals, with their cost

**One exit-code vocabulary.** Codex's answer, which this review adopts:
0 success; 1 a negative outcome (failed, refused, different); 2
incomplete or still running; 64 usage, configuration or an unmet
precondition; 65 rejected input; 69 not implemented; 70 unclassified
error; 75 retryable (transient, timeout, lock held). It lives in a
package-neutral module, not in the stage runner, and the stage contract
keeps its permitted subset explicit. Replacing today's numeric constants
with the shared names changes nothing a caller sees. Finishing the
unification does: `release` usage and precondition failures move from 2
to 64, the top-level parse failure moves from 2 to 64 (help stays 0),
and `run create` against an incomplete release moves from 2 to 64. Known
dependants: the release tests that assert usage 2, the parser tests that
expect `SystemExit(2)`, and `op-processing-date-loop.sh`, which forwards
the loop's code. The release hook runner maps every non-zero hook result
to release exit 1, so a hook's own codes never reach the caller; that
should stay true through the change. About a day, most of it tests.

**One binding primitive.** Keep both composers, which do different jobs
(the CLI replaces one template entry with one producer's output; the
loop assembles multi-source sets for `maintain`, `crossmatch` and
`alerts`), and move their shared tail into `rapidpipe.runs`: collect the
registered instance ids, bind them, commit, then write the manifest last
and treat an existing manifest as already bound. The id rule should be
the one submission already uses (`runs/inputs.py`
`manifest_instances`). For the CLI that is a behavioural correction, not
deduplication: it starts binding a template's result sets, which it
does not today. Preserve the CLI's refusal of an existing destination,
its reuse path under `run start`, and the order of admission and
copying. About a day.

**One source for the host helpers.** `lib.sh` becomes the home, with
lookup separated from wake: a pure lookup that never starts a machine
(RDP refuses automatic start on purpose), an opt-in wake-and-wait, and
an account guard that prints nothing on success. `bin/rapid` sources it
and keeps passing its profile explicitly, so the guard and the commands
that follow use one identity. `rapid start` and `rapid stop` keep a
clean stdout. The existing resolver fixtures do not cover profile,
stdout or readiness behaviour; those fixtures come first. Half a day
to a day.

**`--json` where a command's output is a record.** Add `--json` to
`run list`, `run show`, `run status`, `run compare` and `check show`,
keeping today's text as the default. `release show` stays JSON. Additive;
half a day.

**One spelling per concept on the command line.** Keep `--policy` as
the alias it now is and make `--check-policy` the documented name;
rename `run create --settings-overlay-ref` to `--settings-ref` with the
old spelling kept as an alias; accept repeated `--stages` beside the
comma form. Additive with aliases; an hour or two.

**One environment rule.** `RAPID_*` names are set by the environment the
code runs in (job definitions, deploy); `RAPIDPIPE_*` names configure
the launcher. The two fallback pairs collapse to the `RAPID_*` name the
job definition already sets, with the `RAPIDPIPE_*` spelling kept as a
local-run override and documented as such. No code change needed to
state the rule; collapsing the pairs is an hour.

**One log line for the operations scripts.** Codex's caution applies:
share one formatter, not one `fail()`. Several scripts' failure
functions close an `ops.runs` row before exiting, and those effects stay
with the script. The line: `<UTC ISO 8601> <script> <LEVEL> key=value
message` on stderr, with stdout reserved for the data a script hands
back (a digest, a row count, JSON lines). The migration markers and the
pins hook's JSON are parsed from remote stdout and are left alone. The
formatter has to work inside the generated SSM documents, which embed
script bodies, so the script's identity is passed explicitly. This is an
output-contract change for `lib.sh`'s callers (the diagnostics leave
stdout, and `PASS:`/`FAIL:` prefixes change), and the broadest of the
proposals for the least mechanism removed: last in line. Two days.

**The em-dash rule.** Either `rapid_systems` adopts the rule for its
prose, or the three repositories agree it belongs to `rapid` and
`rapid_docs` only. The four system pages that broke the site's own rule
are fixed (rapid_docs #39). The lead's call for the rest.

## Simplifications of the design

These go beyond consistency: each removes a mechanism.

- **One recovery path for a failed loop date.** Today `loop run
  --retry-failed` seeds a replacement run when the date has a failed
  unit, and a separate reopen path resumes the same run when it has none.
  One sentence would do: a failed date is recovered by a seeded
  replacement run. It needs new behaviour, not only a removed branch:
  today a seed with no non-complete unit is refused (`SeedRefused`), so
  the seed plan would have to learn to re-run a date that failed before
  any unit existed. About a day.
- **Scratch expiry without warnings.** The warning mechanics were never
  designed (the lead, 2026-09-26). Proposed: none. A scratch run expires
  fourteen days after creation unless pinned, and `run list` and `run
  show` print the expiry date. The first live `run expire` stays the
  lead's, by hand, on or after 2026-10-09.
- **One rule for registration.** The database-writing stages (`load`,
  `crossmatch`, `alerts` and their neighbours) register their result sets
  inside the transaction that writes the rows, while file products go
  through a separate `register` unit, which is why the loop's chain names
  `register` twice. That split is defensible (a result set and its rows
  must commit together; a file stage has no database transaction), so
  the proposal is to state it as the rule in one sentence on the stage
  contract page, not to merge the two paths. Small.
- **One notion of "current".** `vbest` on the `dev` tables and
  `current_selection` both answer "which one do consumers see", and
  promotion maintains both. Consumers moving to `current_selection` is
  already the recorded direction ([products](../system/products.md));
  retiring `vbest` maintenance waits for the team's existing queries to
  move.
- **The transitional cleanup grant.** The workstation role still carries
  the scratch-cleanup permission directly beside the assumed cleanup
  role ([tool](../system/tool.md)); the assumed path is proven, so the
  direct attachment can go.
- **Chain switch as the only non-extending catalog promotion.** The
  operations page proposes it for both reprocessing and corrections
  ([operations](../system/operations.md)).

## Open questions on the pages

Each open item on the system pages, proposed or frozen here. Items that
repeat across pages are grouped.

| Question | Pages | Disposition |
|---|---|---|
| Lead sign-off on a check policy; automatic promotion | checks, specification, tool | Proposed: `rebuild-production@1` on [operations](../system/operations.md); the approval stays the lead's |
| Checks that read S3 | checks | Frozen: no check needs file contents yet |
| Light-curve HATS port, and where exports and light curves are read from | export, photometry | Frozen: a scheduled port; the reader is the delivery adapter, undefined |
| Naming two exports of one field apart; checking a field-versus-source-set mismatch | export | Frozen: no second export exists to name |
| Real deliveries per date; cadence; publishing alerts | loop, specification | Proposed on [operations](../system/operations.md) (discovery, cadence); publishing frozen on the undefined delivery protocol |
| Parallel dates; loop lanes | loop | Proposed on [operations](../system/operations.md) (batches, lanes on the two queues) |
| Reference eligibility, selection, and the field-level resolver | reference, specification, tool | Proposed on [operations](../system/operations.md) |
| Reference PSF source; Photutils reference catalog wiring; `reference_sets` | reference | Frozen: `dev` never wired these either; no caller needs them yet |
| Zero-point handoff from `reference` to `difference` | reference | Closed by the lead's 2026-09-26 ruling, landed with the `difference` change |
| Signing tags or images | releases | Frozen: no consumer verifies signatures |
| The `v1` cutover and the production database as a release target | releases, specification | Frozen: the lead's, at the SMDC cutover |
| The concurrent-cut window | releases | Frozen: one person cuts; the record serialises every other case |
| Registration field lists for remaining kinds | products, stage contract | Narrowed: only `light-curve` remains, with its port |
| Storage layout beneath the attempt | products | Frozen: per-stage member paths are recorded in each manifest, which is what readers use |
| Derived-product logical keys | products, specification | Proposed: identity key and slot on [operations](../system/operations.md), with cost |
| The cross-run reading rule for file products | products | Proposed: the dependency-eligibility table on [operations](../system/operations.md) |
| Mission/RAPID data boundary; admission of duplicate or corrected inputs; a date's boundary | specification | Admission proposed on [operations](../system/operations.md) under stated mission assumptions; the boundary frozen on the mission interface |
| SMDC platform facts; recovery targets; alert payload split; ephemerides | specification | Frozen: SMDC's or the lead's, none blocks the prototype |
| The `smdc` branch inventory and issue triage | specification | Frozen: a discrete pass the specification already schedules |
| Before or after pruning for delivered statistics | stage contract | Frozen: the lead's science call |
| Infrastructure failures to retry | stage contract | Narrowed: `rapid_systems`' ratified spot-and-retry policy states the taxonomy; the page should cite it once public |
| C tool packaging | stage contract | Frozen: the image builds them today |
| Expiry warning mechanics | runs | Proposed: none (above) |
| Workstation cleanup principal; `batch:TerminateJob` for the workstation role | runs, tool | Proposed: drop the direct attachment (above); grant `TerminateJob` in `rapid_systems` |
| Alerts' chain source sets as dependency edges | alerts | Frozen: the reading rule already covers them on read |
| `dev`'s `aid` de-duplication keeps the last row; the rebuild keeps the first | statistics | Frozen: a question for the lead, as the page says |

## Before the cutover

Recorded here so the SMDC cutover has one list. None of these is
started by this review.

- The adopted per-field `dev` tables need a `MAINTAIN` grant, and an
  enumeration of which tables are adopted.
- Production lacks `refimimages` and has an empty `refimmeta`.
- The release's pins step writes `ops.deployed_pins` as the `postgres`
  superuser. The least-privilege login, `rapid_ops_writer`, already
  exists with the grant and a secret the database host can read, so no
  new provisioning is needed; what is not settled is the path, since the
  hook runs on the database host and nothing yet connects from there to
  the pooler. Either confirm that path or dispatch the insert from
  `rapid-admin`, as `op-pin-sweep.sh` does. Not changed by this review
  for that reason.
- The lead's gate before operational use, the real-tool comparison with
  the IMSS reference, has not run; the control image's catalogs differ
  from `dev`'s (below).
- A lead-approved production check policy.
- `batch:TerminateJob` for the workstation role.

## Two images kept

Two images in the pipeline registry are not release tags but are still
pinned by ACTIVE job-definition revisions: `rebuild-844ff2d-20260925`
(`rapid-rebuild:15`, `rapid-rebuild-production:6`) and
`rebuild-f8756a5-20260925` (`rapid-rebuild:18`,
`rapid-rebuild-production:9`). No lifecycle rule can expire them, and
none should while those revisions are active, because a run bound to a
revision must be able to start another attempt. Retiring them is two
steps, both the lead's: deregister the four revisions once no open run
is bound to them, then delete the two images by hand.

## Science verification

**Zero point.** The lead ruled on 2026-09-26 that gain matching reads
`MAGZP` from the reference it is given, with `[awaicgen] zprefimg` an
explicit override only. It landed as rapid #152, with the difference and reference pages
(rapid_docs #38). The `dev`-built control reference carries `MAGZP` 17.0, the old
default, so the control chain's gain matching is unchanged; references
the rebuild builds carry the filter's zero point, which the step 8 demo
had to copy into an overlay by hand.

**The 143707-versus-131427 gap** is a comparison of two different
differencers, not a departure. `dev`'s only difference image for the
control exposure, pid 1105, is its SFFT difference
(`sfftdiffimage_masked.fits`), and the 131427 rows `dev` stored for it are
that attempt's SFFT Photutils catalogs, line for line (115825 positive,
15602 negative); its `nsexcatsources`, 90852, is the SFFT SExtractor
count. The rebuild registers and loads ZOGY. The same `dev` attempt's own
ZOGY catalogs, still in the products bucket, agree with the rebuild's:

| Catalog | `dev` ZOGY | Rebuild ZOGY | `dev` SFFT (what `dev` stored) |
|---|---|---|---|
| Photutils, positive | 84656 | 85104 | 115825 |
| Photutils, negative | 57995 | 58623 | 15602 |
| SExtractor, positive | 21736 | 21749 | 90852 |

Source for source, within 0.2 arcseconds, 99.95% of `dev`'s ZOGY
Photutils sources inside the image have a rebuild counterpart, at a median
separation below a milliarcsecond and a median relative flux difference
near 1e-5. The rebuild finds about 0.5% more positive and 1.1% more
negative sources than `dev`'s ZOGY did; their cause is not verified, and
is consistent with the artifact-repair step `dev` added on 2026-08-20,
which the rebuild ports and `dev`'s 2026-08-09 run predates. Stamping a
field per source changes no row count: it writes one column's value. The
lead's approval of that stamping (2026-09-26) is recorded on
[load](../system/load.md).

Two consequences for the pages. [products](../system/products.md) says ZOGY
registers "as in `dev`", but `dev`'s own run of 2026-08-09 registered its
SFFT difference for this exposure; which differencer `dev` registers is a
question for the lead. And the rebuild's execution records hold `{}` for
resolved settings on these attempts, so the settings a past attempt ran
under could only be recovered here from the overlay files, not from the
database: a provenance gap in the recording, proposed for a fix alongside
the timing groundwork.

A rerun of the control on Batch under the exact-reproduction overlay
(release rebuild-v0.7, job definition `rapid-rebuild:23`, 58 minutes for
`difference`) produced 143714 rows against the earlier 143707, and the
same match against `dev`'s ZOGY catalogs: 99.94% and 99.96% of `dev`'s
positive and negative sources matched, at a median separation below a
milliarcsecond.

**The six findings of 2026-09-12**, checked against `rebuild`:

| Finding | In `rebuild` |
|---|---|
| Currency sweeps compared unrelated identifiers | Fixed: replaced by `prune`, which joins on shared identifiers and never deletes |
| The reference path's read-noise variance lacks the division by gain squared that the science path has | Present, ported unchanged from `dev`, and live at the rebuild's default gain of 2.0; the equivalence check ran at gain 1, where the two agree |
| Ten million unseeded normal samples in every clipped-statistics call | Present by default: a seed setting exists and is off. It also costs run time in `difference` |
| Object statistics: RA wrap, flux sign, mixed filters | RA wrap fixed; dropping the flux sign and mixing filters present |
| Crossmatch not idempotent within a batch | Duplicate rows fixed by uniqueness constraints; the order dependence of chaining is present |
| Coadd inputs re-fetched after the checksum; `NFRAMES` capped at 25 | Re-fetch not applicable (input sets replaced it); the cap fixed |

The present ones are science behaviour and are proposals for the lead,
not changes: each needs a ruling on which side is right before code
moves.

**Runs with no expiry date.** 39 scratch runs and 10 production runs in
the trial database have a null `expires_at`: 27 test-suite fixtures
owned by `brusholme` from 2026-09-23, 12 scratch runs of 2026-09-23 and
24 (two of them pinned control runs), and every production run, which
never expires by design. Proposed: backfill the scratch rows to their
creation plus fourteen days in one migration-free update, run by the
lead; the fixtures then expire with the first attended `run expire` on
or after 2026-10-09, and the pinned control runs stay. Nothing was
deleted or changed.
