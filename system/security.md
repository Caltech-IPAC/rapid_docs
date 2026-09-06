# Security

**Status: ADOPTED**

## Reproducibility boundary

**Status: ADOPTED**

RAPID's results must be reproducible by the external community. The
governing policies are NASA SPD-41a (Scientific Information Policy for
the Science Mission Directorate) and the Astrophysics Division's APD
Policy-13; the operative test is APD Policy-13 §2.3 "scientifically
useful": anything a scientist needs to assess, interpret, evaluate,
validate, or reproduce RAPID's results is public. RAPID is Research
class under SPD-41a (a ROSES-selected investigation), so Section VII
of that policy applies.

The boundary:

| Content | Placement |
|---|---|
| RAPID-authored software, including compiled tools invoked by the pipeline | Public, under a permissive license, in the public repositories |
| Third-party dependencies | Named in a public pinned manifest (package and exact version, from the environment lock files); the software itself is obtained from its own public source, not republished |
| Container base image | Publicly identified by image name and digest |
| Base-OS package closure | Private: substrate, not scientifically useful |
| Build recipes and infrastructure definitions | Private: an environment functionally equivalent for reproduction is reconstructable from the public manifest without them |
| Credentials, security-relevant configuration | Private, always |

The environment definition — package recipes and pinned manifests —
has one authoritative home, the infrastructure repository; the
pipeline repository declares its dependencies and carries no copies of
third-party software.

Release of RAPID-authored software follows SPD-41a III.D: permissive
license with broad community acceptance, contribution guidelines and a
code of conduct, registration in the NASA software catalog, and a
persistent identifier for citation.

## Identifier exposure

**Status: ADOPTED**

Identifiers divide along the same public/private boundary as content.

The public surface is anything the community can obtain: URLs, public
bucket names, alert content, published documents and data products,
the public repositories, and any distributable artifact — container
images, shared machine images. Whatever is baked into an artifact is
exposed the moment a copy is handed out, so distributable artifacts
are built with no internal identifiers in them; scrubbing after the
fact is not a control.

Public-surface identifiers carry science semantics only — project,
product, version. They never embed AWS account numbers, IAM principal
names, internal hostnames or network identifiers, or personal
usernames and paths. AWS regions may appear where endpoints require
them.

Published names are permanent. A bucket cannot be renamed, a
published name cannot be recalled, and a released public bucket name
can be claimed by another AWS account that would then receive
requests intended for it — so a name, once published, is never
released, and every identifier is checked against these rules before
first publication. Publication, not creation, is the one-way door:
no storage name is an interface — the community-facing entry point
is project-owned DNS with catalog-mediated discovery, so the
underlying resource can be re-pointed and no raw bucket name need be
published. Raw resource names are published only where a
deliberately adopted access mechanism requires them.

The AWS account number is not a secret — it is visible in every
shared ARN — it is simply never volunteered on the public surface.
All buckets share one naming scheme, `roman-rapid-<purpose>` (short
lowercase purpose noun; no environment markers, no account or region
components, no personal names), per the storage design. Squat
resistance is policy, not name machinery: names are held
continuously once claimed, and every service identity and VPC
endpoint policy carries a bucket-owner condition, so no RAPID
principal can read or write a bucket this account does not own
(fleet-wide condition coverage is verified before cutover —
storage.md § Naming).

## Service identity and access

**Status: ADOPTED** — human credential custody remains not yet
covered, noted at the end.

The pipeline is owned by service identities, not people — the cloud
form of the UNIX service account that owns a pipeline installation.

- Every automated function runs as its own dedicated IAM role, scoped
  to that function alone. No automated path uses a personal
  credential, and no person operates under a service identity — one
  identity per actor is what makes the audit trail read as
  who-did-what without reconstruction.
- People authenticate through SSO with time-bounded sessions; the
  read-only role is the day-to-day default, mirroring the database
  posture — humans read, services write. Elevated roles are assumed
  for the action that needs them, never held as a resident login.
- Write-capable access, cloud and database alike, is granted per
  named need, scoped to the need, recorded, and revocable.
- No long-lived static keys anywhere: machines get instance and task
  roles; people get SSO. Machine secrets — database passwords and
  peers — live in the secrets store, are fetched at use under the
  caller's IAM role, and rotate without redeployment. No credential
  appears in an environment dump, job definition, image, or version
  control.
- Audit is a property of the paths, not a bolt-on: every
  control-plane action lands in CloudTrail under the identity that
  made it; database DDL travels only through the versioned migration
  stream; operator mutations go through the constrained procedures and
  the append-only operator-action ledger of the operations design.
  Break-glass paths exist, end in an audit event, and are the only
  sanctioned exception.

