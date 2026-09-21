# Products

**Status: DRAFT**

Companion to the [stage contract](stage-contract): the product vocabulary the
stages' `consumes` and `produces` declarations name, what makes each product
unique, and the metadata `register` needs from its manifest entry. Written
2026-09-21 from the `dev` schema and the stage contract, revised on a Codex
review, direction approved by the lead.
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
| `difference-image` | detector-image | l2 instance, reference instance, differencer, settings hash | FITS bundle: difference, uncertainty, significance | `difference` | `diffimages`, `diffimmeta` |
| `source-catalog` | detector-image | difference instance, catalog type, sign | table | `difference` | none until `load` |
| `alert-container` | detector-image | difference instance, alert schema version | Avro object container plus JSON summary | `alerts` | the outbox |
| `light-curve` | field | field, object set instance, request id | Parquet | `photometry` | none; exported |
| `catalog-export` | field | field, export type, result-set instance | HATS | `export` | none; exported |

A bundle is one product with several member files. The manifest entry
names the primary member and lists every member with its role, size and
SHA-256; member paths resolve against the attempt's output location.

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

Checksums are SHA-256 throughout, stored with the algorithm named.
External identifiers (the observatory's exposure id) are stored as
delivered and mapped to internal ids at admission.

The full field list per kind is fixed one kind at a time, with the
columns that hold it, difference image first; see the [runs](runs) page
for how the run model attaches to the existing tables. For the difference image:

| Field | Source |
|---|---|
| l2 instance, reference instance, differencer, settings hash | manifest identity |
| field, filter, observation time | lookup on the l2 instance |
| image centre and four corners (RA, Dec) | manifest, from the difference WCS |
| science and reference info bits | manifest |
| source counts per catalog type and sign | manifest |
| registration residuals: x and y RMS and median | manifest |
| reference scale factor | manifest |
| spatial indexes | derived from the centre at registration |
| file paths, sizes, checksums | manifest members |
| run, attempt, result-set, instance ids | enclosing manifest and allocation |
| current flag, status | allocation; never current at registration |

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
        "infobits_science": 0,
        "infobits_reference": 0,
        "source_counts": {"sextractor": {"positive": 412, "negative": 388}, "photutils": {"positive": 405, "negative": 391}},
        "registration_residual": {"x_rms": 0.031, "y_rms": 0.029, "x_median": 0.004, "y_median": -0.002},
        "reference_scale_factor": 0.998
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

- Whether delivered statistics describe the association set, the pruned
  set, or both. The lead's science call.
- Whether both catalog families (SExtractor and Photutils) are retained
  in the rebuild.
- The registration field lists for the remaining kinds; each is fixed
  with its schema.
- Storage layout beneath the run: the path scheme under the attempt's
  output location.
- The alert outbox shape and the per-alert record.
