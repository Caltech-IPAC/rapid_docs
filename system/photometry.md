# Unported forced photometry

**Status: DRAFT.** Forced photometry is not ported; the rebuild carries
no photometry stage.

Forced photometry remains `dev`'s standalone script,
`pipeline/forcedPhotometryForField.py`. It takes a field and a CSV of
`reqid, ra, dec` sky positions. It has no `ppid` row in `dev`'s pipeline
table, and the inventory did not find where or how it is scheduled in
production.

`ExitCode.NOT_IMPLEMENTED` (69) remains reserved in the stage contract's
exit-code table ([stage-contract](stage-contract)). No stage in this
build returns it. The ruling is on [decisions](decisions).
