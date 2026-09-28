# The finalize stage

**Status: DRAFT**

The `finalize` stage stamps a difference image's header and republishes
its bundle as new instances. It lands on the pipeline repository's
`rebuild` branch
(`rapidpipe/stages/finalize.py`, `rapidpipe/science/finalize/headers.py`,
`rapidpipe/settings/finalize.toml`, `rapidpipe/products/diffimage.py`),
ported from `dev`'s post-processing pipeline, `ppid` 17
(`pipeline/awsBatchSubmitJobs_runSinglePostProcPipeline.py`). Every
ported stage minimises differences from `dev` and leaves optional
features designed in but off by default. The [products](products) page
fixes the vocabulary.

## In plain terms

`dev` adds a dozen bookkeeping keywords to a difference image's header,
lets astropy stamp `CHECKSUM` and `DATASUM`, then overwrites the S3
object it read and updates `diffimages` in place. The rebuild never
overwrites a published instance. Instead, `finalize` takes a
`difference` attempt's completed output, writes a new instance of the
same kind with the stamped header, and copies every other file in the
bundle unchanged. `dev`'s reference-image stamp is not ported: the
reference is already the `reference` stage's own product instance, and
`finalize` never rewrites it.

Chain order is `difference -> finalize -> register -> load`, with one
`register` pass, matching `dev`'s one `diffimages` row per image.
`register` records only the finalized instance; the raw instance
`difference` wrote is never registered on its own. `load` reads the
finalized instance's catalogs.

## Inputs

`--inputs` is a `difference` attempt's output location: its completion
manifest and files. The stage reads:

