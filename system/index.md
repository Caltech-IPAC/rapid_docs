# System

The specification defines what RAPID is built to be on SMDC. It is
authoritative and carries equal weight to the code: the pipeline must
be rederivable from it.

Its status is **DRAFT**: under iteration for the team's review at the
cutover to SMDC. **ADOPTED** means normative; nothing becomes ADOPTED
without that review.

The specification replaced seventeen earlier design documents, which
described the system that had accumulated and remain in this
repository's history. The rebuild starts from this page.

## Documents

| Document | Status | Scope |
|---|---|---|
| [`specification.md`](specification) | DRAFT | Purpose and outcome; the pipelines and their stages; the stage contract; runs, the three output states, promotion, attempts and deletion; tools; the three repositories and their boundary; releases; the manifest edges; constraints; sequencing; what is not yet decided |
| [`decisions.md`](decisions) | DRAFT | The team's rulings, one dated line each with its author: Ben's rulings of 2026-10-22 on what follows the wide-area ramp (housekeeping first, the other filters before injection, the reference bound by `mjdobs`, a reference per dataset, field and filter with the chain in admission order, injection outside the pipeline, the container-side producer last, the `catalogs` key with its dataset, difference outputs trimmed, GBTDS after injection, the PSF from the CRDS ePSF reference, Spot parked), his rulings of 2026-10-21 evening (the instance type recorded with no family pinned; the exercised HLWAS pipeline as the plan in force), his rulings of 2026-10-20 and 2026-10-21 on the foundation, its SMDC step and the night through the chain (latency later, the PSF kind, the read role, the Batch retry), his rulings of 2026-09-27, his rulings of 2026-10-06 on weekly maintenance on SMDC, earlier rulings, and the rulings carried from the build pending team review |
| [`foundation.md`](foundation) | DRAFT | The foundation and the thin chain: runs, jobs, recorded inputs, scientific keys, official bindings and change groups, publish-last; the PSF key's kind and the `catalogs` key's dataset; the decisions with their reasons; the verbs, the `file://` and `s3://` prefixes with the working directory removed after upload, and a job on Batch with its retry rule, instance type, Batch job id and per-stage memory; the thin chain, with the `intake`, `import`, `associate` and `packet` stages, the reader and the publication to Kafka with its consumer check; the eight queries and the team's spatial shapes; the procedure proof; the SMDC procedure, the night run on it (cutover, live loop, campaign, one group making it official, a mid-night replacement, undo) and the HLWAS run from SOC L2 files to the topic (the live run beside the GBTDS one, one pointing, the loop, the ramp to 426 epochs) and the housekeeping after it (bytes, Batch, the pass, the reference bound); the ten validation checks, the script that runs six of them and their outcomes; the night's, the ramp's and the housekeeping's measurements with the disjoint reference's counts; what is not yet decided |
| [`stage-contract.md`](stage-contract) | DRAFT | The `rapidpipe` package and its dependency direction; a stage as `run(job)` and its `JobContext`; settings from the run's body; the manifest; inputs told apart by key, the PSF kind among them; running a job locally, again or on Batch, with its image digest, instance type, Batch job id and peak memory; exit codes, a refusal because the run is not live exiting 0, and the Batch retry of exit 75; `admit` and `finalize`, still on the older contract |
| [`reference.md`](reference) | DRAFT | The `reference` stage on `run(job)`: its scope and `l2files` inputs, the awaicgen coadd and SExtractor catalog in `dev`'s order, the header stamp, the three declared tables and the drawn `rfid`, its settings, and what it measured |
| [`difference.md`](difference) | DRAFT | The `difference` stage on `run(job)`: its scope and four inputs with the two PSF kinds, the ZOGY, SFFT and naive steps in `dev`'s order, the declared `diffimages` row and source set with the drawn `pid`, one differencer published, the gzipped files it keeps and why, its settings and determinism, and what it measured against `dev` |
| [`intake.md`](intake) | DRAFT | The `intake` stage on `run(job)`: one SOC L2 ASDF file under the run's source root, the conversion ported from `dev`, the declared `l2files` row and the `exposures` row of the one SCA that expects it, with the packed `expid`, its settings, and what the ramp measured |
| [`load.md`](load) | DRAFT | The `load` stage as ported from `dev`: its inputs, the child tables, what lands in `sources`, the source-set result set, its settings and exit codes; the `psf` registration block |
| [`maintain.md`](maintain) | DRAFT | The `maintain` stage: the once-per-date CLUSTER and ANALYZE of a `sources` child table moved out of `load`, its `detector-date` unit, its manifest and exit codes |
| [`crossmatch.md`](crossmatch) | DRAFT | The `crossmatch` stage as ported from `dev`: one field's two passes, the catalog a pass reads (base plus delta), the per-field tables and their set-scoped keys, what lands in `astroobjects` and `merges`, the association set, its settings and exit codes |
| [`statistics.md`](statistics) | DRAFT | The `statistics` stage as ported from `dev`: per-object position and flux statistics over an association set's base-plus-delta membership, what lands in `astroobjectsmeta`, the statistics-set result set, its settings and exit codes |
| [`finalize.md`](finalize) | DRAFT | The `finalize` stage as ported from `dev`'s post-processing pipeline: the chain order, the manifest it republishes as new instances, the header stamp, its settings and exit codes |
| [`alerts.md`](alerts) | DRAFT | The retired `alerts` stage as ported from `dev`'s alert production: the input-set manifest, what it reads from the source, association and statistics sets, the container and the alert outbox, its registration, settings and exit codes; its Kafka section points at the foundation's publication |
| [`prune.md`](prune) | DRAFT | The `prune` stage: the not-best merge exclusion ported from `dev`'s `pruneNotBestMerges`, its `pruned-set` result set and `prunedmerges` rows, the run model's own-run exclusion clause, its settings and exit codes |
| [`photometry.md`](photometry) | DRAFT | Forced photometry: the alert-driven measurement inside the `packet` stage, and `dev`'s standalone `forcedPhotometryForField.py`, not ported |
| [`export.md`](export) | DRAFT | The `export` stage as ported from `dev`'s `generateSourceHATSCatalog.py`: the named source sets it reads, the CSV dump and the `hats-import` build, the `catalog-export` bundle and registration, its settings and exit codes; the light-curve catalog is not ported |
| [`tool.md`](tool) | DRAFT | The command-line tool `rapidpipe`, every subcommand and its flags, the operations mapped from the specification's Tools sentence onto subcommands, the input-set composer, the tool's own exit codes, personal submission from a workstation, and where it runs |
| [`loop.md`](loop) | DRAFT | The loop, `rapidpipe loop`: the selection as arguments, one pass's order from intake to Kafka with the listing by the selection, the Batch reconcile and one flush, pending, failed and drained, the reference bound and held fields, the per-field chains in admission order, its exit codes and what it measured; it replaces the run model's processing-date loop |
| [`operations.md`](operations) | DRAFT | Operations proposals the team has not yet ruled on: what they assume about the mission, three shapes of the run model and the recommended named stream of batch runs, replacement scope and the chain switch, batch cadence against the latency requirement, a proposed production check policy, reference eligibility and selection, staged inputs of a production run, capacity lanes |
| [`observability.md`](observability) | DRAFT | The `rapidpipe` log line and where it goes, the record of an attempt with and without CloudWatch, monitoring with `rapidpipe` alone, queue, execution and orchestration time per Batch job, profiling a stage, and today's job-duration baseline against a 30-minute target |

```{toctree}
:hidden:

specification
decisions
foundation
stage-contract
reference
difference
intake
load
maintain
crossmatch
statistics
finalize
alerts
prune
photometry
export
tool
loop
operations
observability
```
