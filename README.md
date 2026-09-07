# rapid_docs

The public documentation site for RAPID (Roman Alerts Promptly from Image
Differencing), built with [Sphinx](https://www.sphinx-doc.org/), the
[MyST parser](https://myst-parser.readthedocs.io/), and
[ABlog](https://ablog.readthedocs.io/), hosted on Read the Docs.

Where every statement about RAPID lives, and what this site is, is the
documentation design: `system/documentation.md`.

## Building and checking locally

Every check that runs in CI runs locally first; nothing is pushed
unverified.

```
uv venv .venv --python 3.12
uv pip install --python .venv/bin/python -r requirements.txt
scripts/check-public-safety.sh
.venv/bin/sphinx-build -W --keep-going -b html . _build/html
.venv/bin/sphinx-build -b linkcheck . _build/linkcheck
scripts/acceptance.sh _build/html
```

## Hosting

Read the Docs project `roman-rapid`: https://roman-rapid.readthedocs.io/.
Every push to `main` builds `latest` through the repository's webhook;
pull requests get preview builds. The project is owned by a RAPID role
account, with individual maintainers added on top.

## Maintaining

- Sections hold pages only when they have content; no placeholders.
- A post is a file under `log/` with `blogpost`, `date`, `author` and
  `category` front matter; posts are never revised after publication.
- `system/` is the design corpus itself, edited here and nowhere else.
  A design change is a pull request against these pages; each page or
  section keeps its DRAFT or ADOPTED marker current. Open design
  questions are issues in the repository they concern (the pipeline
  repository for code, science and interfaces; the infrastructure
  repository for hosting, fleet and CI); a page may list its open
  points briefly, and the discussion lives in the issue.
- Dependencies are pinned exactly in `requirements.in` and resolved to
  `requirements.txt` with `uv pip compile requirements.in -o
  requirements.txt --python-version 3.12 --generate-hashes`.

## Contributing

Pull requests are welcome; the checks above must pass. The pipeline
repository's [CONTRIBUTING](https://github.com/Caltech-IPAC/rapid/blob/main/CONTRIBUTING.md)
and [CODE_OF_CONDUCT](https://github.com/Caltech-IPAC/rapid/blob/main/CODE_OF_CONDUCT.md)
apply here too.

## License

The configuration, scripts, and templates in this repository are licensed
under the BSD 3-Clause License (see `LICENSE`). The documentation text is
licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
