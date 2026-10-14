#!/usr/bin/env bash
set -euo pipefail

opa=("$@")
[ ${#opa[@]} -eq 0 ] && opa=(opa)

tests=$("${opa[@]}" test . --ignore .github --timeout 120s --format json | jq -r '.[] | "\(.package).\(.name)"' || true)
if [ -z "$tests" ]; then
  echo "opa test found no tests"
  exit 1
fi
repeated=$(grep '#' <<<"$tests" || true)
if [ -n "$repeated" ]; then
  echo "Two tests share a name, so -r can't pick out each of them:"
  sed 's/#.*//' <<<"$repeated"
  exit 1
fi

total=$(wc -l <<<"$tests" | tr -d ' ')
ran=0
while read -r part; do
  pattern="^($(tr ' ' '\n' <<<"$part" | sed 's/\./\\./g' | paste -sd'|' -))\$"
  out=$("${opa[@]}" test . --ignore .github --target wasm --timeout 120s -r "$pattern") || { echo "$out"; exit 1; }
  echo "$out"
  ran=$((ran + $(sed -nE 's/^PASS: ([0-9]+)\/[0-9]+$/\1/p' <<<"$out")))
done < <(xargs -n 150 <<<"$tests")

echo "Ran $ran of $total tests compiled to Wasm"
[ "$ran" -eq "$total" ]
