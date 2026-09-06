# External interfaces

**Status: DRAFT** — under team review; not adopted except where a
passage notes otherwise.

## Purpose

The interfaces RAPID consumes and presents: what each contract
promises, what it deliberately does not promise, and the open points
that must close before implementation freezes. Eight interfaces:
SOC input, the live alert stream, the product archive, forced
photometry, user-generated cutouts, processing records, public
operational metadata, and the consumer-facing release interface.
Internal design (pipeline stages, workflow state, database access)
belongs to the operations, observability, and database documents;
release composition and validation belong to the release document.

## SOC input

The SOC owns calibrated science images. RAPID consumes individual L2
SCA products — the 18 SCAs of an exposure independently, never waiting
for a complete exposure. Each becomes its own admitted observation
and, once its references are pinned, its own difference work unit over
an exposure-detector subject.

- Initial operations expect SOC ASDF input, converted by RAPID to a
  FITS processing representation. Native ASDF processing is a
  modernization topic, not an operational prerequisite.
- An input's identity is its logical SCA identity plus immutable SOC
  version or checksum evidence — a filename is not an identity or an
  idempotency key.
- Inputs are validated (schema, integrity, required metadata) before
  scientific processing. An invalid SCA is quarantined without
  blocking unrelated SCAs, recorded internally, and reported to the
  SOC outside the public alert stream. An unchanged invalid object is
  not re-retried; a new SOC version makes the logical SCA eligible
  again.
- Inputs must carry an explicit schema/format version; the contract
  is never inferred from filenames or incidental structure. During
  commissioning, old and new input versions may be supported
  concurrently for short, case-dependent transitions.
- RAPID processes from SOC-controlled storage without creating a
  durable copy of the original object; local caches are disposable
  and never authoritative. The converted L2 FITS representation is
  durably archived through at least the first supported release;
  long-term retention is open. Converted inputs are internal
  artifacts, not public products.
- RAPID does not require the SOC to preserve every exact L2 version
  a release used; if a version disappears, exact reproduction from
  that input is accepted as impossible. This is a deliberate bound
  on the reproducibility boundary, not an oversight: reproducibility
  is promised from RAPID's published manifests given mission-archived
  inputs; where the mission itself supersedes an input version,
  bit-exact reproduction of the superseded processing is not
  promised. Input custody is upstream's; RAPID's obligation is exact
  identification (version/checksum) of what it consumed.
- Before the first supported release, a new SOC version of a logical
  SCA may trigger automatic reprocessing; after it, SOC replacements
  enter a controlled release/reprocessing path rather than silently
  changing the active release.

Whatever mechanism carries availability, the contract it must satisfy
is fixed: the source is durable and replayable, so that RAPID can
resume from a checkpoint rather than depend on having caught a
notification. Admission is idempotent — a repeated observation returns
its existing admission, so re-delivery is always safe and never
required for correctness. A source that cannot replay needs a durable
buffer in front of admission. An input is never lost because RAPID was
unavailable when it arrived.

Open: the availability-notification mechanism itself (notification,
manifest, or poll — all three can satisfy the contract above, so the
choice is operational fit; bucket-watch is the likely model, not an
agreed interface, and whether object creation suffices or a readiness
marker is required is undecided); the visit-completion marker;
handling of late, corrected, and versioned arrivals; and the
cross-account access arrangement, which is requested and awaiting
confirmation.

## Live alert stream

Kafka is the hot interface, not the archive. Kafka-native is a hard
requirement rather than a preference: the alert format follows the
established community schema, which rules out the cloud provider's
non-Kafka streaming and queueing services.

**Substrate.** A provisioned three-broker cluster across three
availability zones with replication factor three, in the consensus
mode that removes the separate coordination service. Provisioned beat
serverless on cost at RAPID's low and latency-relaxed publication
rate. Authentication on the internal bus is identity-based, using the
cloud provider's own identity service rather than passwords or
certificates.

Public distribution runs on a **separate cluster** and is a later
phase. This is not a deferral of convenience: public accessibility is
fixed when a cluster is created and cannot be switched on afterwards,
so the private cluster can never become the public one. The ingress
pattern for that public tier is not settled and depends on what the
hosting environment permits.

**Access.** Authenticated, by request; no anonymous consumers. The
administrative unit is an organization (organizational credentials,
likely network allowlists); established brokers first, possibly
research organizations later. Roman data carry no proprietary
boundary, so an approved organization may read the complete stream —
topics route and bound volume, they are not authorization boundaries.
Access complies with SMDC security policy.

**Topics and retention.** The namespace distinguishes RAPID release
and Core Community Survey, with a bounded time component; concurrent
releases use separate namespaces during overlap; no topic spans the
mission. Time partitioning is provisionally by publication time
(daily UTC partitions are a candidate; empty periods acceptable).

