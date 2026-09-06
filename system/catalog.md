# Catalog

**Status: ADOPTED**. The catalog's promotion mechanics, delivery
records, recoverability projection, and restore acceptance criteria.
The executor-fence and product-identity paragraphs in § Promotion are
also ADOPTED.
The per-bucket key grammar and writer authority live in the storage
design; the catalog's table schemas live in the database migration
stream, which implements this document.

## Principles

1. **The catalog is the symlink** (storage design, principle 4):
   immutable objects, promotion by pointer, never rename or
   overwrite. This document states the pointer's mechanics.
2. **Evidence precedes reference.** No catalog row cites an object
   that could not already be durable: records are written before rows
   cite them, manifests before promotion references them, catalog
   state before its S3 projections.
3. **One transaction per attempt.** The registration transaction is
   the promotion transaction; no observer sees a unit half-promoted.
4. **Enforcement is structural.** Invariants live in constraints and
   guarded transitions, not in read-then-write conventions; a code
   path that cannot exist beats a convention that must be followed.
5. **Verified presence over citation.** Recovery follows a citation
   to the object and verifies it; a pointer is a claim, not a fact.
6. **Three version concepts, three homes.** Row version (internal,
   minted at insert), delivery version (public, minted at delivery),
   release identity (a tag). One mint point each; no concept borrows
   another's home.

## Promotion

`vbest` on the four identity tables (`l2files`, `refimages`,
`diffimages`, `psfs`) is the promotion pointer: 0 = not current, 1 =
current best, 2 = locked best (operator pin; promotion refuses to
demote it). Insert never promotes: rows land `vbest = 0`,
`version = max+1`. Promotion is demote-then-promote inside the
`update*` functions.

**The registrar acts on a single premise: exactly one registrar runs
against a given attempt at a time.** The premise is enforced, not
assumed — a transaction-scoped advisory lease on the attempt key,
acquired inside the same product/outcome/watermark transaction the
registration commit uses, with a post-lock re-read of the watermark
state before any write. The operator pass and the manual
`JOB_TYPE_REGISTRATION` route share one lock namespace and key
derivation, so a restart overlap or a manual registration cannot
double-write. This is the registrar's own instance of the lease
primitive; the reconciler's closure protocol runs the same primitive
shape over its own prefix-listing, lexical-max selection — that
machinery belongs there, not here.

**The promotion manifest is the attempt's cited terminal record** —
fetched by the attempt row's own recorded key and sequence, not
discovered by listing. The row's cited sequence is authoritative; the
record is fetched by exact key and validated — parseable, same attempt
identity and sequence, checksum where the row's classification records
one — before any flip.

Attempt identity alone is not the fence. Because an ambiguous
submission can leave more than one physical execution against a single
attempt, the transaction verifies the **fenced executor**: the
authoritative execution recorded for that attempt, so a result
produced by a duplicate execution cannot register or promote. Attempt
identity establishes which logical try a result belongs to; the
executor fence establishes which physical run is allowed to win. Both
are checked, in that order.

Scientific identity is independent of both. A product's identity is a
deterministic digest of process specification, canonical subject,
ordered inputs and role — never a path, a Batch identifier, an array
index or an attempt identifier. Attempt identity governs idempotent
registration; it does not name the product. A store fault defers registration to a later
pass; a validation rejection commits its own registration-outcome
entry, in its own transaction, without advancing the registration
watermark — the attempt stays retryable and the rejection stays
durable. Records are complete canonical accounts; consumers never
chain-fold.

**Product roles bind in the declared set.** A declared product set
may name a product by role — a stable contract name bound in release
content to the concrete product that fills it. The difference-image
role is bound to the SFFT difference image; the ZOGY and naive
variants remain published, checksummed products in the record with
no identity-table rows. Every consumer of a role-named product —
registration, alert cutouts, catalog readers — resolves the same
binding; no consumer carries an algorithm literal. Measurements
registered alongside a role-bound product are drawn from the bound
product's own processing chain. Changing a role binding is a release
change.

**Completeness is checked against a pinned declaration.** Each job
type declares its required product set and its promoting dispositions
in release content, which is versioned with the image; the attempt's
submission-time execution binding pins the image digest, so replayed
registration retrieves the same declaration forever. Promotion occurs
only on a promoting disposition with the declared product set fully
named; the record schema carries, per product: URI, checksum, size,
format version, product class.

**The commit** is one database transaction per attempt: product-row
inserts, the `vbest` flips for every product the record names, the
registration-outcome entry, and the registration watermark, together.
The borrowed-connection single-transaction envelope is the only path;
the per-call autocommit fallback is removed for identity-table
mutations (a standalone caller borrows an explicit envelope).

