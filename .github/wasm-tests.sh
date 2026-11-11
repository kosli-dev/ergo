#!/usr/bin/env bash
set -euo pipefail

opa=("$@")
[ ${#opa[@]} -eq 0 ] && opa=(opa)

.github/build-ergo.sh
tests=$(.github/tests.sh "${opa[@]}")
total=$(wc -l <<<"$tests" | tr -d ' ')
batches=$(((total + 49) / 50))
ran=0
for batch in $(seq 0 $((batches - 1))); do
  pattern=$(awk -v b="$batches" -v k="$batch" '(NR - 1) % b == k' <<<"$tests" | .github/test-pattern.sh)
  out=$("${opa[@]}" test engines/rego dist spec:spec examples:examples --ignore src --target wasm --timeout 120s -r "$pattern") || { echo "$out"; exit 1; }
  echo "$out"
  ran=$((ran + $(sed -nE 's/^PASS: ([0-9]+)\/[0-9]+$/\1/p' <<<"$out")))
done

echo "Ran $ran of $total tests compiled to Wasm"
[ "$ran" -eq "$total" ]
