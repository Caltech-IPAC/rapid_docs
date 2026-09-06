# Storage

**Status: ADOPTED** — except the open point listed at the end
(disaster-recovery posture), which is marked where it arises.

## Purpose

How RAPID stores everything durable: the classification that derives
the bucket set, the naming scheme, enforced immutability, promotion
and swap mechanics, and the assurance controls. The catalog's
internal schema belongs to the database design; interface contracts
(what consumers are promised) belong to the interfaces design.

## Classification

Every stored artifact is classified on five axes, and storage
structure is derived from the classification:

| Axis | Values |
|---|---|
| Mutability | write-once · append-only · CAS-updated pointer · replaceable current file · replaceable cache |
| Custody | RAPID is durable owner · cache of upstream · durable derived commitment · destined for MAST |
| Retention | permanent · release-lifetime · tiered decay · short fixed window · current-only |
| Audience | community · team · pipeline-internal · ops-only |
| Writer | enumerated, minimal, one authoritative writer per class |

| Artifact | Mutability | Custody | Retention | Audience | Authoritative writer |
|---|---|---|---|---|---|
| Published products (images, catalogs, auxiliaries) | write-once | RAPID → MAST | permanent while RAPID-owned | community | job role |
| Alert archive | append-only | RAPID | permanent | community | archive sink |
| Records, provenance | write-once | RAPID | permanent | team | job role (attempt-scoped) · reconciler (terminal/reconstructed) |
| Manifests (completeness markers) | write-once | RAPID | permanent — a manifest survives its data's expiry; lifecycle rules exempt manifest keys | pipeline | the producing authority of what each manifest describes |
| Reference sets (per release) | write-once per version | RAPID | release-lifetime, then per release ruling | pipeline | reference builder |
| Converted L2 representation | write-once | durable derived commitment (through at least the first supported release) | release-lifetime; long-term open with the release design | pipeline | conversion process |
| Staged inputs | replaceable cache, immutable per generation | upstream | until generation retired | pipeline | staging process |
| Diagnostics bundles | write-once | RAPID | tiered decay per the observability design, tag-driven | team | job role · reconciler (reconstructed bundles; retention tags on all) |
| Public operational metadata (rolling current file) | replaceable current file | RAPID | current-only | community | ops publisher |
| Operational pointers (registers, current-manifest) | CAS | RAPID | tiny, permanent | pipeline | controller |
| Database backups | write-once | RAPID | ladder per the backup design | ops | backup process |
| Build artifacts | replaceable cache | RAPID | short fixed window | ops | build identity |
| RPM repository | packages write-once (accumulating history) · repodata CAS | RAPID | packages permanent · repodata current | team | publisher identity |
| Git mirror | replaceable current file | RAPID | current-only, bounded noncurrent history | ops | mirror job |
| Logs and assurance reports | append-only in effect | RAPID | short fixed window | ops | log-delivery and Inventory delivery principals |

## Principles

1. **A container exists per enforceable policy point.** Split where
   an axis difference needs bucket-level enforcement (versioning,
   Object Lock, bucket-policy shape, writer isolation); carry
   prefix-enforceable differences (lifecycle, prefix-scoped writers)
   as prefixes. A split not forced by enforcement may be taken for
   operational legibility — stated as such, never silently.
2. **No storage name is an interface.** The catalog resolves science
   queries to locations; project-owned DNS fronts public
   byte-serving; configuration parameters bind the pipeline to its
   containers. No raw bucket name is published, so no bucket name is
   permanent and every bucket is recreatable. Publication, not
   creation, is the one-way door.
3. **Immutability is enforced, not promised.** Versioning alone does
   not enforce it — a second PUT creates a new current version.
   Write-once classes carry policy-enforced conditional creates and
   denial of both ordinary and version-specific deletes; append-only
   classes get writers with no delete or overwrite capability; CAS
   pointers accept only conditional updates; multipart uploads land
   under the same condition at completion. One mutability class per
   policy scope. Lifecycle expiry still operates (a service action,
   not a principal request). Bulk loads into create-once buckets
   follow **enforce-after-load** — a server-side copy can satisfy
   the create-once condition per object, but bulk sync tooling
   cannot send conditional headers, so the bucket starts with
   enforcement off and the policy attaches once the load verifies
   (verified live).
4. **The catalog is the symlink.** Immutable objects, new versions
   written beside old, promotion by one atomic pointer update,
   demotion by pointing back. Never rename, never overwrite, never
   delete-to-replace. The replaceable-current-file classes (public
   operational metadata, git mirror) are the contract-level
   exceptions.
