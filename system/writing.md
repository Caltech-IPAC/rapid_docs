# Writing

**Status: DRAFT**, under team review.

## Purpose

How every page on the site is written: voice, tense, the shape of a
page, terminology, typography, and what a post is. The documentation
design owns venues, sections, audiences, currency and page placement;
this design owns the sentences. It applies to reference pages and posts
alike, and to any agent drafting either.

The standard every rule below serves: technical prose that a working
astronomer or engineer reads straight through once, precise and plain
at the same time. A page that meets every rule and still costs the
reader effort at every sentence has failed; where a rule and
readability conflict, the reviewer reads for the reader.

The site is written to be read without friction by three kinds of
reader: astronomers who arrive from the Roman documentation and expect
Roman's nouns, software engineers who arrive from developer
documentation and expect procedures and schemas, and agents that read
one page at a time with no other context. What each of them needs from
the site is its terminology and self-contained pages, not its template.

## Registers

Every page or section is in one of three registers, fixed by its kind.
A register fixes who is addressed and whether the author appears; it
does not fix the grammatical subject, which is whatever actor the fact
needs: RAPID, the pipeline, a product, the SOC, the archive.

| Register | Where | Address | Tense |
|---|---|---|---|
| Reference | Home, Products, Science, System, Project; the reference and guarantee sections of product pages | Nobody is addressed; no "you", "we", "users" or "the community" | Present |
| Procedure | "How to use it" sections, the getting-started page, contribution steps | The reader, as "you", in the imperative for steps; declaratives for prerequisites, results and explanation | Present |
| Post | The log and the blog | The author, as "I" or "we", named in the post's metadata | Past for what happened, present for what is |

A reference sentence whose subject is the reader is rewritten with the
thing as its subject. "Users can query the catalog by position" becomes
"The catalog supports positional queries", and the query itself goes
under "How to use it". The reader is either "you", in a procedure, or
absent.

## Tense and status

Reference prose is in the present tense: what a thing is and does.
Whether the thing exists yet is carried by a label, so that a reader
tells delivered from planned without parsing verbs. Two labels, with
different meanings:

- **Design status**, on System pages: DRAFT or ADOPTED, per the
  documentation design. It says whether the team has ratified the
  design, and nothing about what is deployed.
- **Availability**, on Products and Science pages, or on a section of
  one: "Available since release 3", or "Not yet available: the design
  target is the alerts interface" with a link. A page with nothing
  delivered and no design to point at does not exist.

Under a not-yet-available label the prose still describes the target
in the present tense, and where a sentence read on its own would pass
for a capability claim, it says what it is: "The design specifies a
forced-photometry history in every alert", "At launch the stream
carries …". What changed, and when, is a log post; a reference page
never announces that it will be updated.

Placeholders never appear in reference prose: "TBD", "to be
determined", "coming soon", "in a future release", "will be updated",
"subject to change". "will" and "currently" are avoided, because the
label carries what they would say; where one survives review it is a
conditional or another party's policy ("MAST will not accept a product
without …"), not a promise about RAPID.

## Guarantees, limits, open points and modals

There are no disclaimer boxes. Every product interface page has a
"Guarantees and known limits" section, and a limit is a fact with its
number or its condition and its source, not a warning tone: "Alert
latency is not bounded. The commissioning median from image
availability to publication is reported in the operational metadata."
A promise RAPID cannot keep through a research mission's unknowns is
not made; a promise it makes is stated once, in the guarantee section,
and cited from everywhere else.

Three kinds of not-knowing, each written its own way:

- **A measurement's uncertainty** is stated with the number and its
  source.
- **An unmeasured quantity** is stated as unmeasured: "Completeness at
  faint magnitudes is not yet measured; the validation battery in the
  release design measures it."
- **An unresolved design choice** is stated as open, as the interfaces
  design does: "Open: the history depth carried in the packet; decided
  by the alert-schema review." An open point names what is undecided
  and what decides it, never how it might come out.

Modal verbs carry normative force and are used only with it: **must**
is a requirement RAPID enforces or a condition a consumer has to meet;
**should** is a recommendation with a reason beside it; **may** is a
permission. "Note that", "please note", "it is important to", "it
should be noted" and "please" are deleted wherever they occur; what
follows them either matters, and stands on its own, or does not, and
goes.

## The shape of a page

- A reference page's title is the noun the page is about; a standalone
  procedure page's title is the imperative it performs; a post's title
  is what happened. All in sentence case.
- A reference page opens with a paragraph stating what it covers and,
  where it is not obvious, for whom. On Products, Science and Project
  pages that paragraph sits under no heading; a System page carries it
  under "Purpose", the design documents' convention. A product
  interface page then follows the shape the documentation design fixes:
  what it is, how to use it, the reference, the guarantees and known
  limits. A Science page states what the stage does, the method, the
  published performance, and its references.
- A procedure has four parts: what the reader needs before starting,
  the steps, what a successful result looks like, and what to do when
  it fails where failure is likely. "How to use it" is the shortest
  working path: one way in, one example, and links to the reference
  for the rest. Which procedures get pages of their own is the
  documentation design's rule.
- Headings are sentence case, one H1, depth at most H3. Reference
  headings are noun phrases; procedure headings are imperatives
  ("Register for the stream"). No heading is a question, and none is
  "Overview", "Introduction", "Summary", "Background" or
  "Miscellaneous": a heading names its content.
- A page is self-contained. It does not say "above", "below" or "in the
  previous section"; it links the section. Every acronym is expanded on
  first use on every page, WFI included, because agents and search
  arrive mid-site; the one exception is RAPID itself, expanded on the
  home page and the citation page. A Roman term links, on first use, to
  the Roman documentation page that owns it; a RAPID term links to the
  site page that owns it.
