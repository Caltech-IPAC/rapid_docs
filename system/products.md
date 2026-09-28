# Products

**Status: DRAFT**

Companion to the [stage contract](stage-contract): the product vocabulary the
stages' `consumes` and `produces` declarations name, what makes each product
unique, and the metadata `register` needs from its manifest entry.
The `dev` schema is kept: its tables and columns
stay as the team knows them, and this vocabulary maps onto them. Where
the vocabulary needs something the tables lack, a column or table is
added; nothing is renamed or dropped. The tables are named below so the
team can see what each product corresponds to.

## In plain terms

A product is one thing a stage makes that another stage or a consumer
uses: an image, a catalog file, an alert file, or a set of rows in the
database. Each kind has a fixed name, a rule for what makes one unique,
and a fixed list of facts its manifest entry must carry so the database
can record it without opening the file. Making the same thing twice
gives two instances of one logical product; the instance id tells them
apart, and promotion says which instance consumers see.

## Identity

Every instance carries three keys.
The **provenance key** is what a manifest entry has always called
`key`: for a difference image, which detector image against which
reference with which differencer and settings. It names the exact
input instances a stage consumed, not a science description, so a
difference from one reprocessing and one from another carry different
provenance keys even where the science is identical. No stage changes
how it writes this key; it stays the column `product_instances.logical_key`,
unchanged, so a reader that already walks a chain through it, a base
association set's ancestor, a retry's reuse lookup, needs no change.

Two more columns describe the same instance for a consumer: the
**identity key** (column `identity`) states everything that makes the
instance scientifically different from another, delivered facts and
science choices only, never an instance id; the **slot** (column
`slot`) is the part of the identity key a consumer selects on, "the
current X for Y". Both are nullable JSON, and neither is written by a
stage. The database derives them from the provenance key, in
`product_identity_fill()`: it resolves identity first, by walking each
producer instance the key names to its own identity in turn, and only
once identity has settled does it read the slot off the finished
identity (below). Because nothing in the manifest changed, a stage
image of any earlier release still registers exactly as it does today;
the database fills the rest afterward.

The derivation, one row per kind. `k` is the provenance key; `V(x)` is
producer instance `x`'s own identity, and `P(x)` is the slot fields
projected from it, since every slot is a subset of its kind's identity
fields. Because `P(x)` reads `x`'s
identity rather than its slot column, a producer whose own slot was
withheld by a collision (below) does not block its
descendants: each row still derives its own slot and identity
independently, from identities alone. A missing producer, or one whose
own identity is still null, leaves the row null until that resolves:

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

An identity key never carries an instance id, but an association set
built from equal source sets over two different bases must still
differ from the other. Its identity therefore carries a hash of the
base's own identity too: the SHA-256 digest of the base's canonical
JSON text, or null when there is no base. The hash is bounded in size
however deep the chain runs, and a pruned or statistics set built on
top inherits the distinction through its own membership's identity.

The fill runs in two stages, and a slot is set only when the identity
is also derived: slot NOT NULL implies identity NOT NULL, for every
kind. The identity stage runs pass after pass, resolving every row
whose own producers already have theirs, until one pass converts
nothing more; no fixed pass count bounds it, only a very large guard
against a cycle, and if that guard trips the call assigns no slots at
all and counts every remaining row unresolved. Only once identities have settled does the fill derive
every still-null slot, in one further pass, straight off each row's
own now-filled identity; the collision rule applies exactly once at
that point, over every current instance's slot, already held or
freshly derived, so both members of a duplicated pair are withheld
together whatever their depth in the chain, a pruned or statistics set
built on a duplicated association pair included. Filling never
rewrites a slot already set, and never assigns one another current
instance already holds; a withheld row keeps its identity but stays
null on slot, counted `duplicate_current` and reported alongside
`unresolved`. Running the fill again resolves what a later
registration completed and leaves an already-filled row alone.

An instance with a null slot, or a null identity, cannot be promoted
until something resolves it: a later registration supplying the
missing producer, or an operator's own correction (a row whose identity
is null can never be promoted, since its slot is null too). At most one
current instance exists per kind and slot, a partial unique index
beside the older (kind, provenance key) index, which stays under the
additive migration rule ([releases](releases)).