5. **Retention is a property of the class, set once in lifecycle
   configuration**; tuning a period is a configuration change.
   Retention follows custody: permanent means permanent while RAPID
   is durable owner; verified MAST custody makes disposability a
   real decision, taken then, under the durable-ownership rules.
6. **Writers are enumerated and minimal.** One authoritative writing
   identity per object class; a bucket carries the fewest writer
   identities its classes require, stated completely in the bucket
   table. Anything outside the stated set is an incident.
7. **Publication is enforced at the front door.** Keys are semantic
   and guessable, so the public byte path serves catalog-issued
   signed requests only: promotion state is checked at issuance, and
   a never-promoted object is unreachable even by a guessed key.

## Naming

One uniform scheme: `roman-rapid-<purpose>` — a short lowercase
purpose noun; no environment markers, no account or region
components, no personal names. Per-dataset input buckets append the
dataset name, and the dataset noun follows the naming design's
grammar `<survey>-<source>(-<qualifier>)*` (`gbtds-rimtimsim`, never
a generic sims label; the live `gbtds-sim` predates the grammar and
is retained); campaign detail — injection date, sim release,
selection — lives in the generation manifest, not the name. Squat
resistance is policy, not name machinery: names are held continuously
once claimed; every service identity and VPC endpoint policy is to
carry a bucket-owner condition so no RAPID principal can read or
write a bucket the account does not own — an owed pre-cutover
verification, not yet an enforced fact (§ Open points and
deliverables). "Recreatable" means the same claimed string is
recreated under continuous holding; a claimed name is never released
or reused, so recreation and squat resistance are compatible.
External principals (front-door origin access, archive partners,
report delivery) are protected by continuous holding and their own
configuration pinning the bucket. The dataset noun's grammar and the
token vocabulary it draws from (surveys, sim sources, data classes)
are registered in the naming design.

## Bucket set

| Bucket | Classes | Versioning | Lifecycle | Writer set · enforcement |
|---|---|---|---|---|
| `roman-rapid-products` | Published products | on | Standard; no expiry while RAPID is durable owner | job role · create-once; no deletes; termination-protected |
| `roman-rapid-alerts` | Alert archive | on | Standard, permanent | archive sink · create-once, append-only; no deletes; termination-protected |
| `roman-rapid-records` | Records, provenance (the terminal records double as the science promotion manifests); submission and delivery manifests, delivery state markers | on | Standard, permanent | worker roles + controller (submission, acceptance and reconciliation) + publisher, prefix-scoped per class (§ Key schema) · create-once; no deletes; termination-protected |
| `roman-rapid-references` | Reference sets; each release's manifest in-prefix | off | tag-driven per release ruling; manifest keys exempted | reference builder · write-once per key |
| `roman-rapid-l2` | Converted L2 representation in release prefixes; each release's manifest in-prefix | off | release-lifetime; long-term open; manifest keys exempted | conversion process · create-once |
| `roman-rapid-inputs-<dataset>` | Staged inputs in immutable generation prefixes; generation manifest written last, in-prefix | off | expire retired generation prefixes; manifest keys exempted | staging process · create-once within generations, no deletes; a stated legibility split per dataset (the dataset is the swap/retire/cost unit) |
| `roman-rapid-diagnostics` | Diagnostics bundles | off | tiers per the observability design, driven by the reconciler-stamped retention tag on classification-neutral keys | job role + reconciler · create-once, no deletes; reconciler retags (full-set rewrite, monotonic toward retention) — the conditional create arbitrates the race: the job's upload wins, the reconciler reconstructs only where absent |
| `roman-rapid-meta` | Public operational metadata | on | current-only; noncurrent expire 30 d | ops publisher · replace-in-place permitted |
| `roman-rapid-pointers` | CAS registers | on | none | controller · either-header conditional-write policy |
| `roman-rapid-backups` | Database backups | off | ladder per the backup design | backup process · write-once |
| `roman-rapid-build` | Build artifacts | off | expire 180 d | build identity · plain |
| `roman-rapid-yum` | RPM repository | off | none — packages accumulate as permanent history | publisher identity · create-once packages + CAS repodata |
| `roman-rapid-mirror` | Git mirror | on | noncurrent expire 90 d | mirror job · replace-in-place permitted |
| `roman-rapid-logs` | Logs; S3 Inventory deliveries | off | expire 90 d | log-delivery + Inventory delivery principals · plain |

