# Releases

**Status: DRAFT**, under iteration; adoption gated on the validation
tests at the end of this document.

## Purpose

This document defines a RAPID release and its lifecycle, from composing
and validating its components through operation and archival. It also
states which changes require a release and which infrastructure changes
can proceed independently.

## The central distinction: scientific identity vs operational substrate

The release policy divides the running system into two categories:

- **Scientific identity**: anything that can change a science
  product: application source revision, environment contents,
  package set, container image, machine image, processing
  configuration, record and alert schema versions, reference and
  calibration data identities.
- **Operational substrate**: everything that cannot: instance types
  and counts, network topology, security groups, fleet shape,
  dashboards, alarms, schedules.

Releases govern scientific identity. The operational substrate may
change at any time without a new release; its state is queried live.
The release manifest records the infrastructure definition's revision
for operational provenance. Reproducing a science product requires the
recorded scientific components, but does not require rebuilding the
infrastructure that ran them.

Identity-bearing artifacts are immutable and content-addressed. Image
tags are never reused, package repositories promote atomically, and
environment archives are named by digest. A changed identity requires a
new version rather than an in-place mutation. A change that affects
scientific identity, such as a new container or environment, therefore
requires a release even if it is made as part of infrastructure work.

## Composition

A **component** is an independently versioned, independently testable
unit of scientific identity:

| Component | Versioned as |
|---|---|
| Pipeline application | Source revision (tag) |
| Environment | Lock-file set and the archive built from it, by digest |
| Package set | Package-repository state (content-addressed ledger) |
| Container images | Image digests |
| Machine image | Image identifier within its lineage |
| Processing configuration | Configuration digest |
| Schemas | Schema versions (records, alerts) |
| Reference/calibration data | Data-set identifiers |

A **release** is an immutable, human-readable manifest binding one
version of every component. It records their names, versions, and
digests, along with the compatibility statements under which the
combination was validated. Components advance independently between
releases, so a new release can change one component while keeping the
others unchanged.

The published pinned dependency manifest is derived from the release
manifest. It is the public record required for reproducibility and is
never maintained separately.

## Release cycle

1. **Compose.** A candidate manifest binds the component versions in
   [Composition](#composition). It also pins the schema migration set,
   database and extension versions, Batch job-definition revisions, and
   task and process specifications. These bindings record the execution
   configuration alongside the built artifacts.
2. **Validate.** The candidate passes the [validation battery](#validation-battery),
   including a test against a real database with its spatial extension
   and representative detector data, before any promotion.
3. **Promote.** Promotion follows a fixed sequence. Build, scan, and
   sign once, then apply backward-compatible expand migrations,
   register immutable job definitions, and deploy the controller and
   publisher. Run a nonpublishing production canary through transform,
   acceptance, and association before atomically activating the release
   for new admissions. Drain work pinned to the previous release, and
   apply contract migrations only after the rollback window closes.
   Only activation is atomic: the pointer to "current" moves in one
   step, and a failed activation leaves the previous release in force.
4. **Operate.** The current release runs; the previous release (N−1)
   remains warm as the rollback target.

   **Work stays pinned to its release.** A work unit runs and has its
   results accepted under the release that admitted it, even after a
   newer release activates. Expand/contract compatibility keeps the old
   worker's results acceptable during deployment. Rollback moves the
   active-release pointer back for future admissions only; completed
   products and the code running in-flight work remain unchanged. The
   [rollback drill](#validation-battery) exercises this operation.

   Services and payloads check the application and schema contract at
   startup and refuse to run on a mismatch.
5. **Supersede.** When a release leaves the rollback window (N−2 and
   older), its bulk artifacts move to deep archival storage and remain
   there indefinitely as records. These include environment archives,
   container images exported from the registry as archive objects, and
   machine images. Diagnostics follow the observability policy's
   stale-release transition. The manifest stays in warm storage so the
   record of what ran remains readily accessible.

A superseded release is never deleted. Every science product remains
traceable through provenance to its release manifest and from there to
the retained artifacts.

## Publication regimes

Products derived from commissioning-epoch observations, including
rehearsal runs on real commissioning data, are never promoted to a
community surface (catalog promotion, front-door service, alert
publication) before the Roman Project's public release of
commissioning data. Until then such products remain at team-internal
access, per the Roman commissioning and First Look Observations
confidential-handling and embargo policy. The publication gate enforces
this restriction without a change to storage configuration.

After the public release of commissioning data, NASA SPD-41a open-data
policy governs publication: no exclusive-access period for new
missions, with a permitted calibration/validation window of up to six
months. The same promotion gate serves both regimes. It selects on
validation state against the stated processing success criteria,
never on scientific content. Machine-readable flags and rejection
reasons in the catalog make non-promotion publicly visible. This design
does not permit withholding a validated product on other grounds.

## Validation battery

A candidate release passes these tests before promotion:

- **Mission mock**: an end-to-end run against the simulated exposure
  schedule (realistic arrival times, sky distribution, and load
  envelope), with the observability query tests answerable throughout:
  what happened to an attempt, what produced an output, where the
  time went, what is missing.
- **Reproduce-from-manifest**: an environment rebuilt from the
  published manifest alone, on clean infrastructure, runs a
  reference job set and matches the release's outputs. The release
  fails validation if the published manifest is insufficient to
  reproduce those outputs.
- **Rollback drill**: promote, roll back to the prior release,
  verify the prior release operates; both pointer moves observed in
  the records.
- **Single-component advance**: one component advances while all
  others stay unchanged. The test verifies that the component can be
  validated and promoted independently, for example by changing the
  environment while keeping the application unchanged.

## Unresolved fork: overlap vs pointer

The consumer-facing interface requires established and replacement
releases to run live concurrently during a migration overlap, with an
announced cutover. This document instead models one current-release
pointer, with N−1 kept warm only for rollback. The release-topology
redesign must reconcile these incompatible models, including the
composable scoped releases described in the interface document and its
source material. Until that design is settled, neither model is
normative, and promotion tooling is not implemented against either.

## Consequences for infrastructure

This policy requires infrastructure for immutable image tags, atomic
content-addressed package promotion, digest-pinned bases, attestation
of built artifacts, and export of superseded images from the registry
to an archive. Container registries have no cold tier, so archival
requires exporting each image as an object to storage with a cold
tier. Any missing mechanism is implementation work required by this
policy.
