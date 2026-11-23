#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/diff-types.py
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT
root=$dir/root
dump=$dir/dump
mkdir -p "$root/spec/cases/t" "$root/engines/rust" "$root/engines/rego/tests" "$dump/t"

python3 -I - "$root" "$dump" << 'PY'
import json
import os
import sys

root, dump = sys.argv[1], sys.argv[2]


def row(check, passed, cause, name="x", value=1, subject="s1"):
    return {
        "requirement": "r",
        "subject": {"type": "thing", "id": subject},
        "check": check,
        "passed": passed,
        "cause": cause,
        "inputs": [{"name": name, "value": value, "locations": ["/x"]}],
    }


satisfied = row("c", True, "satisfied")
failed = row("c", False, "not equal")
scenarios = [
    ("passed differs", {"results": [satisfied]}, {"results": [failed], "compliant": False}),
    ("row missing", {"results": [satisfied]}, {"results": []}),
    ("row extra", {"results": [satisfied]}, {"results": [satisfied, row("d", True, "satisfied")]}),
    ("compliant differs", {"results": [satisfied], "compliant": True}, {"results": [satisfied], "compliant": False}),
    (
        "status differs",
        {"results": [satisfied], "status": {"r": "pass"}},
        {"results": [satisfied], "requirements": {"r": {"status": "fail"}}},
    ),
    ("cause differs", {"results": [failed]}, {"results": [row("c", False, "missing")]}),
    ("inputs differ", {"results": [satisfied]}, {"results": [row("c", True, "satisfied", name="y")]}),
    (
        "dollar row ignored",
        {"results": [satisfied]},
        {"results": [satisfied, row("$k", True, "satisfied")]},
    ),
    (
        "same number written differently",
        {"results": [row("c", True, "satisfied", value=1)]},
        {"results": [row("c", True, "satisfied", value=1.0)]},
    ),
    (
        "nested cause",
        {"results": [dict(satisfied, entries=[{"cause": "a"}])]},
        {"results": [dict(satisfied, entries=[{"cause": "b"}])]},
    ),
]
cases = []
index = []
for number, (description, want, report) in enumerate(scenarios, 1):
    case = {"description": description, "input": {}}
    case.update(want)
    cases.append(case)
    report = dict(report)
    report.setdefault("compliant", True)
    report.setdefault("requirements", {"r": {"status": "pass"}})
    with open(os.path.join(dump, "t", "%d.json" % number), "w") as f:
        json.dump(report, f)
    index.append("%d\tt / g / %s\n" % (number, description))
with open(os.path.join(dump, "t", "index.txt"), "w") as f:
    f.write("".join(index))
with open(os.path.join(root, "spec", "cases", "t", "cases.json"), "w") as f:
    json.dump([{"description": "g", "policy": {}, "cases": cases}], f)
with open(os.path.join(root, "engines", "rust", "known-failures.txt"), "w") as f:
    f.write("".join("t / g / %s\n" % s[0] for s in scenarios))
PY

printf 'package spec_test\n\nknown_differences := set()\n' > "$root/engines/rego/tests/spec_test.rego"

out=$dir/out
fail() {
  echo "diff-types_test: $1" >&2
  cat "$out" >&2
  exit 1
}

python3 "$script" --root "$root" --dump "$dump" > "$out" || fail "a run with a dump should exit 0"
grep -q "type 1 (verdict differs): 5" "$out" || fail "five verdict differences expected"
grep -q "type 2 (a row's cause differs): 1" "$out" || fail "one cause difference expected"
grep -q "type 3 (anything else): 4" "$out" || fail "four other differences expected"
grep -q "^- t / g / passed differs" "$out" || fail "type 1 list should name the case"
grep -q "^- t / g / cause differs" "$out" || fail "type 2 list should name the case"
grep -q "^- t / g / nested cause" "$out" && fail "a nested cause is type 3 and must not be listed"
grep -q "t: 5 / 1 / 4" "$out" || fail "the family line should count per type"
grep -q "known_differences.*: 0" "$out" || fail "an empty known_differences should say 0"

python3 "$script" --root "$root" --dump "$dump" --summary > "$out" || fail "summary should exit 0"
grep -q "type 1 (verdict differs): 5" "$out" || fail "summary should count type 1"
grep -q "^- t / g / passed differs" "$out" && fail "summary should not list cases"

if python3 "$script" --root "$root" --dump "$dump" --require-no-type-1 > "$out" 2>&1; then
  fail "--require-no-type-1 should exit non-zero when a type 1 is left"
fi

printf 't / g / cause differs\nt / g / inputs differ\n' > "$root/engines/rust/known-failures.txt"
python3 "$script" --root "$root" --dump "$dump" --require-no-type-1 > "$out" || fail "--require-no-type-1 should pass without type 1"
grep -q "type 1 (verdict differs): 0" "$out" || fail "no type 1 expected"

if python3 "$script" --bogus > "$out" 2>&1; then
  fail "a bad argument should exit non-zero"
fi
if python3 "$script" --root "$root" > "$out" 2>&1 --dump "$dir/missing"; then
  fail "a dump folder that doesn't exist should exit non-zero"
fi
echo "diff-types_test: ok"
