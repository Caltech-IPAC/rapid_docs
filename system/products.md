# Products

**Status: DRAFT**

The [stage contract](stage-contract)'s `consumes` and `produces`
declarations use the product vocabulary defined here. Each kind has a
uniqueness rule and manifest metadata that `register` uses to record it.
The tables below map this vocabulary onto the `dev` schema. Existing
tables and columns keep their names and meanings; missing columns or
tables are added, and nothing is renamed or dropped.

## In plain terms

A product is something a stage makes for another stage or a consumer:
an image, catalog file, alert file, or set of database rows. Each kind
has a fixed name and required manifest fields, so registration never
needs to open the file. Making the same thing twice gives two instances
of one logical product. The instance id tells them apart; promotion
selects the one consumers see.

## Identity

Every instance carries three keys. The provenance key is the manifest's
`key`: for a difference image, the detector image, reference,
differencer and settings. It names the exact input instances consumed,
so reprocessings have different provenance keys even when their science
is identical. Stages write this key unchanged; it remains in
`product_instances.logical_key`. Existing readers, including a base
association set's ancestor walk and a retry's reuse lookup, need no
change.

The identity key (column `identity`) contains every scientific
distinction: delivered facts and science choices, never instance ids.
The slot (column `slot`) is the subset a consumer selects on, "the
current X for Y". Both columns are nullable JSON. Stages write neither;
the database derives them from the provenance key through
`product_identity_fill()`. It first resolves each named producer's
identity, then derives the instance's identity and finally its slot.
The manifest is unchanged, so stage images from any earlier release
still register as before; the database fills the new columns afterward.

In the table, `k` is the provenance key, `V(x)` is producer instance
`x`'s identity, and `P(x)` projects the slot fields from that identity.
Every slot is a subset of its kind's identity fields. Because `P(x)`
reads `x`'s identity, a collision that withholds the producer's slot
(below) does not block descendants: each row derives independently
from identities alone. A missing producer or null producer identity
leaves the row null until resolved.

