# Documentation

**Status: DRAFT** — the open points are listed at the end.

## Purpose

Where every statement about RAPID lives, who it is written for, and
what the public documentation site is. This design owns the venue
rules and the site's structure; the repository set and its visibility
belong to the repositories design, and the external interfaces the
site documents belong to the interfaces design.

## Classification

Four axes classify any piece of documentation, and the venue follows
from them:

| Axis | Values | What it decides |
|---|---|---|
| Audience | community, institutional, team, lead | Who must be able to read it and at what skill floor |
| Currency | current-state, dated | Whether it is updated in place or written once and never revised |
| Visibility | public, team, lead | Which venue may hold it at all |
| Coupling | to the code, to operations, to neither | Whether it versions with the code, with the deployment, or on its own |

Two rules derive everything below. **One home per fact:** a statement
lives in exactly one venue and every other venue cites it. **Currency
is a property of the page, not the site:** a page is either
current-state, undated, and updated in place, or dated, attributed, and
never revised. No page mixes the two.

## Audiences

| Audience | Comes for | Skill floor |
|---|---|---|
| Time-domain astronomer, light coding — the majority of the community list | What RAPID is and produces, how to obtain products, what to trust, how to cite | Reads prose; table tools and some Python |
| Researcher, power user | Schemas with units, versions and provenance, published performance numbers, bulk access, release contents | Fluent Python and git |
| Downstream integrator (alert broker) | Wire format, transport, access process, latency, change policy, a synthetic stream before the live one | Professional software engineer, no Roman context |
| Institutional: NASA, the archive, the science operations center, peer infrastructure teams, reviewers | Charter, interfaces on both sides, licenses and persistent identifiers, citation, the data and software policy | Reads documents |
| Team developer, and any agent working in a repository | How the system is built, code standards, how to contribute, how the project is run | Scientific programmer |
| Team operator | Runbooks, account specifics, deploy state, alarms | Team only |
| Lead | Planning, research, decisions in flight | Lead only |

The community pages are written to be comprehensible to any reader with
a college degree; the system pages assume a scientific programmer.

## Venues

| Venue | Holds | Visibility | Rule |
|---|---|---|---|
| Documentation site and its repository | Every public statement about RAPID: reference pages (current-state) and posts (dated) | Public | The reference. Anything public and durable lives here or cites here |
| Pipeline repository | Code, docstrings, a README that points to the site, the contribution files the software policy requires | Public | No documentation tree. Its issues are the pipeline discussion |
| Infrastructure repository | Everything operational and private, with one operational tracker | Team | Never restates a design; cites the site's page. Its issues are the infrastructure discussion |
| Design authority repository | Planning and research the team does not depend on | Lead | Holds nothing the team needs and nothing operational |
| Institutional project page | One paragraph and a link to the site | Public | Maintained by the institute; not a RAPID venue |
| Team wiki | Roster with addresses, list memberships, onboarding, meeting notes | Team | Institutional records about people; never design or operations |
| Announcement list and chat | Announcements and conversation | Public list, team chat | Ephemeral; anything durable is posted to the site and linked |
| Archive and software-release registries | The data products and the software releases, with their persistent identifiers | Public | The site cites the identifiers; it does not mint them |

Consequences. The pipeline repository loses its documentation tree; the
pages worth keeping are re-derived into the site, not converted, and
stale pages are not carried. The design documents move to the site as
its system section and are edited there. Design statements state the
target; the infrastructure repository records what is deployed.

## The public site

One site, one front door, five sections and a log. Sections are the
kinds of question a reader arrives with; within a section every page
of a kind has the same shape.

