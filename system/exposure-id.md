# The exposure id

**Status: DRAFT** (a design: nothing on this page is built yet)

An exposure's `expid` becomes an integer handed out by the database that
carries no meaning, and the producer's own name for the exposure is
stored beside it as text, unique within a dataset. Each reader supplies
that name, so a change in Roman's naming, or a new simulation's, touches
one reader function and no key. Ben ruled the shape on 2026-11-14; a key
packed from Roman's identifiers, wider or not, was rejected for that
reason.

This page is the design the build implements. It answers six questions,
each in one sentence followed by its reason and the place in the code it
binds, and ends with the changes by file, the contracts the tests assert
and what a landing needs. The code was read on the pipeline repository
at `rebuild` 745d3d81 with the commissioning ports that touch the id
(the program selection, 3f21016e, which carries the program from the
file, 8a040c08; the MAST stream, 3ed3e36b), and `dev`'s serial at
`dev` 7e75f711.

## Why the key changes

`rebuild` packs `expid` from the file name as `pass * 10**6 +
observation * 10**4 + visit * 10**2 + exposure` (`intake.expid`,
`loop.stem_expid`), because a SOC exposure's own identifier, 23 digits,
fits no `integer` ([intake](intake)). Program, execution plan and
segment are not in it. MAST's file names of four commissioning programs
show what that does: 188 of program 1043's 250 packed ids and all 48 of
program 1062's are shared by more than one exposure, the clashes between
execution plans, and 88 ids are shared across programs. Two exposures
with one id share one `exposures` row: the second program's row is never
written, its L2 rows take the first one's `program_id`, and a clash in
one SCA and filter has its binding refused. Program 1049 alone has no
clash.

`dev`'s `expid` is a database serial (`exposures_expid_seq`, returned
by `addExposure`, which finds an exposure by its `dateobs`), unique
across programs. The rebuild keeps `dev`'s column name and its
`integer` type.

## The design in one paragraph

One table, `exposure_ids`, holds `(dataset, name, expid)`: `expid` an
`integer` identity, `name` the producer's text, unique per dataset. The
loop resolves the names of the stems it is about to take in to ids
before it plans, inserting the names it has not seen, and puts the id in
each intake job's scope; every later stage, file and script reads the id
as an opaque integer and reads the name, never the digits, when it needs
to know which exposure it is. Each reader's branch of `loop.stem_ids`
gives the name, the stem with its detector and its file-kind suffix
removed, and nothing else in the code reads an id's meaning from a file
name.

```sql
CREATE TABLE exposure_ids (
    expid integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dataset text NOT NULL,
    name text NOT NULL,                              -- the producer's name for the exposure (loop.stem_ids)
    created timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE (dataset, name)
);
```

The table is bookkeeping, as `jobs` and `official` are, not a product:
no job writes it and nothing binds it. Its rows are never changed or
deleted, so a name keeps its id across passes, reruns and runs of its
dataset. One identity serves every dataset, so no two exposures anywhere
share an `expid`; the same exposure taken into two datasets has two.

## The six questions

### How the 18 SCAs of one exposure agree on one id

**The 18 SCAs never assign an id: the loop resolves their one shared
name to one id in one statement before it submits any of them, and the
`UNIQUE (dataset, name)` constraint makes any two resolutions of that
name return the same row.** The 18 stems of an exposure arrive in one
listing and reduce to one name, so one pass sees one name; a second loop
of another run on the dataset, or the hand verb below, racing on that
name, waits on the uncommitted insert and then reads the row it made
(`INSERT … ON CONFLICT (dataset, name) DO NOTHING`, then `SELECT`, in
`READ COMMITTED`). It binds `rapidpipe/foundation/loop.py`, a new
`exposure_ids(conn, dataset, names)` called from `run_pass`. `dev`'s
answer, an insert that first looks the exposure up by `dateobs`, lost:
the lookup and the insert are two statements, so two SCAs racing both
miss and both insert, and the observation date is a meaning the key
would then carry.

### Where the id is assigned

