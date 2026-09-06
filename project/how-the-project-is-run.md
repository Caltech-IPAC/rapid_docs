# How the project is run

**The bet.** Do the things that are hard to change up front; let the
rest stay rough. The science pipeline will be rough until real data
arrives, by necessity, so at cutover it has to run end to end and no
more: a foundation to build on, a basis for iteration. Commissioning and
early science will be a long bootstrap; the pipeline is built to be
iterated through that, not finished before it. Hard to change, therefore
done properly now: the data model and schema, storage layout and naming,
identity and roles, the interfaces other PITs consume. Soft, therefore
allowed to be rough: stage internals, tuning, alert content.

**The team.** Teammates work independently on the pipeline. Nothing
requires the lead's sign-off; hard-to-change decisions become team
discussions. The design documents, published on this site, state the
target; GitHub issues hold the discussion; git log holds the history.
Nothing else is a record, and there is no separate decision register.

**The docs.** Two kinds of writing for two audiences. The design docs are shared
reference for humans and agents alike: one standard plan, unambiguous,
independent of any one person; that is what lets everyone work to the
same thing without asking. Messages from the lead to the team are a
colleague's notes: what changed, what they need to know, a starting
point that points into the reference.

**The code.** Code states what is true now. A docstring never cites a
rule that isn't written down somewhere the reader can find it. Nothing
is there because a reviewer once flagged it.