| Section | Content | Audience | Currency |
|---|---|---|---|
| Home | The acronym expanded, the mission and infrastructure-team context, the four services, the funding acknowledgement; three links: find products, read the latest, cite RAPID | Everyone | Current-state |
| Products | The delivered products first: what reaches the archive, tables and columns with units, file layout and naming, bulk access. Then forced photometry, cutouts, processing records, and the release list. Alerts are one page: a registered interface, the brokers that carry the stream for everyone else, the format for registrants. One getting-started page for the astronomer who does not code | Community, integrators | Current-state |
| Science | The algorithms — tessellation, reference construction, differencing, candidate extraction, real/bogus classification, photometry — and the published performance numbers | Researchers, institutional | Current-state |
| System | The design documents, architecture first, each carrying its status | Team, agents, institutional | Current-state |
| Project | Team and contact; how the project is run; contributing; how to cite; the data and software policy; where things live (this design) | Everyone | Current-state |
| Log and blog | One blog, two categories with separate feeds. Blog: curated, external, occasional. Log: the team's blow-by-blow development record | Community (blog), team and followers (log) | Dated |

Product interface pages share one shape: what it is, how to use it,
the reference (schema, format, naming), the guarantees and known
limits. The release list is the site's only versioned reference
content: state per version, not narrative.

Posts carry an author, a date, and a category, and are never revised
after publication. A correction goes into the reference page it
concerns and, where it matters, into a new post. The log replaces the
dated evidence and changelog pages the pipeline repository's tree
carried. Nothing else on the site is dated: a design document's status
marker says DRAFT or ADOPTED, with at most the scope it applies to;
who ratified what, and when, is the repository's history.

Pages exist only when they have content; a section may be thin, never
a skeleton.

## Machine readership

Agents and indexers are first-class readers. Every source is Markdown;
every page's source is exposed beside its rendering; the site root
serves an `llms.txt` index built from the same sources; each blog
category publishes an Atom feed; URLs are stable, and a moved page
leaves a redirect.

## Public-safety boundary

The site is public by construction, so its content is safe without
review. The boundary is the deployment's instance, not its design: a
design document states what runs where, when, and under which
identity, and names the resources it designs; what never appears is
the instance — account, instance, and network identifiers, addresses,
alarm destinations, where a credential is kept, the state of what is
deployed today, and its shortfalls — nor any opinion or criticism of
existing work. People appear by name in two
places only: the team page, by name, role, and affiliation, without
addresses; and as the author of a post, including the log's listing of
posts by author. Contact routes are the role address, the announcement list,
the pipeline repository's issues, and the registration route for the
alert stream; no route names a person.

## Policy compliance

The site is where the science information policy's documentation
obligations are met, and the project's own posture is stated on it:

- The Science section is the documented-algorithm record required for
  reanalysis of the products.
- The Products section is the description of the data, user guide, and
  calibration description, at the required comprehension bar.
- The Project section states the licenses (permissive for software; the
  public-domain dedication for data unless a restriction applies), the
  persistent identifiers and citation guidance, and the release
  commitments; the code of conduct and contribution guidelines live in
  the pipeline repository as the policy requires, and the site points
  to them.
- Open formats and indexability are met by Markdown sources on a
  crawlable static site.

## Toolchain

Markdown sources through the Sphinx documentation generator with the
MyST parser and the ABlog extension, built and hosted on Read the Docs
under a project of its own (`roman-rapid.readthedocs.io`), owned by a
project role account, pull-request previews enabled. Versions are
pinned exactly, transitive dependencies included, and reviewed at each
upgrade. The site build fails on warnings; the pull-request check also
fails on a broken link and on a public-safety violation; a page that
does not pass does not merge. The design documents' status markers are
preserved in the System section.

## Open points

- **Alert registration route.** The Products alert page names the
  registration route once the live-alert interface defines it.
- **Pipeline documentation tree.** Which of its pages are re-derived
  into Science and Products, and which are not carried, is decided
  page by page at the re-derivation; the tree's removal from the
  pipeline repository is sequenced by the repositories design.
- **Prose license.** The policy requires none for documentation text;
  whether the site declares one is undecided. Until it is, the site
  repository's license covers its configuration and scripts only.
