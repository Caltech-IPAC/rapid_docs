# System

The specification is the authoritative statement of what RAPID is built
to be on SMDC. It carries equal weight to the code: the pipeline must be
rederivable from it. It is marked **DRAFT** (under iteration; what the
team reviews) or **ADOPTED** (normative). It is DRAFT at present: the
team's review lands at the cutover to SMDC, and nothing becomes ADOPTED
without that review.

The specification replaced the earlier design corpus of seventeen
documents. That corpus described the system that had
accumulated; the rebuild starts from this page. The earlier documents
remain in this repository's history.

## Documents

| Document | Status | Scope |
|---|---|---|
| [`specification.md`](specification) | DRAFT | Purpose and outcome; the pipelines and their stages; the stage contract; runs, the three output states, promotion, attempts and deletion; tools; the three repositories and their boundary; releases; the manifest edges; constraints; sequencing; what is not yet decided |
| [`decisions.md`](decisions) | DRAFT | The team's rulings, one dated line each with its author: Ben's rulings of 2026-09-27, earlier rulings, and the rulings carried from the build pending team review |
| [`products.md`](products) | DRAFT | Product kinds and result-set kinds, logical key versus instance id, bundles, reading across runs, registration metadata with one source per field, one complete worked manifest |
| [`runs.md`](runs) | DRAFT | The run-model tables beside the kept `dev` schema; unit and attempt state machines; instances and the three custody states; promotion under one lock with before and after per key; guarded deletion as the only deleter; storage layout; identifiers |
| [`stage-contract.md`](stage-contract) | DRAFT | The `rapidpipe` package and its dependency direction; the stage declaration, one invocation form, attempts, the manifest, six exit codes, settings; local fixtures; what it replaces |
| [`reference.md`](reference) | DRAFT | The `reference` stage as ported from `dev`'s reference pipeline: its input set and selection rule, the awaicgen coadd and SExtractor catalog, the header stamp, identity, the four registration tables, and its settings |
| [`difference.md`](difference) | DRAFT | The `difference` stage as ported from `dev`: its input set, the steps it runs, its outputs, the registration fields and columns, and its settings |
| [`load.md`](load) | DRAFT | The `load` stage as ported from `dev`: its inputs, the child tables, what lands in `sources`, the source-set result set, its settings and exit codes; the `psf` registration block |
| [`maintain.md`](maintain) | DRAFT | The `maintain` stage: the once-per-date CLUSTER and ANALYZE of a `sources` child table moved out of `load`, its `detector-date` unit, its manifest and exit codes |
| [`crossmatch.md`](crossmatch) | DRAFT | The `crossmatch` stage as ported from `dev`: one field's two passes, the catalog a pass reads (base plus delta), the per-field tables and their set-scoped keys, what lands in `astroobjects` and `merges`, the association set, its settings and exit codes |
| [`statistics.md`](statistics) | DRAFT | The `statistics` stage as ported from `dev`: per-object position and flux statistics over an association set's base-plus-delta membership, what lands in `astroobjectsmeta`, the statistics-set result set, its settings and exit codes |
| [`finalize.md`](finalize) | DRAFT | The `finalize` stage as ported from `dev`'s post-processing pipeline: the chain order, the manifest it republishes as new instances, the header stamp, its settings and exit codes |
| [`alerts.md`](alerts) | DRAFT | The `alerts` stage as ported from `dev`'s alert production: the input-set manifest, what it reads from the source, association and statistics sets, the container and the alert outbox, its registration, settings and exit codes |
| [`prune.md`](prune) | DRAFT | The `prune` stage: the not-best merge exclusion ported from `dev`'s `pruneNotBestMerges`, its `pruned-set` result set and `prunedmerges` rows, the run model's own-run exclusion clause, its settings and exit codes |
| [`photometry.md`](photometry) | n/a | Not ported: forced photometry stays `dev`'s `forcedPhotometryForField.py`, and the rebuild carries no photometry stage |
| [`export.md`](export) | DRAFT | The `export` stage as ported from `dev`'s `generateSourceHATSCatalog.py`: the named source sets it reads, the CSV dump and the `hats-import` build, the `catalog-export` bundle and registration, its settings and exit codes; the light-curve catalog is not ported |
| [`releases.md`](releases) | DRAFT | The release tag and record, the `cut` command and its hook contract, migrations at release time, the launcher reading a release instead of a branch, promotion's released-image eligibility, deployed pins, and what is not yet decided |
| [`tool.md`](tool) | DRAFT | The command-line tool `rapidpipe`, every subcommand and its flags, the operations mapped from the specification's Tools sentence onto subcommands, the input-set composer, the tool's own exit codes, personal submission from a workstation, and where it runs |
| [`loop.md`](loop) | DRAFT | The processing-date loop: the operations-registry trigger, the venue and spec it runs from, the production run and stage chain per date, base-catalog binding across dates, promotion, its own records, and release binding |
| [`checks.md`](checks) | DRAFT | What a check is, the two candidate checks and their measurements and bounds, check policies as versioned TOML files, the promotion gate they validate, and automatic promotion's design; the check commands are on the tool page |
| [`operations.md`](operations) | DRAFT | Operations proposals the team has not yet ruled on: what they assume about the mission, three shapes of the run model and the recommended named stream of batch runs, replacement scope and the chain switch, batch cadence against the latency requirement, a proposed production check policy, reference eligibility and selection, staged inputs of a production run, capacity lanes |
| [`observability.md`](observability) | DRAFT | The `rapidpipe` log line and where it goes, the record of an attempt with and without CloudWatch, monitoring with `rapidpipe` alone, queue, execution and orchestration time per Batch job, profiling a stage, and today's job-duration baseline against a 30-minute target |

```{toctree}
:hidden:

specification
decisions
stage-contract
products
runs
reference
difference
load
maintain
crossmatch
statistics
finalize
alerts
prune
photometry
export
releases
tool
loop
checks
operations
observability
```