Wherever this page says a product references another (a reference
version, a source set, a base association set) it means the complete
instance id, never a bare version number.

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
| `light-curve` | field | field, object set instance, request id | Parquet | `photometry` | none; exported |
| `catalog-export` | field | field, export type, selection digest of the named source sets | HATS | `export` | none; exported |

A bundle is one product with several member files. The manifest entry
names the primary member and lists every member with its role, size and
SHA-256; member paths resolve against the attempt's output location.

The difference-image bundle's roles are declared per differencer.
`difference` and `uncertainty` are always present. `significance` is
present where the differencer produces one: ZOGY does, SFFT does not.
`psf`, the difference PSF, is a named optional role for any
differencer; `kernel`, the matching-kernel solution, is a named
optional role for SFFT. A role a differencer declares but does not
deliver fails registration. Which member the catalog stage detects on
is a per-differencer setting recorded with the instance: significance
for ZOGY, difference for SFFT.

The port of the difference stage minimises differences to the `dev`
branch; improvements come later. A mechanism that can be designed in
but left unused is designed in, off by default.

The reference recipe names the reference pipeline and its settings, so
two ways of building a reference for one field never share a version
namespace. A reference's constituent inputs are `l2-image` instance
ids, each fixing exposure, detector and delivered version. The logical
key's `version` is a selection digest: the full SHA-256 digest,
hex-encoded, over the sorted constituent instance ids plus the resolved
settings hash, so the same selection rebuilt is another instance of one
logical product and a different selection is a new one.
`refimages.version` is not this digest -- it is the legacy per-(field,
fid, ppid) counter the table has always carried, allocated at
registration like every other legacy version column below, globally
across every run rather than scoped to one (see the reference-image
field list and [reference](reference)).

`finalize` reads an immutable input instance and writes a new instance
of the same kind in its own attempt location. Its manifest records the
input instance, the output revision, and the sizes and checksums of the
finalized files. `register` consumes the selected finalized instance.
The chain, the stamped header and the source-catalog republication are
fixed on the [finalize](finalize) page.

Alert names are not a file product. `alerts` writes one record per
alert (name, candidate id, first-seen time, position) into the alert
outbox alongside the container's byte range; `register` records the
container. The outbox row's locator is a block offset and length plus
the record's ordinal position, not a per-alert byte range, and `alerts`
registers the container and its alert-set itself, with `register`
validating and replaying them; both are fixed on the [alerts](alerts)
page.

## Database result sets

Catalog stages produce rows, not files. A result set is the named,
versioned group of rows one stage attempt wrote, identified by a
result-set instance id, and it is what the next stage names as its
input. Completion is recorded on the result-set record, so an empty
result set can be complete.

| Kind | Unit | Provenance key | Rows in | Made by |
|---|---|---|---|---|
| `source-set` | detector-image | difference instance, catalog type | `sources` | `load` |
| `association-set` | field | field, frozen input selection, crossmatch settings hash | `merges`, `astroobjects` | `crossmatch` |
| `pruned-set` | field | base association set, pruning settings hash | membership table | `prune` |
| `statistics-set` | field | membership set (association or pruned) | `astroobjectsmeta` | `statistics` |

The frozen input selection of an association set is the list of exact
source-set instance ids it read, the catalog versions, any seed object
set, and the epoch-selection rule that produced the list. Field
membership is complete when every source set the selection names is
complete.

A pruned set is its base association set minus an explicit list of
excluded pairs (object, source) within that base; the base is never
mutated. A statistics set names the exact membership it describes, so
"before or after pruning" is read off the input, not stored as a flag.
Delivered statistics describe the association set, as `dev` computes
them: `dev` runs crossmatch, then statistics, then prune. The pruned
set as a statistics input is designed in, since the `statistics-set`
row already keys on either, and left unused.

