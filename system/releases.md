# Releases

**Status: DRAFT**

How operations move from a commit to a running, verified version: the
tag, the record that ties a commit to a schema and an image, the
command that cuts one, and what promotion and the launcher require of
it. Written 2026-09-24 from supervisor step 5's rulings (R1 through R9).
The [specification](specification)'s Releases section states the
requirement; this page records how the rebuild meets it.

## In plain terms

`main` moves every day; operations do not follow it. A release is one
point on that history that has been tagged, migrated, built into an
image and deployed, with a database row recording each step. Cutting a
release is the one operation that performs all of it in order and
refuses to record success until every step's evidence says so. A run
created under a release reads that row, never the branch or the
environment, so what a run used is exactly what the record says it
used.

## The command

`rapidpipe release cut|show|list|verify`, also runnable as
`python -m rapidpipe.release`, and wrapped unchanged by the future
`rapidctl` (ruling R1, 2026-09-24). `cut` takes `--tag`, `--ref`,
`--hooks-dir`, `--skip HOOK`, `--resume TAG` and `--dry-run`; `show`
prints one release's record; `list` prints every recorded release;
`verify` checks a recorded release against its live state. The Python
interface is `rapidpipe.release.core`: `next_tag`, `cut`, `show` and
`verify`, and the `Release` dataclass the record above maps onto.

## The tag

A release tag is annotated, on the `rebuild` branch, named
`rebuild-v0.<n>` where `n` is one more than the highest tag already
pushed; remote tags are authoritative, not a local checkout's (ruling
R2, 2026-09-24). The scheme becomes `v1.<n>` once the rebuild replaces
`main`, the specification's own sequencing point for that move.

The tag message is the release's initial manifest: the tag, the source
revision it points at, the schema version the tagged tree carries, and
who cut it and when. Once written it is never amended, moved or
deleted; everything a cut learns afterwards, images built and
consumers deployed, lives in the release record instead, not in the
tag. The image registry tag equals the git tag, and registry tag
immutability then does the same job on the image side: a second build
under the same tag fails outright, which is the immutability the
specification asks for without any check the cut has to write itself.

## The record

Two tables carry a release's state (ruling R3, 2026-09-24). `releases`
holds one row per tag: source revision, schema version, image digest,
image reference, a state that advances `migrated`, `built`,
`deployed`, `complete`, who cut it and when, and when it completed.
`release_deployments` holds one row per consumer a release reaches:
the release, the consumer, the job definition name and revision
deployed, and who deployed it and when.

A run created under a release copies its source revision and image
digest from this record; it reads nothing from git or the environment
to get them. An attempt's execution record carries the release
identity its job definition was deployed under, read from the
deploy-time environment variable `RAPID_RELEASE_IDENTITY`; a job
definition never deployed under a release reports `unreleased`, and
reconcile stores whichever value it finds.

## The order of a cut

`cut` runs six steps in order: tag, migrate, record, build, deploy,
pins. The account-specific steps, migrate, build, deploy and pins, are
hooks: executables the systems repository supplies, which `cut` invokes
in order with the release's tag, source revision and schema version in
their environment (ruling R4, 2026-09-24). The pipeline repository
itself names no account, host or bucket; everything account-specific
lives in the hook, on the other side of that boundary.

Each hook reports its result as one JSON object on its last line of
output, and `cut` reads only that line:

| Hook | Reports |
|---|---|
| migrate | the schema version reached and the migration files applied |
| build | the image digest and its registry reference |
| deploy | each consumer's job definition revision |
| pins | the number of rows written |

Hooks are idempotent, so `--resume TAG` re-enters a cut at the state
its record already reached without re-tagging; `cut` itself never
retries a hook; a hook that fails leaves the record at its last
completed step for a person to fix and resume. `--skip HOOK` omits one
step for a cut whose account side was already done by hand; `--dry-run`
prints the planned order and each hook's command without running any of
them or writing the record.

## Migrations at release time

A release's schema version is the greatest migration filename present
in its tagged tree. The migrate hook applies that tree's migrations to
the release's database target, and `cut` refuses to record the release
until every one of those files is applied with the checksum the
migration applier recorded for it (ruling R5, 2026-09-24). Migration
therefore always precedes the image deploy in a cut, so a job
definition revision never runs code ahead of the schema it expects. A
run started without a release still submits by the unversioned job
definition name and may pick up a revision a later deploy repoints it
to, the specification's "scratch runs may use any commit" carried
through to the job definition itself.

## The launcher reads the release

A run created under a release submits every unit to the job definition
revision that release's `release_deployments` row records for the
run's kind, verified `ACTIVE` before submission; there is no fallback
to whatever revision is latest (ruling R6, 2026-09-24). That makes a
job definition revision something operations must keep alive past its
own release: a later cut's deploy step repoints the job definition to a
new revision, and a run still reading the earlier release needs the
earlier revision to still exist. Retention of superseded revisions is a
systems-repository concern, not a pipeline one.

The processing-date loop's binding to a release is resolved on the
[loop](loop) page: the loop's spec names the release, and the scheduled
operation checks that tag out before running each date (supervisor step
7, 2026-09-24).

## Promotion eligibility

Promotion checks executed provenance, not a tag on a commit: every
deliverable's selected producing attempt must have an execution record
whose image digest matches a complete release's digest, and whose
recorded release, when it has one, is that release's tag. A deliverable
that fails this refuses promotion, unless the operator passes the
explicit unreleased exception, which the promotion's request context
then carries (ruling R7, 2026-09-24). This closes the trial exception
the [runs](runs) page recorded for step 3: promotion no longer treats a
missing released-image check as passing by default, it treats it as
refused unless waived.

## Deployed pins

The last step of a cut appends one row per rebuild consumer to the
operations pin table, reading each consumer's live job definition and
writing the release identity beside it, so which release is deployed
has a database answer rather than a person's memory of the last deploy
(ruling R8, 2026-09-24). The daily pin sweep that already runs against
the legacy pipeline's own consumer set is unchanged; a cut's pin step
covers the rebuild's consumers alongside it.

## Selftests are not part of a cut

CI on `rebuild` gates the source before any tag is cut; a cut's own
steps stop at deploy and pins. Selftests run on Batch under the newly
deployed revision afterwards, as evidence that the deployed image
behaves, not as a gate the cut itself waits on (ruling R9, 2026-09-24).

## Not decided here

- Signing of tags or images.
- The `v1` cutover and whether the production database becomes a
  release target.
- Whether a release change overlaps for consumers mid-migration or
  switches by pointer: the specification's own "Not decided here" list
  carries this one.
