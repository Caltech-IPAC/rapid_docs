# The finalize stage

**Status: DRAFT**

What the `finalize` stage reads, what it republishes, the header stamp it
writes, and its settings and exit codes. Written 2026-09-24 from the port
landing on the pipeline repository's `rebuild` branch
(`rapidpipe/stages/finalize.py`, `rapidpipe/science/finalize/headers.py`,
`rapidpipe/settings/finalize.toml`, `rapidpipe/products/diffimage.py`),
ported from `dev`'s post-processing pipeline, `ppid` 17
(`pipeline/awsBatchSubmitJobs_runSinglePostProcPipeline.py`). The port
follows the lead's rule of 2026-09-22: minimise differences to `dev`, and
design in, off by default, anything that can be left unused. The
[products](products) page fixes the vocabulary; this page records how
the stage meets it.

## In plain terms

`dev` finishes a difference image by adding a dozen bookkeeping keywords
to its header, letting astropy stamp `CHECKSUM` and `DATASUM`, then
overwriting the S3 object it just read and updating `diffimages` in
place. The rebuild never overwrites a published instance, so `finalize`
takes a `difference` attempt's completed output, writes a new instance
of the same kind with the stamped header, and copies every other file
in the bundle unchanged. `register` then records the finalized instance;
the raw instance `difference` wrote is never registered on its own, and
`load` reads the finalized instance's catalogs. `dev`'s reference-image
stamp is not ported: a reference is the `reference` stage's own
product, already an instance in its own right, and `finalize` never
rewrites it.

Chain order is `difference -> finalize -> register -> load` (supervisor
step 2, 2026-09-24), one `register` pass, matching `dev`'s one
`diffimages` row per image. `register_manifest` writes a dependency edge
for every producer named in `inputs.products`, and that edge has a
foreign key to `product_instances`, so `inputs.products` can only name
instances that already have a row there. `finalize`'s own raw input does
not, since it is never registered; `finalize` instead names the raw
difference manifest's own upstream, `l2-image` and, when the difference
manifest carried it, `reference-image`, the same instances `difference`
itself already depended on and that are already registered. Provenance
to the raw difference instance is kept three other ways: the finalized
block's `finalized_from` field, each copied catalog's `copied_from`
field, and the `RPFINFRM` keyword stamped into the file itself; the
manifest's own `inputs.manifest` reference also points at the raw
difference attempt's manifest.

## Inputs

`--inputs` is a `difference` attempt's output location: its completion
manifest and files. The stage reads:

| Entry | Members | Used for |
|---|---|---|
| the `difference-image` entry for `[finalize] differencer` | `difference`, `uncertainty`, `significance` where present, `psf`, `kernel` where present | the file to stamp and copy, and the registration block to extend |
| its `source-catalog` entries, however many are keyed to it (0..n) | `catalog`, and any other declared member (Photutils `finder`, `residual`, `parquet`; SFFT's own catalogs) | copied through unchanged |

A difference manifest can carry two `difference-image` entries, ZOGY's
and SFFT's, when `[sfft] register_sfft` was on; `[finalize] differencer`
picks the one `finalize` republishes, the same convention `load`'s own
`differencer` setting uses. The other differencer's entry and its
catalogs are dropped, named in the execution record's `notes.dropped`
as `[{kind, instance, differencer}]`, and never written anywhere.
Every catalog keyed to the chosen entry passes through, in input order;
none is required, so an image whose Photutils catalog was not produced
simply has fewer entries to carry through. Every member is verified for
size and SHA-256 before use. A manifest that is not stage `difference`'s,
that has no entry for the chosen differencer, or that carries an entry
finalize does not know how to republish, is rejected.

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

Nothing is read from the file contents to do this beyond the stamped
primary member; the catalogs and the other difference-bundle members
move as bytes. The copy costs about 330 MB per detector image, mostly
the difference bundle's own members moving from the raw instance's
location to the finalized instance's; this is recorded as a known cost
of never referencing another attempt's location, not fixed here (a
manifest entry able to point at another attempt's file would remove it,
at the cost of the immutability the run model is built on).

`registration.md5` is recomputed over the stamped primary file, not
carried over from the input: it is the one field the header rewrite
actually changes.

## The header stamp

Only the primary HDU of the `difference` member is touched; its data and
every other HDU are written back unchanged. `dev`'s database-id keywords
(`PID`, `RID`, `EXPID`, `FID`, `DIFIMVER`) and its S3 location keywords
(`S3BUCKN`, `S3OBJPRF`) are not stamped: those legacy ids and locations
are `register`'s to allocate and record, not finalize's, and `RPOUTLOC`
replaces the bucket-and-prefix pair with this attempt's own output
location. `PPID`, `INFOBITS`, `FIELD`, `DIFFILEN` and `DATE` keep `dev`'s
names and meanings. The keyword list is fixed in
`rapidpipe/science/finalize/headers.py`, not a setting.

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

Every keyword is checked FITS-legal (eight characters or fewer, `A-Z
0-9 _ -`) and unique before the stage runs. A value too long for one
card (`RPSETHSH`, `RPFSETHS`, `RPIMGDIG`, or a long `RPOUTLOC`) is
written with the FITS long-string convention, `&` continuation plus
`CONTINUE` cards, rather than letting astropy silently cut its comment.

## Settings

`rapidpipe/settings/finalize.toml`:

| Setting | Default | Meaning |
|---|---|---|
| `[finalize] differencer` | `zogy` | which of the input manifest's `difference-image` entries this attempt republishes, `load`'s own convention; must be `zogy` or `sfft` |
| `[pipelines] zogy` | 15 | the `pipelines` row `PPID` records for a ZOGY-differenced image, `dev`'s science-pipeline row |
| `[pipelines] sfft` | 16 | the `pipelines` row `PPID` records for an SFFT-differenced image, the row the lead assigned 2026-09-24 |

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
which builds a synthetic `difference` attempt's output
(`rapidpipe/selftest/support/fakefinalize.py`) and checks the republished
manifest, the stamped header and every copied member against it. The
stage runs no external tool and touches no database, so the fixture is
the same with and without `--real-tools`, and the same fixture runs
through `rapidpipe selftest --stage finalize` on Batch.
