---
blogpost: true
date: 2026-11-08
author: licence-audit run
category: log
---

# The rapid repository's licences, component by component, and the purge set for the switch to `rebuild`

The public `rapid` repository is labelled BSD 3-Clause (its `LICENSE`,
copyright California Institute of Technology), and everything in it was
assumed to be under that label. This post reads every component the
label covers, `c/src/*`, `c/common/*`, `modules/*` and `cdf/*`, plus the
locked Python environment the pipeline image runs on, and records what
each one actually says about its own licence. It was read on `rebuild` at
`5c93ca51` (2026-11-08).

Two components could not be redistributed under the label. Numerical
Recipes' `select`, the k-th-smallest routine inside `bkgest`, which every
difference job runs, was rewritten from Hoare's quickselect in rapid
PR 551, and `bkgest` writes byte-equal images before and after. GPC, the
polygon clipper vendored in `computeOverlapArea`, is free for
non-commercial use only; the rebuild never calls it, so it goes in the
purge set. Three components need a licence statement from their authors:
`awaicgen`, ZOGY's `py_zogy.py` and the real/bogus classifier
`modules/rubrat`. Everything else is fine as it stands or leaves the
repository at the switch for a reason other than its licence.

Nothing was deleted. The purge and the slimming happen when `rebuild`
becomes the team's branch; the purge set at the end of this post is the
list that switch executes.

## How to read the table

Each row gives the licence as the component states it, as an SPDX
identifier: from its own `LICENSE` or `COPYING`, its file headers or
its tarball. `NOASSERTION` means the component states no licence;
`LicenseRef-…` names a real licence text that SPDX does not list.
"Runs in `rebuild`" names the call site in `rapidpipe`, or the base-image
RPM a tool comes from, or says neither. "Ships in" is where the bytes
go: the public repository, an RPM built by `rapid_systems`, the
pipeline image. The finding is one of three: fine, needs a licence
statement, or purge on the switch, each with its reason.

The C tools never enter the image from this repository: the image's
`build.sh` leaves `c/` out, and the tools come from `rapid_systems`' RPMs,
each built from its own upstream source. The two exceptions are
`rapid-cmodules`, built from this repository's `c/src` and
`c/common/{nan,numericalrecipes}` at a pinned commit, and `rapid-awaicgen`,
built from an `awaicgen` tarball in this repository at its own pinned
commit.

## `c/src`: the in-house tools

All eight are RAPID's own code, written at Caltech (Russ Laher), with
copyright headers but no licence grant of their own; the repository's
BSD 3-Clause, from the same copyright holder, is their licence. All eight
are built into the `rapid-cmodules` RPM; only `bkgest` is run by the
rebuild.

| Component | Licence, as stated | Runs in `rebuild` | Ships in | Finding |
|---|---|---|---|---|
| `bkgest` | `NOASSERTION` in its files; the repository's BSD-3-Clause | yes: `science/difference/background.py`, on the science image and the resampled reference, from `rapid-cmodules` | repository, `rapid-cmodules`, image | fine, once rapid PR 551 removed Numerical Recipes' `select` from the library it links (below) |
| `computeOverlapArea` with `gpc.c`, `gpc.h` | GPC 2.32: `LicenseRef-GPC-non-commercial` ("free for non-commercial use … You may not use this software, in whole or in part, in support of any commercial product without the express consent of the author"); `computeOverlapArea.c` itself `NOASSERTION`, Caltech | no call site | repository, `rapid-cmodules`, image | purge on the switch: the non-commercial clause cannot sit under a BSD label. The file's own comment says GPC carries no licensing restrictions, citing Wikipedia; GPC's header says otherwise |
| `cforcepsfaper` | `NOASSERTION`, "(c) 2026, All Rights Reserved", Caltech; taken from ZTF's repository | no call site | repository, `rapid-cmodules`, image | purge on the switch: only `dev` uses it |
| `generateSmoothLampPattern`, `hdrupdate`, `imheaders`, `makeTestFitsFile`, `verifyHduSums` | `NOASSERTION`, Caltech | no call site | repository, `rapid-cmodules`, image | purge on the switch: only `dev` uses them |

## `c/common`: the two RAPID libraries and the vendored tarballs

