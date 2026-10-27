#!/bin/sh
set -eu
if [ $# -ne 3 ]; then
  echo "usage: .github/release-notes.sh CHANGELOG VERSION LINK_BASE" >&2
  exit 2
fi
notes=$(awk -v h="## $2" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$1")
if ! printf '%s\n' "$notes" | grep -q '[^[:space:]]'; then
  echo "$1 has nothing under \"## $2\", so there are no release notes" >&2
  exit 1
fi
printf '%s\n' "$notes" | sed -E "s#\]\(([A-Za-z0-9_./-]+\.md)(\#[^)]*)?\)#]($3\1\2)#g"
