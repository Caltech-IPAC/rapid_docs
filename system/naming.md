# Naming

**Status: ADOPTED**

## Purpose

How RAPID names things across shared namespaces: the principles new
names follow, the registered token vocabulary they draw from, the
dataset-noun grammar, and the disambiguation map for the word
`rapid`. Adjacent naming authority stays where it lives: key grammars
and bucket naming in the storage design, Python code naming in the
code standards, delivered filenames in the CCSP PIT standard (storage
design). This document owns what none of them state: how a new name
is chosen, and the controlled vocabulary it is built from.

## Principles

1. **Canonical names are descriptive; brevity is solved locally.**
   A name typed often earns shell completion and personal aliases,
   never a shortened canonical form. The fleet CLI's single-letter
   alias layer is the model. Shortening a canonical surface trades
   clarity and collision-safety for keystrokes already saved by
   completion — `rapidctl` stays `rapidctl`; `rctl` is FreeBSD's
   resource-control utility.
2. **Prefix only where the namespace is shared.** A name carries the
   `rapid` (or `roman-rapid`) prefix exactly when it lives in a
   namespace RAPID does not own: the EC2 console, the global S3
   bucket namespace, an account-wide tag set. Where context already
   scopes, the prefix is dropped: instance `rapid-<login>` in the
   console, bare `<login>` as its CNAME under the project DNS zone.
3. **Machine tokens are lowercase and registered; prose follows the
   owner's rendering.** Identifiers are built from the token registry
   below. Prose uses each name owner's own form (High-Latitude
   Time-Domain Survey per the Roman documentation; RImTimSim;
   OpenUniverse). Lowercase acronym tokens deliberately sidestep
   upstream rendering disagreements — the survey names are hyphenated
   at STScI and unhyphenated at IPAC and GSFC.
4. **Names are absolute and, once claimed, held.** No relative labels
   (`new`, `old`, `prev`) as names; a forward-tracking alias may
   exist beside an absolute name, never instead of it. Public names
   are permanent (identifier-exposure ruling, security design);
   superseded names are retired, never reused.
5. **A new name is derived, not invented.** Before coining one: does
   the registry already hold the noun; does context scope it
   (principle 2); will it need siblings later — leave grammatical
   room, as the dataset grammar does. Names are never authoritative
   identity: parsing a name is permitted for routing and attribution
   only, and only when verified by round trip against authoritative
   metadata.

## The `rapid` namespace map

`rapid` is legitimately many names, each scoped by its namespace:

| Name | Namespace | Names |
|---|---|---|
| `rapid` | GitHub, Caltech-IPAC | the pipeline repository |
| `rapid` | conda environments on the fleet | the fleet-wide Python substrate |
| `rapid` | fleet shell PATH | the team fleet/account operator CLI |
| `rapidctl` | pipeline container | the constrained pipeline-operator surface (operations design) |
| `rapid` | MAST PIT registry | the registered PIT short name — CCSP filename field, MAST directory, database keyword |
| `Group=rapid` | AWS cost-allocation tags | RAPID's resources, under `Project=roman` |
| `rapid-<host>` | EC2 console | fleet hosts (`rapid-admin`, `rapid-db`, `rapid-<login>`) |
| `rapid.roman.sciencecloud.nasa.gov` | delegated DNS | the project zone; interior records drop the prefix |
| `roman-rapid-<purpose>` | global S3 namespace | the bucket set (storage design) |
| `imss-rapid-*` | legacy Caltech account | retiring-account resources; the `imss` marker separates them from SMDC |

## Token registry

Append-only. Enforcement joins the storage design's enumerated-name
registries: builders validate membership; review is the gate for new
tokens.

Tokens are atomic: lowercase `[a-z0-9]+`, no interior hyphens;
hyphens belong to grammars that join tokens. One registered
exception: data-class values are compound tokens (the `real-pristine`
family) that appear only between `/` delimiters in object keys, never
inside hyphen-joined names.

