#!/bin/sh
set -eu
if [ $# -gt 1 ]; then
  echo "usage: sync-facts.sh [BASE]" >&2
  exit 2
fi
base=${1:-origin/main}
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
if ! git -C "$root" rev-parse --verify --quiet "$base^{commit}" > /dev/null; then
  echo "sync-facts.sh: $base is not a commit" >&2
  exit 2
fi
exec python3 -I - "$root" "$base" << 'PY'
import json
import subprocess
import sys

root, base = sys.argv[1], sys.argv[2]
SECTIONS = [
    "Where ergo.rego and the Rust engine differ",
    "Where both engines differ from a rule",
    "Differs from the general rules",
    "Differs from the decisions",
]


def branch_text(path):
    try:
        with open(root + "/" + path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def base_text(path):
    run = subprocess.run(["git", "-C", root, "show", base + ":" + path], capture_output=True, text=True)
    return run.stdout if run.returncode == 0 else None


def branch_case_files():
    import glob
    return sorted(path[len(root) + 1:] for path in glob.glob(root + "/spec/cases/*/cases.json"))


def count_cases(read, listing):
    total = 0
    for path in listing:
        text = read(path)
        if text is None:
            continue
        for group in json.loads(text):
            total += len(group["cases"])
    return total


def base_case_files():
    run = subprocess.run(["git", "-C", root, "ls-tree", "-r", "--name-only", base, "spec/cases/"], capture_output=True, text=True)
    return sorted(p for p in run.stdout.split("\n") if p.endswith("/cases.json"))


def families(text):
    counts = {}
    for line in text.split("\n"):
        if line.strip():
            family = line.split(" / ")[0]
            counts[family] = counts.get(family, 0) + 1
    return counts


def known_differences(text):
    if text is None:
        return None
    rows = 0
    inside = False
    for line in text.split("\n"):
        if line.startswith("known_differences := {"):
            inside = True
        elif inside and line.startswith("}"):
            break
        elif inside and line.startswith("\t\""):
            rows += 1
    return rows if inside or rows else None


def open_sections(text):
    result = {}
    if text is None:
        return {name: None for name in SECTIONS}
    current = None
    for line in text.split("\n"):
        if line.startswith("## "):
            current = line[3:].strip()
            if current in SECTIONS:
                result[current] = 0
        elif current in result and line.startswith("- **"):
            result[current] += 1
    return {name: result.get(name) for name in SECTIONS}


def facts(read, case_files):
    known = read("engines/rust/known-failures.txt")
    known_lines = known.rstrip("\n") if known else ""
    by_family = families(known_lines)
    total = count_cases(read, case_files)
    return {
        "known": sum(by_family.values()),
        "families": by_family,
        "differences": known_differences(read("engines/rego/tests/spec_test.rego")),
        "sections": open_sections(read("spec/OPEN.md")),
        "cases": total,
    }


def share(f):
    if f["cases"] == 0:
        return "no cases found"
    return "%.1f%%" % (100.0 * f["known"] / f["cases"])


def shown(value, found="not found"):
    return found if value is None else str(value)


def block(title, f):
    out = ["### " + title, ""]
    out.append("- lines in `engines/rust/known-failures.txt`: %d" % f["known"])
    for family in sorted(f["families"]):
        out.append("  - %s: %d" % (family, f["families"][family]))
    out.append("- `known_differences` rows in `engines/rego/tests/spec_test.rego`: " + shown(f["differences"], "not found"))
    out.append("- entries in `spec/OPEN.md`:")
    for name in SECTIONS:
        out.append("  - %s: %s" % (name, shown(f["sections"][name], "section not found")))
    out.append("- spec cases: %d, failing in the Rust engine: %s" % (f["cases"], share(f)))
    out.append("")
    return out


def delta(a, b):
    if a is None or b is None:
        return "n/a"
    return "%+d" % (b - a) if b != a else "0"


def change(old, new):
    out = ["### Change against " + base, ""]
    out.append("- known failures: %s" % delta(old["known"], new["known"]))
    for family in sorted(set(old["families"]) | set(new["families"])):
        d = new["families"].get(family, 0) - old["families"].get(family, 0)
        if d:
            out.append("  - %s: %+d" % (family, d))
    out.append("- `known_differences` rows: " + delta(old["differences"], new["differences"]))
    for name in SECTIONS:
        out.append("- %s: %s" % (name, delta(old["sections"][name], new["sections"][name])))
    out.append("- spec cases: %s" % delta(old["cases"], new["cases"]))
    out.append("- failing share: %s to %s" % (share(old), share(new)))
    out.append("")
    return out


new = facts(branch_text, branch_case_files())
old = facts(base_text, base_case_files())
lines = ["## How far the engines are from the spec", ""]
lines += block("Branch", new) + block(base, old) + change(old, new)
print("\n".join(lines).rstrip("\n"))
PY