| Component | Licence, as stated | Runs in `rebuild` | Ships in | Finding |
|---|---|---|---|---|
| `nan` | `NOASSERTION`, RAPID-authored | linked into `bkgest` | repository, `rapid-cmodules` | fine |
| `numericalrecipes` | `NOASSERTION`, RAPID-authored (`$Id` lines, laher, 2010 to 2012) | linked into `bkgest`, `cforcepsfaper`, `generateSmoothLampPattern` | repository, `rapid-cmodules` | `selectkthvalue.c` followed Numerical Recipes' `select`: replaced in rapid PR 551. Every other file is fine (the verdicts below) |
| `awaicgen` (`awaicgen-5.2.tar`, `awaicgen-5.3.tar`, `awaicgeneric_russ_tested.tar`, which is 5.4) | `NOASSERTION`: Caltech copyright in `libtwoplane/two_plane.[ch]`, Frank Masci named as author, no licence text; the RPM records `LicenseRef-RAPID-internal` | yes: the reference stage's coadd (`science/reference/awaicgen.py`, `stages/reference.py`), from `rapid-awaicgen` | repository, `rapid-awaicgen`, image | needs a licence statement from IPAC (the open item licence-statements). The three tarballs at the tip also purge on the switch: `rapid-awaicgen` reads `awaicgen-5.4.tar` from its own pinned commit, never from the tip, and 5.3 carries prebuilt objects and an executable |
| CCfits 2.6 | `LicenseRef-CCfits-NASA` (`License.txt`) | no (no rebuild code links CCfits) | repository | purge on the switch: `rapid-ccfits` fetches upstream |
| ATLAS 3.10.3, LAPACK 3.12.0 | BSD-3-Clause (ATLAS's header, LAPACK's `LICENSE`) | no: `dev`'s laptop build only | repository | purge on the switch: only `dev` uses them |
| CFITSIO 4.3.1 | `LicenseRef-CFITSIO-NASA` (`License.txt`) | the library runs, from `rapid-cfitsio` (4.6.4, upstream); this tarball does not | repository | purge on the switch: the RPM fetches upstream |
| FFTW 3.3.10 | GPL-2.0-or-later (`COPYRIGHT`, `COPYING`) | as a library, from `rapid-fftwf` (upstream); this tarball does not | repository | purge on the switch: the RPM fetches upstream |
| fitsverify 4.22, with its `Makefile` | `LicenseRef-fitsverify-NASA` (`License.txt`) | no call site | repository | purge on the switch: `rapid-fitsverify` fetches upstream |
| GSL 2.5 | GPL-3.0-or-later (`COPYING`, `README`) | as a library, from `rapid-gsl` (2.8, upstream); this tarball does not | repository | purge on the switch: the RPM fetches upstream |
| SExtractor 2.25.0 and 2.28.2, `configure_hacked` | GPL-3.0-or-later (`COPYRIGHT`); bundled levmar GPL, bundled WCS LGPL; `configure_hacked` is an Autoconf script under the FSF's unlimited permission | `sex` runs, from `rapid-sextractor` (2.29.0, upstream); these tarballs do not | repository | purge on the switch: the RPM fetches upstream |
| SWarp 2.41.5 | GPL-3.0-or-later (`COPYRIGHT`) | `swarp` runs, from `rapid-swarp` (upstream); this tarball does not | repository | purge on the switch: the RPM fetches upstream |
| WCSLIB 8.2.2 | LGPL-3.0-or-later (`README`, `COPYING.LESSER`) | as a library, from `rapid-wcslib` (8.9, upstream); this tarball does not | repository | purge on the switch: the RPM fetches upstream |
| WCSTools 3.9.7 | GPL-2.0-or-later (the programs), LGPL-2.1 (`libwcs/COPYING`) | no call site | repository | purge on the switch: `rapid-wcstools` fetches upstream |

The fifteen tarballs come to 129 MB. The twelve third-party ones each carry their own licence text,
which redistribution of the source allows; they leave because nothing
on `rebuild` reads them, not because of their licences. `c/builds/`,
`dev`'s build scripts that the per-directory `Makefile`s include, goes
with them: `rapid-cmodules` compiles with its own lines.

The rest of `numericalrecipes`, read for any other routine derived from
Numerical Recipes:

