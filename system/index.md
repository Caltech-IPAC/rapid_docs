# System

The design documents are the authoritative statement of what RAPID is
built to be. They carry equal weight to the code: the pipeline must be
rederivable from them. Each document owns the rules and requirements of
its domain and states its design directly — self-contained, impersonal,
current-state. Every document (or section, where mixed) is marked
**DRAFT** (under iteration; what the team reviews) or **ADOPTED**
(normative).

## Cross-cutting design rules

Every domain document derives from, and may strengthen but never
contradict, these:

1. **Simplicity first.** Prefer the design a scientific programmer can
   reason about and debug over the theoretically optimal one.
2. **Low operational load.** The team is small; designs that need
   constant attendance are wrong. Automate periodic processes.
3. **Single source of truth.** Every fact, dataset, and configuration
   has exactly one authoritative home; duplicates cite it.
4. **Explicit over implicit.** Assumptions, interfaces, and failure
   behavior are written down; an undocumented behavior is a defect.
5. **Failure is observable.** Silence is a state, not an answer: every
   operation is attributable and its outcome recorded (see the
   observability policy).
6. **Guarantees to consumers are conservative.** The external community
   gets promises RAPID can keep through a research mission's unknowns.
7. **Same structural family.** AWS Batch + PostgreSQL/Q3C remain the
   skeleton; assumptions within that family are relaxable when the
   consequences are implemented, not avoided. No event-driven
   rearchitecture at this stage.
8. **Scientific layer protected.** Operational redesign leaves the
   scientific/algorithmic layer minimally impacted.
9. **Familiar workflows.** Users and developers come from Mac laptops
   and an HPC/HTC-like working model: ssh, POSIX filesystems, personal
   compute instances. Prefer designs that fit that model; adopt a
   cloud-native pattern only where it clearly pays for the new mental
   model it demands — where a job's logs live is as much a design
   choice as where its data lives.

## Documents

| Document | Status | Scope |
|--------------|----|------------------------------------------|
| [`architecture.md`](architecture) | ADOPTED | The orienting view: what the system is, the six governing principles, the processing graph, the identity chain, data stores, execution substrate, convergence, boundaries, operator and observability surfaces, releases, failure behavior |
| [`repositories.md`](repositories) | ADOPTED | The repository set: roles, organizations, visibility, operation and design authority, content placement, branch protection, and the build/publish surface |
| [`security.md`](security) | ADOPTED | Reproducibility boundary and identifier exposure adopted; the eight service identities re-derived against the target; human credential custody pending |
| [`code-standards.md`](code-standards) | ADOPTED | Ruff as style/lint authority, one-time reformat mechanics, naming and diagnostics rules, environment-variable policy |
| [`naming.md`](naming) | ADOPTED | Cross-namespace naming: coining principles, the `rapid` disambiguation map, token registry (surveys, sim sources, data classes), dataset-noun grammar; reserved words; complete-identifier and tombstone registers; the data-class key component lives in the storage key schema |
| [`observability.md`](observability) | ADOPTED | Logging, metrics, records, failure visibility, retention; diagnostics lifecycle and attempt record adopted; operational views, symptom metrics and paging set |
| [`storage.md`](storage) | ADOPTED | Five-axis storage classification, bucket set and naming, enforced immutability (bucket policy, no Object Lock), promotion/swap mechanics, assurance; DR posture open |
| [`catalog.md`](catalog) | ADOPTED | Catalog core: promotion and product roles, delivery records, recoverability projection, restore acceptance; executor fence and product identity |
| [`data-model.md`](data-model) | ADOPTED | The data-model map: entity layers including the workflow and delivery layers, writers, relationships, the submission as an entity; the eleven cross-cutting invariants |
| [`operations.md`](operations) | ADOPTED | Operational lifecycle, the controller, admission, result acceptance, reconciliation, association, alert production via the outbox, failure and problems paths, the `rapidctl` operator surface |
| [`compute.md`](compute) | ADOPTED | Execution substrate: the three queues, compute environments, resource profiles and job definitions, scratch, the submission protocol, retry taxonomy, payload contract |
| [`database.md`](database) | ADOPTED | Access model and typed repositories, pooling and sizing, availability and durability, schema management, failure behavior; pooler (PgBouncer + auth_query) |
| [`releases.md`](releases) | DRAFT | Release composition, validation battery, lifecycle and archival; scientific identity vs operational substrate; promotion sequence and release pinning; overall status still gated on the validation tests |
| [`interfaces.md`](interfaces) | DRAFT | The eight external interfaces: SOC input, live alerts, product archive, forced photometry, user cutouts, processing records, public metadata, release interface; overall status still under team review |
| [`documentation.md`](documentation) | DRAFT | Documentation policy: the classification axes, audiences, one rule per venue, the public site's six sections and page shapes, post rules, machine readership, the public-safety boundary, science-information-policy compliance, toolchain |

## Planned coverage

- **Security (remaining scope).** Human credential custody: admin
  credential holding, break-glass key material.
- **Testing.** End-to-end simulated-data testing that informs each
  design iteration, driven by a full mission mock: realistic arrival
  times, sky distribution, and load envelope.
- **Build and publish.** The continuous-integration and artifact
  promotion architecture is adopted and operating, but no document yet
  scopes it: the mechanism, its failure behavior, and its
  supply-chain guarantees are owed a home of their own.

```{toctree}
:hidden:

architecture
repositories
security
code-standards
naming
observability
storage
catalog
data-model
operations
compute
database
releases
interfaces
documentation
```
