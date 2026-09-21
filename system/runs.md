# Runs, attempts and custody

**Status: DRAFT**

Companion to the specification's Runs section, the [stage contract](stage-contract)
and the [products](products) page: how runs, units of work, attempts, product
instances, result sets and the three custody states are held in the database
and laid out in storage. Written 2026-09-21, revised on a Codex review and on
the lead's schema ruling; direction approved by the lead.
## In plain terms

A run is a row that says who started a pass over which inputs with
which code and settings, and whether its outputs are a person's or the
project's. Each piece of work in the run is a unit; each try at a unit
is an attempt with its own output folder. Every product a finished
attempt made, file or database rows, is an instance row. Three states
on the instance row say whose it is and whether consumers see it.
Promotion changes those rows under one lock and writes down what it
changed, so it can be undone. Files never move; only rows change.
Deleting a scratch run is one guarded operation, and nothing else
deletes run data.

## Tables

| Table | One row per | Key columns |
|---|---|---|
| `runs` | run | id, kind (`scratch`, `production`), owner login, created, state (`open`, `finished`, `deleting`, `deleted`), purpose, selected stages, code revision, image digest, schema version, settings overlay ref, input selection ref, lane, resource profile, database target, max attempts per unit, auto-promote flag, check-policy ref, seed run, expires at, pinned, deleted at |
| `units` | piece of work in a run | run, stage, unit kind, unit id, state (`pending`, `ready`, `running`, `complete`, `failed`, `cancelled`), selected attempt, cancel reason |
| `unit_inputs` | frozen input binding | unit, producer instance |
| `attempts` | execution of a unit | id, run, stage, unit, started, ended, exit code, disposition (null while queued or running; `succeeded`, `failed`, `transient`, `killed`, `lost`), output location, execution record, scheduler job id |
| `execution_records` | attempt | attempt, source revision, working-copy patch, image digest, schema version, resolved settings, settings hash, scheduler metadata; contents stored, not referenced into the run prefix |
| `product_instances` | product an attempt made, file or result set | instance id, kind, logical key, run, producing stage, producing attempt, registering attempt, custody (`scratch`, `candidate`, `current`), format version, primary location, manifest ref, published at, deletion state |
| `product_members` | file in a bundle | instance, role, path, bytes, sha256 |
| `result_sets` | one-to-one extension of an instance that is rows | instance, complete flag, row count |
| `promotions` | promotion action | id, who, when, reason, check-policy version, check result ids, request context |
| `promotion_changes` | affected logical key in a promotion | promotion, kind, logical key, before instance (nullable), after instance (nullable) |
| `checks` | verification result | instance, check name, version, required flag, outcome, when, detail |
| `dependencies` | provenance edge | consumer instance, producer instance |

The `dev` schema's product tables (`l2files`, `refimages`, `diffimages`,
`sources`, `merges`, `astroobjects`, `astroobjectsmeta` and their
companions) are kept with their names and columns. Each gains `run`,
`attempt` and `instance` (or `result_set`) columns, and where a
uniqueness constraint would block two runs holding the same logical
product it is widened to include the run or set. Nothing is renamed and
nothing is dropped (lead, 2026-09-21: changing confuses the team;
`smdc` deleted too much).

## Rules

**Runs.** A run's kind is fixed at creation and decides the custody of
everything it makes: a scratch run makes scratch, a production run makes
candidates. A run freezes its input selection at creation. A run may
bind a complete current result-set instance from another run as a
frozen input; that binding stays valid if the instance is later
superseded, because the dependency retains it. Scratch result sets are
usable only within their own run. Production runs use the one
production database; scratch runs may name a trial database. A run is
finished when every unit is terminal; a finished run is never reopened.
Seeding a new run copies configuration and permitted input selections;
it does not authorise reuse of another run's scratch outputs.

**Units.** A unit is pending until its declared input set is complete
and its upstream attempts are selected. It then becomes ready, and
running when an attempt is allocated. Selection of a successful
completed attempt makes it complete. A retryable failure returns it to
ready while attempts remain; otherwise it becomes failed. Cancellation,
or a permanently failed required dependency, makes an unstarted unit
cancelled with a recorded reason. Complete, failed and cancelled are
terminal. Unit state is stored, not derived. Inputs are bound in
`unit_inputs` before execution and retained for retries.

**Attempts.** Each try is an attempt with a fresh id and an exclusive
output location; an attempt has no disposition while queued or running.
Success requires a valid completion manifest and complete declared
outputs; exit zero alone is not success. Selection locks the unit row
and atomically sets its selected attempt and complete state; the
selected attempt belongs to that unit and the selection never changes.
Late results cannot reopen a terminal unit or replace its selected
attempt. The run records the maximum attempts per unit, counting the
first attempt and all Batch retries; only code 75 and explicitly
approved infrastructure failures are retried; an exhausted allowance
fails the unit. `lost` means the scheduler lost the job: unresolved
execution, treated as a possible writer until resolved.