Enforcement shorthand: "create-once" and "write-once per key" mean
policy-enforced conditional creates plus denial of both delete
actions for all principals; "plain" marks a replaceable, re-derivable
class. Every lifecycle configuration also aborts incomplete multipart
uploads at 7 days and expires orphaned delete markers; noncurrent
versions on versioned write-once buckets need no expiry (creates are
unique, deletes denied), keeping versioning cost-neutral there.

## Writer mapping

Every logical writer resolves to exactly one IAM principal; the
security design's role boundaries carry the corresponding grants.
Grants are wired per bucket when its first consumer cuts over, never
speculatively.

**[ADOPTED]**

| Logical writer | IAM principal |
|---|---|
| Transform workers (Batch) — products, attempt-class records, diagnostics, reference sets, converted L2, all under their attempt prefix | Batch job role (transform tier: no database, submission, publication, or external-effect access; alert production is not a Batch writer — accepted alert packets reach the outbox via the controller's acceptance path and leave only through the publisher) |
| Reconciliation — closure and terminal records, reconstructed diagnostics, retention tags on all bundles | Controller role (reconciliation is one of its functions; diagnostics write adopted with this design, tag rewrite with the payload co-design) |
| Controller — CAS pointers, pointer-level promotion manifests, submission manifests, public operational metadata | Controller role (science-product promotion manifests are the terminal records, job-written — catalog design) |
| Delivery process — delivery manifests and state markers | No principal yet: no delivery exists before the public-path design, which owes the mapping; the grant wires at first cutover per the wiring rule |
| Archive sink — alert archive | Archive sink role |
| Staging process — input generations and their manifests | rapid-admin instance role (the staging host by team policy; grant attached from the bucket stack) |
| Backup process | Database host instance role (the existing backup identity) |
| Build identity | The CI build-project role |
| Mirror job | The existing mirror identity, unchanged until its cutover step |
| Log and Inventory delivery | AWS service principals, enumerated per template |

## Key schema

Keys identify one immutable processing result forever; reprocessing
writes new keys. Numeric components are fixed-width zero-padded. Key
order serves stable identity, lifecycle scoping, MAST export, and
operational diagnosis — request rates sit far below per-prefix
scaling baselines, so performance imposes no ordering constraint
beyond avoiding a monotonic head on a sustained high-rate prefix.
Prefixes exist where policy or a consumer needs them and nowhere
else. Objects carry their producing release as a tag where lifecycle
or supersession may act on them; permanent-class objects carry
SHA-256 checksums computed at upload. Staged input files keep their
upstream names verbatim — exact identification, never renaming, is
RAPID's obligation for material in upstream custody.
Community-facing product file names follow the mission's CCSP PIT
filename standard, under which `rapid` is the registered PIT short
name.

**Data class rides the key grammar, not a sixth classification
axis.** The data-class component is derived from the two-axis
identity (substrate × injection; operations design § Continuous
validation) within the existing container set — the five axes and
the container inventory stand unchanged. The component's tokens are
the naming design's registered set (`real-pristine`, `real-injected`,
`sim-pristine`, `sim-injected`). The mandate is scoped, not universal:
the component is mandatory and leading in the product-grammar
buckets — products at the bucket root, references and converted L2
immediately inside their `{release}/` prefixes — so the science gate
and the prefix-scoped grants bind to one literal leading prefix.
Records, pointers, public metadata, backups, build, yum, mirror, and
logs carry no data-class component; diagnostics are
classification-neutral by design. Policy and validation tooling uses
each family's stated schema, never a universal assumption. The
science gate is prefix-scoped: promotion and publication roles hold
no capability outside the science prefix, making a validation-data
leak an IAM impossibility rather than a checked rule; any retention
difference for validation products is a lifecycle rule on the same
prefixes.