Every row carries the run id, the attempt id that wrote it and its
result-set id. Keys are set-scoped: statistics for one object in two
sets are two rows, `(statistics_set, object)`. A stage reads a result
set by id, never "whatever is current". Promotion atomically selects
compatible file and database-result instances and records the previous
selection for reversal. Deleting a scratch run removes only result sets
that no active attempt or retained output depends on.

### Reading across runs

Crossmatch needs the sources of earlier epochs, which earlier runs
produced. Current result sets are therefore readable by any run as
frozen inputs, by instance id; scratch result sets are readable only
within their own run. This amends the specification's sharing rule, so
that production can accumulate a catalog across processing dates.
Whether selected candidates are readable across runs, as the table below
allows, is pending team review
({ref}`sharing rule <decision-pending-sharing-rule>`).

"Readable by any run" is narrower than it sounds, and reading is a
different question from promotion: a stage may read an input it may
not publish from. The table gives both answers for every product
instance, file products and result sets alike.

| Input's state | A stage of another run may read it | A product built from it may be promoted |
|---|---|---|
| Scratch, own run | yes | no, scratch never leaves scratch |
| Scratch, another run | no, exit 65 | no |
| Candidate, from an unselected attempt | no, exit 65 | no |
| Candidate, selected | yes | yes, once its own required checks pass under the resolved check policy ([checks](checks) page has the gate) |
| Current | yes | yes |
| Superseded (current before, candidate now) | yes, as any candidate from a selected attempt | yes |

A read needs completeness and retention always. A same-run read needs
nothing more, so a run may still name its own orphaned set. Only a
cross-run read, of any instance anywhere in a dependency chain, needs
its producing attempt to be selected; a candidate whose promotion was
refused by checks is readable all the same, since a failed or missing
check leaves a candidate, not a scratch instance, and reading does not
distinguish a checked candidate from an unchecked one. Only a promotion
needs more: complete, retained, and current, superseded, or itself a
member of the same promotion request, followed through the whole chain
of dependencies, not only the instance named directly ([checks](checks)
page has the walk).