| Entry | Members | Used for |
|---|---|---|
| the `difference-image` entry for `[finalize] differencer` | `difference`, `uncertainty`, `significance` where present, `psf`, `kernel` where present | the file to stamp and copy, and the registration block to extend |
| its `source-catalog` entries, however many are keyed to it (0..n) | `catalog`, and any other declared member (Photutils `finder`, `residual`, `parquet`; SFFT's own catalogs) | copied through unchanged |

When `[sfft] register_sfft` was on, a difference manifest can carry two
`difference-image` entries, ZOGY's and SFFT's. `[finalize] differencer`
selects which one `finalize` republishes, following `load`'s
`differencer` convention. The other entry and its catalogs are dropped
and never written anywhere; the execution record names them in
`notes.dropped` as `[{kind, instance, differencer}]`.

Every catalog keyed to the chosen entry passes through in input order.
None is required: a missing Photutils catalog simply leaves fewer
entries to copy. Every member is checked for size and SHA-256 before
use. The stage rejects a manifest that is not stage `difference`'s,
has no entry for the chosen differencer, or carries an entry finalize
cannot republish.

## What it republishes

`finalize` writes one new instance per input entry, all under a single
new instance id shared by the difference-image entry (the source-catalog
entries get their own new ids, keyed to it):

- The `difference-image` entry keeps its logical key. Its `difference`
  member is rewritten with the stamped header, written with astropy's
  `writeto(..., checksum=True)` so `CHECKSUM` and `DATASUM` are
  recomputed for every HDU; every other member (`uncertainty`,
  `significance`, `psf`, `kernel`) is copied byte for byte. All members
  are re-hashed under the new instance's location. The registration
  block is copied from the input and extended with `finalized_from`,
  the raw instance id, and `revision`, set to 2 (a block without these
  two fields is revision 1, as `difference` writes it).
- Each `source-catalog` entry gets a new instance id and a key whose
  `difference` field now names the finalized instance; its other key
  fields (`catalog_type`, `sign`) are unchanged. Every member is copied
  byte for byte. The registration block is copied from the input and
  extended with `copied_from`, the input catalog instance id.

`registration.md5` is recomputed over the stamped primary file, not
carried over from the input: it is the one field the header rewrite
changes.

Only the stamped primary member's contents are read; the catalogs and
other difference-bundle members move as bytes. Copying costs about
330 MB per detector image, mostly to move the difference bundle from
the raw instance's location to the finalized instance's. This known
cost of never referencing another attempt's location is not fixed here.
Allowing a manifest entry to point at another attempt's file would
remove it at the cost of the run model's immutability.

`register_manifest` writes a dependency edge for every producer in
`inputs.products`. The edge's foreign key to `product_instances` means
each named instance must already have a row there. The raw input has
none, so `finalize` names the raw difference manifest's registered
upstream instances instead: `l2-image` and, when the manifest carried
it, `reference-image`. These are the same instances `difference`
already depended on.

Provenance to the raw difference instance remains in the finalized
block's `finalized_from`, each copied catalog's `copied_from`, and the
file's `RPFINFRM` keyword. The manifest's `inputs.manifest` also points
to the raw difference attempt's manifest.

## The header stamp

Only the primary HDU of the `difference` member is touched; its data and
every other HDU are written back unchanged. `dev`'s database-id keywords
(`PID`, `RID`, `EXPID`, `FID`, `DIFIMVER`) and its S3 location keywords
(`S3BUCKN`, `S3OBJPRF`) are not stamped: `register` allocates and records
those legacy ids and locations. `RPOUTLOC` replaces the bucket-and-prefix
pair with this attempt's output location. `PPID`, `INFOBITS`, `FIELD`,
`DIFFILEN` and `DATE` keep `dev`'s names and meanings. The keyword list
is fixed in `rapidpipe/science/finalize/headers.py`, not configurable.

| Keyword | Source |
|---|---|
| `RPRUN` | this finalize attempt's run id |
| `RPATTMPT` | this finalize attempt's attempt id |
| `RPINST` | the new, finalized difference-image instance id |
| `RPSTAGE` | the literal `finalize` |
| `RPFINFRM` | the input (raw) difference-image instance id |
| `RPL2INST` | the raw difference manifest's `inputs.products` l2-image id, or the logical key's `l2` field if that entry is absent |
| `RPREFINS` | the raw difference manifest's `inputs.products` reference-image id, or the logical key's `reference` field if that entry is absent (`difference` omits the entry for a dev-registered reference) |
| `RPDIFFER` | the logical key's `differencer` |
| `RPSETHSH` | the logical key's `settings_hash`, the original difference attempt's, unchanged by finalize |
| `RPFSETHS` | this finalize attempt's own resolved settings hash |
| `RPSRCREV` | the difference attempt's execution record `source_revision`, or `unknown` if the record is absent or the field is empty |
| `RPIMGDIG` | the difference attempt's execution record `image_digest`, or `unknown` under the same rule |
| `RPOUTLOC` | this finalize attempt's output location, as `--outputs` was given |
| `PPID` | the `pipelines` row id for the differencer: `zogy` 15, `sfft` 16, from the `[pipelines]` setting, the same map `rapidpipe.db.diffimages.DIFFERENCER_PPIDS` uses |
| `INFOBITS` | the registration block's `catalog_outcome_bits`, `dev`'s `infobitssci` meaning kept |
| `FIELD` | the Roman tessellation field of the registration block's `centre` (RA, Dec), the same closed-form lookup `load` uses |
| `DIFFILEN` | the base name of the primary member |
| `DATE` | the stamp time, UTC, ISO 8601 to the second |
| `CHECKSUM`, `DATASUM` | astropy's own, from `writeto(..., checksum=True)` |

Before the stage runs, every keyword is checked for uniqueness and FITS
legality (eight characters or fewer, `A-Z
0-9 _ -`). Values too long for one card (`RPSETHSH`, `RPFSETHS`,
`RPIMGDIG`, or a long `RPOUTLOC`) use the FITS long-string convention:
`&` continuation plus `CONTINUE` cards. This prevents astropy from
silently cutting their comments.

## Settings

`rapidpipe/settings/finalize.toml`:

| Setting | Default | Meaning |
|---|---|---|
| `[finalize] differencer` | `zogy` | which of the input manifest's `difference-image` entries this attempt republishes, `load`'s own convention; must be `zogy` or `sfft` |
| `[pipelines] zogy` | 15 | the `pipelines` row `PPID` records for a ZOGY-differenced image, `dev`'s science-pipeline row |
| `[pipelines] sfft` | 16 | the `pipelines` row `PPID` records for an SFFT-differenced image, the row the team assigned |

An invalid `[finalize] differencer`, or a non-positive value in
`[pipelines]`, fails settings validation.

## Exit codes

| Code | When |
|---|---|
| 0 | republished: the finalized entries were written and the manifest published |
| 64 | a setting is missing, empty, or invalid, including `[finalize] differencer` outside `zogy`/`sfft` or a non-integer or non-positive `[pipelines]` value |
| 65 | the input manifest is not stage `difference`'s, does not have exactly one `difference-image` entry for `[finalize] differencer`, carries an entry finalize does not republish, a member fails its size or SHA-256 check, the primary member cannot be opened as FITS, an execution record is present but unreadable, or the chosen differencer has no `[pipelines]` row |
| 70 | any unclassified error, including a failure while writing the stamped file |
| 75 | not used, because the stage has no external dependency |

## Local execution

`make stage-finalize` runs `tests/fixtures/finalize/run_fixture.py`,
which builds a synthetic `difference` attempt's output with
`rapidpipe/selftest/support/fakefinalize.py`. It checks the republished
manifest, stamped header and every copied member against that output.
The stage runs no external tool and writes no database rows, so the fixture
is the same with and without `--real-tools`. It also runs through
`rapidpipe selftest --stage finalize` on Batch.
