# Products

**Status: DRAFT**

Companion to the [stage contract](stage-contract): the product vocabulary the
stages' `consumes` and `produces` declarations name, what makes each product
unique, and the metadata `register` needs from its manifest entry. Written
2026-09-21 from the `dev` schema and the stage contract, revised on a Codex
review, direction approved by the lead. The difference-image and l2-image
registration field lists were fixed later the same day.
The `dev` schema is kept (lead, 2026-09-21): its tables and columns
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

A **logical key** identifies the output being selected or replaced: for
a difference image, which detector image against which reference with
which differencer and settings. An **instance id** identifies one
published output and records its run, stage, attempt and revision.
Retries and reruns produce several instances of one logical key;
downstream stages consume only the instance the launcher selected, and
reference it by instance id, never by logical key. Promotion records
the previous and replacement instances for each affected logical key.
Instances are immutable once their manifest is published.

Wherever this page says a product references another (a reference
version, a source set, a base association set) it means the complete
instance id, never a bare version number.

## File products

| Kind | Unit | Logical key | Format | Made by | Today's table |
|---|---|---|---|---|---|
| `l2-image` | detector-image | exposure, detector, delivered version | FITS or ASDF as delivered | `admit` | `l2files` |
| `psf` | detector-image | filter, detector, version | FITS | `admit` | `psfs` |
| `reference-image` | field | field, filter, reference recipe, version | FITS bundle: image, coverage map, uncertainty | `reference` | `refimages`, `refimimages`, `refimmeta` |
| `reference-catalog` | field | reference instance, catalog type | table, format per catalog type | `reference` | `refimcatalogs` |
| `difference-image` | detector-image | l2 instance, reference instance, differencer, settings hash | FITS bundle, roles declared per differencer | `difference` | `diffimages`, `diffimmeta` |
| `source-catalog` | detector-image | difference instance, catalog type, sign | table | `difference` | none until `load` |
| `alert-container` | detector-image | difference instance, alert schema version | Avro object container plus JSON summary | `alerts` | the outbox |
| `light-curve` | field | field, object set instance, request id | Parquet | `photometry` | none; exported |
| `catalog-export` | field | field, export type, result-set instance | HATS | `export` | none; exported |

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
for ZOGY, difference for SFFT (lead, 2026-09-22).

The port of the difference stage minimises differences to the `dev`
branch; improvements come later. A mechanism that can be designed in
but left unused is designed in, off by default (lead, 2026-09-22).

The reference recipe names the reference pipeline and its settings, so
two ways of building a reference for one field never share a version
namespace. A reference's constituent inputs are `l2-image` instance
ids, each fixing exposure, detector and delivered version.

`finalize` reads an immutable input instance and writes a new instance
of the same kind in its own attempt location. Its manifest records the
input instance, the output revision, and the sizes and checksums of the
finalized files. `register` consumes the selected finalized instance.

Alert names are not a file product. `alerts` writes one record per
alert (name, candidate id, first-seen time, position) into the alert
outbox alongside the container's byte range; `register` records the
container.

## Database result sets

Catalog stages produce rows, not files. A result set is the named,
versioned group of rows one stage attempt wrote, identified by a
result-set instance id, and it is what the next stage names as its
input. Completion is recorded on the result-set record, so an empty
result set can be complete.

| Kind | Unit | Logical key | Rows in | Made by |
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
row already keys on either, and left unused (lead, 2026-09-22).

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
within their own run. Ruled by the lead 2026-09-21 as an amendment to
the specification's sharing rule, so that production can accumulate a
catalog across processing dates.

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
  would need relaxing `l2files.checksum`'s NOT NULL constraint (lead,
  2026-09-22).
- **Legacy version columns are allocated the way the team's procedures
  allocated them**, the next number for the table's logical pair within
  the run, except where the version is delivered (the l2 image).
- **Legacy current flags are never set at registration.** `vbest` is 0
  on every row a run writes; custody lives on the instance row.
  Promotion maintains `vbest` on the `dev` tables for the team's
  existing queries, alongside `current_selection`; consumers moving to
  `current_selection` is a later improvement (lead, 2026-09-22).

For the difference image (`difference` makes it, `register` records it):

| Field | Source | Column |
|---|---|---|
| l2 instance | manifest identity | `diffimages.rid`, with `expid` and `sca` copied from that `l2files` row |
| reference instance | manifest identity | `diffimages.rfid`: that instance's `refimages` row, through the `instance` column added with the `difference` stage; for a reference registered by `dev`, which has no instance, the legacy rfid the registration block carries as `reference_rfid` |
| differencer | manifest identity | `diffimages.ppid`: the `pipelines` row for the differencer; the name-to-row mapping is fixed with the `difference` stage. ZOGY registers as in `dev`. SFFT registration is a stage setting, off by default; when on, its output is its own `difference-image` instance, with its own `diffimages` row and `ppid`. The naive subtraction is an optional diagnostic file, never a registered instance. |
| settings hash | manifest identity | the instance's logical key only; no legacy column |
| field, filter, observation time | lookup on the l2 instance | `field`, `fid`, `jd` (from that row's `mjdobs`), on `diffimages` and `diffimmeta` |
| image centre and four corners (RA, Dec) | manifest, from the difference WCS | `ra0`, `dec0` to `ra4`, `dec4` |
| reference info bits | manifest, `infobits_reference` | `infobitsref`: the reference instance's info bits |
| catalog-outcome mask | manifest, `catalog_outcome_bits`, set per job when no Photutils catalog was produced | `infobitssci`, its `dev` meaning kept: a six-bit mask, one bit per differencer and sign (see below). The manifest also carries `infobits_science`, the l2 image's quality bits; only the mask is registered. |
| source counts per catalog type and sign | manifest | `diffimmeta.source_counts`, all of them as the manifest carries them; `diffimmeta.nsexcatsources` holds the SExtractor positive count for the team's existing queries. Both catalog families, SExtractor and Photutils, are retained in the rebuild (lead, 2026-09-22). |
| registration residuals: x and y RMS and median | manifest | `dxmedianfin`, `dymedianfin` measured; `dxrmsfin`, `dyrmsfin` from ZOGY's astrometric-uncertainty inputs (dx, dy), a named stage setting defaulting to 0.0, reproducing `dev` and registering as 0.0 under that default. The measured residuals stay in the stage log (lead, 2026-09-22). |
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

- The registration field lists for the remaining kinds (reference
  image, reference catalog, source catalog, alert container, the
  exports); each is fixed with its stage.
- Storage layout beneath the run: the path scheme under the attempt's
  output location.
- The alert outbox shape and the per-alert record.