| Kind | Slot | Identity adds |
|---|---|---|
| `l2-image` | exposure, detector, from `k` | version |
| `psf` | filter, detector, from `k` | version |
| `reference-image` | field, filter, from `k` | recipe, version (the selection digest) |
| `reference-catalog` | `P(k.reference)` plus catalog type | `V(k.reference)` plus catalog type |
| `difference-image` | `P(k.l2)` plus differencer | exposure, detector, version from `V(k.l2)`, differencer, the reference's `V(k.reference)`, settings hash |
| `source-catalog` | `P(k.difference)` plus catalog type, sign | `V(k.difference)` plus catalog type, sign |
| `source-set` | `P(k.difference)` plus catalog type | `V(k.difference)` plus catalog type |
| `alert-container`, `alert-set` | `P(k.difference)` (an alert set shares its container's slot; one alert set per difference) | `V(k.difference)` plus schema version |
| `association-set` | field, from `k` | field, settings hash, the sorted identities of `k.source_sets`, plus a hash of the base's own identity (below) |
| `pruned-set` | `P(k.base)`, which is field | the base association set's identity, settings hash |
| `statistics-set` | `P(k.membership)` plus which kind of set `k.membership` names | the membership set's identity, plus that kind |
| `light-curve` | field, request id, from `k`, when both are present, else null (declared, not yet ported) | nothing beyond the slot |
| `catalog-export` | field, export type, from `k` | the selection digest, as today |

An unknown kind resolves to null and is counted unresolved, the same as
a missing producer.

Association sets built from equal source sets over different bases
must have different identities. Each therefore includes the SHA-256
digest of its base identity's canonical JSON text, or null when there is no
base. This hash stays bounded however deep the chain runs, without
introducing an instance id. Pruned and statistics sets inherit the
distinction through their membership's identity.

The fill has two stages. For every kind, slot NOT NULL implies identity
NOT NULL. The identity stage repeatedly resolves rows whose producers
already have identities, stopping when a pass resolves no more. There
is no fixed pass count, only a very large cycle guard. If it trips,
the call assigns no slots and counts every remaining row unresolved.

Once identities settle, one further pass derives every still-null slot
from its row's identity. The collision rule applies once across all
current slots, held or newly derived. Both members of a duplicated
pair are withheld together at any chain depth, including pruned or
statistics sets built on a duplicated association pair. The fill never
rewrites an existing slot or assigns one another current instance
holds. A withheld row keeps its identity and null slot, counted as
`duplicate_current` alongside `unresolved`. Re-running the fill
resolves rows completed by later registrations and leaves filled rows
alone.

An instance with a null slot or identity cannot be promoted until a
later registration supplies the missing producer or an operator
corrects it. A partial unique index allows at most one current instance
per kind and slot. The older (kind, provenance key) index remains under
the additive migration rule ([releases](releases)).

A reference to another product (a reference version, source set or base
association set) always means its complete instance id, never a bare
version number.

## File products

| Kind | Unit | Provenance key | Format | Made by | Today's table |
|---|---|---|---|---|---|
| `l2-image` | detector-image | exposure, detector, delivered version | FITS or ASDF as delivered | `admit` | `l2files` |
| `psf` | detector-image | filter, detector, version | FITS | `psf-import` | `psfs` |
| `reference-image` | field | field, filter, reference recipe, version | FITS bundle: image, coverage map, uncertainty | `reference` | `refimages`, `refimimages`, `refimmeta` |
| `reference-catalog` | field | reference instance, catalog type | table, format per catalog type | `reference` | `refimcatalogs` |
| `difference-image` | detector-image | l2 instance, reference instance, differencer, settings hash | FITS bundle, roles declared per differencer | `difference` | `diffimages`, `diffimmeta` |
| `source-catalog` | detector-image | difference instance, catalog type, sign | table | `difference` | none until `load` |
| `alert-container` | detector-image | difference instance, alert schema version | Avro object container plus JSON summary | `alerts` | the outbox |
| `light-curve` | field | field, object set instance, request id | Parquet | none (not ported) | none; exported |
| `catalog-export` | field | field, export type, selection digest of the named source sets | HATS | `export` | none; exported |

A bundle is one product with several files. Its manifest entry names
the primary member and lists every member's role, size and SHA-256.
Member paths resolve against the attempt's output location.

Each differencer declares its bundle roles. `difference` and
`uncertainty` are always present; `significance` is present where the
differencer produces one: ZOGY does, SFFT does not. The optional roles are `psf`
(the difference PSF) for any differencer and `kernel` (the
matching-kernel solution) for SFFT. A declared role that is not
delivered fails registration. The catalog stage's detection member is
a per-differencer setting recorded with the instance: significance for
ZOGY, difference for SFFT.

The difference-stage port minimises differences to the `dev` branch;
improvements come later. Mechanisms that can be designed in but left
unused are included, off by default.

The reference recipe names the pipeline and settings, giving each way
of building a reference for a field its own version namespace.
Constituent inputs are `l2-image` instance ids, each fixing exposure,
detector and delivered version. The logical key's `version` is the
full, hex-encoded SHA-256 digest of the sorted constituent instance ids
plus the resolved settings hash. Rebuilding the same selection makes
another instance of one logical product; a different selection makes
a new logical product.

`refimages.version` remains the legacy per-(field, fid, ppid) counter.
Like every other legacy version column below, it is allocated at
registration, globally across runs rather than within one. It is
separate from the selection digest (see the reference-image field list
and [reference](reference)).

`finalize` reads an immutable instance and writes a new instance of the
same kind in its own attempt location. Its manifest records the input
instance, output revision, and finalized file sizes and checksums.
`register` consumes the selected finalized instance. The
[finalize](finalize) page fixes the chain, stamped header and
source-catalog republication.

Alert names are not a file product. `alerts` writes one outbox record
per alert (name, candidate id, first-seen time, position) alongside the
container's byte range; `register` records the container. The outbox
locator is a block offset and length plus the record's ordinal
position, not a per-alert byte range. `alerts` registers both the
container and its alert-set itself; `register` validates and replays
them. The locator and registration are fixed on the [alerts](alerts)
page.

## Database result sets

Catalog stages produce rows, not files. A result set is the named,
versioned group of rows one stage attempt wrote. Its instance id identifies the next
stage's input. Completion is recorded on the result set, so an empty
set can be complete.

| Kind | Unit | Provenance key | Rows in | Made by |
|---|---|---|---|---|
| `source-set` | detector-image | difference instance, catalog type | `sources` | `load` |
| `association-set` | field | field, frozen input selection, crossmatch settings hash | `merges`, `astroobjects` | `crossmatch` |
| `pruned-set` | field | base association set, pruning settings hash | membership table | `prune` |
| `statistics-set` | field | membership set (association or pruned) | `astroobjectsmeta` | `statistics` |

An association set's frozen input selection records the exact source-set
instance ids read, catalog versions, any seed object set, and the
epoch-selection rule that produced the list. Field membership is
complete when every named source set is complete.

A pruned set excludes an explicit list of (object, source) pairs from
its base association set without mutating the base. A statistics set
names the exact membership it describes; its input determines whether
it is before or after pruning, with no separate flag. Delivered
statistics describe the association set, following `dev`'s order:
`dev` runs crossmatch, then statistics, then prune. The `statistics-set`
row accepts either membership kind, but pruned-set input is designed in
and left unused.

Every row carries its run id, writing attempt id and result-set id.
Keys are set-scoped: statistics for one object in two sets are two
rows, `(statistics_set, object)`. Stages read result sets by id, never
"whatever is current". Promotion atomically selects compatible file and
database-result instances and records the previous selection for
reversal. Scratch-run deletion removes only result sets with no active
attempt or retained output depending on them.

### Reading across runs

Crossmatch needs earlier epochs' sources from earlier runs to accumulate
a catalog across processing dates. Current result sets are readable by any run
as frozen inputs, by instance id; scratch result sets are readable only
within their own run. This amends the specification's sharing rule.
Cross-run reads of selected candidates, allowed by the table below,
remain pending team review
({ref}`sharing rule <decision-pending-sharing-rule>`).

A stage may read an input it cannot publish from. The table separates
reading from promotion for all product instances, both files and result
sets.

| Input's state | A stage of another run may read it | A product built from it may be promoted |
|---|---|---|
| Scratch, own run | yes | no, scratch never leaves scratch |
| Scratch, another run | no, exit 65 | no |
| Candidate, from an unselected attempt | no, exit 65 | no |
| Candidate, selected | yes | yes, once it is itself promoted, earlier or in the same request, where it passes the gate on its own ([checks](checks) page has the gate) |
| Current | yes | yes |
| Superseded (current before, candidate now) | yes, as any candidate from a selected attempt | yes |

Every read requires completeness and retention. A same-run read needs
nothing more, so a run may name its own orphaned set. A cross-run read
also requires a selected producing attempt for every instance in the
dependency chain. Checked and unchecked candidates are equally
readable: a failed or missing check leaves a candidate, even when it
refuses promotion. Promotion requires complete, retained dependencies
that are current, superseded, or members of the same promotion request,
throughout the chain, not just the directly named instance. The
[checks](checks) page describes the walk.

Each instance has one of seven states, computed once by
`rapidpipe.runs.eligibility.instance_state`: `deleted`, `incomplete`,
`scratch` and `unselected` rule it out first, using only custody,
completeness and selection facts. The remaining states are `current`,
`superseded`, and `candidate`. The promotion walk and `run show` use
this state without re-deriving it. The [checks](checks) page defines the
states; the [tool](tool) page gives `run show`'s format.

`register_manifest` applies the read rule to every dependency edge,
refusing foreign file products on the same terms as foreign result
sets. Every reader uses
`rapidpipe.db.objects.assert_readable_instance`. Its result-set wrapper,
`assert_readable_result_set`, is called by `source_set_table`,
`association_chain`, and set resolution in `statistics`, `prune`,
`alerts` and `export`. This defines which foreign instances the sharing
rule permits and keeps a still-running scratch attempt's half-written
outputs, including files, out of production inputs.

The stage guard, `rapidpipe.runs.readguard.assert_inputs_readable`, uses
the same rule. After parsing the input manifest and before fetching any
other object, `run_stage` calls it over every named instance. Direct
invocation, the local launcher and Batch all reach `run_stage`, so none
of the three bypasses the guard.

The rule refuses ids that name no product instance; the guard handles
those separately. An unregistered entry with no members (a
result-set-style entry) is readable because it names nothing to check.
For a file-product entry, each member's path and SHA-256 must match
either no registered instance or at least one readable instance. A
member matching only unreadable instances refuses the entire entry,
regardless of its other members. A fresh id therefore cannot stand in
for another run's scratch files.

The guard requires a database connection to check named inputs. A
stage without one, including a dry run, refuses execution. For S3
inputs, only the manifest is fetched before the guard runs. Afterward,
only its named member files are fetched, one at a time; the rest of the
prefix is never fetched. The [tool](tool) page gives the exit codes.

## Registration metadata

Each target column has one source: a manifest value, an immutable
parent-instance lookup, a deterministic derivation, or a database
allocation or default. The manifest carries the stage's measurements
and omits anything registration can derive (spatial indexes from a
position) or allocate (row ids, current flags). An unavailable measurement
is never replaced with zero, and a missing required value fails validation.

Checksums use SHA-256, stored with the algorithm named, except for the
legacy MD5 columns below. External identifiers, such as the
observatory's exposure id, are stored as delivered and mapped to
internal ids at admission.

Field lists and their columns are fixed one kind at a time; the
[runs](runs) page describes how the run model attaches to existing
tables. Two lists are fixed so far: the difference image, the first
kind the rebuild registers, and the l2 image, because `admit` is the
first stage built and `register` needs its list. Remaining kinds follow
with their stages.

Three rules preserve the `dev` tables' meaning across all kinds:

- Legacy checksum columns keep MD5. `l2files.checksum`,
  `refimages.checksum` and `diffimages.checksum` are 32-character MD5
  columns. Stages compute the primary member's MD5 alongside its SHA-256
  and carry it as `md5` in the registration block. SHA-256 goes to
  `product_members`, so each name describes what it stores. Dropping
  MD5 would require relaxing `l2files.checksum`'s NOT NULL constraint.
- Legacy version columns follow the team's procedures: the next number
  for the table's logical pair, except for delivered versions (the l2
  image). When registration retains a `dev` stored function unchanged,
  as `refimages` does through `addRefImage`, allocation uses `dev`'s
  `coalesce(max(version),
  0) + 1` for the pair across the whole table and every run. The row
  records the run, but the counter is not run-scoped. Concurrent
  allocations for the same pair are serialised by a transaction-level advisory
  lock, `pg_advisory_xact_lock(hashtext('refimages:<field>:<fid>:<ppid>'))`
  for `refimages`, taken before the allocation and released
  automatically at the transaction's end.
