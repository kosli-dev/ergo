#!/usr/bin/env bash
set -euo pipefail

opa=("$@")
[ ${#opa[@]} -eq 0 ] && opa=(opa)

tests=$(git ls-files '*.rego' | grep -v '^\.github/' | while read -r f; do
  "${opa[@]}" parse "$f" --format json | jq -r '(.package.path[1:] | map(.value) | join(".")) as $p | .rules[]? | .head.ref[0].value | select(startswith("test_")) | "data.\($p).\(.)"'
done | sort)
if [ -z "$tests" ]; then
  echo "found no tests"
  exit 1
fi
repeated=$(uniq -d <<<"$tests")
if [ -n "$repeated" ]; then
  echo "Two tests share a name, so -r can't pick out each of them:"
  echo "$repeated"
  exit 1
fi
tests=$(uniq <<<"$tests")

shard=${SHARD:-0}
shards=${SHARDS:-1}
total=0
ran=0
batch=0
while read -r part; do
  batch=$((batch + 1))
  [ $(((batch - 1) % shards)) -eq "$shard" ] || continue
  total=$((total + $(wc -w <<<"$part")))
  pattern="^($(tr ' ' '\n' <<<"$part" | sed 's/\./\\./g' | paste -sd'|' -))\$"
  out=$("${opa[@]}" test . --ignore .github --target wasm --timeout 120s -r "$pattern") || { echo "$out"; exit 1; }
  echo "$out"
  ran=$((ran + $(sed -nE 's/^PASS: ([0-9]+)\/[0-9]+$/\1/p' <<<"$out")))
done < <(xargs -n 150 <<<"$tests")

echo "Ran $ran of $total tests compiled to Wasm"
[ "$ran" -eq "$total" ]
