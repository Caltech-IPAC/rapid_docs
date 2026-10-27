# System

The specification states what RAPID is built to be on SMDC. The
[foundation](foundation) page replaced its Runs and Releases sections
and its candidate checks, and where the two differ the foundation page
governs, as the specification's own header says.

A page's status is in its first lines. **DRAFT** marks a page that is
unfinished, carries rulings still pending, or in part describes the run
model the foundation replaced; **current** marks a page whose text was
read against the `rebuild` branch's tip (2026-10-26); **retired** marks the record of a stage retired from
`rebuild`. **ADOPTED** means normative; nothing becomes ADOPTED without
the team's review.

The specification replaced seventeen earlier design documents, which
described the system that had accumulated and remain in this
repository's history. The rebuild starts from this page.

## Documents

| Document | Status | Scope |
|---|---|---|
| [`specification.md`](specification) | DRAFT | Purpose and outcome; the pipelines and their stages; the stage contract; runs, the three output states, promotion, attempts and deletion; tools; the three repositories and their boundary; releases; the manifest edges; constraints; sequencing; what is not yet decided |
| [`decisions.md`](decisions) | DRAFT | The team's rulings, one dated line each with its author: Ben's rulings of 2026-10-24 on the second iteration (the bright-star residual flagged, not fixed; Spot as a probe), the association in the difference job; Ben's rulings of 2026-10-22 on what follows the wide-area ramp (housekeeping first, the other filters before injection, the reference bound by `mjdobs`, a reference per dataset, field and filter with the chain in admission order, injection outside the pipeline, the container-side producer last, the `catalogs` key with its dataset, difference outputs trimmed, GBTDS after injection, the PSF from the CRDS ePSF reference, Spot parked; the other filters as datasets of their own), his rulings of 2026-10-21 evening (the instance type recorded with no family pinned; the exercised HLWAS pipeline as the plan in force), his rulings of 2026-10-20 and 2026-10-21 on the foundation, its SMDC step and the night through the chain (latency later, the PSF kind, the read role, the Batch retry), his rulings of 2026-09-27, his rulings of 2026-10-06 on weekly maintenance on SMDC, earlier rulings, and the rulings carried from the build pending team review |
| [`foundation.md`](foundation) | current | The foundation and the thin chain: runs with settings resolved from three layers, jobs, recorded inputs with the object catalog read at execution, scientific keys, official bindings and change groups, publish-last; the PSF key's kind and the `catalogs` key's dataset; the decisions with their reasons; the verbs, the `file://` and `s3://` prefixes with the working directory removed after upload, and a job on Batch with its retry rule, instance type, Batch job id and per-stage memory; Spot as a probe and its four rules; the thin chain, with the `intake`, `import`, `psf` and `packet` stages, association in the difference job, the reader, the quality gate, and the publication to Kafka from the packet job with the recovery sweep and the direct consumer check; the eight queries and the team's spatial shapes; the procedure proof; the SMDC procedure, the night run on it (cutover, live loop, campaign, one group making it official, a mid-night replacement, undo) and the HLWAS run from SOC L2 files to the topic (the live run beside the GBTDS one, one pointing, the loop, the ramp to 426 epochs) and the housekeeping after it (bytes, Batch, the pass, the reference bound), and the breadth run over the six other filters, one dataset each, and why, the fixes and the second iteration; the ten validation checks, the script that runs six of them, the check script for a run and their outcomes; the night's, the ramp's, the housekeeping's, the breadth run's, the fixes' and the second iteration's measurements, with the null test's residuals labelled as artefacts, the bright end flagged, completeness and purity of injected sources per magnitude, and Spot's first data points; what is not yet decided, cross-band association among it |
| [`datasets.md`](datasets) | DRAFT | The simulations the rebuild reads, one section each (HLWAS r00342, GBTDS r00340, OpenUniverse TDS): their data, their quirks and each quirk's disposition on the dataset's settings overlay, a reader or a recorded line |
| [`measurements.md`](measurements) | current | The hand measurements the code's constants and the dataset overlays cite, one section each with its sample, date and numbers: run 17's difference detections and the quality numbers' constants, the WCS against the stars, the reference image's PSF, the DQ mask at intake, the association's match semantics, the team's query shapes |
| [`stage-contract.md`](stage-contract) | current | The `rapidpipe` package and its dependency direction; a stage as `run(job)` and its `JobContext`; settings from the run's body; the manifest; inputs told apart by key, the PSF kind among them; running a job locally, again or on Batch, with its image digest, instance type, Batch job id and peak memory; exit codes, a refusal because the run is not live exiting 0, and the Batch retry of exit 75 |
| [`reference.md`](reference) | current | The `reference` stage on `run(job)`: its scope and `l2files` inputs, the awaicgen coadd and SExtractor catalog in `dev`'s order, the header stamp, the three declared tables and the drawn `rfid`, its settings, and what it measured |
| [`difference.md`](difference) | current | The `difference` stage on `run(job)`: its scope and three inputs with the science PSF, the reference PSF measured by the job, the ZOGY, SFFT and naive steps in `dev`'s order, the declared `diffimages` row and source set with the drawn `pid`, the association with its objects and memberships, the bright-star footprint flag and the quality numbers, one differencer published, the gzipped files it keeps and why, its settings and determinism, and what it measured against `dev` |
| [`intake.md`](intake) | current | The `intake` stage on `run(job)`: one SOC L2 ASDF file under the run's source root, the conversion ported from `dev`, the check that its science PSF was made from the file's own ePSF reference, the declared `l2files` row and the `exposures` row of the one SCA that expects it, with the packed `expid`, its settings (the reader, the DQ mask, the WCS translation and re-derivation) and the Gaia-offset metric, and what the ramp measured |
| [`psf.md`](psf) | DRAFT | The `psf` stage on `run(job)`: the CRDS ePSF reference a file names, fetched by that name; the fixed reduction to a pipeline PSF; the science kind it declares and the `EPSFREF` the intake checks; its settings; the F146 comparison with `dev`'s copied PSF and the job's measurements; the position, the reference PSF rule and a reference part in the key, not yet decided |
| [`photometry.md`](photometry) | current | Forced photometry: the alert-driven measurement inside the `packet` stage, and `dev`'s standalone `forcedPhotometryForField.py`, not ported |
| [`tool.md`](tool) | current | The command-line tool `rapidpipe`: every command it has on `rebuild` with its flags, what it does not have and what to use instead, its exit codes, and the environment it reads |
| [`loop.md`](loop) | current | The loop, `rapidpipe loop`: the selection as arguments with the passes, one pass's order from the psf submission and hold through intake to the Kafka recovery sweep with the listing by the selection, no field chains, the submission cap and the Spot queue, the Batch reconcile, pending with one automatic rerun, failed and drained, the reference bound and held fields, the per-field chains' history, its exit codes and what it measured, six filters at once among it; it replaces the run model's processing-date loop |
| [`operations.md`](operations) | DRAFT | Operations proposals the team has not yet ruled on: what they assume about the mission, three shapes of the run model and the recommended named stream of batch runs, replacement scope and the chain switch, batch cadence against the latency requirement, a proposed production check policy, reference eligibility and selection, staged inputs of a production run, capacity lanes |
| [`observability.md`](observability) | DRAFT | The `rapidpipe` log line and where it goes, the record of an attempt with and without CloudWatch, monitoring with `rapidpipe` alone, queue, execution and orchestration time per Batch job, profiling a stage, and today's job-duration baseline against a 30-minute target |
| [`backups.md`](backups) | DRAFT | The database's pgBackRest repository read against pgBackRest 2.60 and the S3 documentation: bucket versioning and the noncurrent expiry, the WAL valve with and without asynchronous archiving and what the alarms see when it drops, with the ruling owed, and retention as what the policy keeps, what the repository holds and what has been restored |
| [`migration.md`](migration) | DRAFT | For a team member who knows `dev`: where each of `dev`'s scripts, settings, stages and terms went on `rebuild`, with the reason a page or ruling records; `dev`'s tables mapped to the rebuild's schema; what has no counterpart; the questions for the team's first week |

