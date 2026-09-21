# RAPID on SMDC: specification

**Status: DRAFT**

Written 2026-09-21 from a stepwise interview with the pipeline lead, revised
on a Codex review and on the lead's reading. It replaces the earlier design
corpus, which remains in this repository's history. The team reviews this
page at the cutover to SMDC; nothing becomes ADOPTED without that review.
## Purpose

RAPID (Roman Alerts Promptly from Image Differencing) finds transients in
Roman Space Telescope images and issues alerts. The pipeline exists today
on the IMSS account and has been partly reworked for the NASA SMDC
account, where it will live. That rework accumulated rather than being
designed. This specification defines the replacement pipeline's
repository boundaries, stage interfaces and operating rules so that all
five team members can run, develop and maintain it.

Nothing that exists today is preserved for its own sake. Infrastructure,
code and database contents on SMDC are disposable and are recreated to
this specification. The IMSS pipeline is the reference for what the
science stages do.

## Outcome

A team member can run the pipeline on SMDC. Concretely:

- They can run any single stage on its own, against real or test inputs,
  to develop and test that subsystem.
- They can run experiments alongside regular operations without
  disturbing them.
- Routine processing runs without manual steps. Failures that automation
  cannot resolve require intervention; nothing else does.
- A team member can deploy, operate and recover the system from the
  repositories and their documented access procedures, without
  instructions from its previous operator.

## The pipelines

Several pipelines run at different cadences. The stage list below is
taken from the IMSS code and names the stages a new team member meets.

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
7. Crossmatch sources across epochs into objects.
8. Compute object statistics.
9. Prune non-best associations.
10. Produce alerts: one Avro container per detector image.

**Slower and on-demand pipelines**, run outside the loop:

- Reference generation over a chosen sky region and time window.
- Forced photometry for light curves, per field.
- Catalog exports (HATS) of sources and light curves.

### The stage contract

The full contract, the package layout and the exit codes are on the
[stage contract](stage-contract) page; this section states the rules
in outline.

Every stage has its own entrypoint and declares its arguments,
configuration, input and output formats, database reads and writes,
resource needs, and exit codes for success and each kind of failure.
Direct invocation and invocation through the command-line tool follow
the same contract.

Each stage declares its unit of work (an exposure, a detector image, a
field, a processing date) and the upstream products it requires; the
scheduler starts it only when those products are complete. Product
identifiers use one documented vocabulary for exposures, detector
images, fields and processing dates.

A stage uses the same command interface on a laptop and on SMDC. Its
local test fixture supplies input files and any database state it needs,
with a documented command that starts those dependencies without account
access. Real data and Batch capacity are the only things that require
being inside the account.

Reference images are immutable, versioned products that record their
constituent exposures. Each differencing job records the exact reference
version it used.

## Runs

In plain terms: a run is one pass over a chosen set of inputs, and
everything it makes carries the run's name. Inside a run the work is
split into pieces, one per detector image or field; a piece may be tried
more than once, but only a finished try counts. Every product is in one
of three places: a person's, the project's but not yet live, or live.
Making a product live is a deliberate step, promotion, which says which
live products it replaces and can be undone. Runs never write to the
same place, and share only the admitted inputs and reference images,
which nobody changes. Provenance is the point of all of this: any
product can be traced to the run, code, settings, inputs and reference
that made it.

A run is one pass of some or all stages over an input set. Every run
records its input set, selected stages, code version, settings, resource
profile, scheduling lane, and the person or scheduler that started it.
Experiments, reprocessing, development, test and regular operations are
all runs. A run freezes its input set at creation; later arrivals enter
another run.

Resource profiles and scheduling lanes are named configurations with
documented limits and defaults. Scratch runs cannot consume capacity
reserved for regular operations.

### Three output states

- **Scratch**: a person's. Never visible to consumers. Deletable by that
  person and expired by policy.
- **Candidate**: the project's, not currently visible to consumers. Its
  verification status is recorded separately.
- **Current**: what consumers see now.

Regular operations produce candidates that become current automatically
when their checks pass. Reprocessing produces candidates that a person
promotes after verification. Experiments produce scratch and stop there.
Superseded current outputs return to candidate with their history
retained.

Every run's mutable files and database results are isolated from other
runs. Admitted inputs and reference images are shared and read-only.
Changes become visible to consumers only through promotion.

### Promotion

Promotion is an action, not a place. A promotion names the product keys
it replaces and leaves other current products unchanged. By default it
switches a whole run's outputs together; a person may promote piecemeal
when that is what is needed. The selected files and database results
become visible together, only once their dependencies are satisfied;
conflicting promotions are refused for review. Each promotion records
who did it, why, and the previous and replacement selections, so an
earlier selection can be restored.