The registry has three append-only tiers: (a) lexical tokens (the
survey/source/class tables below); (b) complete claimed identifiers —
every claimed dataset noun, bucket name, and similar permanent
identifier, registered whole and treated as opaque; (c) tombstones —
retired identifiers and aliases, recorded so they are never reused
and so operational language can distinguish a tombstoned identifier
from a live lexeme. A new data-class value is not an append-only
change: it amends the two-axis identity model (operations design) and
its science/non-science authorization status, so it requires its own
ratification.

**Surveys** — lowercase acronyms of the Core Community Surveys and
General Astrophysics Surveys: `hltds`, `gbtds`, `hlwas`, `gps`,
`gas`.

**Simulation sources**:

| Token | Name | Provenance |
|---|---|---|
| `openuniverse` | OpenUniverse2024 | high-latitude survey sims, IRSA-hosted, frozen; no Galactic bulge |
| `rimtimsim` | RImTimSim — Roman IMage and TIMe-series SIMulator | Wilson et al. 2023, ApJS (doi:10.3847/1538-4365/acf3df); RGES-PIT lineage; pixel-level GBTDS sims |
| `socsim` | SOC-produced simulations | SOC simulation releases; a producer tag, not a lineage — before any bucket is claimed under it, the actual SOC simulation family must be registered under a lineage name, since one producer shipping two families must not share a token |
| `socsim-r00340` | SOC simulation release r00340 | The lineage `socsim` reserves a name for. The SOC's own release identifier, from the source of truth `s3://stpubdata/roman/nexus/soc_simulations/r00340/` and carried in every file name RAPID ingested (`r0034001002001001003_0001_wfi01_f146_cal_lite.fits.gz`) — the family names itself, so nothing here is coined. This is what `g0001`'s inputs are; the second SOC family gets `socsim-r<its own release>` and the two never collide, which is exactly the confusion the `socsim` row exists to prevent. Metadata only — a `source` value in provenance records. It renames nothing: the bucket `roman-rapid-inputs-gbtds-sim`, the dataset noun `gbtds-sim`, and the generation `g0001` are claimed names and are held (principle 4) |

**Data classes** — the substrate × injection identity (operations
design), as compound self-describing tokens that sort as a family:
`real-pristine` (science), `real-injected`, `sim-pristine`,
`sim-injected`.

## Dataset nouns

The dataset noun in `roman-rapid-inputs-<dataset>` follows the
grammar `<survey>-<source>(-<qualifier>)*`: registry tokens, most
general first; survey and source are both mandatory, qualifiers are
zero or more, and each qualifier is an atomic registry token. Source
is part of the identity because the dataset is the swap/retire/cost
unit and two sources for one survey retire independently. Campaign
detail — injection date, sim release, selection — stays in the
generation manifest, never the noun (storage design). Examples:
`hltds-openuniverse`, `gbtds-rimtimsim`, `gbtds-socsim`. The complete
noun is registered whole (tier b) and treated as opaque: no tool or
reader infers fields by splitting on `-`. The live `gbtds-sim`
predates the grammar and is retained: claimed names are held. The
retired rehearsal noun `socsim` is tombstoned (tier c).

## Reserved words

A semantic dictionary scoped to RAPID-owned identifiers and normative
prose — not a global prohibition. Ecosystem terms (an RPM Release, a
GitHub Actions run) and grandfathered names are explicit exceptions.

- Generic type nouns are never canonical identifiers; artifacts take
  role-qualified names.
- `alert` = astronomical event only; infrastructure events are
  notifications.
- `pipeline` = the RAPID processing graph only; CI is a workflow;
  container images are named for their content.
- `product key` = the catalog's science-identity digest; an S3 path
  is an object key (storage design owns the ruling).
- `release`, `generation`, `dataset`, `run`, `attempt`, `delivery`:
  single-meaning within RAPID-owned naming.

## What needs no new names

- Tests and source injection are data classes, not places: no test
  bucket, no test naming (operations design).
- Staged-input interiors keep upstream names verbatim (storage
  design).
- Delivered filenames are the CCSP namespace, disjoint from internal
  keys (storage design).
- Key grammars: storage design. Python code: code standards.
