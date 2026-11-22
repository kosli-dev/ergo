#!/bin/sh
set -eu
if [ $# -gt 1 ]; then
  echo "usage: pairs-facts.sh [BASE]" >&2
  exit 2
fi
base=${1:-origin/main}
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
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
export PAIRS_FACTS_BASE_NAME=$base

if [ -z "${PAIRS_FACTS_RUST:-}" ]; then
  export ASDF_RUST_VERSION=1.99.0
  tree=$work/base
  git -C "$root" worktree add --detach "$tree" "$base" > /dev/null 2>&1
  build() {
    find "$1/engines/rust" -name '*.rs' -exec touch {} +
    (cd "$1/engines/rust" && CARGO_TARGET_DIR=$2 cargo build -q -j 4 -p ergo-policy-cli)
  }
  build "$tree" "$work/base-target"
  build "$root" "$work/head-target"
  export PAIRS_FACTS_BASE_BIN=$work/base-target/debug
  export PAIRS_FACTS_HEAD_BIN=$work/head-target/debug
  export PAIRS_FACTS_BASE_TREE=$tree
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


def read(path):
    with open(path) as handle:
        return json.load(handle)


def run_with_path(directory, ids, tree):
    saved = os.environ["PATH"]
    os.environ["PATH"] = directory + os.pathsep + saved
    try:
        return sweep.run_rust("sh -s", ids, tree)[1]
    finally:
        os.environ["PATH"] = saved


def first_message(report):
    if "error" in report:
        return "error: " + str(report["error"])
    results = report.get("results", [])
    failed = [r for r in results if not r.get("passed")]
    return str((failed or results or [{}])[0].get("message", "no message"))


def window(text, other):
    same = 0
    while same < min(len(text), len(other)) and text[same] == other[same]:
        same += 1
    start = max(0, same - 30)
    shown = text[start:start + 80]
    return ("..." if start else "") + shown + ("..." if start + 80 < len(text) else "")


def change(old, new):
    old, new = first_message(old), first_message(new)
    return f"{window(old, new)} -> {window(new, old)}"


def plural(count, one, many):
    return one if count == 1 else many


if os.environ.get("PAIRS_FACTS_RUST"):
    pairs = sweep.load_pairs(os.environ["PAIRS_FACTS_PAIRS"])
    rego = read(os.environ["PAIRS_FACTS_REGO"])
    head = read(os.environ["PAIRS_FACTS_RUST"])
    before = read(os.environ["PAIRS_FACTS_BASE_RUST"])
else:
    pairs = sweep.load_pairs(os.path.join(root, ".github", "sweep-pairs.json"))
    for i, pair in enumerate(pairs):
        pair["id"] = str(i)
    ids = [pair["id"] for pair in pairs]
    subprocess.run([os.path.join(root, ".github", "build-ergo.sh")], cwd=root, check=True, stdout=subprocess.DEVNULL)
    sweep.write_cells(pairs)
    rego = sweep.run_rego(os.environ.get("OPA", "opa"), ids)
    head = run_with_path(os.environ["PAIRS_FACTS_HEAD_BIN"], ids, root)
    with open(os.path.join(os.environ["PAIRS_FACTS_BASE_TREE"], "engines", "rego", "src", "shared", "basics.rego")) as handle:
        base_spec = re.search(r'^_spec := "([^"]*)"', handle.read(), re.M).group(1)
    for pair in pairs:
        pair["policy"] = dict(pair["policy"], ergo_spec=base_spec)
    sweep.write_cells(pairs)
    before = run_with_path(os.environ["PAIRS_FACTS_BASE_BIN"], ids, os.environ["PAIRS_FACTS_BASE_TREE"])

base = os.environ["PAIRS_FACTS_BASE_NAME"]
total = len(pairs)
differ = sum(1 for i in range(total) if sweep.differences(rego[i], head[i]))
wants = [i for i, p in enumerate(pairs) if p["want"] is not None]
rego_says = sum(1 for i in wants if sweep.says(rego[i], pairs[i]["want"]))
rust_says = sum(1 for i in wants if sweep.says(head[i], pairs[i]["want"]))

moved = []
away = []
for i, pair in enumerate(pairs):
    if before[i] == head[i]:
        continue
    now_equal = not sweep.differences(rego[i], head[i])
    was_equal = not sweep.differences(rego[i], before[i])
    line = f"{pair['name']}: {change(before[i], head[i])} (Rust equals Rego: {'yes' if now_equal else 'no'}"
    lost_want = False
    if pair["want"] is not None:
        now_says = sweep.says(head[i], pair["want"])
        was_says = sweep.says(before[i], pair["want"])
        lost_want = was_says and not now_says
        line += f", says want: {'yes' if now_says else 'no'}"
    moved.append(line + ")")
    if (was_equal and not now_equal) or lost_want:
        away.append(f"{pair['name']}: {change(before[i], head[i])}")

if away:
    print(f"PAIRS THAT MOVED AWAY FROM REGO OR FROM THEIR WANT: {len(away)}")
    print()
    for line in away:
        print(f"- {line}")
    print()
print("## Pairs")
print()
print(f"{differ} of {total} pairs differ between Rego and Rust.")
print()
print(f"Pairs that say their want message: Rego {rego_says} of {len(wants)}, Rust {rust_says} of {len(wants)}.")
print()
if moved:
    print(f"Rust output changed on {len(moved)} {plural(len(moved), 'pair', 'pairs')} between {base} and the working tree.")
    print()
    for line in moved:
        print(f"- {line}")
else:
    print(f"No pair's Rust output changed between {base} and the working tree.")
PY
