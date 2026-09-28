# Unported forced photometry

Not ported. The rebuild carries no photometry stage. Forced
photometry stays `dev`'s standalone script,
`pipeline/forcedPhotometryForField.py`, given a field and a CSV of
`reqid, ra, dec` sky positions; no `ppid` row exists for it in `dev`'s
pipeline table, and the inventory did not find where or how it is
scheduled in production. `ExitCode.NOT_IMPLEMENTED` (69) stays in the
stage contract's exit-code table as a reserved code no stage in this
build returns ([stage-contract](stage-contract)); the ruling is on
[decisions](decisions).