**Enforcement**: partial unique indexes, one per identity table, on
the identity group where `vbest IN (1, 2)` — `refimages (field, fid,
ppid)`, `diffimages (rid, ppid)`, `l2files (expid, sca)`,
`psfs (fid, sca)`. The `update*` functions catch a violation and
re-raise through their existing exception contract.

**Conflicts**: two constraint families are retryable — the
natural-unique constraints containing `version` and the partial
`vbest` indexes. Either violation aborts the losing transaction whole;
the attempt stays closed-but-unregistered and retries on the
registrar's next pass against re-read state, under the same per-attempt
lease. A later-pass registration behaves exactly as a serial later
registration — its promotion legitimately supersedes the earlier
winner, because serial registration order is the supersession order.
Nothing partial commits. Same-attempt replay is idempotent under the
attempt-identity guard.

**A locked incumbent is not a failure.** Where one product's identity
group carries a `vbest = 2` pin, that product's new row lands and
stays at `vbest = 0` while the unit's other products promote and the
transaction commits. The commit is atomic; the resulting current view
is deliberately composite — the pin's designed effect. Suppressed
promotions are recorded in the registration outcome; promoting one
later is an operator action through the audited mutation surface.

**The registration outcome** is a structured field on the attempt row:
promotions performed, promotions suppressed by pins, validation
rejections, post-registration supersession observations. Appends are
append-once, keyed by event identity (type, record key, sequence,
checksum), with an observed-sequence high-water mark for supersession
observations. A validation rejection commits its entry without
advancing the registration watermark — the attempt stays retryable,
the rejection stays durable. A record superseded after registration
never re-promotes: the observation is appended and no product mutates.

**Provenance**: all four identity tables carry `attempt_id` /
`registered_record_sequence` and an FK to `attempts`; product-cited
attempt rows are permanent, and any attempts-retention policy excludes
them. `filename` columns are `text`; the one length constraint is the
delivered-name 90-character check on delivery records.

**Demotion** is a pointer move within the same machinery — promoting a
prior version's row, or an operator flip through the audited mutation
surface — never a delete, never a key rewrite.

## Delivery records

Deliveries are first-class catalog records: a parent delivery record
(unique delivery identity, state, acknowledgment or void facts) over
member rows (delivered CCSP filename, delivery version, the product
row carried, checksum as sent). The delivered name is written once at
mint, never re-derived; superseded-product naming in later manifests
is a catalog query over delivery history.

The commit protocol is a serialized state machine with the catalog as
sole commit authority; S3 objects are deterministic projections of
committed state, and a repair pass re-emits any projection a crash
left missing:

- **States**: prepared → delivered, or prepared → voided. Every
  transition is a guarded update (`where state = 'prepared'`); zero
  rows affected means replay or conflict, examined not reapplied; no
  transition leaves a terminal state.
- **Prepare**: one transaction mints the delivery identity (unique;
  deterministic from the delivery's scheduling identity, stable under
  replay — derivation owed by the public-path design), the delivery
  version per replacing product under a unique constraint on
  (delivered science identity, delivery version), every delivered
  filename (the CCSP mint and 90-character check bind here), and
  every checksum. Replay with identical membership is a no-op;
  different membership under the same identity aborts.
- **Manifest projection**: the MAST-facing manifest (additions,
  replacements, superseded-product names) is generated from the
  prepared rows in canonical serialization — sorted keys, no
  nondeterministic content — and written create-once to the records
  bucket's delivery prefix. Replay lands idempotently; different
  content at the same key is a defect.
- **Transfer**: the external archive action. Completion is the
  archive's explicit acknowledgment; whether re-notification is
  idempotent on the archive side is an open external confirmation,
  and until it arrives, resuming an unacknowledged transfer is an
  operator action.
- **Confirm / void**: the catalog transition commits first, pinning
  acknowledgment identity and timestamp (or void rationale) in the
  parent record; the create-once marker (`confirmed` or `voided`) is
  then written with a body derived entirely from the committed rows —
  byte-deterministic replay. Voided deliveries never reuse minted
  versions; version gaps are permitted and recorded.

One crash window is unrecoverable from S3 alone: a terminal transition
committed whose marker was not yet emitted reads, from S3, as still
prepared. The repair pass closes it whenever the catalog is available,
so the S3 view's divergence is bounded to deliveries with a repair
pending, and a post-restore catalog↔S3 delivery reconciliation names
exactly those.

## Recoverability projection