Automatic promotion stays off until the lead approves the checks that
gate it. Each candidate records its check results; a failed or missing
check leaves it a candidate.

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

The team touches one command-line tool, `rapidpipe`, shipped in the pipeline repo,
with a small set of operations: create a run, start a stage or the whole
loop, rerun part of a run, watch progress, cancel and restart from
failure, list and compare runs, promote a candidate, delete scratch. Each operation reports the
affected run identifier and a meaningful exit status. Each stage is also
a plain script that the tool calls and a person can call directly.
Design the interface around these operations and the stage contracts;
the previous tool is not the starting point.

## Repositories

Three repositories, each standalone for the team. None refers to any
person's private repository, machine or notes.

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

Operations run a tagged version. Release tags are immutable. Each release
records its source commit, image digest and the schema versions it
supports; each run records the image digest and schema version it used.
`main` moves ahead of the release. Scratch runs may use any commit or a
working copy. A candidate becomes current only if its recorded image is a
released artifact; tagging related source afterwards is not enough.
Schema deployment documents migration order, compatibility with active
runs, and recovery, before operations move to a release.

## Edges

Both edges are versioned manifests, and each manifest is the provenance
record for its side. Admission accepts a manifest of input identities,
locations, checksums and required metadata. Delivery reads a manifest of
current alert products with their identities, locations, checksums and
schema versions. The pipeline's responsibility ends at alert files and
their manifest in the account today. MSK is available in SMDC and alerts
may also be written there; external delivery uses current products only
and records delivery attempts against stable product identities. Input
delivery from the observatory and output delivery to brokers and MAST
are to be determined and are not design drivers; their adapters read and
write the manifests and are outside this specification.

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
- Requirements carried from the retired issue backlog on 2026-09-21,
  each still binding on the rebuild:
  - The alert stream retains two months at the project level; the
    stream itself is not the archive, so an archive sink with stated
    retention and ownership is required before alerts are published.
  - Backups: no lifecycle rule may expire the newest backup chain, and
    sizing follows a stated classification, cadence and growth model.
  - The product store needs a growth model and tiering; about 60 TB of
    legacy IMSS products and NASA records retention bear on it.
  - Human credential custody and a break-glass procedure for the
    account must be written down and rehearsed.
  - Database connections through the pooler use TLS; the pooler's
    posture is a security requirement, not a convenience.
  - Long-lived connections must account for the Nitro default
    connection-tracking idle timeout.
  - Platform facts still open with SMDC: address-range collision,
    egress model, IAM PassRole scoping, backup-plan scope and recovery
    path.

## Sequencing

Specification first, then the rebuild by part, each part a pull request
that CI verifies and the lead merges. Proposed order, earliest first:

1. Repository boundaries: move schema, glue and build recipe into
   `rapid`; strip personal tooling and residue from all three repos;
   inventory what the `smdc` branch improved over `dev` (connection
   pooling and logging among them) and keep what stands on its own;
   triage existing issues against this specification, keeping applicable
   requirements and recording why each remaining issue is closed.
2. Stage entrypoints: one runnable script per stage against a local
   fixture, with the test data to exercise it. Each rebuilt science stage
   is compared with the IMSS reference on fixed inputs, and the lead
   approves expected differences and tolerances before it enters regular
   operations.
3. Runs, attempts and the three output states in the schema and storage
   layout.
4. The command-line tool over the above.
5. Releases: tagging, image build, the move of operations to a tag.
6. Candidate checks, promotion and recovery, exercised by hand.
7. The scheduled processing-date loop as self-running production, once
   the above have been exercised.
8. Slower pipelines and exports.

## Not decided here

- The internal shape of the command-line tool.
- Storage layout beneath the three states.
- The checks that gate automatic promotion: their content is scientific
  and the lead's.
- The boundary between mission-supplied data and RAPID-derived
  products, and what each side's retention and provenance owe.
- Admission rules for duplicate, incomplete or corrected inputs,
  including how a re-delivered observation supersedes the earlier one;
  the science half of the input contract (discovery, completeness,
  versioning); and the processing-date time convention.
- Reference-image eligibility and selection rules, and where the
  reference PSF is resolved from.
- Product identity under concurrent processing: collision, publication
  and replay semantics beyond the science identifier and context stamp.
- Whether a release change overlaps for consumers mid-migration or
  switches by pointer.
- Recovery targets per storage family and the stance on failover read
  cost.
- Whether alert payload bytes are split from delivery evidence after a
  retention horizon.
- Churning reference data such as ephemerides: cached at run time or
  baked into the image.
- External delivery protocols.

Stage contracts and the promotion rules must be approved before their
implementations are accepted.
