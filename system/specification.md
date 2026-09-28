# RAPID on SMDC: specification

**Status: DRAFT**

This specification replaces the earlier design corpus, retained in the
repository's history. The team owns the design and every ruling recorded
on the [decisions](decisions) page. The team reviews this page at the
SMDC cutover; nothing becomes ADOPTED without that review.

## Purpose

RAPID (Roman Alerts Promptly from Image Differencing) finds transients in
Roman Space Telescope images and issues alerts. It runs today on the
IMSS account and has been partly reworked for its future home, the NASA
SMDC account. That rework accumulated without a design. This
specification defines the replacement's repository boundaries, stage
interfaces and operating rules so all five team members can run,
develop and maintain it.

Existing work is kept only where it serves this specification. SMDC
infrastructure, code and database contents are disposable and recreated
to the specification. The IMSS pipeline is the reference for what the
science stages do.

## Outcome

A team member can run the pipeline on SMDC:

- Run any stage on its own against real or test inputs to develop and
  test that subsystem.
- Run experiments alongside regular operations without disturbing them.
- Leave routine processing to automation, intervening only for failures
  it cannot resolve.
- Deploy, operate and recover the system using the repositories and
  their documented access procedures, without the previous operator's
  instructions.

## The pipelines

The pipelines run at different cadences. These stages come from the
IMSS code and are the ones a new team member meets.

**The processing-date loop**, which regular operations run for each
date's exposures:

1. Admit exposures: register arriving L2 files and their metadata.
2. Build reference images: for each field and filter that needs one,
   coadd earlier exposures.
3. Difference: for each detector image, resample the reference into the
   science frame, subtract, and extract sources. ZOGY is the primary
   differencer, SFFT an optional second.
4. Finalize products: complete headers and checksums.
5. Register results: record each completed job's products in the
   database.
6. Load source catalogs into the database.
7. Maintain: cluster and analyze the date's loaded source table.
8. Crossmatch sources across epochs into objects.
9. Compute object statistics.
10. Prune non-best associations.
11. Produce alerts: one Avro container per detector image.

**Slower and on-demand pipelines**, run outside the loop:

- Reference generation over a chosen sky region and time window.
- Forced photometry for light curves, per field.
- Catalog exports (HATS) of sources and light curves.

### The stage contract

The [stage contract](stage-contract) page defines the full contract,
package layout and exit codes. The outline follows.

Every stage has its own entrypoint and declares its arguments,
configuration, input and output formats, database reads and writes,
resource needs, and exit codes for success and each kind of failure.
Direct invocation and the command-line tool use the same contract.

