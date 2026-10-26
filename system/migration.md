# Moving from dev to the rebuild

**Status: DRAFT**

This page is for a team member who knows `dev` and reads notes, scripts
or queries written against it. It says where each thing they used went
on `rebuild`, why where a page records the reason, and what has no
counterpart. The [foundation](foundation) page states the design these
rows summarise; this page states no rule of its own.

The rows were read against `dev` at `c931b001` and `rebuild` at
`a761ae23` (2026-10-24). A status is **changed** where a counterpart
exists and works differently, **partial** where part of it exists, and
**same** where it carried over as it was. "No recorded reason" means no
page or ruling states why.

## Where each thing went

### Runs, jobs and records

| `dev` | `rebuild` | Status | Why |
|---|---|---|---|
| `vbest` (0, 1, 2) and the `vbest = 2` human lock | official bindings: the `official` table and the `<table>_official` views; a change group with a reason in place of the lock | changed | `vbest` was a second, mutable copy of the truth with its own write path ([foundation](foundation.md#why-it-is-this-way)) |
| `version` column on L2Files, DiffImages, RefImages | the `job` id on every row; two executions over one input coexist | changed | a job replaces a version ([foundation](foundation.md#published-rows-name-their-job)) |
| `ppid`, `pipelines`, `swversions` (`svid`) | the run's `revision` and `settings`, `jobs.stage`, `jobs.image_digest`; the published differencer is the run's `[difference] diff_flavor` | changed | the run's revision and settings record what they recorded ([foundation](foundation.md#why-it-is-this-way)); {ref}`the differencer as a setting <decision-published-differencer>` |
| `ProcReqs`, `reqid`, `PROCREQ` | a `runs` row from `rapidpipe run create`: who, why, revision, the full settings body, survey and dataset | changed | a run is a recipe someone launched for a reason ([foundation](foundation.md#runs)) |
| a `jobs` row per pipeline instance (`jid`, `ppid`, `rid`, `awsbatchjobid`, `reqid`) | a `jobs` row per execution of one stage (`stage`, `scope`, `state`, `batch_job_id`, `attempts`), local and Batch alike | changed | [foundation](foundation.md#jobs) |
| `JOBPROCDATE` and the `<procdate>/req<reqid>/jid<N>/` layout | no processing date; `<RAPIDPIPE_OUTPUTS_ROOT>/<run>/<stage>/<job>/<attempt>/` | changed | bytes are immutable; a retry writes new files and never overwrites a referenced one ([foundation](foundation.md#why-it-is-this-way)) |
| one test database per dataset (`rapidopsdb`, `socsimsdb`, `fakesourcesdb`, ...) | `dataset` in every scientific key; one live run per survey and dataset, all in one database | changed | one live run per survey and dataset, for every stage ([foundation](foundation.md#why-it-is-this-way)) |
| registration stages 3, 6 and 9 (`parallelRegisterCompletedJobsInDB*.py`) and done files | the publisher, at the end of `job run`: one transaction loads the declared rows and attempts the binding; an empty expected product binds nothing unless the stage marks it `empty_ok` | changed | publish last ([foundation](foundation.md#publish-last)) |
| post-processing pipeline (ppid 17, stages 7 and 9: database ids in headers, checksums) | none: `finalize`, never run by the loop, was retired with the older stage contract (rapid PR 464); `pid` and `rfid` drawn by the stage; checksums at publish | partial | no recorded reason; the port of `finalize` is open ([stage contract](stage-contract.md#not-decided-here)) |
| prune (`pruneNotBestMerges.py`, `pruneNotBestSources.py`, stages 16 and 17) | a membership is official when its source set is; nothing is deleted | changed | a superseded source set's memberships leave with it ([foundation](foundation.md#why-it-is-this-way)) |
| `pruneRedundantMerges.py` | the publisher reconciles two jobs' founded objects under per-field locks | changed | two epochs in flight at once are reconciled at publish ([foundation](foundation.md#why-it-is-this-way)); {ref}`association in the difference job <decision-association-in-difference>` |
| `rapid_db.py` writer methods (`add_diffimage`, `start_job`, ...) | `rapidpipe.db.connection` and `rapidpipe.foundation` (the publisher, `official change`) | changed | stages read, compute in memory, and the publisher writes ([foundation](foundation.md#why-it-is-this-way)) |
| hand-written SQL (the Q3C examples in `db.rst`) | `database/queries.sql`, named statements over the `_official` views | changed | joins are on scientific keys, never on another product's row id; spatial queries stay in SQL ([foundation](foundation.md#why-it-is-this-way)) |
| `schema/*.sql`, `migrations/` and `buildDatabase.sh` (PostgreSQL 15.2) | one `database/schema.sql` on PostgreSQL 18, and seven dated incremental SQL files beside it | changed | one schema file, applied fresh ([foundation](foundation.md#why-it-is-this-way)) |
| `DBNAME`, `DBSERVER`, `DBUSER`, `DBPASS` | the `PG*` environment, `RAPID_DB_SECRET_ID`, or the `RAPID_PARAMETER_PATH` tree | changed | no recorded reason; the resolution order is in the [specification](specification.md#constraints) |

### The chain and its scheduling

| `dev` | `rebuild` | Status | Why |
|---|---|---|---|
| the Virtual Pipeline Operator, `virtualPipelineOperator.py` | `rapidpipe loop` | changed | one verb run under a timeout from a host ([loop](loop)) |
| `ingestL2FilesDaemon.py` (every N seconds under a lock file) | the loop's source-root listing and intake submission; no daemon, no lock file | changed | one verb run under a timeout from a host ([loop](loop)) |
| the 18-stage chain, run by the VPO or by hand | `psf`, `intake`, `reference`, `difference` and `packet` as stages of the loop, each pass ending at the Kafka sweep | changed | the run model's database stages were retired with its schema ([stage contract](stage-contract.md#what-this-replaces)); [loop](loop.md#one-pass) |
| wait stages 2, 5 and 8, and the resubmit of infrastructure failures (`n_retry_failed_aws_batch_job`) | the loop's Batch reconcile with one automatic `-rerun`; Batch retries exit 75, which a transient failure exits with; `job wait` exits 0, 1 when a job failed, 2 on timeout | changed | {ref}`Batch retries exit 75 and nothing else <decision-batch-retry>`; custom retries given up on purpose ([foundation](foundation.md#why-it-is-this-way)) |
| the open-loop high-water mark (latest `obsendtime` of a finished request) | the source-root listing against the dataset's published intakes and the run's intake jobs | changed | [loop](loop.md#the-selection) |
| `STARTDATETIME`, `ENDDATETIME` | `--pointings`, `--passes`, `--filters`, `--scas`, or a source root of chosen files; no datetime range | changed | no recorded reason |
| `[VPO_SETTINGS]` (`min/max_elapsed_observation_seconds`, `open_loop_sleep_seconds`, `l2file_settle_seconds`) | `loop --interval`, `--max-intake`, `[batch] max_submissions_per_pass`; no settle rule | partial | no recorded reason |
| `RUNFID`, `NUM_CORES`, `DRYRUN` | `--filters`; per-stage `[batch.memory_mib]`; no dry run (`loop --once` submits) | partial | no recorded reason |

### Intake and inputs

| `dev` | `rebuild` | Status | Why |
|---|---|---|---|
| `ingestL2Files.py` | the `intake` stage: `dev`'s `build_fits_file` conversion, writing under the outputs prefix and declaring `l2files` and `exposures` rows | changed | stages read, compute in memory, and the publisher writes ([foundation](foundation.md#why-it-is-this-way)); [intake](intake) |
| `RAPIDL2INPUTBUCKET`, `RAPIDL2OUTPUTBUCKET`, `RAPIDDATASOURCE` | `[intake] source_root` (a `--set` at `run create`), `RAPIDPIPE_OUTPUTS_ROOT`, `[intake] program_id` and `reader` | changed | no recorded reason; [where outputs live](foundation.md#where-outputs-live) |
| `db_register_socsim_files.py`, `db_register_rimtimsim_files.py`, `db_register_troxel_sim_files.py` | intake readers `soc-l2`, `openuniverse` and `rimtimsim`; no Troxel reader | partial | [datasets](datasets.md#rimtimsim-2026-06-22) for the RimTimSim reader; no recorded reason for Troxel |
| `db_backfill_*` (limmag, overlapfields, hp6, hp9) | computed by the intake before publish | changed | a later correction is a new job's row, rebound ([foundation](foundation.md#why-it-is-this-way)) |
| `db_register_sciimg_psfs.py` (a copied WebbPSF in `PSFs`) | the `psf` stage from the file's CRDS ePSF reference, kind `science` or `reference` in the key; `import` can still bring `dev`'s | changed | {ref}`the PSF from the ePSF reference <decision-psf-from-epsf>`; {ref}`the PSF kind <decision-psf-kind>` |
| commissioning's DQ mask (`dqMaskSubs.py`, `DQMASKBITS`) | `[intake] dq_mask_bits`, default 0 as `dev`; the overlays set `0x2110C01` | changed | the measurement is in the overlay's comment ([intake](intake.md#settings)) |
| the `Exposures` observation-id columns (`pass`, `segment`, `observation`, `visit`, `exposure`, ...) | the same columns, `dev`'s names and types, written by intake from the converted header and carried into every packet; a packed `expid` parsed from the stem and checked against the file; `program_id` kept; `--pointings VVV_EEEE` | changed | the `expid` and the packet fields ([intake](intake.md#declared-outputs)) |
| the `Fields` table and the `romantessellation` sqlite file | the `fields` table; the tessellation in closed form | changed | the static tables stay plain tables; the tessellation is computed ([foundation](foundation.md#why-it-is-this-way)) |
| in-pipeline fake-source injection (`[FAKE_SOURCES]`, `inject_fake_sources_into_l2_asdf_files.py`) | `scripts/inject_dataset.py` writes an injected dataset; the in-pipeline flag is refused | changed | {ref}`injection outside the pipeline <decision-injection-outside>` |

### References, differences, sources and objects

| `dev` | `rebuild` | Status | Why |
|---|---|---|---|
| `launchBunchOfReferenceImagePipelines.py`; `RefImages`, `RefImImages`, `RefImCatalogs`, `RefImMeta` | one `reference` job per dataset, field and filter; a 9100 px mosaic graded with `dev`'s status and InfoBits; `refimages`, `refimimages`, `refimcatalogs`; `RefImMeta` reduced to `nframes`, `cov5percent` and manifest metrics | changed | {ref}`a reference per dataset, field and filter <decision-chain-admission-order>`; [reference](reference) |
| `STARTREFIMMJDOBS`, `ENDREFIMMJDOBS` | `[reference.selection] before_mjd` (a `--set` per run) and `min_frames`; an upper bound only | partial | {ref}`the reference bound by mjdobs <decision-reference-bound>` |
| `DiffImMeta` (`scalefacref`, `dxrmsfin`, `nsexcatsources`, ...) | metrics in `jobs.manifest`, read through the `job_metrics` view and `scripts/inspect_run.py`; the quality gate reads them | changed | no recorded reason for the table's removal; {ref}`the gate on lost sky and misregistration <decision-gate-coverage-registration>` |
| `Sources` from the SFFT difference image's PSF-fit catalog (since 2026-04-20) | `sources` from the published differencer, `[difference] diff_flavor`, shipped `sfft` with `dev`'s prefilter, as `dev`; ZOGY runs in every difference job, its catalogs kept as diagnostics, and `zogy` publishes it | changed | {ref}`the SFFT default <decision-sfft-default>`; {ref}`the HLWAS SFFT block <decision-hlwas-sfft-block>` |
| `Sources`: every row above the prefilter | `[difference] max_sources = 500`, the brightest by fluxfit over fluxerr; under `sfft`, `dev`'s prefilter first | changed | no recorded reason for the cap |
| `[DATABASE_PREFILTER]` (`sumrat`, `rb`, aperture S/N) | `[difference.database_prefilter] sumrat_prefilter_threshold` (0.4) and a 2 px edge, applied under `diff_flavor = "sfft"` only; no `rb` and no aperture-S/N cut | partial | {ref}`dev's prefilter under sfft <decision-dev-prefilter>` |
| `sumrat`, `nneg`, `nbad` columns | measured on every SFFT PSF-fit candidate after a 64 px local background; carried on `sources` under `sfft`, null under `zogy` | partial | {ref}`dev's pixel columns <decision-pixel-columns-fail>` |
| `Sources` child tables `sources_<date>_<sca>`, `loadPSFCatIntoDBSourcesTable.py` | `sources`, one source set per (dataset, expid, sca, fid) and job, declared by the difference job | changed | a source is official when its set is ([foundation](foundation.md#why-it-is-this-way)) |
| `AstroObjects_<field>`, `Merges_<field>` | `objects` and `memberships`, append-only; `objects_official`, `memberships_official`; object ids are position hashes that never change | changed | {ref}`association in the difference job <decision-association-in-difference>` |
| `AstroObjectsMeta_<field>` (means, spreads, `nsources`) | sufficient sums in `objects_official`, turned into means and spreads by `rapidpipe.science.statistics.sums` | changed | sums are additive, so the order of arrival does not matter ([foundation](foundation.md#why-it-is-this-way)) |
| `crossMatchSources.py` (a per-field chain, exposures in time order) | association inside the difference job, in memory, against the source's own field and its neighbours | changed | {ref}`association in the difference job <decision-association-in-difference>`; {ref}`by the source's field <decision-association-by-source-field>` |
| `[SOURCE_MATCHING] match_radius` | `[associate] match_radius` at `dev`'s 0.00001528 degrees, with `source_flags` and `min_snr = 5.0` | same | carried at `dev`'s value ([foundation](foundation.md#settings-of-the-thin-run)) |

### Alerts and products

| `dev` | `rebuild` | Status | Why |
|---|---|---|---|
| stage 18 (`produceAlertsForProcDate.py`, `alerts/`; Avro to S3, no Kafka) | the `packet` stage, one packet set per difference image, sent to Kafka as the job's last act, with `rapidpipe publish` as the sweep; schema 00.07, as `dev`, its Roman observation identifiers and `survey` filled from `exposures` and `surveys`, its three reliability fields null | changed | a packet set is per difference image ([foundation](foundation.md#why-it-is-this-way)); {ref}`the producer in the packet job <decision-producer-last>`; {ref}`reliability null <decision-reliability-null>` |
| `alertnames`, `nalertpackets` | the `packets` index: file, byte offset and length per source | changed | an object's alert history is a query over the index ([foundation](foundation.md#why-it-is-this-way)) |
| `forcedPhotometryForField.py` (a CSV of positions in one field) | forced photometry inside `packet`, rows in `forced`; the standalone script is not ported | partial | nothing outside packets needs it yet ([photometry](photometry)) |

### Settings, tools and development

| `dev` | `rebuild` | Status | Why |
|---|---|---|---|
| the `.ini` (`cdf/awsBatchSubmitJobs_launchSingleSciencePipeline.ini`) | `foundation-thin.toml`, a dataset overlay and `--set`, stored whole in `runs.settings` with `runs.layers` | changed | [foundation](foundation.md#runs); a dataset's quirk is a key on its overlay ([datasets](datasets)) |
| `docker run -it --entrypoint bash` into the image, scripts by hand | `rapidpipe` from a Python environment; jobs on the Batch job definition `rapid-rebuild:<revision>`; the repository README's Getting started runs one epoch locally inside the pipeline image against a throwaway PostgreSQL 18 | changed | no recorded reason |
| exit codes 64 and above are errors | `rapidpipe/exitcodes.py`: 0, 1, 2, 64, 65, 69, 70, 75; a tool's nonzero exit fails the job with 70; a transient failure exits 75; `loop` exits 1 for a failed or refused job and 64 when its first pass admits nothing | changed | {ref}`a tool's nonzero exit fails the job <decision-tool-exit-checked>`; [stage contract](stage-contract.md#exit-codes) |
| per-stage `.out` log files in `/work` | one `rapidpipe.log` line shape to stderr, in UTC, which Batch sends to CloudWatch | changed | no recorded reason; [observability](observability.md#the-line) |
| test entries per date (`dev/*_tests.rst`) | `tests/unit`, `tests/db`, `tests/cli`; `scripts/validate_run.py` and `scripts/check_run.sh` per run | changed | no recorded reason |
| branch from `dev`, pull request to `dev` | branch from `rebuild`, pull request to `rebuild`, green CI; a `ported-from:` pin on every ported module, and `scripts/science-drift.sh` listing unported `dev` commits | changed | {ref}`the dev-to-rebuild science flow <decision-science-flow>` |

## What has no counterpart

The rebuild does none of the following. Each is a thing `dev` does
that no stage, script or table on `rebuild` does today.

| `dev` | What it did | Why the rebuild does not |
|---|---|---|
| `avid`, `archiveversions`, `archivestatus` | recorded each product's archive version and delivery state | retention and archive are deferred ([foundation](foundation.md#why-it-is-this-way)) |
| `XSources`, `XMerges`, `XAstroObjects`, `XAstroObjectsMeta`; stages 11, 13, 15 and 17 | loaded SExtractor difference-image detections, cross-matched them and computed their statistics | no recorded reason; the SExtractor difference-image settings remain only for outcome bits |
| `rb`, `rblabel`, the RUBRAT classifier (`[RUBRAT]`) | scored each source real or bogus | no score is computed; the alert fields are stubs marked "not run" ([difference](difference.md#not-decided-here)) |
| redelivery detection (S3 modification time against `l2files.created`) | took in an L2 file again when it was redelivered | no recorded reason; the loop skips a file once the dataset has a published intake of it |
| `socprocs` | recorded SOC deliveries | no recorded reason |
| `generateSourceHATSCatalog.py`, `generateLightCurveHATSCatalog.py`, `[HATS_CATALOGS]` | built HATS catalogs of sources and light curves | the `export` stage is retired, and the light-curve HATS catalog is not ported ([specification](specification.md#sequencing)) |
| `prod/rapid-product-files_*.txt`, `download_files.py`, `download_reqid_products.sh`, `reqid_products_to_csv.sh` | listed and fetched a request's products | no recorded reason; a job's products are in `job show`'s manifest, fetched with `aws s3` |
| commissioning's `stream_l2_files.py` | downloaded a program's L2 files from MAST into the ingest bucket | no recorded reason; the intake reads a source root only, and the flight files held were copied there outside the pipeline ([datasets](datasets.md#flight-data-program-1049)) |

## Schema

Every product table on `rebuild` adds `job` and `dataset`; the rows
below do not repeat them. `dev`'s side is `rapidOpsTables.sql`,
`rapidOpsSourcesTable.sql`, its migrations and the tables its scripts
create per field; `rebuild`'s is `database/schema.sql` and the dated
files beside it.

| `dev` | `rebuild` | Columns | Why |
|---|---|---|---|
| `filters` | `filters` | the same (`fid`, `filter`) | the static tables stay plain tables ([foundation](foundation.md#why-it-is-this-way)) |
| `scas` | `scas` | the same, with a check of 1 to 18 | as `filters` |
| `surveys` | `surveys` | the same; rows -1, -2 and -3 for SOCSIMS, OpenUniverse and RimTimSims | as `filters` |
| `fields` | `fields` | the same | as `filters` |
| `exposures` | `exposures`, `exposures_official` | kept: `expid`, `dateobs`, `exptime`, `program_id`, `execution_plan` and the observation-id columns (`pass`, `segment`, `observation`, `visit`, `exposure`, `visit_id`, `observation_id`; null on rows written before 2026-10-26, no backfill); dropped: `field`, `hp6`, `hp9`, `fid`, `mjdobs`, `status`, `infobits`, `created` | the columns kept are the ones the team's queries read ([foundation](foundation.md#why-it-is-this-way)); the `expid` ([intake](intake.md#declared-outputs)) |
| `l2files` | `l2files`, `l2files_official` | dropped: `version`, `vbest`, `ctype1/2`, `cunit1/2`, the SIP orders and coefficients (the SIP stays in the FITS header), `equinox`, `paobsy`, `pafpa`, `skymean`; `l2filemeta`'s centre and corners folded in; `limmag` and `overlapfields` computed before publish; unique on (dataset, expid, sca, fid, job) | as `exposures`; backfilled columns are computed before publish ([foundation](foundation.md#why-it-is-this-way)) |
| `l2filemeta` | folded into `l2files` | `ra0` to `dec4`, `hp6`, `hp9`, `fid`, `sca`, `mjdobs` live on `l2files` | no recorded reason |
| `refimages` | `refimages`, `refimages_official` | dropped: `ppid`, `version`, `vbest`, `hp6`, `hp9`, `svid`, `avid`, `archivestatus`; added from `refimmeta`: `nframes`, `cov5percent`; `status` and `infobits` carry `dev`'s grade | no `vbest`, no `version`, no `ppid` (`database/schema.sql` header); [reference](reference.md#declared-outputs) |
| `refimmeta` | folded into `refimages` and `jobs.manifest` | kept: `nframes`, `cov5percent`; the rest dropped, some as manifest metrics in `job_metrics` | no recorded reason |
| `refimimages` | `refimimages`, `refimimages_official` | the same (`rfid`, `rid`) | |
| `refimcatalogs` | `refimcatalogs`, `refimcatalogs_official` | kept: `rfcatid`, `rfid`, `cattype`, `filename`, `checksum`; dropped: `ppid`, `field`, `hp6`, `hp9`, `fid`, `svid`, `status`, `created`, `archivestatus`, `avid` | no recorded reason |
| `diffimages` | `diffimages`, `diffimages_official` | dropped: `ppid`, `version`, `vbest`, `hp6`, `hp9`, `svid`, `avid`, `archivestatus`, `nalertpackets`; `rid` and `rfid` kept as lineage, not join keys | joins are on scientific keys ([foundation](foundation.md#why-it-is-this-way)) |
| `diffimmeta` | metrics in `jobs.manifest`, the `job_metrics` view | `scalefacref`, `dxrmsfin`, `dyrmsfin`, `dxmedianfin`, `dymedianfin`, `nsexcatsources` are manifest metrics | no recorded reason |
| `psfs` | `psfs`, `psfs_official` | dropped: `version`, `vbest`; added: `kind` (`science` or `reference`) in the key | {ref}`the PSF kind <decision-psf-kind>` |
| `sources` and its children `sources_<yyyymmdd>_<sca>` | `sources`, `sources_official` | `sid` numbered within the source set, keyed (job, sid); dropped: `npix`, `rb`, `rblabel`; `sumrat`, `nneg`, `nbad` kept, nullable; position, fit and flag columns kept; `flags` bit 14 (16384) marks the bright-star footprint | a source is official when its set is ([foundation](foundation.md#why-it-is-this-way)); {ref}`dev's pixel columns <decision-pixel-columns-fail>`; {ref}`the bright-star flag <decision-bright-star-flag>` |
| `xsources` and its children | none | not ported | no recorded reason |
| `astroobjects_<field>` | `objects`, `objects_official` | one table for every field; dropped: `flux0`; added: `survey`, `field`, the founding job, `ra0` and `dec0` as the founding position; `aid` is a position hash | {ref}`association in the difference job <decision-association-in-difference>` |
| `merges_<field>` | `memberships`, `memberships_official` | `(aid, sid)` becomes (`object_job`, `aid`, `source_job`, `sid`), with `dra`, `ddec` and `flux`, the source's share of the sums | as `astroobjects` |
| `astroobjectsmeta_<field>` | columns of `objects_official` | means and spreads become `sumra`, `sumra2`, `sumdec`, `sumdec2`, `sumflux`, `sumflux2`; `nsources` kept | sums are additive ([foundation](foundation.md#why-it-is-this-way)) |
| `xastroobjects`, `xmerges`, `xastroobjectsmeta` | none | not ported | no recorded reason |
| `jobs` | `jobs` | `rid`, `fid`, `expid`, `sca`, `field` move into `scope`; `awsbatchjobid` becomes `batch_job_id`, `reqid` becomes `run`, `status` becomes `state` (`launched`, `running`, `published`, `failed`); dropped: `ppid`, `machine`, `qwaited`, `elapsed`, `slurm`; added: `image_digest`, `instance_type`, `manifest`, `refusal`, `attempts`, the Kafka offsets | [foundation](foundation.md#jobs); {ref}`the instance type recorded <decision-instance-type>` |
| `procreqs` | `runs` | `reqid` becomes `id`; dropped: `obsstarttime`, `obsendtime`, `started`, `ended`, `elapsed`, `status`; added: `who`, `why`, `revision`, `settings`, `layers`, `survey`, `dataset` | [foundation](foundation.md#runs) |
| `pipelines`, `swversions` | none | replaced by the run's `revision` and `settings` and `jobs.image_digest` | the run records what they recorded ([foundation](foundation.md#why-it-is-this-way)) |
| `archiveversions` | none | not carried | retention and archive are deferred ([foundation](foundation.md#why-it-is-this-way)) |
| `socprocs` | none | not carried | no recorded reason |
| `alertnames` | `packets`, `packets_official` | one row per (packet set, source): `object_job`, `aid`, `source_job`, `sid`, `trigger_mjd`, `band`, `schema_version`, `filename`, `byte_offset`, `byte_length` | a packet set is per difference image ([foundation](foundation.md#why-it-is-this-way)) |
| none | `runs`, `job_inputs`, `official` | new bookkeeping: product bindings (product, key, job) and live bindings (survey, dataset, run), each with who, when, why and group | [foundation](foundation.md#the-foundation) |
| none | `forced`, `forced_official` | a packet set's forced-photometry rows; `dev`'s per-object forced store is not carried | forced photometry is a packet-set output with named inputs ([foundation](foundation.md#why-it-is-this-way)) |
| none | `catalogs`, `external` and their views | reference catalogs (Gaia, NED, NED-LVS, solar-system) as products; Gaia match rows | reference catalogs are products ([foundation](foundation.md#why-it-is-this-way)); {ref}`the catalogs key's dataset <decision-catalogs-dataset>` |
| none | the `job_metrics` view | one row per job and metric, from manifests, container seconds and Batch submissions | no recorded reason |
| roles, tablespaces, grants and stored procedures (`rapidOpsRoles.sql`, `*Grants.sql`, `*Procs.sql`) | none in `schema.sql` | grants live in the infrastructure repository; no stored procedures; the publisher writes | {ref}`the read role <decision-read-role>`; the publisher writes ([foundation](foundation.md#why-it-is-this-way)) |

## Questions for the team's first week

No page settles these. Each is the team's to answer, and the answer
goes on [decisions](decisions) as a ruling.

- **The database.** Which database does the team's work move to, and
  when? The rebuild runs on SMDC's, a prototype
  ({ref}`ruling <decision-smdc-prototype>`); `dev` and commissioning
  use the operations databases. Are `dev`'s tables copied into the
  rebuild's schema for flight data, or does the `import` stage take
  their place?
- **Access.** Who gets which access: the `psql` login, and a
  workstation role to run `loop`?
- **The image.** Which job definition revision does the team start on,
  and who builds the next one?
- **The flight stream.** Does commissioning's flight stream move onto
  the rebuild, with which reader and which overlay, and does the IMSS
  comparison named on [difference](difference) come first? Program
  1049's files are held and no run has read them
  ([datasets](datasets.md#flight-data-program-1049)).
- **The differencer.** The published differencer is SFFT with `dev`'s
  prefilter, as `dev` ({ref}`ruling <decision-sfft-default>`); is
  source-level parity with `dev`, not yet verified, required before
  operational use?
- **The cap.** Is 500 sources per difference image the production
  value, where `dev` keeps every source above its prefilter?
- **Real/bogus and the X tables.** Are real/bogus scoring, the XSources
  family and `dev`'s `rb` and aperture-S/N prefilter cuts ported or
  retired, and who decides? `dev`'s owners of RUBRAT and the X tables
  are the people to ask.
- **HATS and positional forced photometry.** What replaces the HATS
  catalogs and forced photometry on a list of positions?
- **Redelivery.** How is a redelivered L2 file handled? The loop skips
  a file once the dataset has a published intake of it.
- **Partial exposures.** What is the settle rule? `dev` waits
  `l2file_settle_seconds` for all 18 SCAs; the loop admits the SCAs it
  sees.
- **Post-processing.** Does `finalize`'s header stamp return? Does
  anyone downstream need the stamped headers?
- **The schedule.** Who starts the loop each night, and at what
  cadence?
- **Undo.** Who may run `official undo` or a correcting change group,
  and how is it reviewed?
- **Canonical docs.** Which documentation site does a team member keep:
  caltech-ipac-rapid, which serves `dev`'s pages, or this one?
- **`dev` and `main`.** When do they retire, does `dev` work keep
  landing until then, and who ports commissioning-only changes?
- **Time zone.** `dev`'s database runs in `America/Los_Angeles`; the
  rebuild logs in UTC, and its `created` columns are `timestamp without
  time zone`, so they take the database's zone. Which zone does a
  query on SMDC show?
