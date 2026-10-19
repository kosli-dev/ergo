#!/usr/bin/env bash
set -euo pipefail

opa=("$@")
[ ${#opa[@]} -eq 0 ] && opa=(opa)
part=${PART:-1}
parts=${PARTS:-1}

tests=$(git ls-files '*.rego' | grep -v '^\.github/' | while read -r f; do
  "${opa[@]}" parse "$f" --format json | jq -r '(.package.path[1:] | map(.value) | join(".")) as $p | .rules[]? | .head.ref[0].value | select(startswith("test_")) | "data.\($p).\(.)"'
done | sort)
if [ -z "$tests" ]; then
  echo "found no tests" >&2
  exit 1
fi
repeated=$(uniq -d <<<"$tests")
if [ -n "$repeated" ]; then
  echo "Two tests share a name, so -r can't pick out each of them:" >&2
  echo "$repeated" >&2
  exit 1
fi
uniq <<<"$tests" | awk -v part="$part" -v parts="$parts" '(NR - 1) % parts == part - 1'