Each stage declares its unit of work (an exposure, a detector image, a
field, a processing date, or a detector's date) and required upstream
products. The scheduler waits for those products to be complete.
Product identifiers use one documented vocabulary for exposures,
detector images, fields and processing dates.

A stage uses the same command interface on a laptop and on SMDC. Its
local test fixture supplies input files and any database state it needs,
with a documented command that starts those dependencies without account
access. Real data and Batch capacity are the only things that require
being inside the account.

Reference images are immutable, versioned products that record their
constituent exposures. Each differencing job records the exact reference
version it used.

## Runs

A run is one pass of some or all stages over a chosen input set.
Experiments, reprocessing, development, test and regular operations are
all runs. Every product carries its run's name and can be traced to the
run, code, settings, inputs and reference that made it.

A run freezes its input set at creation; later arrivals enter another
run. It records that set, selected stages, code version, settings,
resource profile, scheduling lane, and the person or scheduler that
started it. Work is split into pieces, one per detector image or field.
A piece may be tried more than once, but only a finished try counts.

Runs never write to the same place. They share only admitted inputs and
reference images, which nobody changes.

Resource profiles and scheduling lanes are named configurations with
documented limits and defaults. Scratch runs must not consume capacity
reserved for regular operations. The rebuild does not yet enforce this:
it records a run's lane and resource-profile columns but nothing reads
them. Batch job definitions set capacity
([decisions](decisions)).

### Three output states

Every product has one of three output states:

- **Scratch**: a person's. Never visible to consumers. Deletable by that
  person and expired by policy.
- **Candidate**: the project's, not currently visible to consumers. Its
  verification status is recorded separately.
- **Current**: what consumers see now.

Regular operations produce candidates that become current automatically
when their checks pass under a policy the team has approved for automatic
promotion. Reprocessing produces candidates that a person
promotes after verification. Experiments produce scratch and stop there.
Superseded current outputs return to candidate with their history
retained.

Every run's mutable files and database results are isolated from other
runs. Admitted inputs and reference images are shared and read-only.
Current result sets are readable by any run as frozen inputs, by
instance id, so production can accumulate a catalog across processing
dates; scratch result sets are readable only within their own run.
Changes become visible to consumers only through promotion.

### Promotion

Promotion is the action that makes products live. It names the product
keys it replaces and leaves other current products unchanged. By default
it switches a whole run's outputs together; a person may promote
piecemeal when needed. The selected files and database results become
visible together once their dependencies are satisfied. Conflicting
promotions are refused for review. Each promotion records who did it,
why, and the previous and replacement selections, so an earlier selection
can be restored.

A candidate records its check results and is eligible for promotion
when its policy's required checks pass. A failed or missing check leaves
it a candidate. There is no separate acceptance record; a check that
fails falsely is fixed in the policy file. A dependency is satisfied
when its named instance is current or superseded, or is promoted in the
same request.

The scheduled loop uses the same automatic-promotion gate as a person's
`run start`: the team must have approved the check policy for automatic
promotion. Under a trial policy a date's production run stays a
candidate until a person promotes it
({ref}`loop promotion <decision-loop-promotion>`,
{ref}`acceptance <decision-acceptance>`).

### Attempts, retries and deletion

Each run, unit of work and execution attempt has a unique identifier.
Retrying the same work cannot duplicate committed results, and
incomplete attempts stay invisible. Execution status is recorded apart
from the three output states, and automatic retries have a configured
limit.

Scratch has a documented default lifetime and is deleted only when no
active job depends on it. Cleanup never removes current products or any
input, reference or provenance record that retained project outputs
depend on.

## Tools

The pipeline repo ships one command-line tool, `rapidpipe`. It can
create a run, start a stage or the whole loop, rerun part of a run,
watch progress, cancel and restart from failure, list and compare runs,
promote a candidate, and delete scratch. Each operation reports the
affected run identifier and a meaningful exit status. Each stage is a
plain script callable by the tool or directly by a person.

The interface must follow these operations and the stage contracts,
without using the previous tool as its starting point.
Subcommands are on the [tool](tool) page.

## Repositories

The team uses three standalone repositories. None refers to a person's
private repository, machine or notes.

| Repository | Visibility | Holds |
|---|---|---|
| `rapid` | Public | Everything portable that defines the pipeline: stage code, the launcher that turns a run into Batch jobs, result registration, the database schema and its migrations, the tool that applies them, the command-line tool, the container build recipe and dependency definitions, tests, code documentation |
| `rapid_systems` | Private | Everything that provisions the account: network, roles, the database server, secret-store configuration and references, Batch environments, image build and publish infrastructure, account-specific configuration. Credential values live outside git |
| `rapid_docs` | Public | This specification and the public site |

`rapid` contains portable pipeline definitions; `rapid_systems` contains
account-specific configuration and infrastructure. Account identifiers,
bucket names and hostnames are injected at deploy time, never committed
to `rapid`. A code change and its schema change land in one pull request
in `rapid` and are tested together by CI. A `rapid` release supplies the
source commit; `rapid_systems` builds and publishes the image and records
the resulting digest.

The pipeline repository's development line is `main`. The `smdc` branch
and the two-branch arrangement end with this rebuild.

## Releases

Operations run a tagged version while `main` moves ahead. Release tags
are immutable. Each release records its source commit, image digest and
supported schema versions; each run records the image digest and schema
version it used. Scratch runs may use any commit or a working copy.

A candidate becomes current only if its recorded image is a released
artifact; tagging related source afterwards is not enough. Before
operations move to a release, schema deployment documents migration
order, compatibility with active runs, and recovery. The
[releases](releases) page defines the mechanism, record and command.

## Edges

Each edge has a versioned manifest as its provenance record. Admission
accepts a manifest of input identities, locations, checksums and required
metadata. Delivery reads a manifest of current alert products' identities,
locations, checksums and schema versions.

Today the pipeline's responsibility ends at alert files and their
manifest in the account. MSK is available in SMDC and alerts may also be
written there. External delivery uses only current products and records
attempts against stable product identities. Delivery from the
observatory and to brokers and MAST remains to be determined and does
not drive this design. Those adapters read and write the manifests and
are outside this specification.

## Constraints

- Team of five, part-time on infrastructure. Simple and supportable at
  that scale beats complete.
- SMDC security requirements apply as SMDC states them and are met in
  `rapid_systems`, not worked around in `rapid`.
- PostgreSQL with Q3C remains the catalog store. AWS Batch remains the
  compute.
- Three operational requirements are unresolved: a second Project-Admin,
  notifications reaching more than one team member, and per-user
  shared-storage quotas. Before unattended operations begin, two team
  members hold tested administrative access and receive failure
  notifications.
- The repositories document access, deployment, diagnosis, restart,
  promotion reversal and database recovery. Account-specific instructions
  live in `rapid_systems`.
- Protected branches with required CI checks on `main` in all three
  repositories.
- Latency, provisional until the team confirms or replaces it: each
  detector image's alerts are current within an hour of its delivery,
  typically, with a longer tail accepted for dense fields; RAPID's share
  is kept short against the exposure-to-L2 delay
  ({ref}`latency <decision-latency>`). Per-delivery batches, fan-out
  within a date over detector images, and the difference stage's runtime
  as the binding constraint follow from this number.
- Requirements carried from the retired issue backlog, each still
  binding on the rebuild:
  - The alert stream retains two months at the project level; the
    stream itself is not the archive, so an archive sink with stated
    retention and ownership is required before alerts are published.
  - Backups: no lifecycle rule may expire the newest backup chain, and
    sizing follows a stated classification, cadence and growth model.
  - The product store needs a growth model and tiering; about 60 TB of
    legacy IMSS products and NASA records retention bear on it.
  - Human credential custody and a break-glass procedure for the
    account must be written down and rehearsed.
  - Database connections through the pooler use TLS as a security
    requirement.
  - Long-lived connections must account for the Nitro default
    connection-tracking idle timeout.
  - Database connections from pipeline code (`rapidpipe.db.connection`)
    resolve the endpoint and credential in one order: an explicit
    `endpoint=`/`credentials=` argument first; then the `PG*` environment
    when those variables are set (`RAPID_DB_SECRET_ID` still resolves the
    credential from Secrets Manager ahead of `PGUSER`/`PGPASSWORD`); then the Batch
    estate's `RAPID_PARAMETER_PATH` SSM parameter tree, whose
    `db/server`/`db/port`/`db/name`/`db/secret-id` keys supply the
    endpoint and, via the same Secrets Manager resolver, the credential.
    The environment is never an in-process transport:
    `rapidpipe.db.connection` never writes it for a downstream reader.
  - Platform facts still open with SMDC: address-range collision,
    egress model, IAM PassRole scoping, backup-plan scope and recovery
    path.

## Sequencing

The specification precedes the rebuild. Each part is a pull request
verified by CI and merged by a team member. Proposed order, earliest first:

1. Repository boundaries: move schema, glue and build recipe into
   `rapid`; strip personal tooling and residue from all three repos;
   inventory what the `smdc` branch improved over `dev` (connection
   pooling and logging among them) and keep what stands on its own;
   triage existing issues against this specification, keeping applicable
   requirements and recording why each remaining issue is closed.
2. Stage entrypoints: one runnable script per stage against a local
   fixture, with the test data to exercise it. Each rebuilt science stage
   is compared with the IMSS reference on fixed inputs, and the team
   approves expected differences and tolerances before it enters regular
   operations.
3. Runs, attempts and the three output states in the schema and storage
   layout.
4. The command-line tool over the above.
5. Releases: tagging, image build, the move of operations to a tag.
6. Candidate checks, promotion and recovery, exercised by hand.
7. The scheduled processing-date loop as self-running production, once
   the above have been exercised ([loop](loop) page).
8. Slower pipelines and exports.

Part 1 is partly done: the schema, glue and build recipe live in
`rapid`; the `smdc` branch's inventory against `dev` and issue triage
against this specification remain open. Parts 2 through 8 are prototypes
on the `rebuild` branch, documented here:

| Part | Scope | Pages |
|---|---|---|
| 2 | Stage entrypoints | [stage-contract](stage-contract); [reference](reference), [difference](difference), [load](load), [maintain](maintain), [crossmatch](crossmatch), [statistics](statistics), [finalize](finalize), [alerts](alerts), [prune](prune), [export](export) |
| 3 | Runs, attempts, the three output states | [runs](runs) |
| 4 | Command-line tool | [tool](tool) |
| 5 | Releases | [releases](releases) |
| 6 | Candidate checks, promotion and recovery by hand | [checks](checks); recovery rules on [runs](runs) |
| 7 | Scheduled processing-date loop | [loop](loop) |
| 8 | Slower pipelines and exports | [reference](reference), [export](export) |

The light-curve HATS catalog and forced photometry are not ported, and
the rebuild carries no photometry stage ([photometry](photometry) has
the state). Every part is a prototype pending the team's review at the
SMDC cutover; none is ADOPTED.

## Not decided here

- The team defines the scientific checks that gate automatic promotion.
  The rebuild ships `rebuild-trial@1`, a trial-level policy requiring
  promotion by hand. A team-approved policy and whether it permits
  automatic promotion remain open
  ([checks](checks) page).
- The boundary between mission-supplied data and RAPID-derived
  products, and what each side's retention and provenance owe.
- Admission rules for duplicate, incomplete or corrected inputs: the
  [loop](loop) page's discovery and classification rule defines delivery
  handling (identical re-delivery refused, checksum conflict quarantined,
  a corrected version deferred). The science half of the input contract
  (discovery, completeness, versioning) and a date's boundary in
  wall-clock or observatory time remain open.
- Reference-image eligibility and selection rules, and where the
  reference PSF is resolved from. The [reference](reference) page
  records `dev`'s selection rule as the launcher's to implement; the
  [loop](loop) page's own chain binds a field's reference by a fixed
  template rather than by running that rule. Which reference a field
  should use among several eligible ones is open on the [tool](tool)
  page too.
- Recovery targets per storage family and the stance on failover read
  cost.
- Whether alert payload bytes are split from delivery evidence after a
  retention horizon.
- Churning reference data such as ephemerides: cached at run time or
  baked into the image.
- External delivery protocols. Kafka publication is designed in and off
  by default in the shipped [alerts](alerts) stage; which protocol, if
  any, replaces that default is still open.

Stage contracts and the promotion rules must be approved by the team
before their implementations are accepted.
