#!/usr/bin/env bash
set -euo pipefail

opa=("$@")
[ ${#opa[@]} -eq 0 ] && opa=(opa)

rules=$(git ls-files '*_test.rego' | while read -r f; do
  pkg=$(sed -n 's/^package //p' "$f" | head -1)
  grep -oE '^test_[A-Za-z0-9_]+' "$f" | sed "s/^/data.$pkg./"
done)
tests=$(sort -u <<<"$rules")
repeated=$(sort <<<"$rules" | uniq -d)
if [ -n "$repeated" ]; then
  echo "Two tests share a name, so -r can't pick out each of them:"
  echo "$repeated"
  exit 1
fi

total=$(wc -l <<<"$rules" | tr -d ' ')
ran=0
while read -r part; do
  pattern="^($(tr ' ' '\n' <<<"$part" | sed 's/\./\\./g' | paste -sd'|' -))\$"
  out=$("${opa[@]}" test . --ignore .github --target wasm --timeout 120s -r "$pattern") || { echo "$out"; exit 1; }
  echo "$out"
  ran=$((ran + $(sed -nE 's/^PASS: ([0-9]+)\/[0-9]+$/\1/p' <<<"$out")))
done < <(xargs -n 150 <<<"$tests")

echo "Ran $ran of $total tests compiled to Wasm"
[ "$ran" -eq "$total" ]
