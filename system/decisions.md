# Decisions

**Status: DRAFT**

Any team member edits this page directly, adding one dated line per
ruling with the author's name; CI on `main` is the only gate. A ruling is
the team's once it is on this page, and the design pages state the rule
itself and cite this page where the attribution matters.

## Rulings

Ben's rulings of 2026-09-27 on the open questions of the rebuild, as he
gave them.

(decision-trial-database)=
**SMDC database**: dedicated to the rebuild. dev's scripts never run
against it, read or write. The shared-writer hazards (vbest, prune,
swversions) are a cutover item, not a defect. (Ben, 2026-09-27)

(decision-science-flow)=
**dev-to-rebuild science flow**: the rebuild side owns it. Each ported
module under `rapidpipe/science` pins the dev file and commit it was
copied from; a CI script on `rebuild` reports dev commits since each pin
that touched the source; porting stays by hand. (Ben, 2026-09-27)

(decision-loop-promotion)=
**Loop promotion**: the spec. The loop uses the same auto-promote gate as
`run start`; under a trial policy a date's production run stays a
candidate until a person promotes it or a team-approved policy with
automatic promotion exists. loop.md and the unit test that expects the
opposite change. (Ben, 2026-09-27)

(decision-acceptance)=
**Acceptance**: "required checks pass" only. The acceptances table,
`check accept` and the nine derived ancestor states go; the ancestor walk
reduces to "every ancestor is current or superseded"; a false failure is
fixed in the policy file. (Ben, 2026-09-27)

(decision-legacy-compatibility)=
**Legacy compatibility**: remove without a probe. The `logical_key`
selector and `_recorded_inverse` path in promote,
`_repair_stranded_succeeded_attempts`, and the rederive-once migration
go; rapid_rebuild is disposable. (Ben, 2026-09-27)

(decision-latency)=
**Fan-out and latency**: rough requirement stated: **within an hour per
detector image, from its delivery to its alert current, typical, with a
dense-field tail accepted; RAPID's time short against the exposure-to-L2
delay.** Consequences: per-delivery batches with an event or ~30-minute
window trigger (operations.md's own rule); within-date fan-out over
detector images; the difference stage's ~58 min runtime (mostly Photutils
PSF fits) is the binding constraint. Parallel dates and lanes follow the
number. (Ben, 2026-09-27; provisional, the team confirms or replaces the
number)

(decision-step-ledgers)=
**Step ledgers**: stay ephemeral. The 632 "supervisor step / R / A"
citations in code and pages are replaced by the design-page section they
implement; the 313 dated narration lines leave the pages.
(Ben, 2026-09-27)

(decision-authority)=
**Authority**: the lead is removed; the team owns the design. A decisions
page in rapid_docs, edited directly by any team member, one dated line
per ruling with the author's name; a ruling is the team's once it is on
the page, no review gate; CI on `main` stays. Every "the lead's" on the
pages becomes the team's. The rulings above go on that page as Ben's,
dated today. Team communication about the rebuild remains Ben's to open.
(Ben, 2026-09-27)

## Earlier rulings

Rulings Ben made while he held the lead role. Under the authority ruling
they are the team's; each page states the rule.

- 2026-09-21: the `dev` schema is kept: nothing is renamed or dropped;
  new columns and tables are added where the vocabulary needs them
  ([products](products)). The rebuild's schema coexists with `dev`'s and
  writes it ([runs](runs)).
- 2026-09-21: nothing about a run's records is ever dropped; deleting a
  run's data changes state, not history ([runs](runs)).
- 2026-09-21: current result sets are readable by any run as frozen
  inputs, by instance id; scratch result sets only within their own run
  ([products](products)).
- 2026-09-22: every ported stage minimises differences from `dev` and
  designs in, off by default, anything that could be left unused (every
  stage page). The catalog stage's detection member is per-differencer
  and recorded with the instance; `vbest` stays the query surface
  ([products](products)).
- 2026-09-22: all promotions take one transaction-scoped advisory lock
  ([runs](runs)).
- 2026-09-23: `dev`'s once-per-date CLUSTER and ANALYZE move to their
  own `maintain` stage ([maintain](maintain), [load](load)).
- 2026-09-23: only one producer's frozen inputs bind at a time
  ([runs](runs)); everything `dev` wrote is never touched by rebuild
  deletion or cleanup ([runs](runs)).
- 2026-09-23: no per-child UNIQUE on `(pid, id, isdiffpos)`; SFFT loads
  against its own `pid`; a psf instance's `version` equals the allocated
  legacy number and `psfs`' key stays global ([load](load)).
- 2026-09-23: ZOGY's astrometric-sigma setting stays 0.0 as in `dev`;
  SFFT's interpreter settings default to empty ([difference](difference)).
