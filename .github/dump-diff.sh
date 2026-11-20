#!/bin/sh
set -eu
if [ $# -ne 2 ]; then
  echo "usage: dump-diff.sh <folder> <folder>" >&2
  exit 2
fi
{
  (cd "$1" && find . -type f)
  (cd "$2" && find . -type f)
} | sed 's|^\./||' | sort -u | while read -r file; do
  if ! cmp -s "$1/$file" "$2/$file"; then
    echo "$file"
  fi
done