### The service roles

Distinct IAM and database roles exist per automated function. Their
trust policies carry source-account conditions — plus source-ARN
conditions where the trusting service supports them — against the
confused-deputy case, and all sit under one shared permissions
boundary that fixes a ceiling no future policy attachment can widen
without an explicit, visible boundary edit.

| Role | Function | Capability boundary |
|---|---|---|
| Controller role | Admission, deriving ready work, submission, retry policy, reconciliation, result acceptance | Batch job lifecycle (submit, terminate, describe) in the project namespace; its own database credential at the pipeline-write tier; result-manifest and records read and write for acceptance and reconciliation; diagnostics retention-tag rewrite; operational-pointer updates and public operational-metadata publish. Never registers job definitions, never touches science pixels, never publishes externally |
| Transform role | Database-free Batch workers: difference and detect, reference construction | Read of its exact declared inputs; write **only to its own attempt prefix**. **No database credential, no submission capability, no publication capability, no secret beyond its own.** Reads and writes nothing another attempt owns |
| Association role | Database-capped Batch association and assessment work | One database credential at the pipeline-write tier through the session-mode lane; detection and association read and write; alert-product write. No submission capability, no external publication, no broker credential |
| Export role | Release export shards | Frozen-release read; export-artifact write to its own shard prefix; its own database credential, read-scoped to the frozen release. No publication capability |
| Publisher role | Delivery of committed alert events | Outbox claim and delivery-state update; immutable packet read; **sole custody of the broker credential**. Cannot alter scientific records, cannot submit jobs, cannot write products |
| Migration runner role | The versioned schema-migration stream, the only DDL path | One capability: read the database admin credential. Reached only by role-chain from the database host, so the admin-credential read always audits under this identity with the migration version as session name |
| Operator role | Constrained operator mutations through `rapidctl` | Execute-only on the constrained procedures; **no table-level write grants**. Every call carries the mutation contract and lands in the operator-action ledger |
| Backup role | Base backups and continuous WAL archiving | Write to the backup repository prefix; no delete on it. No science-store access, no application database credential |

The separations that carry correctness rather than convenience are
three. **Transform workers hold no database, submission or publication
access at all** — the property that makes duplicate physical execution
harmless is enforced at the identity layer, not only in code: a
worker that cannot connect, submit or publish cannot commit an
unaccepted effect however many copies of it run. **The publisher alone
holds the broker credential**, so no Batch job can perform an external
side effect. And **the operator role holds execution rights on
procedures only**, so routine operation cannot bypass the mutation
contract with handwritten SQL.

Deliberate absences are properties, not gaps: no worker role has a
log-stream grant (the bounded safety stream is delivered by the host
instance role), no worker role has Batch actions (a job cannot spawn
jobs), and no role has delete on a science store — records and
products are immutable and supersession appends. Object deletion is
reachable only through the garbage-collection path's own identity,
against a recorded plan.

Job configuration has three homes: per-invocation identifiers arrive
in the container environment; operational configuration — bucket
names, endpoints, mode toggles — is read from the pipeline parameter
tree at startup under the running identity, persisted as a content-addressed
snapshot, and hashed into the attempt record's configuration digest;
anything that can alter a science product — tuning, reference-data
versions — is release content, versioned with the image and never in
the mutable tree, and never reachable from the environment. The one
sanctioned per-run override channel for a science-affecting value is
the submission manifest's enumerated override fields (compute
design), recorded in provenance by the manifest checksum, with
override-bearing products barred from community promotion. A worker
identity's parameter read extends only over that tree.

### Database service credentials

One secret per connecting identity — the credential is the identity at
the database handshake, so sharing one would merge audit trails the
role separation exists to split. Each secret holds a JSON
username/password pair; each maps to its own database login role at
the tier the database design assigns: the controller, association and
export identities at the pipeline-write tier, the publisher scoped to
the outbox and delivery tables, the operator to procedure execution
only, and the migration runner at the schema-owning administer tier —
never the superuser. Transform workers appear nowhere in this list:
they hold no database credential at all. Consumers fetch at connection
time and cache nothing across connections, so rotation is a password
change plus a new secret version, with no restart, redeploy, or
job-definition change; the seconds-wide authentication window during
rotation is an accepted, recorded failure mode that retries under
normal policy. Rotation is a recorded operator procedure — no standing
rotation machinery until a compliance requirement demands a schedule.

Human credential custody — admin credential holding and the
break-glass procedure's key material — is not yet covered by this
document.
