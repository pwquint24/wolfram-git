#!/usr/bin/env bash
# wolfram-git-md-to-org.sh: Convert a Markdown companion file to Org mode and
# prepend the sci-wolfram prologue source block.

set -euo pipefail

md_file="${1:-}"
if [ -z "$md_file" ] || [ ! -f "$md_file" ]; then
  echo "Usage: wolfram-git-md-to-org.sh <file.md>" >&2
  exit 1
fi

if ! command -v pandoc >/dev/null 2>&1; then
  echo "Error: pandoc is required to convert Markdown to Org mode." >&2
  exit 1
fi

org_file="${md_file%.md}.org"

{
  printf '%s\n' \
    '#+name: import-sci-wolfram-image-package' \
    '#+begin_src wolfram' \
    '(* Please run "M-x sci-wolfram-import-package RET display image RET" from this line *)' \
    '#+end_src' \
    ''
  pandoc -f markdown-auto_identifiers -t org "$md_file"
} > "$org_file"

echo "$org_file"