**The loop assigns it, before it plans the intake, and the intake job
carries it in its scope; neither a stage nor the publisher assigns
it.** A job's output keys are fixed when it is submitted (`expects`,
recorded in `job_inputs` with `dataset, expid, sca, fid`), before any
stage runs, and the publisher only binds those keys; a stage computes in
memory and writes files, so the id must exist before the job does. It
binds `loop.run_pass` (resolve, then `plan`), `loop.plan` (the intake's
scope becomes `{"dataset", "file", "expid"}`; the `exposures`
expectation still rides on the first SCA's intake, now by the scope's
`expid` of the pending intakes rather than by re-packing their stems),
and `rapidpipe/stages/intake.py` `run` (the rows' `expid` is
`job.scope["expid"]`; `expid` and the `READERS` `expid` entries go). A
job run by hand gets its id from one verb, `rapidpipe exposure id
--dataset D --name N`, which runs the same function and prints the id
(`rapidpipe/cli/main.py`). The alternative, a default on
`exposures.expid` drawn at publish as `dev` draws it, lost: seventeen of
the eighteen intakes write no `exposures` row, and their `l2files` keys
are fixed at submission.

### How the loop selects without arithmetic on the id

**A stem is selected by its own terms from `stem_ids`, and an official
L2 row by the terms of the stem its intake job read (`jobs.scope ->>
'file'`), so `--passes`, `--pointings` and `--programs` never read the
id; `--expids` becomes `--exposures`, a list of name prefixes.**
`admits_row` today recovers pass and pointing from the id's digits
(`expid // 10**6`, `(expid // 100) % 100`, `expid % 100`), which a
serial does not carry; every L2 row already names its intake job, whose
scope holds the stem, so the snapshot reads the stem with the row and
one parser serves both. It binds `loop.snapshot` (the L2 query joins
`jobs` for the stem), `Selection.admits_row` (takes the row's stem, not
its id) and `Selection.admits_stem`, `Selection.parse` and `summary`.
An imported row has no intake stem: it is admitted only when no pass,
pointing or exposure term is set, which is also the only selection its
`dev` serial ever answered correctly under the packed terms. `--exposures r0034201002,r0034201005001003061`
admits a stem or row whose name starts with any of the prefixes;
because a SOC name runs program, plan, pass, segment, observation,
visit, exposure, a prefix is the stretch of the hierarchy the packed
ranges were for (pass 2 whole; pass 5 observation 3 visit 61), now with
the program and plan in it. Keeping `--expids` as ranges of the serial
lost: an id does not exist until its stem has been listed and resolved,
so it cannot select a first intake, and its ranges mean nothing to an
operator. `scripts/socsims_truth.py`'s `--expids` becomes `--exposures`
the same way; `scripts/completeness.py`'s `--expids`, a list of a
finished run's own ids, stays.

### What the new id changes downstream

**Nothing downstream changes shape: difference and packet scopes,
output prefixes and the packet's `expId` carry the serial as they
carried the packed id, the `import` stage takes its id from the verb,
and each script that matched exposures by the packed id matches them by
name.** The id is opaque in all of them; only places that read meaning
into it, or met it before a run existed, change. In detail:

| Where | With the serial |
|---|---|
| Job scopes | `difference` and `packet` keep `{"expid", "sca", "fid"}` (`loop.plan`); `intake` gains `expid`; `psf` and `reference` carry none. `job_metrics.expid` (`schema.sql`, from the scope) now fills on intake jobs too. |
| Output prefixes | `<outputs root>/<run>/<stage>/<job>/<attempt>/` (`foundation/local.py`) has no id in it. Inside, intake's `<stem>_cal.fits.gz` keeps the stem and the packet's `packets/<expid>-<sca>-<fid>.avro` (`stages/packet.py`) the serial, unique within its job's prefix: unchanged. |
| `import` | An epoch's scope still names `expid`, now the destination dataset's id, which the operator gets from `rapidpipe exposure id` for the `soc-l2` name of `dev`'s L2 file (`dev`'s converted L2 file keeps the SOC file's stem, `output_fits_basename` in `pipeline/ingestL2Files.py`); `dev`'s own serial is no longer kept, while `rid` and `pid` stay `dev`'s (`stages/import_products.py`, docstring and README). An imported and a pipeline exposure of one name in one dataset so share one id, where `dev`'s serial would have collided with the identity. |
| Packet fields | `expId` (`science/alerts/param_registry.py`, `DIA_SOURCE_PARAMS` and the forced-photometry params) carries `sources.expid` and `diffimages.expid`, already described as "RAPID-assigned exposure identifier (pipeline database serial, not a Roman SOC identifier)"; it now is one. `segment`, `observation`, `visit` and `exposure` keep carrying the `exposures` row's Roman identifiers. No field is added or changes meaning. |
| `completeness.py` | The truth's `expid` column becomes `exposure`, the name; the script maps names to the run's ids through `exposure_ids` of the run's dataset, then joins by `(expid, sca)` as now. A truth written before the change (the injected footprint's) still carries packed ids, so the script keeps the old packing as one function used only to map such a truth: it packs each run exposure's intake stem and joins on that. |
| `completeness_ou.py` | The OpenUniverse truth index is found by pointing, which it read as the `expid`; it reads the pointing from the difference's L2 row's intake stem through `stem_ids`. |
| `inspect_run.py` | The gallery's first and last epoch are by `mjdobs` (the difference's `jd`), not by id, and a label shows the name beside the id. |
| `compare_runs.py` | Two runs' epochs pair by `(name, sca)`, the name from `exposure_ids` of each run's dataset, since two datasets give one exposure two ids. |
| `inject_dataset.py` | The truth carries `exposure`, the name, for `expid`; each file's noise seed takes the name's SHA-256 digest where it took the packed id, so a new injection with an old seed differs from the old one (the footprint already written is not rewritten). |
| `socsims_truth.py` | The truth carries `exposure` for `expid`; `--exposures` for `--expids`. |