Hot retention is required to be two months, set at project level. It
must in any case exceed the time to make the archived alert
representation verifiably accessible — hot alerts are never retired
before their archive demonstrably serves them, which makes the archive
a precondition for shortening retention rather than an alternative to
it. Holding the full two-month window entirely on the brokers is
expensive enough that the split between broker-held and archive-held
retention is a live cost decision, settled once the archive cadence
is. That window also sets the replay floor for checkpoint-and-replay
and bounds backlog retention.

Open: the archived representation's writer, retention policy, and
ownership. Until they are decided, anything not archived is lost when
it ages out of the broker — including embedded cutouts, which cannot be
recovered from a recomputed context. Either the archive path is
completed or the loss beyond the retention window is accepted
explicitly; it is not something to leave implicit.

**Latency.** No formal public latency requirement exists. The
operational objective is to add no substantial delay after an L2 SCA
becomes available; one hour for ~95% of ordinary observations
(Galactic plane excluded) is a development target, not a guarantee.
The clock runs from SCA availability to alert publication, retries
and queueing included, measured per stage as well as end to end.
Late results enter the live stream only while useful — provisionally
one day after L2 availability; later completions go to the database
and archive only. The stream never publishes failure or gap
messages; it is the best set of alerts producible at the time, with
missing results documented through archival and operational
metadata.

**Who writes the stream.** The publisher alone. Alerts reach the
stream only through the transactional outbox and the publisher's
identity, which holds the sole broker credential; no pipeline job
performs an external side effect. Deliveries carry deterministic
idempotency keys, and an ambiguous broker acknowledgement is answered
by resending the identical packet with the identical alert identifier
rather than constructing a new one — the at-least-once contract below
is the consequence of that choice, not a substitute for it.

**Alert packets.** Immutable once published: no supplements,
corrections, or re-issues — later knowledge appears in later alerts
and archival products; a correction is a new linked event. Each published message carries a schema-version
header ahead of its payload, resolved against a schema registry, so a
consumer reads the packet's contract from the packet rather than
inferring it — and a published alert's schema version is a recorded
fact, not a deployment assumption. Each alert carries three mandatory cutouts
(science, reference, difference; matched triplet, same footprint,
direct pixel slices, fixed dimensions approximating a provisional
one arcminute, gzip-compressed FITS payloads, NaN padding at
boundaries with valid-bounds metadata, fractional detection
coordinates per cutout), its real–bogus score and model version, and
its provenance (release identity, and specialist revision where
applicable). Alert cutouts initially exclude mask and uncertainty planes — a
live-packet size trade-off only, never archive policy. Positive and
negative difference-residual detections share one candidate and
alert schema and one topic model: signed measurements distinguish
them, and both signs associate with the same persistent object
identity. Field naming follows Roman conventions first, then
Rubin, then ZTF; a field that differs subtly from a Rubin field is
visibly differently named. Established fields are never removed,
reinterpreted, or silently renamed within a release; new fields may
be appended.

**Persistent astronomical-object identity** is a release-independent
identifier for the inferred astronomical object — not for
detections, measurements, or associations, which may change between
releases. It is a wanted, unresolved interface commitment: split,
merge, ambiguity, and release-transition semantics are undesigned
(a hierarchical identifier that represents splits by child terms is
attractive; the community comparator's system should be studied, not
copied). Alert and catalog identity fields stay provisional until
this design lands.

Open: topic partition design and schema-evolution mechanics; packet
size versus cutout target; archived-representation cutout treatment
(strip, store separately, or regenerate); the cutout pixel-origin
and centering convention (drives odd-versus-even dimensions);
persistent-identity semantics as above.

## Product archive

**Scope.** As much scientifically useful material public as
practical. The supported current dataset emphasizes alert-referenced
products and what is needed to interpret them. Publication follows
the atomic SCA-level success boundary: a failure inside that unit
(difference-image construction, source extraction, or the SCA health
gate) keeps the image and catalog internal — a downstream anomaly
may indicate the image itself is bad; a candidate-level failure
after the unit promotes (forced photometry, cutouts, alert assembly)
drops only that candidate while the promoted image and catalog stay
public. Limitations and failures of published products are visible
in image metadata and mirrored as searchable catalog fields. Archived images are complete
— uncertainty, mask/data-quality, and other necessary extensions
stay with the image (plane-stripping is a live-cutout trade-off,
never archive policy). PSF models and other auxiliaries are separate
products; an image's provenance names the exact immutable
auxiliaries used.