Each instance settles to one of seven states, computed once by
`rapidpipe.runs.eligibility.instance_state`: `deleted`, `incomplete`,
`scratch` and `unselected` rule an instance out first, from custody,
completeness and selection facts only; what remains is `current`,
`superseded`, or `candidate`. The promotion walk and `run show` both
read this one state rather than re-deriving it ([checks](checks) page
has the states; the [tool](tool) page has `run show`'s format).

`register_manifest` applies the read rule to every dependency edge now:
a foreign file product's edge is refused on the same terms as a foreign
result set's. One function enforces the read side for every reader:
`rapidpipe.db.objects.assert_readable_instance`, of which
`assert_readable_result_set` is the result-set wrapper that
`source_set_table`, `association_chain`, and the set resolution
`statistics`, `prune`, `alerts` and `export` already call. This closes
the gap the sharing rule above left open: which of another run's
instances counts as readable, and is what keeps a still-running scratch
attempt's half-written output out of a production run's inputs, file
products included.

The same rule backs the stage's own guard,
`rapidpipe.runs.readguard.assert_inputs_readable`, which `run_stage`
calls over every instance a stage's input manifest names, once the
manifest is parsed and before any other object is fetched. Direct
invocation, the local launcher and Batch all reach `run_stage`, so none
of the three can bypass the guard by choosing a path. The rule itself
refuses an id naming no product instance at all; the guard never asks it
about one. Instead, an unregistered manifest entry with no members (a
result-set-style entry) is readable, since it names nothing to check,
and a file-product entry's members are judged one at a time: a member
whose path and SHA-256 match a registered instance's must match one the
rule accepts, a member matching no registered instance is readable, and
one member that matches only unreadable instances refuses the whole
entry, whatever its other members match. So a fresh id cannot stand in
for another run's scratch files. The guard needs a database connection
to check named inputs; a stage without one, a dry run included, refuses
rather than skipping the check. On an S3 input location the guard runs
once the manifest alone is fetched, and only the member files it names
are fetched afterward, one at a time, never the rest of the prefix
([tool](tool) page has the exit codes).

## Registration metadata

Each target column has exactly one source: a manifest value, a lookup
on an immutable parent instance, a deterministic derivation, or a
database allocation or default. The manifest carries measurements the
stage made; it does not carry what registration can derive (spatial
indexes from a position) or allocate (row ids, current flags). Nothing
substitutes zero for an unavailable measurement; a missing required
value fails validation.

Checksums are SHA-256 throughout, stored with the algorithm named;
the one exception is the legacy MD5 columns, ruled below. External
identifiers (the observatory's exposure id) are stored as delivered and
mapped to internal ids at admission.

The full field list per kind is fixed one kind at a time, with the
columns that hold it; see the [runs](runs) page for how the run model
attaches to the existing tables. Two lists are fixed so far: the
difference image, because it is the first kind the rebuild registers,
and the l2 image, because `admit` is the first stage built and
`register` needs its list. The remaining kinds follow with their stages.

Three rules hold across every kind, so that the `dev` tables keep the
meaning the team knows:

- **Legacy checksum columns keep their MD5.** `l2files.checksum`,
  `refimages.checksum` and `diffimages.checksum` are 32-character MD5
  columns. The stage computes the MD5 of the primary member alongside
  its SHA-256 and carries it in the registration block as `md5`; the
  SHA-256 goes to `product_members`. Nothing is stored under a name that
  misdescribes it. The MD5 carry is kept rather than dropped, which
  would need relaxing `l2files.checksum`'s NOT NULL constraint.
- **Legacy version columns are allocated the way the team's procedures
  allocated them**, the next number for the table's logical pair, except
  where the version is delivered (the l2 image). Where registration
  keeps a `dev` stored function unchanged, as `refimages` does through
  `addRefImage`, that allocation is `dev`'s own `coalesce(max(version),
  0) + 1` over the whole table for the pair, global across every run,
  not scoped to the registering run; the run is still recorded on the
  row, just not part of the counter. Two attempts allocating for the
  same pair at once are serialised by a transaction-level advisory
  lock, `pg_advisory_xact_lock(hashtext('refimages:<field>:<fid>:<ppid>'))`
  for `refimages`, taken before the allocation and released
  automatically at the transaction's end.
- **Legacy current flags are never set at registration.** `vbest` is 0
  on every row a run writes; custody lives on the instance row.
  Promotion maintains `vbest` on the `dev` tables for the team's
  existing queries, alongside `current_selection`; consumers moving to
  `current_selection` is a later improvement.

For the difference image (`difference` makes it, `register` records it):

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

For the reference image (`reference` makes it, `register` records it):

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

For the reference catalog (`reference` makes it, `register` records it):

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

For the l2 image (`admit` makes it, `register` records it; admission is
the one stage that reads the delivered header, so every header value the
tables need travels in its manifest entry). `admit` has no upstream
stage: its input manifest is a delivery manifest, written by whoever
stages the delivered file, with stage `delivery`, one `l2-image` entry
of format version `delivered` whose key names the exposure, detector and
delivered version, and the delivered file as its member. `admit`
verifies the delivered bytes, copies the file into the attempt's output
location, and publishes a new instance; the delivery's instance id and
source are kept in the registration block, not as a dependency, because
a delivery is not a registered product.

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

`register` validates each entry against its kind's schema, checks it
against the enclosing manifest, resolves the upstream instance ids, and
writes rows from manifest fields, execution provenance, documented
lookups and defaults. It does not read product files.

## Not decided here

- The registration field lists for the remaining kinds (source catalog,
  and `light-curve`, `photometry`'s export); each is fixed with its
  stage. `light-curve`'s declared contract, pending the real port, is on
  the [photometry](photometry) page. `catalog-export`'s registration
  field list is fixed with the `export` stage, on the [export](export)
  page. The source set's
  rows and result-set record, and the `psf` block, are on the
  [load](load) page. The `alert-container` registration block and the
  `alert-set` result set are on the [alerts](alerts) page.
- Storage layout beneath the run: the path scheme under the attempt's
  output location.
- Closed by the Identity section above: a derived product's science
  identity, and the slot it supersedes by, are now derived for every
  kind, not only `l2-image`.