Component law: widths are contracts (exposure 6, SCA 2, attempt 10,
record sequence 4, generation 4 — exceeding one is a defect, not a
rollover); the records-prefix and diagnostics-bundle key families
carry bare (unpadded) attempt ids deliberately — existing objects and
key-derivation compatibility make retro-padding harmful — while the
10-digit attempt width applies to product-grammar object keys; free
identifiers
(`run_id`, `logical_job_id`, `batch_id`, `delivery_id`) are lowercase
alphanumeric plus hyphen, letter-first, ≤ 32; enumerated names
(`job_type` from the dispatch contract's validated route set; `view`
from the infrastructure-pointer view registry, created empty here and
populated by the first such view's design; meta-bucket artifact names
from the interfaces design's public-metadata set) are lowercase
snake, ≤ 32; `data_class` is the naming design's registered set —
compound tokens, lowercase with an interior hyphen, ≤ 32 — an
explicit exception to the lowercase-snake rule above; `release` is
`r`-prefixed lowercase alphanumeric plus `.`, ≤ 16; digests are 64
lowercase hex; basenames add `.` and `_`, ≤ 128. The model-to-token
mapping is normative, part of the builders' validation table, not a
convention: substrate `real|simulated` maps to key tokens
`real|sim`; injection `pristine|injected` maps to `pristine|injected`.
Builders are the enforcement point, validating components and
registry membership; the shared sanitizer is the last-resort gate,
deliberately broader than any one class. Identity is never parsed
from a basename — it travels alongside as catalog columns, record
fields, or header keywords. Internal keys and delivered names are
distinct namespaces: no internal key embeds a CCSP filename, no
delivered name derives from an internal key. "Product key" is
reserved for the catalog's science-identity digest (catalog design);
the keys defined here are object keys, and no document or tool calls
an S3 key a product key. Stored references to object keys record the
key-schema version alongside the URI.

Product-class buckets (products; references and converted L2 under
their release prefixes) carry one grammar, exclusively:

```text
{data_class}/{job_type}/{run_id}/{exposure:06d}/{sca:02d}/attempt-{attempt_id:010d}/{basename}
```

Basenames are unique within one attempt prefix — the producing stage
emits distinct names, and the conditional create is the backstop that
makes a collision a loud attempt failure, never an overwrite. A
post-processed product is a distinct object under its own
job-type/attempt prefix, related to its input by unit identity, never
by shared key.

Records bucket prefixes, one writer each:

| Prefix | Content | Writer |
|---|---|---|
| `attempts/records/{run_id}/{logical_job_id}/attempt-{attempt_id:010d}/seq-{seq:04d}.json` | terminal records (seq 0, job) and closure records (seq ≥ 1, reconciler) | split by sequence, protocol-owned |
| `attempts/config-snapshots/sha256/{digest}.json` | config snapshots, content-addressed | job role |
| `submissions/{batch_id}/manifest.json` | submission manifests | controller |
| `deliveries/{delivery_id}/` | delivery manifests and state markers | delivery process |

Attempt scoping is protocol-enforced, not IAM-enforced: keys derive
from immutable identity and every write is a conditional create, so a
replayed write lands idempotently or fails loudly; conditional
creation prevents mutation, not a misplaced first write — that defect
class is caught by the catalog↔inventory reconciliation. IAM operates
at the prefix-class level.

Remaining buckets: references and L2 carry `{release}/` prefixes with
the release manifest at `{release}/manifest.json` written last (the
manifest keys exempt from lifecycle, as with staged inputs);
diagnostics bundles are
`attempts/bundles/{run_id}/{logical_job_id}/attempt-{attempt_id}.tar.gz`
(bare attempt id per the component law),
classification-neutral, retention by reconciler-stamped tags; the
alert archive's layout is the publication design's (the sink's writer
code is its canonical builder); pointers are `{view}.json`, one CAS
pointer per view; public metadata follows the interfaces design's
artifact set, replace-in-place; backups, build artifacts, yum, mirror,
and logs are tool- or service-owned key spaces, delegated as such —
the bucket is single-writer and the owning tool's layout is the
contract.

Delivered names, minted only at the delivery boundary (catalog
design): `ccsp_rapid_<instrument-settings>_<target>_<wave>_<version>_<product-type><.extension>`, all fields mandatory; lowercase ASCII
alphanumeric with `_` field / `-` element separators, `.` in target,
version, and extension, `+` in target only; ≤ 90 characters,
constraint-enforced at mint; directory names ≤ 20 characters, agreed
with MAST; `version` is `vX[.Y[.Z]]` carrying the delivery-minted
counter, decoupled from row version and release identity;
`product-type` from the MAST-agreed set; extensions `.asdf` or
`.parquet` only — the FITS→ASDF/parquet conversion precedes first
MAST delivery.

## Promotion and swap

| Level | Mechanism | Atomicity |
|---|---|---|
| Science current-view | `vbest` row flip over immutable keys, the attempt's terminal record as the promotion manifest — full mechanics in the catalog design | one database transaction per attempt, index-enforced |
| Infrastructure pointer | CAS root-pointer object referencing an immutable manifest | single-object conditional PUT |
| Staged dataset | new generation prefix; parameter flip to its finalized manifest | parameter update |
| Public surface | front-door origin re-point | not atomic — dual-origin overlap and drain |

The promotion unit is an immutable manifest (keys, sizes, checksums,
format versions), written create-once beside what it describes, by
the producing authority, after every object it names — its existence
is the completeness marker. At the science level that manifest is the
attempt's terminal record, written by the job as producing authority
and consumed by registration; no separate product manifest exists
there. At the infrastructure-pointer level the controller is the
producing authority. Promotion always references a finalized
manifest, never a bare prefix, never an enumeration. One root
pointer per view. Consumers pin the manifest they started with,
recorded in the attempt record; a retry replays the same manifest —
consuming a newer generation is new work. A parameter flip changes
only what new work sees; both generations stay readable during
drain; a retired generation expires by lifecycle after a drain
criterion.

Rejected mechanisms: access points as a pointer layer (bucket
binding is fixed at creation); rename (nonexistent on general
purpose buckets); overwrite-in-place of a stable key as promotion;
whole-bucket swap for routine generation change (reserved for
genuine policy or ownership changes); S3 Express One Zone
(single-AZ); Glue Data Catalog in the baseline — it is a tabular
metastore for Athena/Spark-class consumers with no model for FITS
objects, and PostgreSQL is the catalog. Revisit Glue only with a
community tabular-over-S3 product.

## Public access

Community byte-service is fronted by project-owned DNS over the
community-audience buckets; discovery and retrieval are
catalog-mediated, and the front door serves catalog-issued signed
requests only (principle 7). The front-door implementation — CDN
with origin access control, or a download service issuing
project-domain URLs — is a named deliverable; bare presigned URLs
expose the raw bucket hostname and are not a distinct option.
Public-access block stays on every bucket; the front door's read
principal is the only non-IAM read principal. MAST delivery is a
cross-account read grant plus a delivery manifest against the
products bucket — the same immutable objects, no staging copy; the
grant is bucket-wide read, accepted deliberately (MAST is a trusted
archive partner). The deferred fork: ecosystem-native raw `s3://`
access (bulk-tooling patterns, sponsored open-data egress). The
working buckets already bear publishable names, so taking it later
is a policy change, not a data copy; it is re-examined once, at
community-read-path design time — raw URIs cannot check promotion
state, so that fork requires either promotion-before-write or an
explicit exposure acceptance.

## Policy and assurance baseline

Every bucket: TLS-only; Object Ownership bucket-owner-enforced (ACLs
disabled); SSE-S3 default encryption; public-access block; gateway
VPC endpoint for all pipeline data traffic; per-bucket cost
allocation tags. Permanent-class buckets additionally: no principal
holds any delete action; CloudFormation deletion and update-replace
policies set to retain, plus stack termination protection — data
outlives any stack operation; break-glass is a recorded stack-policy
change, not a standing capability.

Assurance: weekly S3 Inventory on the three permanent buckets,
delivered to the logs bucket; scheduled catalog↔inventory
reconciliation over keys, versions, sizes, and ETags; checksum
verification separately by sampled object-attribute reads or a
periodic batch checksum pass. CloudTrail S3 data events on the
permanent buckets for write and delete attempts. Config rules assert
encryption, versioning, public-access block, lifecycle, and policy
state — drift is detected, not assumed absent. Storage Lens plus
per-bucket budgets with anomaly alarms; storage-class analysis runs
before any tiering beyond the adopted diagnostics tiers.

## Performance

No striping, no pre-sharding: per-prefix request-rate baselines
exceed the pipeline's concurrency profile; SDK default retries
absorb S3's gradual repartitioning; CRT-based transfer clients
handle multipart and ranged-GET parallelism. Before the first
full-scale run against a fresh high-volume prefix, pre-partitioning
may be requested from AWS Support; otherwise the ramp is accepted.

## Open points and deliverables

Object Lock is not enabled on any bucket: immutability enforcement
is the bucket policies above, and no external WORM requirement
exists — reopens only on an actual requirement.

Open: disaster-recovery posture (RPO/RTO per
policy family, per-bucket
replication rulings for products, alerts, and records, catalog
backup/PITR as the catalog-contract recovery path — manifests plus
Inventory reconstruct the object index only).

Delivered: the per-bucket key grammar (§ Key schema), the promotion
transaction protocol, delivery records, recoverability projection,
and restore acceptance criteria (catalog design), and the
logical-writer mapping (above; grants wire per bucket at each
consumer's cutover). Still owed: MAST delivery contract and the
front-door implementation choice with its URL-validity/withdrawal
semantics (interfaces design). Verifications before cutover relies
on them: exact bucket-owner condition keys per principal type; the
restore drill per the catalog design's acceptance criteria. (The
conditional-copy verification is resolved — see the
enforce-after-load rule under principle 3.)
