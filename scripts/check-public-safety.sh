#!/usr/bin/env bash
# Limited mechanical guard for operational identifiers and internal
# references that must not appear in the public documentation source.
# This is a pattern scan only: it does not judge names or prose — those
# are review matters, not this script's job. Portable to macOS bash 3.2
# and Ubuntu; grep -E only, no GNU-only flags. Uses temp files to
# accumulate violations so the exit status survives shell/subshell
# differences, and filename-safe NUL-delimited traversal so paths with
# spaces or newlines can't break the scan.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

hitfile="$(mktemp)"
grepfile="$(mktemp)"
trap 'rm -f "$hitfile" "$grepfile"' EXIT

# Patterns forbidden everywhere. Word boundaries expressed as
# (^|[^A-Za-z0-9-]) / ([^A-Za-z0-9-]|$) rather than \b for portability
# (verified \b IS supported by grep -E on this Mac's BSD grep, but the
# explicit-class form needs no such verification on any other grep).
patterns='(^|[^0-9])[0-9]{12}([^0-9]|$)
(^|[^A-Za-z0-9-])i-[0-9a-f]{8,}([^A-Za-z0-9-]|$)
(^|[^A-Za-z0-9-])fs-[0-9a-f]{8,}([^A-Za-z0-9-]|$)
(^|[^A-Za-z0-9-])sg-[0-9a-f]{8,}([^A-Za-z0-9-]|$)
(^|[^A-Za-z0-9-])vpc-[0-9a-f]{8,}([^A-Za-z0-9-]|$)
(^|[^A-Za-z0-9-])subnet-[0-9a-f]{8,}([^A-Za-z0-9-]|$)
arn:aws
/Users/
~/Vault
scratchpad
register §
(^|[^A-Za-z0-9_])constitution([^A-Za-z0-9_]|$)
AKIA[0-9A-Z]{16}
-----BEGIN'

# Tracked text sources: every *.md (README.md included), conf.py,
# .readthedocs.yaml, workflow files — excluding _build, .venv,
# requirements.txt. NUL-delimited so filenames with spaces/newlines
# survive.
scan_failed=0
while IFS= read -r -d '' f; do
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    set +e
    grep -nE -- "$pat" "$f" > "$grepfile" 2>/dev/null
    rc=$?
    set -e
    if [ "$rc" -gt 1 ]; then
      scan_failed=1
    elif [ "$rc" -eq 0 ]; then
      sed "s#^#$f:#" "$grepfile" >> "$hitfile"
    fi
  done <<EOF_PATTERNS
$patterns
EOF_PATTERNS
done < <(find . \
  \( -path ./_build -o -path ./.venv \) -prune -o \
  \( -name '*.md' -o -name 'conf.py' -o -name '.readthedocs.yaml' \
     -o -path './.github/workflows/*.yml' -o -path './.github/workflows/*.yaml' \) \
  -not -name 'requirements.txt' -type f -print0)

if [ "$scan_failed" -ne 0 ]; then
  echo "check-public-safety: SCAN FAILED (grep error), treating as violation"
  exit 1
fi

if [ -s "$hitfile" ]; then
  cat "$hitfile"
  echo "check-public-safety: FAILED, violations listed above"
  exit 1
fi

echo "check-public-safety: OK, no violations found"