`difference.py`, `packet.py`, `validate_run.py`, the association
(`science/crossmatch`, which orders exposures by `mjdobs`) and
`database/queries.sql` read the id as an opaque key and do not change.

### What the exposure name is for every reader

**The name is the file's stem with its detector and its file-kind
suffix removed, given by the reader's branch of `loop.stem_ids`:**

| Reader | Example stem | Name |
|---|---|---|
| `soc-l2` | `r0034201001001004001_0001_wfi08_f146` | `r0034201001001004001_0001` |
| `socsims-lite` | `r0034001005001003061_0001_wfi02_f146` (`_cal_lite.fits.gz`) | `r0034001005001003061_0001` |
| `openuniverse` | `roman_tds_H158_1012_wfi04` | `roman_tds_H158_1012` |
| `rimtimsim` | `rimtimsim_WFI_F213_SCA02_000000411_lite` | `rimtimsim_WFI_F213_000000411` |

A SOC-format name is the stem up to and including the exposure number,
so it holds program, execution plan, pass, segment, observation, visit
and exposure, everything that tells one exposure from another and
nothing that tells one detector from another; `socsims-lite` reads the
SOC stem and so gives the SOC name. OpenUniverse's name keeps the
survey, the filter and the observing sequence's row; RimTimSim's the
filter and GBTDS's exposure number; each loses only the SCA. One
function serves the loop, the intake's check and the truth writers,
because `stem_ids` already dispatches every reader's stem in the loop
(`rapidpipe/foundation/loop.py`), where the listing and the selection
read it; `stem_expid` goes. The intake's own `parse_stem` per reader
stays, for the identifiers it checks against the file's metadata, and
no longer feeds a key.

### What becomes of the refusal `ports-plus-601` adds

**It is removed with the build, and the intake's one check becomes that
its scope's `expid` is the id `exposure_ids` holds for its stem's name
in its dataset (exit 65 otherwise).** The refusal exits 65 when a SOC
file's program, plan or segment differ from the official `exposures` row
of the same `expid`; once the id is the name's, one id means one name,
and the name contains program, plan and segment, so the condition cannot
arise, while `_check_key` already holds the file's metadata to its name.
The new check guards the one way two exposures could still meet under
one id, a hand-typed scope. It binds `rapidpipe/stages/intake.py` `run`
(the refusal, where `ports-plus-601` puts it, and the new check, a read
of `exposure_ids` through `job.connect()`). Keeping the refusal beside
the new check lost: it compares three fields where the name compares
all of them, and it tests a state the key makes impossible.

## Changes

Every file that changes, at `rebuild` with the commissioning ports:

