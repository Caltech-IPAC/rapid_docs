# Glossary

**Status: DRAFT**

RAPID's vocabulary is named for its data model rather than for the
science, and a reader meeting it for the first time has to learn a dozen
words before any runbook or design page reads cleanly. This page is
where those words are defined once. The design documents own the
concepts; this page owns only the definitions, and each entry says where
the concept is designed.

Terms specific to one domain stay in that domain's document. What is
collected here is the vocabulary that appears across several documents
and in the operational runbooks: the words that a reader cannot avoid.

## The processing chain

**l2file**: A calibrated science image from the Roman Science
Operations Center, and RAPID's pipeline input. "L2" is the calibration
level; an l2file is one such product as RAPID holds it, registered in
the `l2files` table with one row per registered image product version.
The corresponding input grain is one SCA, not one exposure. Designed in
[`data-model.md`](data-model) (identity layer) and
[`interfaces.md`](interfaces) (SOC input).

**grain**: The granularity at which a thing is processed or measured,
what one unit of it is. RAPID's measurement grain is one L2 SCA, the
subject of one difference work unit, and the 18 SCAs of an exposure are
processed independently, with no wait for the full exposure. Grain is
declared per job type (exposure/SCA, date/SCA, date/field, field, or
release-unit) rather than assumed, and dedup identity derives from the
declared subject rather than from a storage path. Designed in
[`operations.md`](operations).

**admission**: The step that takes input files and makes them eligible
for processing: RAPID accepts them, stamps them with a release identity,
and records that they are now the system's to process. Nothing is
processed that was not admitted, and what admission stamps is what the
rest of the chain must agree with. Designed in
[`operations.md`](operations).

**admission pointer**: The record of which release identity admission
is currently stamping. It is a pointer rather than a setting because it
moves: campaigns and production advance it deliberately, and a
submission whose release identity disagrees with it is refused rather
than run. Moving the pointer is an audited mutation.

**work unit**: RAPID's independent unit of processing: one immutable
process specification applied to one canonical typed subject and input
set. It is the thing that either gets done or does not. A work unit is
not a job: it may be attempted more than once, and it closes only when
an attempt succeeds. Designed in [`operations.md`](operations) and
[`data-model.md`](data-model).

**attempt**: One try at a work unit. The attempt is the record that
carries what actually happened: which release and image digest ran, when
it started and ended, its exit, its stage timings, and its outcome. A
work unit has at most one active attempt at a time; the history of a
work unit is the sequence of its attempts. Most operational questions
are answered from the attempts table rather than from work units,
because the attempt is where the evidence is. Designed in
[`data-model.md`](data-model) and [`observability.md`](observability).

**submission**: A first-class record of one act of submitting work,
carrying the attempts it launched. It exists as an entity rather than as
an event because the system has to be able to say afterwards what was
submitted together, under which release, by whom. Designed in
[`data-model.md`](data-model); the protocol is in
[`compute.md`](compute).

**batch execution**: The AWS Batch side of an attempt: the job the
scheduler actually ran. It is deliberately a separate record from the
attempt, because the scheduler's view and RAPID's view can disagree:
Batch can report a job gone that the database still believes is in
flight, and reconciliation exists to resolve exactly that disagreement.
Designed in [`compute.md`](compute).

## Outcomes and state

**currency**: Which version of a product is the current one. Products
are registered per version rather than overwritten, so "current" is a
pointer (`vbest`) rather than a fact about the file, and registering a
new version demotes the old one. Currency is scoped: as of the run-scoped
registration work, a run's products are current within their run rather
than globally. Designed in [`catalog.md`](catalog) (promotion and
product roles) and [`data-model.md`](data-model).

**dead letter**: An attempt that never ran, blocked by an internal
failure rather than by anything about the data. Dead letters accumulate
as a class to be released, re-offered for attempt, rather than being
retried silently, so that the failure stays visible. Some dead-letter
classes grow by design and nobody works them; that is a deliberate
choice about where evidence lives, not an oversight. This term is
operational vocabulary: it is used by `rapidctl` and the runbooks and is
not otherwise defined in the design documents.

## Scope

**run**: A named, bounded piece of processing, with its own identity
(`run_id`) that its work units, attempts and products carry. A run is
what an operator asks for and what gets compared, archived and reasoned
about afterwards. Runs are the unit of isolation the system is being
moved toward: schema support for per-run scoping exists, and making the
writers honour it throughout is open work.

A run is not one submission. A single run is typically submitted in many
batches, each with its own submission name, which is why tooling that
takes a run name will not accept a submission name.

**campaign**: Processing run deliberately, by a person, over a chosen
set of inputs: a bounded piece of work with a start, an end and a
purpose. Campaigns are how reprocessing, validation and scale testing
are done, and how every run on the deployed environment is currently
done.

**production**: Processing run continuously by the controller as data
arrives, without a person asking for each piece. Production is the
routine-operations posture the system is designed for; the operating
lifecycle in [`operations.md`](operations) describes why it cannot begin
immediately after launch.

The distinction matters operationally, not just descriptively. The two
use separate lanes, so a campaign does not disturb production's products
or currency. And they are mutually exclusive in practice today: the
controller's gatherers select work by processing date, field and attempt
state rather than by run, so a live controller and a hand-driven
campaign over the same dates would both find the same work and both
submit it. The controller is therefore held while campaigns run.

## Related

- [`operations.md`](operations): the operational lifecycle, the
  controller, admission, reconciliation, and the `rapidctl` surface.
- [`data-model.md`](data-model): the entity layers and the identity
  chain.
- [`naming.md`](naming): how names are coined, and the token registry.
