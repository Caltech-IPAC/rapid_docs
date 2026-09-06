#!/usr/bin/env bash
# Verify the built site against the documentation-site acceptance
# checklist. Run after `sphinx-build -b html . <outdir>`. Portable to
# macOS bash 3.2 and Ubuntu; grep -E only, no GNU-only flags.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

html="${1:-_build/html}"

fail=0
check() {
  # $1 = description, $2 = shell condition already evaluated (0/1)
  if [ "$2" -eq 0 ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    fail=1
  fi
}

if [ ! -d "$html" ]; then
  echo "FAIL: $html does not exist — run the html build first"
  exit 1
fi

# 1. Navigation: index links to system/project/log.
r1a=0; grep -q 'href="system/index.html"' "$html/index.html" || r1a=1
r1b=0; grep -q 'href="project/index.html"' "$html/index.html" || r1b=1
r1c=0; grep -q 'href="log/index.html"' "$html/index.html" || r1c=1
r1=1
if [ "$r1a" -eq 0 ] && [ "$r1b" -eq 0 ] && [ "$r1c" -eq 0 ]; then r1=0; fi
check "index.html links to system, project, log" "$r1"

# 2. system/index.html links to all design pages: derive the list from
#    system/*.md excluding index.md, not a hard-coded string, so a new
#    or removed page is caught automatically.
docs=""
while IFS= read -r -d '' f; do
  b="$(basename "$f" .md)"
  if [ "$b" = "index" ]; then continue; fi
  docs="$docs $b"
done < <(find system -maxdepth 1 -name '*.md' -type f -print0)

r2=0
for d in $docs; do
  grep -q "href=\"$d.html\"" "$html/system/index.html" || { r2=1; echo "  missing link to $d.html"; }
done
check "system/index.html links to all design pages" "$r2"

# 3. Every system page except index has a bold Status line.
r3=0
for d in $docs; do
  grep -q '<strong>Status:' "$html/system/$d.html" || { r3=1; echo "  missing <strong>Status: in $d.html"; }
done
check "Status lines render as <strong>Status: ...</strong>" "$r3"

# 4. Source available beside every built page: _sources/<docname>.md.txt
#    exists, and system/architecture.html links to its own source file
#    (the source link proper, not the edit-this-page button).
r4=0
while IFS= read -r -d '' pagemd; do
  docname="${pagemd#./}"
  docname="${docname%.md}"
  # Only pages actually built (Sphinx excludes README.md via
  # exclude_patterns, so it never gets a page or a _sources copy).
  [ -f "$html/$docname.html" ] || continue
  [ -f "$html/_sources/$docname.md.txt" ] || { r4=1; echo "  missing _sources/$docname.md.txt"; }
done < <(find . \
  \( -path ./_build -o -path ./.venv \) -prune -o \
  -name '*.md' -type f -print0)

grep -o 'href="[^"]*"' "$html/system/architecture.html" \
  | grep -q '_sources/system/architecture\.md\.txt"$' || {
    r4=1
    echo "  system/architecture.html does not link to its own _sources/system/architecture.md.txt"
  }
check "every built page has a _sources/<docname>.md.txt and architecture links its own source" "$r4"

# 5. llms.txt / llms-full.txt exist, and every link target in llms.txt
#    resolves to an existing file under the output dir.
r5=0
[ -f "$html/llms.txt" ] || { r5=1; echo "  missing llms.txt"; }
[ -f "$html/llms-full.txt" ] || { r5=1; echo "  missing llms-full.txt"; }
if [ -f "$html/llms.txt" ]; then
  targets="$(grep -oE '\]\([^)]+\)' "$html/llms.txt" | sed -E 's/^\]\(//; s/\)$//')"
  while IFS= read -r t; do
    if [ -z "$t" ]; then continue; fi
    case "$t" in
      http://*|https://*) continue ;;
    esac
    [ -f "$html/$t" ] || { r5=1; echo "  llms.txt link target missing: $t"; }
  done <<EOF_TARGETS
$targets
EOF_TARGETS
fi
check "llms.txt and llms-full.txt exist and llms.txt links resolve" "$r5"

# 6. Blog posts: every log/*.md with `blogpost: true` (excluding
#    log/index.md) has a built page, linked from log/archive.html; the
#    log category page exists. atom.xml is reported as a note only.
r6=0
while IFS= read -r -d '' postmd; do
  if [ "$postmd" = "./log/index.md" ]; then continue; fi
  grep -q '^blogpost: *true' "$postmd" || continue
  # A post carries date, author and category in its front matter.
  for field in date author category; do
    grep -qE "^$field: *[^ ]" "$postmd" || { r6=1; echo "  $postmd lacks front-matter field: $field"; }
  done
  docname="${postmd#./}"
  docname="${docname%.md}"
  pagehtml="$html/$docname.html"
  [ -f "$pagehtml" ] || { r6=1; echo "  missing built page for $postmd: $docname.html"; }
  rel="$(basename "$docname").html"
  if [ -f "$html/log/archive.html" ]; then
    grep -q "href=\"$rel\"" "$html/log/archive.html" || { r6=1; echo "  $docname.html not linked from log/archive.html"; }
  fi
done < <(find log -maxdepth 1 -name '*.md' -type f -print0)

[ -f "$html/log/archive.html" ] || { r6=1; echo "  missing log/archive.html"; }
[ -f "$html/log/archive/category/log.html" ] || { r6=1; echo "  missing log/archive/category/log.html"; }
check "blog posts built and linked from log archive; log category page exists" "$r6"

if find "$html" -name 'atom.xml' 2>/dev/null | grep -q .; then
  echo "  NOTE: atom.xml present"
else
  echo "  NOTE: atom.xml not present"
fi

# 7. README.md did not become a page.
r7=0
if [ -f "$html/README.html" ]; then r7=1; fi
check "README.html was not built" "$r7"

exit "$fail"
