#!/bin/sh
set -eu
if [ $# -lt 2 ]; then
  echo "usage: matrix-facts.sh BASE NAME..." >&2
  exit 2
fi
base=$1
shift
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
for name in "$@"; do
  if [ -z "${MATRIX_FACTS_RUST:-}" ] && [ ! -f "$root/.github/matrix/$name.py" ]; then
    echo "no generator called $name in .github/matrix" >&2
    exit 2
  fi
done
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
fi

for name in "$@"; do
  export MATRIX_FACTS_NAME=$name
  if [ -z "${MATRIX_FACTS_RUST:-}" ]; then
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


def run_with_path(directory, ids, tree):
    saved = os.environ["PATH"]
    os.environ["PATH"] = directory + os.pathsep + saved
    try:
        return sweep.run_rust("sh -s", ids, tree)[1]
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


def rank(verdict):
    if verdict is None or len(verdict) != 2:
        return None
    if verdict[0]:
        return len(CAUSES)
    return CAUSES.index(verdict[1]) if verdict[1] in CAUSES else None


SPLIT = r"; |, and (?!\d+ more)"
MORE = re.compile(r"(and )?\d+ more")
PREFIX = re.compile(r"^(?:item \d+ of [^:;]+?: |[\w.$\[\]]+: )+")


def parts(text):
    return [part for part in re.split(SPLIT, text) if part and not MORE.fullmatch(part)]


def problems(row):
    found = set()

    def collect(node, path):
        if isinstance(node, dict):
            if node.get("kind") == "item" and node.get("name") and node["name"] not in path:
                path = path + (node["name"],)
            if isinstance(node.get("message"), str):
                for part in parts(node["message"]):
                    here = path
                    lead = PREFIX.match(part)
                    for named in re.findall(r"item \d+ of [^:;]+?(?=: )", lead.group(0) if lead else ""):
                        if named not in here:
                            here = here + (named,)
                    found.add((here, PREFIX.sub("", part)))
            for key, value in node.items():
                if key != "message":
                    collect(value, path)
        elif isinstance(node, list):
            for value in node:
                collect(value, path)

    collect(row.get("failures"), ())
    if not row.get("failures"):
        for part in parts(row.get("message") or ""):
            found.add(((), PREFIX.sub("", part)))
    return found


def names(row):
    found = set()

    def collect(node):
        if isinstance(node, dict):
            if node.get("name"):
                found.add(node["name"])
            for value in node.values():
                collect(value)
        elif isinstance(node, list):
            for value in node:
                collect(value)

    collect(row.get("failures"))
    return found


def cut(row):
    texts = []

    def collect(node):
        if isinstance(node, dict):
            if isinstance(node.get("message"), str):
                texts.append(node["message"])
            for value in node.values():
                collect(value)
        elif isinstance(node, list):
            for value in node:
                collect(value)

    collect(row)
    return any(re.search(r"(and )?\d+ more$", text) for text in texts)


def said(row):
    if row is None:
        return "none"
    return json.dumps(row.get("message") or "none")


def missing(base_row, head_row):
    if base_row is None or base_row.get("passed"):
        return []
    have = problems(head_row) if head_row is not None else set()
    truncated = head_row is not None and cut(head_row) and not any(name.startswith("item ") for name in names(head_row))
    lost = []
    for path, text in sorted(problems(base_row)):
        if any(said == text and (set(there) <= set(path) or set(path) <= set(there)) for there, said in have):
            continue
        if truncated:
            continue
        lost.append(f"{': '.join(path)}: {text}" if path else text)
    return lost


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
    head = run_with_path(os.environ["MATRIX_FACTS_HEAD_BIN"], ids, root)
    with open(os.path.join(os.environ["MATRIX_FACTS_BASE_TREE"], "engines", "rego", "src", "shared", "basics.rego")) as handle:
        base_spec = re.search(r'^_spec := "([^"]*)"', handle.read(), re.M).group(1)
    for pair in pairs:
        pair["policy"] = dict(pair["policy"], ergo_spec=base_spec)
    sweep.write_cells(pairs)
    before = run_with_path(os.environ["MATRIX_FACTS_BASE_BIN"], ids, os.environ["MATRIX_FACTS_BASE_TREE"])

base = os.environ["MATRIX_FACTS_BASE_NAME"]
down = []
less = []
up = []
for i, pair in enumerate(pairs):
    g, b, h = verdicts(rego[i]), verdicts(before[i]), verdicts(head[i])
    gr, br, hr = sweep.rows(rego[i]), sweep.rows(before[i]), sweep.rows(head[i])
    if "error" in before[i] and "error" not in head[i]:
        continue
    for key in sorted(set(g) | set(b) | set(h)):
        gv, bv, hv = g.get(key), b.get(key), h.get(key)
        if hv == bv and head[i] == before[i]:
            continue
        line = f"{pair['name']}: {key}: base {show(bv)}, working tree {show(hv)}, Rego {show(gv)}"
        old, new, ref = rank(bv), rank(hv), rank(gv)
        if hv == bv:
            old = new = None
        went_down = (old is not None and new is not None and new > old) or (ref is not None and new is not None and new > ref)
        went_up = (old is not None and new is not None and new < old) or (ref is not None and new is not None and new < ref)
        if went_down:
            already = old is not None and ref is not None and old > ref
            down.append(f"- {line}{' (already on base)' if already and new > ref else ''}")
        if went_up and not went_down:
            up.append(f"- {line}")
        if "error" in head[i] and "error" not in before[i]:
            less.append(f"- {pair['name']}: {key}: base {show(bv)}, working tree error")
            continue
        row_key = next((k for k in set(br) | set(hr) if f"{k[0]}/{k[1]}" == key), None)
        lost = missing(br.get(row_key), hr.get(row_key))
        if lost:
            quoted = ", ".join(json.dumps(part) for part in lost)
            less.append(f"- {pair['name']}: {key}: missing {quoted}; base says {said(br.get(row_key))}, working tree says {said(hr.get(row_key))}")


def section(title, lines):
    print(f"### {title}: {len(lines)}")
    print()
    print("\n".join(lines) if lines else "None.")


print(f"## Matrix {os.environ['MATRIX_FACTS_NAME']}")
print()
section("Cause went down (usually a bug)", down)
print()
section(f"Says less than {base} (usually a bug)", less)
print()
section("Cause went up (usually the rule problems.all_said; list for the Rego steps)", up)
PY
done