- 2026-09-24: SFFT's `pipelines` row is `ppid` 16, priority 6
  ([difference](difference), [finalize](finalize)).
- 2026-09-26: gain matching reads the reference's own `MAGZP` header by
  default, with `[awaicgen] zprefimg` as an override; SFFT registers as
  its own `difference-image` instance by default; which differencer's
  instance is current downstream is a promotion choice
  ([difference](difference), [reference](reference)).
- 2026-09-26: each source's field is its own tessellation tile, a stated
  departure from `dev` ([load](load)).
- 2026-09-26: the proof spec stays unrepaired ([operations](operations)).

## Carried from the build, pending team review

Rulings made during the rebuild by its build sessions and their reviews.
Each is in force as its page states it until the team confirms, changes
or removes it here.

(decision-slot-identity)=
- **Association-set identity.** The slot-identity table on
  [products](products) is the one statement. An association set's identity
  adds the field, the crossmatch settings hash, the sorted identities of
  its source sets, and a hash of its base's own identity; the proposal's
  shorter wording, which omitted the base, is withdrawn with the table
  copy it sat in. (2026-09-27)

(decision-pending-sharing-rule)=
- **Sharing rule widening.** The specification lets any run read
  *current* result sets and keeps scratch within its run; the eligibility
  table on [products](products) also lets another run's stage read a
  *selected candidate*, whatever its check outcome. The team decides
  whether selected candidates are readable across runs and aligns the
  specification or the table. (2026-09-26)
- **Trial policy.** `rebuild-trial@1`'s `approval: trial` is a trial
  approval, not the team's sign-off; promotion refuses a policy with
  `approval: none`, and automatic promotion needs a team approval and
  `auto_promote: true` ([checks](checks)). (2026-09-24, 2026-09-25)

### Checks

- A check always records a row, and a check that raises records
  `failed`. (2026-09-24)
- `catalog-counts-vs-reference@1` finds its reference by slot;
  `rebuild-trial@1` marks `difference-image-statistics` required and
  `catalog-counts-vs-reference` advisory. (2026-09-24, 2026-09-26)
- `run_policy_checks` fills every candidate's slot before any check
  runs. (2026-09-26)
- Known defect, recorded not fixed: the gate can miss a check-result
  row committed after its read. (2026-09-27)
- Checks run outside the pipeline image, on a workstation or the
  launcher host, reaching the database through the instance role.
  (2026-09-24)

### Runs and promotion

- `promotion_changes` carries a nullable `slot`; a replacement's kind
  and slot must equal the requested selector; `StalePlan` refuses when
  the selection or the run's candidates moved since the plan.
  (2026-09-26)
- A bare after-instance with no before is accepted only when the slot
  has no current occupant; a change into an `association-set` slot with
  a non-null expected-before must have the before as an ancestor of the
  after. (2026-09-24)
- Promotion's dependency walk covers every ancestor recursively;
  rollback skips the check-policy gate, the walk and the
  association-set chain-direction rule. (2026-09-24, 2026-09-26,
  2026-09-27)
- Released-image validation and check-policy validation are separate.
  (2026-09-24, 2026-09-26)
- A same-request ancestor passes the dependency walk and is validated
  on its own, against the same eligibility rule and check policy any
  other after-instance answers to. (2026-09-27)
- Rollback reverses by slot only; a recorded change with no slot is
  refused as not reversible. (2026-09-27)
- A policy refusal (`PromotionRefused`, `StalePlan`,
  `CheckPolicyRefused`) exits 1; an argument-shaped refusal or an
  unknown run, instance or promotion id exits 64. (2026-09-27)
- The check-policy gate's `FOR SHARE` lock on the `checks` rows it
  relies on stays; the pipeline role can update `checks` rows, so the
  table is not append-only. (2026-09-27)
- The `approval` value `lead` is renamed `team`. (2026-09-27)
- Seeding a replacement run from a failed one is `--seed --only-failed`;
  seeded instances re-kinded to production become candidates.
  (2026-09-24)
- Run deletion locks the run, verifies the owner, and refuses while a
  frozen input binding depends on it or a reference row would be
  orphaned; the science-row cleanup set is fixed on [runs](runs).
  (2026-09-24)
- Every submission binds its input set before allocating the attempt; a
  name that resolves to nothing is logged, not refused; an unreadable
  manifest refuses with exit 65 before anything is written. (2026-09-25)
- A retry after a failed commit writes a fresh result set; only the
  calling attempt's own prior try or a succeeded attempt's set is reused
  ([crossmatch](crossmatch), [statistics](statistics), [prune](prune)).
  (2026-09-25)
- A scratch run reads the `_SCRATCH`-suffixed job definition and never
  falls back to the unsuffixed one. (2026-09-24)
- Runs written under the first-run prefix stay where they were written.
  (2026-09-24)