| Loss | Recovery source | Path |
|---|---|---|
| Catalog | backups (PITR per the backup design) + S3 state | restore; catalog↔Inventory reconciliation over keys, versions, sizes, ETags; checksums by the storage design's separate verification mechanism |
| Object index only (no usable backup) | terminal records + delivery objects + generation/release manifests + S3 Inventory | reconstruct locations, product identity, promotion candidates, and delivery history from record content; promotion state beyond record content is re-ruled by operator |
| In-flight attempts at loss | reconciler | evidence-ranked classification and closure per the observability design; the application owns record sequence 0, the reconciler all higher sequences |
| Dangling citations beyond the reconciler's window | operator supersession | terminal rows past the 24 h supersession window are beyond the service's reach; the remedy is appending superseding closure records classifying the attempts evidence-lost |
| Orphaned objects | detection by reconciliation; disposition per storage class | the orphan contract below |
| Superseded delivered products | delivery records + manifests | prior delivered filename and checksum reconstructible with or without the database |

**Minimum record fields.** The degraded path holds only if the
evidence carries the identity that basenames deliberately do not: the
terminal record requires attempt identity, unit identity, job type,
and per product URI, checksum, size, format version, product class;
the delivery manifest requires the delivered-name ↔ internal-URI
mapping, versions, and supersedes relations. These field obligations
are part of this design.

**Citation verification.** Every pointer class verifies by the full
triple — key, sequence, checksum (rows written before the checksum
upgrade verify by key + sequence + the record body's own identity
validation). Rows with no pointer (`missing_or_contradictory`) are
their own outcome: flagged for a human, never resolved by
reconstruction. Reconstruction reads verified object presence, never
citation alone, and every projection query is horizon-aware —
`application_closed` is an open state, and lifecycle state read
without horizon context misclassifies.

**The orphan contract.** Detection roots and eligibility per key
family; classification only past the grace period — grace ≥ the
enforced maximum job duration plus the reconciler's 24 h supersession
window, floor 7 days, instantiated from the verified duration ceiling.

| Key family | Detection root | Eligibility |
|---|---|---|
| Product-template objects | registered product rows + terminal records; release manifests for release-prefixed buckets | owning attempt terminal past every horizon; cited by no reachable record, row, or manifest |
| Attempt records + bundles | attempt rows, associated by key derivation — every sequence of a live attempt is legitimate | object outside every existing attempt's derived prefix |
| Config snapshots | config digests recorded in attempt rows (written by the started CAS) | digest recorded by no attempt row |
| Submission manifests | submission rows | unreferenced key |
| Delivery objects | delivery rows | unreferenced key |
| Staged-input generations | generation state: finalized (manifest) or abandoned (recorded declaration) | only finalized or abandoned generations classify; an unfinalized generation is in staging, unbounded, listed for operator attention only |
| Manifests and markers | — | exempt — roots, permanent by the manifest lifecycle exemption |
| Alert archive; CAS pointers; public metadata; tool-owned buckets | — | out of scope — sink continuity checks, class rules, and tool retention govern respectively |

Detection is a scheduled reconciliation report, never a deleter.
Disposition follows the retention axis: permanent classes retain or
take a recorded break-glass action; release-lifetime classes ride
their release ruling; replaceable classes ride lifecycle.

**Boundaries.** S3-before-database is the recovery-safe direction for
product and record publication — a crash strands sweepable objects,
never rows citing absent evidence. The delivery protocol deliberately
inverts this for its terminal transitions, because there the catalog
is the commit authority and the S3 object is a projection. Evidence
lost is a terminal classification, not a repair target; products never
promote on reconstruction alone. RPO/RTO numbers are owned by the
disaster-recovery posture ruling; this projection states the paths and
preconditions that ruling prices.

## Restore acceptance criteria

The restore-path proof drill passes when all of:

1. **Catalog restore** from backups alone, to a stated point in time,
   on a separate host, by the documented procedure, elapsed time
   recorded.
2. **Agreement**: post-restore catalog↔Inventory reconciliation clean
   on the permanent buckets (keys, versions, sizes, ETags); checksum
   verification separately by the adopted mechanism over a stated
   sample; differences fully explained by the restore point's age.
3. **Promotion-state integrity**: the partial unique indexes rebuild
   and hold — at most one current-or-locked row per identity group —
   and a sampled current-view query set returns identical results
   pre- and post-restore.
4. **Object-index reconstruction**, two phases: the delivery repair
   pass with the catalog available (exercising the crash boundaries),
   then reconstruction with the database withheld, from records,
   delivery objects, manifests, and Inventory alone — stating
   explicitly what it cannot recover.
5. **Provenance**: for sampled products across all four identity
   tables, the chain resolves — row → attempt → record fetched and
   verified per its class → inputs (actual-used where the route
   records them, submission intent for pass-through routes).
6. **Documentation-only execution**: run from the documented
   procedure alone, evidence captured into the drill's ledger.
