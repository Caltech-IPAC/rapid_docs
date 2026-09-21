# How the project is run

RAPID develops an image-differencing pipeline for Roman observations,
with a public alert stream and data products for time-domain astronomy.
Its design supports both routine production and the research needed to
develop the pipeline. A small team maintains the system throughout the
mission, so the design favors familiar tools and workflows that
scientific programmers can understand and operate.

The design allows scientists to start processing from their own
workstations, change parameters, compare results, and discard outputs without
affecting published products. Scratch and production runs share a data
model and record the code, configuration, and inputs used. Their outputs
have different retention and deletion rules, described in the
[specification](../system/specification), which also
states the manifest contracts at the pipeline's edges. The production
service is designed for the mission's full data volume.

## Development approach

RAPID gives early attention to decisions that become costly to change as
data accumulate and other software depends on them. These include data
identity and relationships, storage organization, access controls, and
external interfaces. They remain open to revision when scientific
workflows reveal a limitation.

Scientific methods and tuning are tested with simulations and refined
through commissioning and survey observations. An end-to-end pipeline provides
a working basis for that development, with recorded inputs, code and
configuration so results can be compared. Individual stages can be
tested and revised independently in scratch runs. Changes enter
production through tagged releases, as the [specification](../system/specification) states.

## Working together

Team members work independently on the pipeline and discuss decisions
that would be costly to change. Routine development does not require
the lead's sign-off. The design documents state the intended behavior;
the code records the implementation. GitHub issues hold open questions
and their discussion, and Git history records changes. There is no
separate decision register.

## Documentation

The design documents are a shared reference for the team and coding
agents. They describe the system independently of its authors, so that
contributors can work from the same specification. Code comments and
docstrings refer to the documented rules they implement.

Updates to the team explain what changed, what colleagues need to know,
and where to find the relevant reference. The [specification](../system/specification)
states which repository holds each kind of information.