**Identity and the current view** (ADOPTED, via the storage design).
Object keys are immutable and identify a particular processing
result; reprocessing creates new objects. A catalog identifies the
supported current result; users discover and resolve through the
catalog — bucket traversal is not a supported interface, and no raw
listing is exposed. Numeric path/identifier components are
fixed-width zero-padded. Validated reprocessed subsets are promoted
to the current view atomically; the promotion unit is an immutable
manifest per the storage design. The catalog's architecture remains
undesigned; Glue Data Catalog is excluded from the baseline.

**Format.** FITS is the processing and public-image baseline through
early mission; a FITS→ASDF transition, if made, has a short overlap
and one long-term supported format. A format change does not itself
constitute a scientific release, but a release stays internally
consistent in format where practical.

**Durable ownership.** Deliveries to MAST are regular (provisionally
monthly) and incremental — additions and replacements with a
manifest distinguishing them and naming superseded products. MAST
behavior (retention of superseded products, atomicity of exposure)
is never assumed. If MAST holds the durable product, RAPID-held
copies are disposable caches; where MAST will not accept a product
or format, RAPID remains its durable host for the release's
supported lifecycle. Removal of superseded RAPID-hosted products
requires a verified accessible replacement and an announced grace
period — and the replacement must preserve the ability to interpret
and reproduce results derived from the prior immutable product, not
merely occupy its place. File sizes and cryptographic checksums are published
wherever practical.

**Public access and cost.** Maximize unauthenticated access subject
to cost and abuse controls; ordinary discovery and retrieval are
catalog-mediated. The long-term model inherits Roman-wide access,
security, and cost policy through MAST and the Roman Research Nexus;
until those paths accept RAPID products, the RAPID-operated
catalog-mediated download path is a production system, not a
best-effort convenience. Bulk use may take a distinct authenticated
path. No public availability guarantee is made; availability
objectives are internal, measured across the integrated task (query
catalog → resolve product → retrieve).

Open: archive volume and durable-archival ownership (institutional,
funding, and policy questions, not just storage design) — the product
store's growth and cost model, its storage-class tiering policy, the
cost of serving scientists directly, and the migration of product data
held under the previous hosting arrangement; the availability target
number; and access-model consultation with the SOC, the archive
partner, and the Nexus before the design freezes.

Specific confirmations are outstanding with the archive partner: that
the community standard product grammar applies, that FITS is
acceptable early in the mission, that ingest can carry a manifest's
logical filename against a differently named stored object, and what
the acknowledgement and idempotence semantics of a delivery are.
Retention and immutability obligations — records requirements, and the
immutability alerts acquire once telescopes act on them — are stated
in neither this document nor the storage design, nor is the product
store's deletion-recovery posture.

## Forced photometry

Alert-driven only: every alert carries a forced-photometry history
for its alerting position, produced as a mandatory stage of alert
production — not by a separate service, and never as an
unrestricted public request service (community demand is effectively
unbounded; users run RAPID-provided capability in the Roman Research
Nexus on their own allocations).

- The history covers every applicable Roman filter; the target is a
  complete mission-to-date history per alert where packet size,
  latency, and cost allow, with the accepted fallback of a bounded
  recent history plus a stable reference to the complete archived
  result.
- Measurements are taken at the detection's measured coordinate on
  difference images only (the object's canonical coordinate serves
  association, not measurement; science-image photometry is SOC
  territory). Results are not assumed reusable between alerts.
- Histories retain every attempted measurement including
  non-detections (a measured flux with uncertainty and quality,
  never an omitted row). Forced-photometry history and
  astronomical-object light-curve history are separate alert
  components. Rows are ordered by observation time; each alert
  records the processing-time cutoff defining its immutable
  snapshot, and does not wait for out-of-order observations.
- On failure after bounded retries, the affected candidate drops
  from live alerting (no partial alert, no follow-up supplement);
  other candidates from the SCA proceed. Dropped candidates remain
  eligible for archival processing without retroactive live alerts.
- A release's mission-to-date history is internally homogeneous: a
  new release recomputes applicable earlier measurements under its
  own baseline before its live stream begins, and each overlapping
  stream carries its own release's history.

Open: history depth/representation in the packet; which
observations and filters are "applicable"; missing-data behavior and
coordinate semantics; archived-result identity for the
complete-history reference; motion-aware forced photometry (wanted
eventually, not early-mission); automatic photometry over a
common-target catalog (future topic — prior art exists in
continuously updated precomputed-light-curve services; no defensible
target catalog or cost model yet).

## User-generated cutouts

