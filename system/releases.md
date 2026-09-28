# Releases

**Status: DRAFT**

Operations run a release while `main` moves every day. A release is a
commit that has been tagged, migrated, built into an image and deployed,
with a database row recording each step. Cutting a release performs
those steps in order and records success only when each step has the
required evidence. The [specification](specification)'s Releases
section states the requirement; this page defines the tag, record and
cut, and what the launcher and promotion require of them.

## The command

`rapidpipe release cut|show|list|verify`, also runnable as
`python -m rapidpipe.release`, and wrapped unchanged by the future
`rapidctl`. The full flag surface for `cut`, `show`, `list` and `verify`
is on the [tool](tool) page. The Python interface is
`rapidpipe.release.core`: `next_tag`, `cut`, `show` and `verify`, and
the `Release` dataclass that represents the release record.

## The tag

A release tag is annotated, on the `rebuild` branch, and named
`rebuild-v0.<n>`. Here `n` is one more than the highest tag already
pushed: remote tags are authoritative. The scheme becomes `v1.<n>`
once the rebuild replaces `main`, as sequenced in the specification.

The tag message is the release's initial manifest: the tag, its source
revision, the tagged tree's schema version, and who cut it and when.
Once written, the tag is never amended, moved or deleted. Later
evidence, including images built and consumers deployed, goes in the
release record. The image registry tag equals the git tag. Registry
tag immutability makes a second build under the same tag fail outright,
meeting the specification's requirement without a separate check in the
cut.

## The record

Two tables carry a release's state. `releases` holds one row per tag:
source revision, schema version, image digest, image reference, who cut
it and when, and when it completed. Its state advances through
`migrated`, `built`, `deployed` and `complete`.
`release_deployments` holds one row per consumer the release reaches:
the release, consumer, deployed job definition name and revision, and
who deployed it and when.

An attempt's execution record carries the release identity its job
definition was deployed under, read from the deploy-time environment
variable `RAPID_RELEASE_IDENTITY`. A job definition never deployed
under a release reports `unreleased`; reconcile stores whichever value
it finds.

## The order of a cut

`cut` runs six steps in order: tag, migrate, record, build, deploy,
pins. The systems repository supplies executables, called hooks, for
the account-specific steps: migrate, build, deploy and pins. `cut`
invokes them in order with the release's tag, source revision and schema
version in their environment. All account-specific details live in the
hooks; the pipeline repository names no account, host or bucket.

Each hook reports its result as one JSON object on its last line of
output, and `cut` reads only that line:

| Hook | Reports |
|---|---|
| migrate | the schema version reached and the migration files applied |
| build | the image digest and its registry reference |
| deploy | each consumer's job definition revision |
| pins | the number of rows written |

Hooks are idempotent. `--resume TAG` re-enters a cut at its recorded
state without re-tagging. `cut` never retries a hook: a failure leaves
the record at its last completed step for a person to fix and resume.
`--skip HOOK` omits one step whose account side was already done by
hand. `--dry-run` prints the planned order and each hook's command
without running them or writing the record.

The final pins step appends one row per rebuild consumer to the
operations pin table. It reads each consumer's live job definition and
records the release identity beside it, so the database states which
release is deployed. The existing daily pin sweep over the legacy
pipeline's consumer set is unchanged; the cut's pin step covers the
rebuild's consumers alongside it.

CI on `rebuild` gates the source before tagging. The cut stops at
deploy and pins. Selftests run afterwards on Batch under the newly
deployed revision as evidence that the image behaves; the cut does not
wait for them.

## Migrations at release time

A release's schema version is the greatest migration filename in its
tagged tree. The migrate hook applies that tree's migrations to the
release's database target. `cut` refuses to record the release until
every file is applied with the checksum the migration applier recorded
for it. Migration always precedes image deployment, so a job definition
revision never runs code ahead of its expected schema.

Migrations must stay additive (new tables and nullable columns; no drop
or rename while an earlier release's runs are open) and compatible with
the readers and writers of every release whose runs remain open. This
is a constraint of the migration rule. Together with the fixed release
binding below, it makes cutting a release while other runs remain open
safe.

## The launcher reads the release

A run's release is fixed at creation by `run create --release`. It
copies the source revision and image digest from the release record,
without reading git or the environment. Every unit submits to the job
definition revision that the release's `release_deployments` row
records for the run's kind, verified `ACTIVE` before submission. There
is no fallback to the latest revision.

A later cut repoints the job definition to a new revision, so operations
must keep earlier revisions alive for runs still using them.
`SkipDeregisterOnUpdate` keeps a revision `ACTIVE` past its own
release. Retention of superseded revisions belongs to the systems
repository. Every attempt reads the same release's recorded revision:
a run never picks up a later cut mid-flight, and its execution records
and `schema_version` all carry the release it was created under.

A run started without a release submits by the unversioned job
definition name and may pick up a revision a later deploy repoints it
to. This carries the specification's "scratch runs may use any commit"
through to the job definition.

The processing-date loop's binding to a release is resolved on the
[loop](loop) page: the loop's spec names the release, and the scheduled
operation checks that tag out before running each date.

## Promotion eligibility

Promotion checks executed provenance. Every deliverable's selected
producing attempt must have an execution record whose image digest
matches a complete release's digest. Its recorded release, when present,
must be that release's tag; a tag on a commit alone does not suffice.
Failure refuses promotion unless the operator passes the explicit
unreleased exception, which is then recorded in the promotion's request
context. This closes the trial exception recorded earlier on the
[runs](runs) page: a missing released-image check refuses promotion
unless waived.

## Concurrent cuts are serialised

Before any fetch or tag, `cut` refuses to start while any `releases`
row has a state other than `complete`, unless `--resume` names that
row. The refusal names the tag and state and exits 1 (the
[tool](tool) page's table). To continue a cut that failed partway, use
`--resume` for the row already in flight.

The row is written only after the tag is pushed. Two cuts started at
the same instant can therefore both pass the check before either has a
row. The rule serialises cuts once a record exists; it is not a lock.
Closing that window remains open.

## Not decided here

- Signing of tags or images.
- The `v1` cutover and whether the production database becomes a
  release target.