| File | Verdict |
|---|---|
| `selectkthvalue.c` | Numerical Recipes' `select` in structure: replaced in rapid PR 551 |
| `swapvaluesinarray.c` | a three-line swap; not derived |
| `computeaverage.c`, `computesum.c`, `computeweightedsum.c` | one-loop sums; not derived |
| `computestddev.c` | the corrected two-pass variance (Chan, Golub and LeVeque, 1983) in a plain loop, with RAPID's own `n == 1` branch; the formula is published, the expression is not derived |
| `computeskew.c`, `computekurtosis.c`, `computejarquebera.c` | textbook moment formulas, each its own function with RAPID's NaN guard; not derived |
| `computepercentile.c` | linear interpolation between two order statistics; RAPID's |
| `computemedian.c`, `computescale.c`, `computeclippedmean.c` | RAPID's wrappers: copy, percentiles, sigma clip |

## `modules` and `cdf`

| Component | Licence, as stated | Runs in `rebuild` | Ships in | Finding |
|---|---|---|---|---|
| `modules/zogy/v21Aug2018/py_zogy.py` | `NOASSERTION`: no header licence; initials SBC and FJM (2016, 2017) and RML (2018), after Zackay, Ofek and Gal-Yam (2016) | yes: the diagnostic ZOGY difference (`science/difference/zogy.py`) | repository, image | needs a licence statement from IPAC (licence-statements) |
| `modules/sfft/sfft_rapid_crowded.py` | `NOASSERTION` in the file; RAPID's (Jacob Jencson, Russ Laher), so the repository's BSD-3-Clause; imports the `sfft` package, MIT | yes: the published differencer (`science/difference/sfft.py`) | repository, image | fine |
| `modules/sfft/sfft_rapid.py` | as above | no: nothing references it | repository, image | purge on the switch: `dev`'s uncrowded script, replaced by the crowded one |
| `modules/rubrat` | `NOASSERTION`: `PROVENANCE.md` says it was copied from RuBR-AT (Aayush Kuloor) at `3e665de` and is maintained in RAPID since; no licence file, and RuBR-AT's repository is not publicly reachable (2026-11-08), so its licence is unknown | yes: the real/bogus score (`science/difference/realbogus.py` imports it) | repository, image | needs a licence statement from RuBR-AT's author; this one is not yet in licence-statements |
| `cdf/rapidSex*StarGalaxyClassifier.nnw` (4) and `cdf/rapidSex{Sci,Ref,Diff,GainMatch}ImageFilter.conv` (4) | byte-identical to SExtractor 2.28.2's `config/default.nnw` and `config/default.conv`: SExtractor's GPL-3.0-or-later | yes: every SExtractor run | repository, image | needs a licence statement the repository can write itself: a third-party notice naming SExtractor and its licence. The repository has no notice file today |
| `cdf/rapidSexDiffImageSfftFilter.conv`, `cdf/rapidSexParams*.inp` (4), `cdf/infobitsref.txt` | RAPID's, the repository's BSD-3-Clause | yes | repository, image | fine |
| `cdf/awsBatchSubmitJobs_launchSingleSciencePipeline.ini`, `cdf/generateInjectionCatalogForField.ini` | RAPID's | no: `dev`'s configuration, named only as the source `foundation-thin.toml` was ported from | repository, image | purge on the switch: only `dev` uses them |
| `cdf/romantessellation_nside10.fits` | `NOASSERTION`: no provenance cards | no reader | repository, image | purge on the switch: nothing reads it |

## The Python environment

The image's Python environment is `rapid_systems`' `rapid-python` RPM,
locked in `rpms/rapid-python/sources/` (23 conda packages and 261 pip
packages, Python 3.14.10). It ships in the RPM and the image, never in
this repository, so none of it bears on the repository's label. The
packages whose licences are not permissive:

| Package | Version | Licence, as recorded in its metadata | Imported by `rapidpipe` |
|---|---|---|---|
| `healpy` | 1.20.1 | GPL-2.0-only | yes (`products/spatial.py`, `science/load/catalogs.py`, `science/catalogs/readers.py`) |
| `psycopg2-binary` | 2.9.13 | LGPL with exceptions | yes (`db/connection.py`) |
| `fitsio` | 1.4.2 | GPL-2.0-or-later | no |
| `healsparse` | 1.16.0 | GPL-3.0-or-later (classifier) | no |
| `hpgeom` | 1.7.1 | GPL-3.0-or-later | no |
| `sep` | 1.4.1 | LGPL-3.0-or-later | no |
| `fastremap` | 1.21.0 | LGPL-3.0 | no |
| `certifi`, `fqdn` | 2026.10.23, 1.6.0 | MPL-2.0 | no |
| `orjson`, `tqdm` | 3.13.0, 4.70.1 | MPL-2.0 with Apache-2.0 or MIT | no |
| `readline`, `ld_impl_linux-64` (conda) | 8.3, 2.46.1 | GPL-3.0-only | the interpreter's |
| `libgcc`, `libgomp` (conda) | 16.2.0 | GPL-3.0-only WITH GCC-exception-3.1 | the runtime's |

