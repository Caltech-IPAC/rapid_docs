# Code standards

**Status: ADOPTED**

The standard is a tool configuration, not a prose style guide. Ruff is
the authority for Python layout and linting, configured in the
pipeline repository's `pyproject.toml`: `ruff format` settles
formatting, `ruff check` settles lint. The configuration file is the
single authoritative statement of style; the developer guidelines
already published in the pipeline documentation (4-space indentation,
no tabs, no trailing whitespace) are subsumed by it. Adjusting the
standard — including backing a rule off, repo-wide or per-file — is a
one-line configuration change, so the standard is binding without
being brittle.

Scope at adoption: formatting in full; linting starts with a minimal,
high-confidence rule set (syntax and import errors, unused names,
known-bug patterns) and grows deliberately rather than arriving all at
once.

The existing code is brought to the standard in a single one-time,
formatting-only commit, recorded in `.git-blame-ignore-revs` so that
line attribution skips it — `git blame` and the hosting platform
continue to show the substantive author of every line. The reformat is
scheduled inside the same coordination window as the repository
history rewrite, so the team absorbs one disruption, not two. After
it, continuous integration gates merges on `ruff format --check` and
`ruff check`.

Naming: lint enforces PEP 8 naming conventions. New code favors short,
clear names; that is review guidance, not a mechanical rule. Bulk
renames of existing code are excluded — established names change
opportunistically, module by module, with the agreement of the code's
maintainer.

Diagnostics: new and modified code uses the Python `logging` module
rather than `print()`. The logging layer itself is rebuilt from the
ground up as part of the IMSS→SMDC migration, to the observability
policy's target; this standard governs style, not that rebuild.

Test doubles in the operational layer must be able to refuse: a
double models the real system's refusal behavior — types,
constraints, conditional-write semantics, rowcounts — because a stub
that accepts anything verifies nothing. SQL under test executes
against a real engine; routing and binding tests construct real
objects, never hand-built fixtures the production path could not
produce; every integration seam carries at least one live probe as
first-class acceptance evidence.

The pipeline repository should carry a conventions file for coding agents
at its root — pointing at the ruff configuration as the style authority
and requiring that feature changes never reformat unrelated code. Agents
are part of the team's development workflow and should receive the
standard the same way developers do: from the repository itself.

## Environment variables

**Status: ADOPTED**

The environment carries per-invocation identity and process-level
plumbing only. Process-level plumbing means values a process needs to
execute at all, carrying no work-selection or science meaning: paths,
interpreter and library locations, temporary directories, core
counts, log level, and rehearsal switches whose default is
production. A required read — one whose absence makes the process
unable to proceed correctly — fails loud naming the variable;
substituting a value for an unset variable without any record is
prohibited in operational code, and a default is legal only for
plumbing where the default is the safe direction. Configuration and
credentials never travel by the environment: configuration lives in
its ratified homes (parameter tree, release content, submission
manifest) and credentials in the secrets store. No process writes the
environment for a downstream reader — the environment is not an
in-process transport; a process may read its own environment at its
boundary and pass values on explicitly. Operational code never
silently defaults an AWS region: resolve `AWS_REGION`, then
`AWS_DEFAULT_REGION`, then the SDK session, then raise. Nothing that
can alter a science product is reachable from the environment.

The policy's scope is the operational path: code executed by the
pipeline's automated operation — payload jobs, the controller,
supervised services, and anything they invoke. Developer tooling and
analysis scripts are outside the policy until promoted into pipeline
operation, at which point they enter it. Third-party contract
variables (CRDS) are honored as that contract requires, with any
fallback made explicit. One named temporary exception exists inside
the operational path: the controller's environment interface to its
four post-DB subprocesses, which expires when those scripts become
bulk-queue job types; no new environment transport may be added under
it.