| File | What changes |
|---|---|
| `database/schema.sql` | `exposure_ids` (above); the key comment at the top names it; `exposures.expid`'s comment says the id is `exposure_ids`'s for the producer's name. No other column changes type or name. |
| `database/schema.dot` | Regenerated by `scripts/schema_diagram.py` with the new table. |
| `rapidpipe/foundation/loop.py` | `exposure_ids(conn, dataset, names)`; `run_pass` resolves the names of the listing's admitted stems no published intake holds, then plans; `plan` takes the mapping, puts `expid` in each intake's scope and counts claimed exposures from pending intakes' scopes; `stem_ids` returns `name` for `expid`, one branch per reader; `stem_expid` deleted; `snapshot` reads each L2 row's intake stem; `Selection.admits_row` takes the stem; `--exposures` prefixes for `--expids` ranges in `Selection`; the module docstring. |
| `rapidpipe/cli/main.py` | `loop --exposures` for `--expids`; the verb `exposure id --dataset --name`; the verb list in the docstring. |
| `rapidpipe/stages/intake.py` | The key's `expid` from the scope; `expid` and the `READERS` `expid` entries deleted; the check of the scope's id against the stem's name; the `ports-plus-601` refusal deleted if it landed; the docstring's paragraph on the packing. |
| `rapidpipe/stages/import_products.py` | The docstring: an epoch's `expid` is the destination's, from `exposure id`; `dev`'s is not kept. |
| `README.md` | The hand-run block: `exposure id` before each `intake` and the `import` of an epoch. |
| `scripts/completeness.py` | The truth's `exposure` names mapped to the run's ids; the legacy packed-truth mapping. |
| `scripts/completeness_ou.py` | The pointing from the intake stem. |
| `scripts/inspect_run.py` | First and last epoch by `mjdobs`; the name in labels. |
| `scripts/compare_runs.py` | Epochs paired by `(name, sca)`. |
| `scripts/inject_dataset.py` | Truth column `exposure`; the seed from the name's digest. |
| `scripts/socsims_truth.py` | Truth column `exposure`; `--exposures`. |
| `tests/db/test_exposure_ids.py` | New: the concurrency and uniqueness contracts below. |
| `tests/db/test_intake_job.py` | The scope's `expid` for the packed literal; the check's refusal. |
| `tests/db/test_loop_snapshot.py` | A row's intake stem in the snapshot. |
| `tests/unit/test_loop.py` | The selection, plan and naming contracts below; the packed literals go. |
| `tests/unit/test_intake.py` | The packing tests go; the scope's `expid` keys the rows. |
| `tests/unit/test_intake_openuniverse.py`, `tests/unit/test_intake_rimtimsim.py` | The scope carries `expid`. |
| `tests/unit/test_completeness.py`, `tests/unit/test_completeness_ou.py`, `tests/unit/test_inspect_run.py`, `tests/unit/test_compare_runs.py`, `tests/unit/test_inject_dataset.py`, `tests/unit/test_socsims_truth.py` | Each script's change above. |

The [intake](intake), [loop](loop) and [tool](tool) pages change with
the build: the packed `expid` paragraph, the selection's `--expids` and
the new verb.

## Tests

The contracts the build asserts, one behaviour each:

1. Two stems of one exposure get one id under concurrent intake: two
   connections resolving the same `(dataset, name)` at once both get
   the same id (`tests/db`), and a pass over the 18 SCA stems of one
   exposure gives every intake the same scope `expid` and exactly one of
   them the `exposures` expectation (`tests/unit`).
2. Two exposures whose stems pack alike get two ids: two stems that
   differ only in execution plan, as program 1043's do
   (`r0104301001001001001_0001_wfi01_f158` and
   `r0104302001001001001_0001_wfi01_f158`), get two names, two ids and
   two `exposures` expectations.
3. A reader's name function is the only thing a naming change touches:
   with `stem_ids`' name replaced by another one-to-one function, the
   plan's submissions, the intake's rows and the selection are the same
   but for the names, every `expid` being the mapping's.
4. A name keeps its id: resolving a name already held returns its id,
   on a later pass and under another run of the dataset; a second row
   for one `(dataset, name)` is refused by the table.
5. The intake exits 65 when its scope's `expid` is not the id of its
   stem's name in its dataset.
6. `--passes`, `--pointings` and `--programs` select an official L2 row
   by its intake stem; a row with no intake stem is selected only when
   none of `--passes`, `--pointings` or `--exposures` is set.
7. `--exposures` admits a stem or row whose name starts with any given
   prefix and no other.
8. A truth written with names is matched to the run's ids, and a truth
   written with packed ids is matched through the legacy mapping, with
   the same counts.
9. `compare_runs.py` pairs two runs' epochs by name and SCA when their
   datasets give one exposure two ids.

## Landing

The schema changes only by a recreate of `public`, which builds it from
the merged `schema.sql`: with the cutover database window if that has
not started when the build is green, otherwise at a recreate of its own
with program 1049 reprocessed. Either way it lands before any flight
program other than 1049 is loaded and before any packet leaves SMDC,
since every row and every sent packet before it carries a packed id.