Each package carries its own licence text in the environment. None is
non-commercial or proprietary, and two packages recorded as "UNKNOWN"
(`isoduration`, `ptyprocess`) ship ISC licence files. Finding: fine for
the repository. The image combines `rapidpipe` with GPL packages it
imports (`healpy`); that is a question about distributing the image, which
this audit does not settle.

## The replacement of Numerical Recipes' `select`

`selectkthvalue(k, data, n)` returns the k-th smallest of `n` values and
sits under `computepercentile`, which `bkgest`'s sigma-clipped means and
scales call for every grid window. Its old body followed Numerical
Recipes' `select`, whose licence forbids redistributing the source. Rapid
PR 551 replaces it with Hoare's quickselect: Hoare's two-index partition
about a median-of-three pivot value, keeping only the side that holds k,
written from the algorithm's public description. The signature and the
result are unchanged; the order the array is left in differs, and every
caller passes a scratch copy.

`bkgest` was built from the commit before the change and from the
branch with the `rapid-cmodules` spec's compile lines, and both were run
on run 12's difference job 1895, its science image and its resampled
reference, with `background.py`'s arguments. Both output images are
byte-equal in their data arrays, and their headers differ only in
`DATE`. The rewritten routine is also faster: `bkgest` takes 1.9 s per
image against 2.9 s. PR 551 carries the tables, and `rapid-cmodules` 1.0.0-8
(rapid_systems PR 499) ships it.

## The purge set

What the switch to `rebuild` removes from the repository's tip, each
with its reason. History keeps everything: the `rapid-awaicgen` and
`rapid-cmodules` pins read their sources from pinned commits.

- `c/builds/`: `dev`'s build scripts; `rapid-cmodules` compiles with its own lines.
- `c/common/CCfits/`, `c/common/cfitsio/`, `c/common/fftw/`, `c/common/fitsverify/`, `c/common/gsl/`, `c/common/sextractor/`, `c/common/swarp/`, `c/common/wcslib/`, `c/common/wcstools/`: their RPMs fetch upstream sources themselves.
- `c/common/atlas/`: `dev`'s laptop build only; no RPM.
- `c/common/awaicgen/`: `rapid-awaicgen` reads 5.4 from its pinned commit, not the tip; 5.2 and 5.3 are `dev`'s versions, and 5.3 carries prebuilt objects and an executable. The licence statement is still needed for the RPM.
- `c/common/nan/Makefile`, `c/common/numericalrecipes/Makefile`, `c/common/numericalrecipes/test.c`, `c/src/bkgest/Makefile`, `c/src/bkgest/readme.txt`: `dev`'s build files, which include `c/builds/definitions.mk`, and a test driver and build notes nothing runs.
- `c/src/computeOverlapArea/`: GPC's non-commercial clause; no call site.
- `c/src/cforcepsfaper/`, `c/src/generateSmoothLampPattern/`, `c/src/hdrupdate/`, `c/src/imheaders/`, `c/src/makeTestFitsFile/`, `c/src/verifyHduSums/`: no call site in the rebuild; only `dev` uses them.
- `modules/sfft/sfft_rapid.py`: nothing references it.
- `cdf/awsBatchSubmitJobs_launchSingleSciencePipeline.ini`, `cdf/generateInjectionCatalogForField.ini`: `dev`'s configuration.
- `cdf/romantessellation_nside10.fits`: nothing reads it.
- In `rapid_systems`, with the first `rapid-cmodules` pin bump after the purge: `rpms/rapid-cmodules/rapid-cmodules.spec` builds, installs and lists `bkgest` alone, and `rpms/build-package.sh`'s `rapid-cmodules` arm archives `c/src/bkgest` in place of `c/src`, with the Release bumped. Until then the RPM keeps shipping `computeOverlapArea`, GPC included, from its pinned commit.

That is 28 paths in `rapid` and one edit in `rapid_systems`.

## What remains

- Licence statements from IPAC for `awaicgen` and `py_zogy.py`, and from
  RuBR-AT's author for `modules/rubrat`.
- A third-party notice in the repository for SExtractor's eight
  configuration files.
- The purge itself, at the switch.
