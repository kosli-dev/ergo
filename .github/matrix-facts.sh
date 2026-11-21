#!/bin/sh
set -eu
if [ $# -gt 2 ]; then
  echo "usage: matrix-facts.sh [NAME [BASE]]" >&2
  exit 2
fi
name=${1:-matrix-a}
base=${2:-origin/main}
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
if [ -z "${MATRIX_FACTS_RUST:-}" ] && [ ! -f "$root/.github/matrix/$name.py" ]; then
  echo "no generator called $name in .github/matrix" >&2
  exit 2
fi
work=$(mktemp -d)
tree=
cleanup() {
  /bin/rm -rf "$root/dist/sweep"
  if [ -n "$tree" ]; then
    git -C "$root" worktree remove --force "$tree" > /dev/null 2>&1 || true
  fi
  if [ "${KEEP_TARGETS:-}" = 1 ]; then
    echo "kept $work" >&2
  else
    /bin/rm -rf "$work"
  fi
}
trap cleanup EXIT
export MATRIX_FACTS_NAME=$name
export MATRIX_FACTS_BASE_NAME=$base

if [ -z "${MATRIX_FACTS_RUST:-}" ]; then
  ASDF_RUST_VERSION=$(sed -n 's/^channel = "\(.*\)"/\1/p' "$root/engines/rust/rust-toolchain.toml")
  export ASDF_RUST_VERSION
  if ! git -C "$root" rev-parse --verify --quiet "$base^{commit}" > /dev/null; then
    echo "cannot find BASE $base" >&2
    exit 1
  fi
  tree=$work/base
  git -C "$root" worktree add --detach "$tree" "$base" > /dev/null
  build() {
    find "$1/engines/rust" -name '*.rs' -exec touch {} +
    (cd "$1/engines/rust" && CARGO_TARGET_DIR=$2 ${MATRIX_FACTS_CARGO:-cargo} build -q -j 4 -p ergo-policy-cli) || {
      echo "the build failed on $3" >&2
      exit 1
    }
  }
  build "$tree" "${MATRIX_FACTS_BASE_TARGET:-$work/base-target}" "BASE $base"
  build "$root" "${MATRIX_FACTS_HEAD_TARGET:-$work/head-target}" "the working tree"
  export MATRIX_FACTS_BASE_BIN=${MATRIX_FACTS_BASE_TARGET:-$work/base-target}/debug
  export MATRIX_FACTS_HEAD_BIN=${MATRIX_FACTS_HEAD_TARGET:-$work/head-target}/debug
  export MATRIX_FACTS_BASE_TREE=$tree
  python3 "$root/.github/matrix/$name.py" "$work/pairs.json" > /dev/null 2>&1
  export MATRIX_FACTS_PAIRS=$work/pairs.json
fi

python3 - "$root" <<'PY'
import json
import os
import re
import subprocess
import sys

root = sys.argv[1]
sys.path.insert(0, os.path.join(root, "spec"))
import sweep

CAUSES = ["not_an_object", "ambiguous", "unusable", "absent", "null", "value"]


def read(path):
    with open(path) as handle:
        return json.load(handle)


def run_with_path(directory, ids):
    saved = os.environ["PATH"]
    os.environ["PATH"] = directory + os.pathsep + saved
    try:
        return sweep.run_rust("sh -s", ids)[1]
    finally:
        os.environ["PATH"] = saved


def verdicts(report):
    if "error" in report:
        return {"report": ("error",)}
    return {
        f"{key[0]}/{key[1]}": (bool(row.get("passed")), row.get("cause"))
        for key, row in sorted(sweep.rows(report).items())
    }


def show(verdict):
    if verdict is None:
        return "missing"
    if len(verdict) == 1:
        return verdict[0]
    return verdict[1] if verdict[1] else ("satisfied" if verdict[0] else "failed")


def lower(rust, rego):
    return (
        rust is not None
        and rego is not None
        and len(rust) == 2
        and len(rego) == 2
        and not rust[0]
        and not rego[0]
        and rust[1] in CAUSES
        and rego[1] in CAUSES
        and CAUSES.index(rust[1]) > CAUSES.index(rego[1])
    )


if os.environ.get("MATRIX_FACTS_RUST"):
    pairs = sweep.load_pairs(os.environ["MATRIX_FACTS_PAIRS"])
    rego = read(os.environ["MATRIX_FACTS_REGO"])
    head = read(os.environ["MATRIX_FACTS_RUST"])
    before = read(os.environ["MATRIX_FACTS_BASE_RUST"])
else:
    pairs = sweep.load_pairs(os.environ["MATRIX_FACTS_PAIRS"])
    for i, pair in enumerate(pairs):
        pair["id"] = str(i)
    ids = [pair["id"] for pair in pairs]
    subprocess.run([os.path.join(root, ".github", "build-ergo.sh")], cwd=root, check=True, stdout=subprocess.DEVNULL)
    sweep.write_cells(pairs)
    rego = sweep.run_rego(os.environ.get("OPA", "opa"), ids)
    head = run_with_path(os.environ["MATRIX_FACTS_HEAD_BIN"], ids)
    with open(os.path.join(os.environ["MATRIX_FACTS_BASE_TREE"], "engines", "rego", "src", "shared", "basics.rego")) as handle:
        base_spec = re.search(r'^_spec := "([^"]*)"', handle.read(), re.M).group(1)
    for pair in pairs:
        pair["policy"] = dict(pair["policy"], ergo_spec=base_spec)
    sweep.write_cells(pairs)
    before = run_with_path(os.environ["MATRIX_FACTS_BASE_BIN"], ids)

base = os.environ["MATRIX_FACTS_BASE_NAME"]
worse = []
lowest = []
for i, pair in enumerate(pairs):
    g, b, h = verdicts(rego[i]), verdicts(before[i]), verdicts(head[i])
    for key in sorted(set(g) | set(b) | set(h)):
        gv, bv, hv = g.get(key), b.get(key), h.get(key)
        if bv == gv and hv != gv:
            worse.append(f"- {pair['name']}: {key}: base {show(bv)}, working tree {show(hv)}, Rego {show(gv)}")
        if lower(hv, gv):
            old = " (already on base)" if lower(bv, gv) else ""
            lowest.append(f"- {pair['name']}: {key}: Rust {show(hv)}, Rego {show(gv)}{old}")

print(f"## Matrix {os.environ['MATRIX_FACTS_NAME']}")
print()
if worse:
    print(f"PAIRS WORSE THAN {base}: {len(worse)}")
    print()
    print("\n".join(worse))
else:
    print(f"No pair is worse than {base}.")
print()
if lowest:
    print(f"RUST CAUSES LOWER THAN REGO'S: {len(lowest)}")
    print()
    print("\n".join(lowest))
else:
    print("No Rust cause is lower than Rego's.")
PY
