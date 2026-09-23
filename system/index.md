# System

The specification is the authoritative statement of what RAPID is built
to be on SMDC. It carries equal weight to the code: the pipeline must be
rederivable from it. It is marked **DRAFT** (under iteration; what the
team reviews) or **ADOPTED** (normative). It is DRAFT at present: the
team's review lands at the cutover to SMDC, and nothing becomes ADOPTED
without that review.

The specification replaced the earlier design corpus of seventeen
documents on 2026-09-21. That corpus described the system that had
accumulated; the rebuild starts from this page. The earlier documents
remain in this repository's history.

## Documents

| Document | Status | Scope |
|---|---|---|
| [`specification.md`](specification) | DRAFT | Purpose and outcome; the pipelines and their stages; the stage contract; runs, the three output states, promotion, attempts and deletion; tools; the three repositories and their boundary; releases; the manifest edges; constraints; sequencing; what is not yet decided |
| [`products.md`](products) | DRAFT | Product kinds and result-set kinds, logical key versus instance id, bundles, reading across runs, registration metadata with one source per field, one complete worked manifest |
| [`runs.md`](runs) | DRAFT | The run-model tables beside the kept `dev` schema; unit and attempt state machines; instances and the three custody states; promotion under one lock with before and after per key; guarded deletion as the only deleter; storage layout; identifiers |
| [`stage-contract.md`](stage-contract) | DRAFT | The `rapidpipe` package and its dependency direction; the stage declaration, one invocation form, attempts, the manifest, five exit codes, settings; local fixtures; what it replaces |
| [`load.md`](load) | DRAFT | The `load` stage as ported from `dev`: its inputs, the child tables, what lands in `sources`, the source-set result set, its settings and exit codes; the `psf` registration block |

```{toctree}
:hidden:

specification
stage-contract
products
runs
load
```