```{toctree}
:hidden:

specification
decisions
foundation
datasets
measurements
stage-contract
reference
difference
intake
psf
photometry
tool
loop
operations
observability
backups
migration
```

## Retired pages

These pages are not stages the loop runs. The first seven describe modules
retired from `rebuild` with the run model; `finalize` was retired on
2026-10-25 with the older stage contract it ran on, with `admit` (rapid PR 464).
Each is kept as the record of its port.

| Document | Status | Scope |
|---|---|---|
| [`load.md`](load) | retired | The `load` stage as ported from `dev`: its inputs, the child tables, what lands in `sources`, the source-set result set, its settings and exit codes; the `psf` registration block |
| [`maintain.md`](maintain) | retired | The `maintain` stage: the once-per-date CLUSTER and ANALYZE of a `sources` child table moved out of `load`, its `detector-date` unit, its manifest and exit codes |
| [`crossmatch.md`](crossmatch) | retired | The `crossmatch` stage as ported from `dev`: one field's two passes, the catalog a pass reads (base plus delta), the per-field tables and their set-scoped keys, what lands in `astroobjects` and `merges`, the association set, its settings and exit codes |
| [`statistics.md`](statistics) | retired | The `statistics` stage as ported from `dev`: per-object position and flux statistics over an association set's base-plus-delta membership, what lands in `astroobjectsmeta`, the statistics-set result set, its settings and exit codes |
| [`alerts.md`](alerts) | retired | The retired `alerts` stage as ported from `dev`'s alert production: the input-set manifest, what it reads from the source, association and statistics sets, the container and the alert outbox, its registration, settings and exit codes; its Kafka section points at the foundation's publication |
| [`prune.md`](prune) | retired | The `prune` stage: the not-best merge exclusion ported from `dev`'s `pruneNotBestMerges`, its `pruned-set` result set and `prunedmerges` rows, the run model's own-run exclusion clause, its settings and exit codes |
| [`export.md`](export) | retired | The `export` stage as ported from `dev`'s `generateSourceHATSCatalog.py`: the named source sets it reads, the CSV dump and the `hats-import` build, the `catalog-export` bundle and registration, its settings and exit codes; the light-curve catalog is not ported |
| [`finalize.md`](finalize) | retired | The `finalize` stage as ported from `dev`'s post-processing pipeline: the chain order, the manifest it republishes as new instances, the header stamp, its settings and exit codes |

```{toctree}
:hidden:
:caption: Retired

load
maintain
crossmatch
statistics
alerts
prune
export
finalize
```
