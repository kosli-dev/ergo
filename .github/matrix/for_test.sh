#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

.github/build-ergo.sh > /dev/null
python3 .github/matrix/for.py "$dir/pairs.json" > /dev/null

echo "every pair for.py writes is read by ergo.rego, and by the Rust engine when ergo is on the PATH"
python3 - "$dir/pairs.json" <<'PY'
import os
import shutil
import sys

sys.path.insert(0, "spec")
import sweep

pairs = sweep.load_pairs(sys.argv[1])
for i, pair in enumerate(pairs):
    pair["id"] = str(i)
sweep.write_cells(pairs)
ids = [pair["id"] for pair in pairs]
engines = {"ergo.rego": sweep.run_rego("opa", ids)}
if shutil.which("ergo"):
    engines["rust"] = sweep.run_rust("sh -s", ids)[1]
bad = []
for name, reports in engines.items():
    for pair, report in zip(pairs, reports):
        if "error" in report or sweep.written_wrong(report):
            bad.append(f"{name}: {pair['name']}")
if bad:
    print(f"{len(bad)} pairs are written wrong or fail to run, like:", file=sys.stderr)
    print("\n".join(bad[:5]), file=sys.stderr)
    sys.exit(1)
PY