**Instances.** `register` preserves the instance ids and the producing
run, stage and attempt recorded in the manifest, and records the
registering attempt separately. Replaying an identical manifest is a
no-op; conflicting content for an existing instance id is an error.
Database-writing stages create their own attempt-scoped result-set
instances and record completion, including empty completion. After an
uncertain commit the same attempt recovers its recorded results rather
than inserting duplicates. Published identity, content metadata and
provenance are immutable; custody and deletion metadata change only
through promotion and deletion.

**Custody.** Scratch never leaves scratch. Candidate becomes current by
promotion; current becomes candidate again when superseded. At most one
current instance exists per kind and logical key, enforced by a partial
unique index where custody is current. The current selection is a view
over the instance table and includes file products and result sets
alike. A consumer resolves a related selection from one database
snapshot.

**Promotion eligibility.** Automatic and manual promotion require
completed, selected outputs, a recorded image digest identifying a
released artifact, and passing results for every required check in the
applicable lead-approved check-policy version. Missing or failed
required checks refuse promotion. Every provenance dependency must
identify a complete, retained instance in project custody; a dependency
need not be current. Automatic promotion stays disabled until the lead
approves its policy; reprocessing is a production run with auto-promote
off.

**Promotion.** Default promotion uses a frozen list of the run's
declared deliverables, with exactly one replacement instance per kind
and logical key, each from its unit's selected completed attempt;
intermediate revisions and unselected attempts are excluded. Piecemeal
promotion names an explicit subset and passes the same validation.
Promotion replaces only identical kind-and-logical-key selections;
different settings or upstream instances produce additional current
products rather than supersede earlier ones. All promotions take one
transaction-scoped advisory lock; after acquiring it the transaction
checks every expected previous selection, including expected absence,
against the actual selection and refuses the whole request on any
mismatch, then validates dependencies, updates custody and records the
action. Each promotion records a before and after instance for every
affected key, either nullable. Reversal submits the inverse mapping and
is refused if the recorded after-selection is no longer current.

**Deletion.** `run delete` is allowed on a scratch run by its owner.
It first locks the run, verifies the owner, refuses if any attempt is
queued, running or unresolved, or if any frozen input binding of
unfinished work or any provenance dependency of a retained output
outside the run points into it, and marks the run deleting, in one
transaction. Attempt allocation, input binding and result acceptance
use the same run fence and refuse a deleting or deleted run. After the
deleting state commits, cleanup idempotently removes the run's object
versions and run-scoped science rows, then records completion; failure
leaves the run deleting so cleanup resumes. Custody stays separate from
deletion state. Run, unit, attempt and instance rows remain as
tombstones with their provenance. Scratch expiry calls the same
operation after the run's expiry date, with a warning first and a pin to
hold a run; no age-based lifecycle rule expires run data on its own.

## Storage layout

Two buckets separate personal and project custody. Candidate and
current objects share the project bucket and never move at promotion.
Ordinary execution roles cannot delete completed objects; only the
cleanup role deletes, and only through `run delete`. Within either
bucket:

```
runs/<run-id>/<stage>/<unit-id>/<attempt-id>/manifest.json
runs/<run-id>/<stage>/<unit-id>/<attempt-id>/<member paths from the manifest>
```

Admitted inputs and reference images live under the same scheme in the
project bucket, in the run that admitted or built them. Consumers read
current products through the selection, never by guessing paths. Alert
containers follow the same scheme; the outbox row carries the
container's location and each alert's byte range.

## Identifiers

Runs, attempts and product instances receive globally unique,
time-ordered identifiers (ULID) before execution or manifest
publication, allocated by whoever creates the row, so the local runner
and the Batch wrapper need no database to allocate; registration
preserves them. Date-and-sequence names such as `r-20260921-007` are
display labels only. Unit identity is unique within a run and stage and
uses the product vocabulary's unit identifiers.

## Schema

The run-model tables above land as one migration beside the baseline.
The additive columns and widened keys on the `dev` product tables land
one kind at a time, difference image first, each with the stage that
writes it. Ruled by the lead 2026-09-21: the `dev` schema coexists and is
kept as far as possible; the rebuild adds, it does not rename or drop.

## Not decided here

- The approved check policy that turns auto-promote on.
- The scratch lifetime and warning mechanics.
- The trial-database mechanism for scratch runs.
- Whether consumers want a reprocessing with changed settings to
  supersede the old result or sit beside it; the rules above make it
  sit beside, per the products page's keys.