- Legacy current flags are never set at registration. Every row a run
  writes has `vbest` 0; custody lives on the instance row. Promotion
  maintains `vbest` on the `dev` tables alongside `current_selection`
  for existing queries. Moving consumers to `current_selection` is a
  later improvement.

### Difference image

`difference` makes the image; `register` records it.

| Field | Source | Column |
|---|---|---|
| l2 instance | manifest identity | `diffimages.rid`, with `expid` and `sca` copied from that `l2files` row |
| reference instance | manifest identity | `diffimages.rfid`: that instance's `refimages` row, through the `instance` column added with the `difference` stage; for a reference registered by `dev`, which has no instance, the legacy rfid the registration block carries as `reference_rfid` |
| differencer | manifest identity | `diffimages.ppid`: the `pipelines` row for the differencer; the name-to-row mapping is fixed with the `difference` stage. When the stage runs both ZOGY and SFFT, both register, each its own `difference-image` instance with its own `diffimages` row and `ppid` (ZOGY 15, SFFT 16); `[sfft] register_sfft` turns SFFT's registration off. Which instance consumers read is a promotion choice under the planned slot supersession, not a code default. `dev`'s own stored sources for the control exposure it processed are its SFFT difference's, not ZOGY's, so the rebuild does not copy `dev`'s choice here; it registers both. The naive subtraction is an optional diagnostic file, never a registered instance. |
| settings hash | manifest identity | the instance's provenance key only; no legacy column |
| field, filter, observation time | lookup on the l2 instance | `field`, `fid`, `jd` (from that row's `mjdobs`), on `diffimages` and `diffimmeta` |
| image centre and four corners (RA, Dec) | manifest, from the difference WCS | `ra0`, `dec0` to `ra4`, `dec4` |
| reference info bits | manifest, `infobits_reference` | `infobitsref`: the reference instance's info bits |
| catalog-outcome mask | manifest, `catalog_outcome_bits`, set per job when no Photutils catalog was produced | `infobitssci`, its `dev` meaning kept: a six-bit mask, one bit per differencer and sign (see below). The manifest also carries `infobits_science`, the l2 image's quality bits; only the mask is registered. |
| source counts per catalog type and sign | manifest | `diffimmeta.source_counts`, all of them as the manifest carries them; `diffimmeta.nsexcatsources` holds the SExtractor positive count for the team's existing queries. Both catalog families, SExtractor and Photutils, are retained in the rebuild. |
| registration residuals: x and y RMS and median | manifest | `dxmedianfin`, `dymedianfin`: the measured offsets. `dxrmsfin`, `dyrmsfin`: the measured astrometric residual RMS from gain matching, not the value ZOGY itself is fed; ZOGY's own astrometric input (`[zogy] astrometric_sigma`, a named stage setting) stays 0.0 as `dev`'s override. |
| reference scale factor | manifest | `scalefacref` |
| spatial indexes | derived from the centre at registration | `hp6`, `hp9` on both tables |
| file path | manifest primary member, resolved against the attempt's output location | `filename` |
| checksum | manifest registration block, `md5` | `checksum` |
| version | allocation: the next number for (`rid`, `ppid`) within the run | `version` |
| software version | allocation from the run's code revision | `svid`: one `swversions` row per code revision, made on first use |
| run, attempt, instance ids | enclosing manifest and allocation | `run`, `attempt`, `instance` on both tables |
| current flag, status | allocation; never current at registration | `vbest` 0, `status` 0 |
| written by later stages | not registration | `avid`, `archivestatus`, `nalertpackets` |

`infobitssci`'s six bits, kept from `dev`:

- bit 0: ZOGY positive
- bit 1: ZOGY negative
- bit 2: SFFT positive
- bit 3: SFFT negative
- bit 4: naive positive
- bit 5: naive negative

### Reference image

`reference` makes the image; `register` records it.

| Field | Source | Column |
|---|---|---|
| constituent l2-image instances | manifest, `registration.constituents` | `refimimages`: one `(rfid, rid)` row per constituent whose `l2files.instance` matches; a constituent without a matching `l2files` row fails registration |
| filter | manifest identity | `refimages.fid`: lookup in `filters` by name |
| field | manifest, `registration.field` | `refimages.field` |
| recipe | manifest identity, fixed `awaicgen` | `refimages.ppid`: 12, the `pipelines` row `dev` used |
| selection digest (the key's `version`) | manifest identity, the instance's provenance key only | no legacy column; `refimages.version` is the separate legacy counter, allocated globally per `(field, fid, ppid)` under an advisory lock, not scoped to the run (above) |
| mosaic centre (RA, Dec) | manifest, `registration.ra_center`, `dec_center` | derived to `hp6`, `hp9` on `refimages` and `refimmeta` |
| frame count | manifest, `registration.nframes` | `refimmeta.nframes` |
| observation time range | manifest, `registration.mjdobs_min`, `mjdobs_max` | `refimmeta.mjdobsmin`, `mjdobsmax` |
| JD range, total exposure time, zero point | manifest, `registration.jd_start`, `jd_end`, `total_exptime`, `zero_point` | carried into the header stamp (`JDSTART`, `JDEND`, `TOTEXPTM`, `MAGZP`), not registered: no matching `refimmeta` or `refimages` column |
| coverage and pixel-uncertainty measures | manifest, `registration.cov5percent`, `medncov`, `medpixunc` | `refimmeta`, same names |
| bad-pixel count | manifest, `registration.npixnan` | `refimmeta.npixnan` |
| clipped image statistics | manifest, `registration.clmean`, `clstddev`, `clnoutliers`, `gmedian`, `datascale`, `gmin`, `gmax` | `refimmeta`, same names |
| catalog FWHM | manifest, `registration.fwhmmedpix`, `fwhmminpix`, `fwhmmaxpix` | `refimmeta`, same names |
| source counts | manifest, `registration.nsexcatsources`, `npucatsources` | `refimmeta.nsxcatsources` (`dev`'s column spelling; the block field is `nsexcatsources`), `npucatsources`: null when `[psfcat]` is off, needing migration `20260924-09` to drop that column's `NOT NULL` |
| settings hash | manifest identity | the instance's provenance key only; no legacy column |
| infobits | manifest, `registration.infobits` | `refimages.infobits`: 0, `dev`'s TODO; no code sets bits |
| checksum | manifest registration block, `md5` | `refimages.checksum` |
| file path | manifest primary member | `refimages.filename` |
| software version | allocation from the run's code revision | `refimages.svid`: one `swversions` row per code revision, made on first use, as `difference` allocates |
| current flag, status | allocation; never current at registration | `refimages.vbest` 0, `status`: the block's `status`, 1 |
| run, attempt, instance ids | enclosing manifest and allocation | `run`, `attempt`, `instance` on `refimages`, the columns migration `20260923-02-refimages-instance.sql` added; `attempt` is the *producing* attempt (the `reference` attempt named in the manifest), not the attempt running `register` -- `psfs`, `diffimages` and `l2files` record the registering attempt instead, so `refimages` is the one exception |

### Reference catalog

`reference` makes the catalog; `register` records it.

| Field | Source | Column |
|---|---|---|
| catalog type | manifest identity, `key.catalog_type` | `refimcatalogs.cattype`: `sextractor` maps to 1, `psf` to 2 |
| reference instance | manifest identity, `key.reference` | `refimcatalogs.rfid`, resolved from the reference instance: registered earlier in the same manifest, or already present in `refimages` |
| field, filter | lookup on the `refimages` row | `field`, `hp6`, `hp9`, `fid`, copied from that row |
| checksum | manifest registration block, `md5` | `refimcatalogs.checksum` |
| file path | manifest primary member | `refimcatalogs.filename` |
| status | manifest registration block | `status`: 1 |
| differencer/recipe id | allocation | `ppid`: 12, the same row the reference image uses |
| source count | manifest registration block, `source_count` | carried, not registered: `registerRefImCatalog` takes no such column, the same treatment the difference stage's `source-catalog` block gets until `load` |
| run, attempt, instance ids | enclosing manifest and allocation | as `refimages` |

### L2 image

`admit` makes the image; `register` records it. Admission alone reads
the delivered header, so its manifest carries every header value the
tables need. `admit` has no upstream stage. Whoever stages the delivered
file writes its input delivery manifest: stage `delivery`, one
`l2-image` entry of format version `delivered`, a key naming the
exposure, detector and delivered version, and the delivered file as
its member.

`admit` verifies the delivered bytes, copies the file into its attempt's
output location, and publishes a new instance. The registration block
keeps the delivery's instance id and source. A delivery is not a
registered product, so it is not a dependency.

| Field | Source | Column |
|---|---|---|
| observatory exposure id | manifest identity, stored as delivered | `exposures`: an external-id column added with the `admit` stage; `l2files.expid` stays the internal id |
| detector | manifest identity | `sca` on `l2files` and `l2filemeta` |
| delivered version | manifest identity | `version`, stored as delivered; the legacy procedure allocated it per (`expid`, `sca`) |
| exposure record | lookup, or allocation on first admission of the exposure | `expid`; the `exposures` row carries the header's date, filter, exposure time and MJD |
| filter | manifest, from the header | `fid` on both tables: lookup in `filters` |
| observation time, exposure time | manifest, from the header | `dateobs`, `mjdobs` (both tables), `exptime` |
| info bits | manifest | `infobits` |
| verification | manifest: 1 when the stage verified the delivered DATASUM and CHECKSUM keywords, else 0 | `status` |
| WCS as delivered: reference point, pixel matrix, axis types and units, SIP coefficients, equinox | manifest, from the header | `crval1` to `cunit2`, `a_order` and `a_*`, `b_order` and `b_*`, `equinox` |
| target position | manifest, from the header | `ra`, `dec` |
| orientation and photometric calibration | manifest, from the header | `paobsy`, `pafpa`, `zptmag`, `skymean` |
| image centre and four corners (RA, Dec) | manifest, from the WCS | `l2filemeta.ra0`, `dec0` to `ra4`, `dec4` |
| spatial indexes | derived from the centre at registration | `field`, `hp6`, `hp9` on both tables; `l2filemeta.x`, `y`, `z`; `l2files.overlapfields` from the corners |
| file path | manifest primary member, resolved against the attempt's output location | `filename` |
| checksum | manifest registration block, `md5` | `checksum` |
| run, attempt, instance ids | enclosing manifest and allocation | `run`, `attempt`, `instance` on both tables, added with the `admit` stage |
| current flag | allocation; never current at registration | `vbest` 0 |

## A complete manifest

```json
{
  "schema_version": "1",
  "run": "r-2026-09-21-0007",
  "unit": {"kind": "detector-image", "id": "e20260821001234/SCA07"},
  "stage": "difference",
  "attempt": "a-01J8Y6QZ3M",
  "execution_record": "exec/a-01J8Y6QZ3M.json",
  "inputs": {
    "manifest": "s3://<inputs-prefix>/manifest.json",
    "products": {
      "l2-image": "pi-l2-0000123456",
      "reference-image": "pi-ref-0000004321",
      "psf": "pi-psf-0000000789"
    },
    "result_sets": []
  },
  "outputs": [
    {
      "kind": "difference-image",
      "format_version": "1",
      "instance": "pi-diff-0000998877",
      "key": {
        "l2": "pi-l2-0000123456",
        "reference": "pi-ref-0000004321",
        "differencer": "zogy",
        "settings_hash": "sha256:4f2a9c0e1b7d6a5f3e2c1d0b9a8f7e6d5c4b3a291807f6e5d4c3b2a1f0e9d8c7"
      },
      "primary": "diff/e20260821001234_SCA07_zogy.fits",
      "members": [
        {"role": "difference",   "path": "diff/e20260821001234_SCA07_zogy.fits",       "bytes": 201326592, "sha256": "sha256:9a1f0e2d3c4b5a69788796a5b4c3d2e1f00112233445566778899aabbccddeef"},
        {"role": "uncertainty",  "path": "diff/e20260821001234_SCA07_zogy_unc.fits",   "bytes": 201326592, "sha256": "sha256:0b2e1f3d4c5a6b7988a7b6c5d4e3f2019900aabbccddeeff0011223344556677"},
        {"role": "significance", "path": "diff/e20260821001234_SCA07_zogy_scorr.fits", "bytes": 201326592, "sha256": "sha256:1c3f2e4d5b6a7c8a99b8c7d6e5f4a3b20aa11bbccddeeff00112233445566778"}
      ],
      "registration": {
        "centre": {"ra": 269.4521, "dec": -28.7710},
        "corners": [[269.39, -28.83], [269.51, -28.83], [269.51, -28.71], [269.39, -28.71]],
        "catalog_outcome_bits": 0,
        "infobits_science": 0,
        "infobits_reference": 0,
        "source_counts": {"sextractor": {"positive": 412, "negative": 388}, "photutils": {"positive": 405, "negative": 391}},
        "registration_residual": {"x_rms": 0.0, "y_rms": 0.0, "x_median": 0.004, "y_median": -0.002},
        "reference_scale_factor": 0.998,
        "detection_role": "significance",
        "reference_rfid": null,
        "md5": "9e107d9d372bb6826bd81d3542a419d6"
      }
    },
    {
      "kind": "source-catalog",
      "format_version": "1",
      "instance": "pi-cat-0000998878",
      "key": {"difference": "pi-diff-0000998877", "catalog_type": "sextractor", "sign": "positive"},
      "primary": "cat/e20260821001234_SCA07_zogy_pos.sexcat",
      "members": [{"role": "catalog", "path": "cat/e20260821001234_SCA07_zogy_pos.sexcat", "bytes": 88214, "sha256": "sha256:2d4a3f5e6c7b8d9aaac9d8e7f6a5b4c31bb22ccddeeff0011223344556677889"}],
      "registration": {"source_count": 412}
    }
  ]
}
```

`register` validates each entry against its kind's schema and enclosing
manifest, then resolves upstream instance ids. It writes rows from
manifest fields, execution provenance, documented lookups and defaults,
without reading product files.

## Not decided here

- Registration field lists for source catalog and `light-curve`, each
  fixed with its stage. `light-curve` has no stage in this build;
  [photometry](photometry) records its state pending the real port.
  `catalog-export`'s field list is fixed with the `export` stage on the
  [export](export) page. The [load](load) page holds the source set's
  rows and result-set record and the `psf` block; [alerts](alerts) holds
  the `alert-container` registration block and `alert-set` result set.
- Storage layout beneath the run: the path scheme under the attempt's
  output location.
- Closed by the Identity section above: a derived product's science
  identity, and the slot it supersedes by, are now derived for every
  kind, not only `l2-image`.