### Loop

- The SSM runbook's `executionTimeout` is 21600 s. (2026-09-24)
- The loop's chain carries two `register` steps, after `admit` and
  after `finalize`, since `finalize` never registers the raw difference
  instance; promoting two candidates for the same kind and key is
  refused. (2026-09-26)
- A field's base catalog is the newest earlier complete date's
  association set; each date records `base_promoted` and
  `bases_skipped`. (2026-09-24, 2026-09-25, 2026-09-26)
- A schedule's first date has no base, so a stream over an
  already-current sky continues the existing schedule until a chain
  switch exists. (2026-09-27)
- A finished run takes no new units. (2026-09-25)
- Discovery: identical re-delivery refused, checksum conflict
  quarantined, a corrected version deferred ([loop](loop)). (2026-09-26)
- Under a check policy without automatic promotion, the loop leaves a
  date's run a candidate rather than refusing it; the next date's base
  still binds to it, so a person promotes in date order, an earlier
  date first. (2026-09-27)

### Stage contract and tool

- `maintain` is a fifth stage and `detector-date` a fifth unit kind.
  (2026-09-24)
- `alerts` and `export` read named, completed result sets; `export`
  writes files only; no stage changes another run's results or the
  current selection. (2026-09-24)
- A stage's `validate_inputs` runs after generic validation and before
  the `--dry-run` return. (2026-09-24)
- A stage never exits 1 or 2; the tool's exit 70 covers every
  unclassified error and a parse failure exits 64; exit 65's family is
  listed on [tool](tool). (2026-09-25, 2026-09-26)
- `photometry` and `export` are declared stages that exit 69 past
  validation where not yet ported. (2026-09-24, superseded below)
- **Photometry stub removed.** The rebuild carries no photometry stage;
  forced photometry stays `dev`'s `forcedPhotometryForField.py`. Exit
  code 69 stays reserved in the stage contract, since no stage in this
  build returns it now. Carried from the build, pending team review.
  (2026-09-27)
- `run cancel` from a workstation needs `batch:TerminateJob` on the
  workstation role, not yet granted. (2026-09-24)
- A stage declaration carries no argument schema and no resource
  defaults: nothing read them, and the Batch job definition owns
  resources ([stage contract](stage-contract)). `run create` takes no
  `--lane`, `--profile` or `--db-target`; the run's lane, resource
  profile and database target columns keep their defaults (`local`,
  `local`, the connection's database) and nothing reads them to decide
  anything. (2026-09-27)

### Releases

- The release command, tag form (`rebuild-v0.<n>`, annotated, remote
  authoritative), the `releases` and `release_deployments` tables,
  account-specific steps as hooks, migrations applied with recorded
  checksums before a cut records, a run submitting only to its release's
  job-definition revision, released-image provenance at promotion, one
  pin row per consumer per cut, selftests as evidence not a gate
  ([releases](releases)). (2026-09-24)
- Migrations are additive while an earlier release's runs are open;
  `cut` refuses while any release row is incomplete unless resumed.
  (2026-09-25)

### Stages

- `alerts` is the first registrar of `alert-container` and `alert-set`;
  the outbox locator is an Avro block offset and length plus the
  record's ordinal; an input naming the wrong base or two pruned sets
  for one association set exits 65. (2026-09-24, 2026-09-25)
- Finalize's chain order is `difference -> finalize -> register ->
  load`, one `register` pass. (2026-09-24)
- `reference` is a transform stage with no database access; filter
  spellings are normalised; frame counts are bounded; steps run in
  `dev`'s order; fake-source injection is not ported; the catalog key,
  the full SHA-256 selection digest, the global `refimages.version`
  counter under an advisory lock, `refimages.attempt` recording the
  producing attempt, nullable `npucatsources`, and replay checked against
  the stored block are as [reference](reference) states. (2026-09-24)
- `statistics` reads crossmatch's completion manifest; an association
  set is its own rows plus its base's, recursively; its source sets
  already decide "best". (2026-09-24)
- `prune` excludes a pair unless its difference image is best
  (`vbest > 0`, maintained by promotion) or was made by this run, and
  depends on promotion maintaining `vbest`, not yet built. (2026-09-24)
- `export`'s catalog key hashes the full sorted set of source-set ids; a
  catalog labelled by one field may hold rows of another. (2026-09-24)
- The per-stage log's final line reaches its S3 copy. (2026-09-26)

### Products

- Every instance carries a provenance key, an identity key and a slot,
  derived in the database; a cycle-guard failure leaves the whole batch
  unresolved; identity and slot are derived for every kind. (2026-09-26)
- The reading and promotion-eligibility table applies identically to
  file products and result sets. (2026-09-26)
- The `refimages` field lists and the `catalog-export` registration
  fields are fixed with their stages. (2026-09-24)