The SOC owns cutouts from calibrated science images; RAPID keeps its
reference and difference products usable as cutout inputs. The
preferred experience is one consistent capability in the Roman
Research Nexus dispatching across SOC and RAPID holdings without
erasing that responsibility boundary. The Nexus team operates the
shared user-facing capability; RAPID supplies and validates the
adapters for its products, and does not operate an unrestricted
public cutout service — generation runs in the Nexus on user
resources, outputs belong to the user's workspace, and limits follow
Nexus policy. Generated cutouts default to complete scientific
products in the source's native format; lighter or converted output
is an explicit user option. The alert-cutout production path is
wholly RAPID-owned, independent of the Nexus service, sharing a
cutout library only where performance and scientific-output needs
are met.

Open: evaluation of the incumbent SOC-associated cutout tool at
RAPID batch scale before adopting or replacing it.

## Processing records

Processing outcomes are per-stage, not binary: difference-image
creation, catalog creation, alert construction, publication, and
archival each have distinct recorded outcomes. The internal
operational database is the complete queryable processing record and
is not a public service; under the observability policy the
immutable attempt records remain the terminal-result authority — the
database indexes and references them, it does not compete with
them. Public products carry a structured processing-history
artifact — approved scientific provenance, versions, warnings, and
useful diagnostics; raw infrastructure logs stay internal so
credentials and network details cannot leak. Every promoted SCA has
a complete public source-extraction catalog (every retained
threshold crossing with deterministic cut flags, machine-readable
rejection reasons, real–bogus score and model version, and live
eligibility status) — public access is not limited to what alerted.
Selected problem status and reason summaries may be exposed; the
internal triage record is not.

A separate public dataset: validated, versioned releases of the
labeled real–bogus corpus, so brokers and researchers can evaluate
and build classifiers — each example with its three cutouts,
engineered features, reviewed label, and model scores; every model
release names its exact training-corpus version and publishes
held-out metrics broken down at least by survey and residual sign.
External labels are candidate evidence, reviewed before admission.

Open: the public catalog format (selected with the archive partner
against access, evolution, performance, and cost); detection
identifiers shared between catalog rows and alerts (revisited with
the persistent-identity design).

## Public operational metadata

Selected operational metadata is published periodically as one
rolling downloadable SQLite file that replaces its predecessor —
never an accumulation of similarly named snapshots. Candidate
content: observation/pointing history, inputs received, stage-level
outcomes, timing and summary statistics, and identifiers/links for
archived products. The artifact identifies its generation time, data
cutoff, RAPID release, and export-schema version. Weekly is the
provisional cadence, adjustable with generation cost and
demonstrated use.

Open: the export schema; its relationship to the product catalog
(whether the rolling artifact is the initial catalog or a distinct
one is needed).

## Release interface

What consumers see of the release machinery (composition and
validation are the release document's subject):

- Concurrent live streams during migration overlap, in separate
  topic namespaces; an announced cutover deadline; consumers choose
  their moment. Provisional overlap: about three months, bounded by
  the cost of indefinite parallel operation.
- Pre-release products (synthetic alerts, commissioning-derived and
  Early Science products) are distributed as they become useful,
  explicitly at consumer risk, with no stability or compatibility
  promises.
- Within a release: appended fields possible, established fields
  never removed, reinterpreted, or renamed; the alert schema stays
  responsive between releases.
- Every release ships concise release notes (what changed,
  compatibility and migration effects, validation summary, known
  limitations), published through the public documentation; material
  later findings arrive as append-only errata, never as rewritten
  notes. Consumers monitor a subscribable feed covering releases,
  errata, compatibility and schema changes, and retirement notices —
  RAPID does not push notifications directly.
- Every release exposes its lifecycle state and transition
  timestamps machine-readably; the minimum public states are
  validating, approved, live-parallel, primary, retired-hot, and
  archive-only.
- Alerts and archived products record base release identity and,
  where applicable, specialist revision as separate provenance
  fields.

Open: release naming; the feed platform; overlap-duration policy per
transition.

**Unresolved fork with the release document:** this interface requires
established and replacement streams to run concurrently through a
consumer migration overlap, while the release document describes one
current release pointer with N−1 warm only as a rollback target.

The adopted release protocol narrows the fork without closing it. It
activates a release atomically for new admissions and then drains work
pinned to the previous release — but that mechanism governs work in
flight across a deployment, bounded by how long in-flight work takes
to finish. A consumer migration overlap is a different quantity,
bounded by an announced deadline and measured in months. One does not
substitute for the other, so the two documents are answering different
questions with the same word.

The reconciliation is therefore either to scope each mechanism to its
own question — drain for deployments, a separately announced overlap
for consumer migrations, in distinct topic namespaces — or to withdraw
the concurrent-stream commitment deliberately, which is a promise to
consumers and cannot lapse by silence. The composable scoped-release
topology subsumes the first. Neither model is normative until this
lands.
