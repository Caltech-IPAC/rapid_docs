# Day one

This page takes a new member of the team from an SMDC login to a merged
pull request and one epoch run on their own machine. It links the pages
that hold each step rather than repeating them. Three repositories are
involved:

| Repository | Holds | Visibility |
|---|---|---|
| [Caltech-IPAC/rapid](https://github.com/Caltech-IPAC/rapid/tree/rebuild) | the pipeline, on branch `rebuild` | public |
| [Caltech-IPAC/rapid_docs](https://github.com/Caltech-IPAC/rapid_docs) | this site | public |
| `IPAC-SW/rapid_systems` | the SMDC infrastructure, the `rapid` command and the team's access files | private, in the IPAC-SW organization |

## Your SMDC login

RAPID runs in an SMDC AWS account. Sign in to the
[SMDC AWS portal](http://aws.sciencecloud.nasa.gov/) and check that
`smdc-aws-roman-rapid` is listed. If it is not, email
support@smce.nasa.gov. This is the first step of `rapid_systems`'
README, Setup.

## The infrastructure checkout

`rapid_systems` is private and lives in a different GitHub organization,
`IPAC-SW`, from the pipeline and this site, which are under
`Caltech-IPAC`. You need membership of `IPAC-SW` before you can clone
it. An owner of that organization adds you.

```sh
git clone git@github.com:IPAC-SW/rapid_systems.git
```

Its README, Setup, then walks you through `RAPID_USER`, the `rapid`
command, SSH to your own workstation (a Personal EC2 on SMDC) and the
software on it. The managed Python environment on every RAPID host is
`/opt/rapid/conda/envs/rapid` (that README, Python environments). The
runbook's `$PY` is its `python3`.

## The pipeline checkout

The pipeline's default branch is `dev`, the pre-rebuild pipeline. The
rebuild and its quickstart exist only on `rebuild`, so clone that branch
by name:

```sh
git clone -b rebuild git@github.com:Caltech-IPAC/rapid.git
cd rapid
git config core.hooksPath .githooks     # the public-safety check, before your first push
```

## One epoch on your own machine

The README's
[Getting started](https://github.com/Caltech-IPAC/rapid/blob/rebuild/README.md#getting-started)
takes one HLWAS epoch through every stage, inside the pipeline image,
against a throwaway PostgreSQL 18. It takes about five minutes and needs
16 GB of memory. It needs two inputs, and the README says how to get
each one:

- **The pipeline image.** From any RAPID host, log in to the account's
  container registry and pull a `rapid-pipeline:rebuild-<sha>` image.
  The fleet's instance roles carry the pull grant (`rapid_systems`
  `cloudformation/rapid-ecr.yaml`).
- **The Gaia DR3 catalog.** The README gives the query that built the
  team's file. It runs inside the image against the public Gaia archive,
  so it needs no AWS access. The team's copy and its location are on
  [Datasets](../system/datasets.md#hlwas-r00342).

## Your first pull request

[Contributing to the pipeline](https://github.com/Caltech-IPAC/rapid/blob/rebuild/CONTRIBUTING.md)
holds the rule. Branch from `rebuild`, open the pull request to
`rebuild`, and merge once CI is green. A pull request names the page on
this site that it implements or corrects, and a page is corrected before
the code that disagrees with it. One review by a named maintainer will
be required once the team names one; until then, green CI and the
doc-first rule are the gate. Changes to this site follow
[Contributing](contributing).

## A night on Batch

The loop page's [Starting a night](../system/loop.md#starting-a-night)
is the recipe. A night runs against the team's database and the Batch
queue, from a checkout of `rebuild` on a RAPID host. The runbook's
Current procedure, in the pipeline repository's
[`docs/foundation-smdc-step.md`](https://github.com/Caltech-IPAC/rapid/blob/rebuild/docs/foundation-smdc-step.md#current-procedure),
holds the environment and the checks.

## What needs Project-Admin today

`Project-Admin` is the SMDC role for IAM-scope stacks. Operators hold
`Project-Power-User` (`rapid_systems` `docs/team-access-policy.md`).
Read from the tips of the three repositories on 2026-10-26:

| Step | Who can do it today |
|---|---|
| The SMDC login and the `smdc-aws-roman-rapid` account | SMDC support |
| Membership of `IPAC-SW` | an owner of the organization |
| One epoch locally, a pull request, CI | anyone with the two checkouts and a RAPID host |
| Building an image for a merged commit and registering its `rapid-rebuild` job-definition revision | `Project-Admin`: the release hook's change set carries `CAPABILITY_NAMED_IAM` (`rapid_systems` `cloudformation/release-hooks/`) |
| Submitting a night's jobs to Batch from your workstation | your workstation's instance role on the submitter roster (`rapid_systems` `docs/workstation-submission.md`), or the administrator profile the runbook names; adding a role to the roster is a stack deploy by `Project-Admin` |
| A schema statement on the team's database, or a fresh schema | the database host's `postgres`, by `Project-Admin` |

Open, and not promised here:

- **The submitter roster** holds one workstation role. Per-owner roles
  for every teammate's workstation are being added. Until they land, a
  night needs `Project-Admin`.
- **A second `Project-Admin`** is required by the access policy, and no
  one is designated yet.
- **The access question** for each member and tier is one of the team's
  [questions for its first week](../system/migration.md#questions-for-the-teams-first-week),
  as is who builds the next image.
