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
| [`stage-contract.md`](stage-contract) | DRAFT | The `rapidpipe` package and its dependency direction; the stage declaration, one invocation form, attempts, the manifest, five exit codes, settings; local fixtures; what it replaces |

```{toctree}
:hidden:

specification
stage-contract
```
