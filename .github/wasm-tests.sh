#!/usr/bin/env bash
set -euo pipefail

opa=("$@")
[ ${#opa[@]} -eq 0 ] && opa=(opa)

tests=$(.github/tests.sh "${opa[@]}")
total=$(wc -l <<<"$tests" | tr -d ' ')
ran=0
while read -r part; do
  pattern=$(tr ' ' '\n' <<<"$part" | .github/test-pattern.sh)
  out=$("${opa[@]}" test . --ignore .github --ignore packages --target wasm --timeout 120s -r "$pattern") || { echo "$out"; exit 1; }
  echo "$out"
  ran=$((ran + $(sed -nE 's/^PASS: ([0-9]+)\/[0-9]+$/\1/p' <<<"$out")))
done < <(xargs -n 150 <<<"$tests")

echo "Ran $ran of $total tests compiled to Wasm"
[ "$ran" -eq "$total" ]