- One home per fact, per the documentation design: a page states the
  facts it owns and links the rest. A page is split by the reader's
  question, not by length; an orienting page such as the architecture
  design is long because its question is.

## Sentences

Defaults, departed from for a reason the reviewer can see:

- One idea per sentence, most under 25 words, in the active voice with
  a concrete subject. A paragraph makes one point in at most five
  sentences. A derivation or a closely coupled set of conditions may
  run longer.
- Three or more parallel items are a list; items with two or more
  attributes each are a table; an argument is prose. A list item is a
  sentence or a noun phrase, consistently within the list.
- Say what is. Say what is not only where a reader would otherwise
  assume it.
- American spelling, the Oxford comma, digits for quantities. No
  contractions in reference prose; posts may use them.
- No filler ("in order to", "it is worth noting"), no intensifiers
  ("very", "significantly" without a number), no marketing adjectives.
  The site describes RAPID once, on the home page; every other page
  assumes it.

## Terminology

- Roman's nouns are Roman's, in the rendering the Roman documentation
  uses: Wide Field Instrument (WFI), Sensor Chip Assembly (SCA), Level
  2 (L2), multi-accumulation (MA) table, skycell. The naming design's
  third principle governs: machine tokens are RAPID's, prose follows
  the owner.
- RAPID's own nouns come from the naming design: its token registry,
  its dataset grammar, and its reserved words, which are the authority
  for what "alert", "notification" and the other reserved terms mean.
  In prose about image differencing, the image a difference is taken
  against is the reference, never the template; the word "template"
  keeps its ordinary meaning elsewhere.
- "RAPID" is the project and the system; "the pipeline" is the
  software; "the RAPID" is never written.
- External software is named as its owner names it: romancal, ASDF,
  MAST, Kafka, PostgreSQL.
- The glossary page defines each term the site uses in its own words
  or links the definition's owner: the naming design for reserved
  words, the Roman documentation for Roman terms, the site page for a
  RAPID product. A term RAPID uses differently from Roman carries the
  mapping. Where the glossary lives is the documentation design's
  rule.

## Typography

- Code font for identifiers, filenames, paths, column and field names,
  commands, environment variables, and version strings. Bold for a
  status marker, for a run-in label that opens a paragraph or list item
  ("**The bet.**"), and for a term at the sentence that defines it;
  never for emphasis inside a sentence. Italics for the titles of works
  only.
- No em dashes, in any register: a comma, parentheses, a colon, or a
  second sentence does the work. Quoted text keeps its own punctuation.
- Units with a space after the number (48 h, 2.3 μm, 0.11 arcsec),
  the unit in the column header of a table ("Latency (h)"), percentages
  as 12%, magnitudes as AB mag. Ranges use "to" in prose and an en dash
  in tables.
- Dates are ISO 8601 (2026-09-06); times are UTC and say so; durations
  are digits and a unit (5 days, 48 h). Versions follow the release
  design.
- A code block is introduced by one sentence ending in a colon, tagged
  with its language, and shows no prompt characters; expected output,
  where it matters, follows in its own block introduced by "Output:".
- Every table has a header row. A table has a caption when another
  page refers to it. Nothing that can be a table is an image.
- Every figure has alt text that says in one sentence what the figure
  shows. A figure that carries information the page depends on, a
  performance plot or a flow diagram, also has that information in the
  adjacent prose or a table, so a reader without the image loses
  nothing. A diagram is kept as source in the repository and rendered
  at build; no screenshots of text.
- One admonition type, `warning`, reserved for irreversible harm: wrong
  science produced silently, lost data, an exposed credential, an
  unexpected cost. An aside that matters is prose; one that does not is
  deleted.
- Link text names the target page or section; no bare URLs in prose and
  no "click here". External claims link their primary source: the Roman
  documentation page, the standard, the repository.
- Papers are cited inline as author and year, linked to the ADS
  abstract, and listed under "References" at the end of a Science page;
  software is cited as its own citation page asks; RAPID is cited as the
  citation page says.

## Posts

A post is a colleague's note, as the project's operating page puts it:
what happened, what the reader needs to know, where to start. It has an
author, a date and a category, is written in the first person, and is
never revised, per the documentation design. Its title says what
happened, not what the post is about. A present-tense claim about the
state of things links the reference page that will still be right when
the post is not. No opener, no sign-off, no boilerplate; its length is
what the news needs.

## Checks

The mechanical rules are a pattern scan, `scripts/check-writing.sh`,
built like the public-safety scan (portable shell, `grep -E`, exit
status) and run beside it in the pull-request checks. It scans the
reference-page sources (every source outside the log and blog; this
page and the repository's agent brief, `AGENTS.md`, excepted by name),
whole words, outside fenced code. Two severities:

- **Blocks the merge**: an em dash, a placeholder ("TBD", "to be
  determined", "coming soon", "in a future release", "will be
  updated"), "click here", an image without alt text, an admonition
  other than `warning`, a heading deeper than H3.
- **Warns, for review**: "will", "currently", "at this time", "for
  now", "subject to change", "please", "note that", and link text that
  is a bare URL. A warning is either fixed or answered in the pull
  request.

Heading case, dates in prose, and everything about register, subject
of sentence, self-containment and one home per fact are what review
reads for. A rule moves from warning to block only after the warning
has shown no false hits; a doctree-aware check, as a Sphinx extension,
replaces the pattern scan once the rules have settled.
