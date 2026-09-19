# How the project is run

**The purpose.** RAPID finds transients in Roman images and tells the
world about them promptly. It is built and run by a small research
team, and it has to work for both audiences at once. For the community
it is a service: every alert and every published product is correct,
permanent, traceable to the code, configuration and inputs that made
it, and delivered at the full volume of the mission. For the team it is
a workbench: anyone can process a set of images on their own machine,
change a parameter, run it again, compare, and throw the result away,
without asking permission and without touching what has been published.
Work you own is scratch; work the project publishes is archive. We keep
one data model and one record of provenance across both. We build with
tools we already know, AWS Batch and PostgreSQL, and we prefer the
design a scientist can explain in a sentence over the one that guards
against everything, because three and a half people have to run it for
the life of the mission.

**The bet.** Do the things that are hard to change up front; let the
rest stay rough. The science pipeline stays rough until real data
arrives, by necessity, so at cutover it has to run end to end and no
more: a foundation to build on, a basis for iteration. Commissioning and
early science are a long bootstrap; the pipeline is built to be
iterated through that, not finished before it. Hard to change, therefore
done properly now: the data model and schema, storage layout and naming,
identity and roles, the interfaces other PITs consume. Soft, therefore
allowed to be rough: stage internals, tuning, alert content, and,
explicitly, owned work: what a scratch run produces is rerun, iterated
on and deleted without ceremony, and only the rerun under the release
that turns it into published work inherits the hard side's guarantees.

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
