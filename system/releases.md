# Releases

**Status: DRAFT** — under iteration; adoption gated on the validation
tests at the end of this document.

## Purpose

What a RAPID release is, how releases compose from independently
versioned components, how a release is validated, promoted, operated,
superseded, and archived — and how release reproducibility coexists
with deliberately flexible infrastructure.

## The central distinction: scientific identity vs operational substrate

Every element of the running system is one of two things:

- **Scientific identity** — anything that can change a science
  product: application source revision, environment contents,
  package set, container image, machine image, processing
  configuration, record and alert schema versions, reference and
  calibration data identities.
- **Operational substrate** — everything that cannot: instance types
  and counts, network topology, security groups, fleet shape,
  dashboards, alarms, schedules.

The release graph governs scientific identity only. The substrate
stays flexible: it may change at any time without a new release, and
its state is queried live rather than frozen. This resolves the
tension between composable releases and flexible infrastructure by
construction — composition constrains exactly the identity-bearing
artifacts, and flexibility is preserved exactly where identity is not
at stake. The infrastructure definition's own revision is recorded in
the release manifest for operational provenance, but reproducing a
science product never requires resurrecting the infrastructure that
ran it.

Two rules follow. Identity-bearing artifacts are immutable and
content-addressed: image tags are never reused, package repositories
promote atomically, environment archives are digest-named, and a
changed identity is a new version, never an in-place mutation. And a
substrate change that would alter a scientific identity — a new
container, a different environment — is by definition not a substrate
change; it enters through the release graph.

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

A **release** is a manifest binding one version of every component: a
small, immutable, human-readable document of names, versions, and
digests, plus the compatibility statements it was validated under. The
manifest is the release; the artifacts are its bindings. Components
advance independently between releases; a release is a vertex of
tested combinations, not a lockstep version bump of everything at
once.

The manifest is also the source of the public surface: the published
pinned dependency manifest required by the reproducibility boundary is
a projection of the release manifest — derived from it, never
maintained separately.

## Release cycle

1. **Compose.** A candidate manifest binds component versions. Beyond
   the components above it pins the schema migration set, the
   database and extension versions, the Batch job-definition
   revisions, and the task and process specifications — everything
   needed to state what ran, not only what was built.
2. **Validate.** The candidate passes the validation battery (below),
   including a test against a real database with its spatial extension
   and representative detector data, before any promotion.
3. **Promote.** Promotion is a fixed sequence, not a single flip:
   build, scan and sign once; apply backward-compatible **expand**
   migrations; register immutable job definitions; deploy the
   controller and publisher; run a **nonpublishing production canary**
   through transform, acceptance and association; atomically activate
   the release for new admissions; drain work pinned to the previous
   release; and apply **contract** migrations only after the rollback
   window closes. The activation step alone is atomic — the pointer to
   "current" moves in one step, and a failed activation leaves the
   previous release fully in force.
4. **Operate.** The current release runs; the previous release (N−1)
   remains warm as the rollback target.

   **Work stays pinned to its release.** A work unit admitted under a
   release runs, and has its results accepted, under that release even
   as a newer one activates — which is what expand/contract
   compatibility buys: an old worker's result remains acceptable
   during a deployment. Rollback changes the active release **for
   future admissions only**. It never edits completed products and
   never moves in-flight work onto different code, so it is a pointer
   move back, exercised, not theoretical.

   Services and payloads preflight the application and schema contract
   at startup and fail closed on a mismatch, so a version skew is
   refused at start rather than discovered mid-run.
5. **Supersede.** When a release leaves the rollback window (N−2 and
   older), a defined supersession step runs: its bulk artifacts —
   environment archives, container images exported from the registry
   as archive objects, machine images — transition to deep archival
   storage, retained indefinitely as records; its diagnostics follow
   the observability policy's stale-release transition. The manifest
   itself never leaves warm storage: reproducing what ran requires
   the record always, the bulk bits almost never.

A release is superseded, never deleted: any science product remains
resolvable through provenance to a release manifest, and through the
manifest to archived artifacts that still exist.

## Publication regimes

Products derived from commissioning-epoch observations — including
rehearsal runs on real commissioning data — are never promoted to a
community surface (catalog promotion, front-door service, alert
publication) before the Roman Project's public release of
commissioning data. Until then such products remain at team-internal
access, per the Roman commissioning and First Look Observations
confidential-handling and embargo policy; the publication gate is the
control, with no change to storage configuration.

With that release the governing policy switches to NASA SPD-41a open
data: no exclusive-access period for new missions, with a permitted
calibration/validation window of up to six months. The promotion gate
is the same mechanism in both regimes and selects on validation
state, never on scientific content — promotion criteria are the
stated processing success boundary, and non-promotion is publicly
visible through machine-readable flags and rejection reasons in the
catalog. Withholding a validated product on other grounds is outside
this design.

## Validation battery

The policy is tested, not asserted. A candidate release passes:

- **Mission mock** — an end-to-end run against the simulated exposure
  schedule (realistic arrival times, sky distribution, and load
  envelope), with the observability query tests answerable throughout:
  what happened to an attempt, what produced an output, where the
  time went, what is missing.
- **Reproduce-from-manifest** — an environment rebuilt from the
  *published* manifest alone, on clean infrastructure, runs a
  reference job set and matches the release's outputs. This is the
  reproducibility boundary made testable: if the public projection is
  insufficient to reproduce, the release fails validation.
- **Rollback drill** — promote, roll back to the prior release,
  verify the prior release operates; both pointer moves observed in
  the records.
- **Single-component advance** — one component advances while all
  others hold, validating that component contracts are real: the
  release graph is only composable if a new environment under an
  unchanged application is a testable, promotable event.

## Unresolved fork: overlap vs pointer

The consumer-facing interface requires established and replacement
releases to run live concurrently through a migration overlap with
an announced cutover; this document currently models one current
pointer with N−1 warm only as rollback. These are incompatible as
stated. The reconciliation belongs to the release-topology redesign
(composable scoped releases beyond a linear sequence, per the
interface document and its source material); until it lands, neither
model is normative and promotion tooling is not implemented against
either.

## Consequences for infrastructure

The infrastructure carries the mechanisms this policy presumes:
immutable image tags, atomic content-addressed package promotion,
digest-pinned bases, attestation of built artifacts, and a
registry-to-archive export path for superseded images (container
registries have no cold tier; archival means exporting the image as
an object into storage that does). Where a presumed mechanism does
not yet exist, building it is release-policy implementation work, not
a new decision.
