# Repositories

**Status: ADOPTED**

RAPID's code and documentation live in three repositories:

| Repository | Organization | Visibility | Role |
|---|---|---|---|
| `rapid` | Caltech-IPAC | Public | The pipeline: all science and operational code |
| `rapid_docs` | Caltech-IPAC | Public | Project documentation, decoupled from the pipeline |
| `rapid_systems` | IPAC-SW | Private | AWS infrastructure definitions, and the build and publish machinery |

A fourth repository holds the pipeline lead's planning and research. It
is private and single-user, and holds nothing the team depends on and
nothing operational.

## Operation and authority

`rapid` and `rapid_systems` are both team-operated. The infrastructure
repository's documentation surface is deliberately lean and
self-explanatory: understanding any file in it requires no lookup into
a decision-identifier scheme — the design documents state the target
and the repositories' issues hold the discussion. What it does keep is
one operational tracker recording deploy state and owed live actions,
which has to be visible to the team.

The design documents sit above both implementation repositories. Where
a design document and an implementation record disagree, the design
document is correct and the implementation record is corrected;
implementation cites the design version it implements. A choice made
in an implementation repository becomes design only when a design
document states it, never by inheritance.

## Documentation placement

Documentation lives apart from the pipeline so that it evolves on its
own cadence rather than riding pipeline releases, and so the
documentation surface can grow without touching pipeline history.
Which venue holds which statement is the documentation design's
(`documentation.md`). In outline: `rapid_docs` holds every public
statement about RAPID, the design documents included, and builds the
public documentation site; `rapid` holds code, docstrings, a README
that points to the site, and the contribution files the software
policy requires — no documentation tree; `rapid_systems` holds
everything operational.

## Content placement

The pipeline repository carries code and its history only: bulk data
artifacts (catalogs, product listings, reference files) do not enter
git history — they belong in data stores and are referenced, not
committed. This keeps clones, CI checkouts, and archival snapshots
light for the repository's lifetime. Third-party software is likewise
not copied in: the pipeline declares its dependencies, and the
environment definition (package recipes and pinned manifests) has its
authoritative home in the infrastructure repository, which is the
production standard for it.

Bulk artifacts already in the pipeline repository's history are removed
by a one-time history rewrite before any persistent identifier is
minted against the repository — after that the cost stops being a
coordinated re-clone and becomes a broken reference.

Which content must be public for reproducibility, and which
account/infrastructure identifiers may appear in public repositories,
are governed by the security document's adopted reproducibility
boundary and identifier-exposure rules; repository visibility above
does not by itself settle content placement.

## Branches and protection

The pipeline repository's active public branch is its development
branch; a separate branch carries the migration work toward the target
account, on a restricted-access basis, and is the branch the migration
lands from. The infrastructure repository develops on its main branch.

Required review checks on protected branches are enabled after the
migration's history rewrite, since that rewrite requires a force-push.
Build provenance establishes which workflow produced a given artifact
from a given source revision, but not that the triggering commit or
the workflow change itself was reviewed — so enforcement is a
governance question that provenance does not answer.

## Build and publish

Builds run in the public continuous-integration service on the pipeline
and infrastructure repositories; publication into the account is
performed by an in-account promoter that pulls built artifacts,
verifies their attestation against the expected workflow identity and
source digest, signs them, and publishes. No credential for the
account is held by the build service. The promoter is the enforcement
point: it refuses to promote across a failed build, and that refusal is
the signal.

This architecture is adopted and operating, but no design document
scopes it; the design home for the build and publish surface is a
recorded coverage gap, not an omission of intent. The in-account
promoter identity is deliberately not among `security.md`'s service
roles: build and publish identities belong to that same gap, not an
oversight in the role table.
