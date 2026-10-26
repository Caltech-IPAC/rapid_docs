# Forced photometry

**Status: current**

Forced photometry for alerts is part of the `packet`
stage; `dev`'s standalone forced photometry for a list of positions is
not ported.

The `packet` stage measures forced photometry at each alerted object's
founding position on the difference and science images of its window,
with `dev`'s algorithm, and publishes the rows as its packet set's
`forced.parquet`. The [foundation](foundation) page states the design:
a packet job names the window's images and its predecessor packet
sets' forced rows as inputs, and measures only what those do not hold.

`dev`'s standalone script, `pipeline/forcedPhotometryForField.py`,
takes a field and a CSV of `reqid, ra, dec` sky positions. It has no
`ppid` row in `dev`'s pipeline table, and the inventory did not find
where or how it is scheduled in production. Nothing outside packets
needs it yet, so it stays unported.
