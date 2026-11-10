#!/usr/bin/env bash
set -euo pipefail

opa=("$@")
[ ${#opa[@]} -eq 0 ] && opa=(opa)
size=${BATCH_SIZE:-50}

root=$PWD
tests=$(.github/tests.sh "${opa[@]}")
total=$(wc -l <<<"$tests" | tr -d ' ')
batches=$(((total + size - 1) / size))
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
git ls-files | grep -v -E '^(\.github|site|packages)/' | tar -cf - -T - | tar -xf - -C "$dir"

plain='} else := _run(doc, policy, _read(policy), params)'
if [ "$(grep -cxF "$plain" "$dir/engines/rego/ergo.rego")" -ne 1 ]; then
  echo "ergo.rego no longer has the line this script changes: $plain"
  exit 1
fi
python3 - "$dir/engines/rego/ergo.rego" "$plain" <<'PY'
import sys
path, plain = sys.argv[1], sys.argv[2]
text = open(path).read()
compiled = "} else := _run(doc, c.policy, _from_compiled(c), params) if {\n\tc := _compiled(compile(policy))\n" + plain + "\n"
open(path, "w").write(text.replace(plain + "\n", compiled))
PY

cd "$dir"
ran=0
for batch in $(seq 0 $((batches - 1))); do
  pattern=$(awk -v b="$batches" -v k="$batch" '(NR - 1) % b == k' <<<"$tests" | "$root/.github/test-pattern.sh")
  out=$("${opa[@]}" test engines/rego spec:spec examples:examples --timeout 120s -r "$pattern") || { echo "$out"; exit 1; }
  echo "$out"
  ran=$((ran + $(sed -nE 's/^PASS: ([0-9]+)\/[0-9]+$/\1/p' <<<"$out")))
done

echo "Ran $ran of $total tests compiled"
[ "$ran" -eq "$total" ]
