#!/bin/sh
set -eu
[ $# -eq 1 ] || { echo "usage: .github/pages-source.sh <tested commit>" >&2; exit 2; }
printf '%s\n' "$1" | grep -Eq '^[0-9a-f]{40}$' || { echo "The tested commit must be a full SHA" >&2; exit 1; }
git merge-base --is-ancestor "$1" refs/remotes/origin/main || { echo "The tested commit is not part of main" >&2; exit 1; }
git checkout --detach "$1"
