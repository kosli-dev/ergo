#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from decimal import Decimal

TYPES = [
    (1, "type 1 (verdict differs)"),
    (2, "type 2 (a row's cause differs)"),
    (3, "type 3 (anything else)"),
]


def norm(value):
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return value
    if isinstance(value, Decimal):
        return {"$n": str(value.normalize())}
    if isinstance(value, list):
        return [norm(v) for v in value]
    return {k: norm(v) for k, v in value.items()}


def key_of(value):
    return json.dumps(norm(value), sort_keys=True)


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.loads(f.read(), parse_float=Decimal, parse_int=Decimal)


def spec_version(root):
    path = os.path.join(root, "engines", "rust", "engine", "src", "policy.rs")
    try:
        with open(path, encoding="utf-8") as f:
            found = re.search(r'pub const SPEC: &str = "([^"]*)"', f.read())
    except OSError:
        return None
    return found.group(1) if found else None


def load_cases(root):
    version = spec_version(root)
    base = os.path.join(root, "spec", "cases")
    cases = {}
    for topic in sorted(os.listdir(base)):
        path = os.path.join(base, topic, "cases.json")
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as f:
            text = f.read()
        if version:
            text = text.replace("{{spec}}", version)
        number = 0
        for group in json.loads(text, parse_float=Decimal, parse_int=Decimal):
            for case in group["cases"]:
                number += 1
                cases["%s / %s / %s" % (topic, group["description"], case["description"])] = (topic, number, case)
    return cases


def read_dump(folder, cases):
    reports = {}
    for topic in sorted(os.listdir(folder)):
        index = os.path.join(folder, topic, "index.txt")
        if not os.path.isfile(index):
            continue
        with open(index, encoding="utf-8") as f:
            for line in f.read().split("\n"):
                if "\t" not in line:
                    continue
                number, case_id = line.split("\t", 1)
                path = os.path.join(folder, topic, number + ".json")
                if os.path.isfile(path):
                    reports[case_id] = read_json(path)
    return reports


def rows_of(case, report):
    want = case.get("results")
    if want is None:
        return None
    listed = {row.get("check") for row in want}
    actual = report.get("results")
    if not isinstance(actual, list):
        actual = []
    kept = [
        row
        for row in actual
        if not isinstance(row.get("check"), str)
        or not row["check"].startswith("$")
        or row["check"] == "$applies"
        or row["check"] in listed
    ]
    return want, kept


def grouped(rows):
    groups = {}
    for row in rows:
        key = (row.get("requirement"), key_of(row.get("subject")), row.get("check"))
        groups.setdefault(key, []).append(row)
    return groups


def requirement_status(report, name):
    requirement = (report.get("requirements") or {}).get(name)
    if not isinstance(requirement, dict) or "status" not in requirement:
        return ("missing",)
    return key_of(requirement["status"])


def verdict_differs(case, report):
    if "compliant" in case:
        if "compliant" not in report or key_of(case["compliant"]) != key_of(report["compliant"]):
            return True
    wanted = dict(case.get("status") or {})
    for name, fields in (case.get("requirements") or {}).items():
        if isinstance(fields, dict) and "status" in fields:
            wanted[name] = fields["status"]
    for name, status in wanted.items():
        if requirement_status(report, name) != key_of(status):
            return True
    rows = rows_of(case, report)
    if rows is None:
        return False
    want, actual = rows
    left, right = grouped(want), grouped(actual)
    if set(left) != set(right):
        return True
    for key, expected in left.items():
        found = right[key]
        if len(expected) != len(found):
            return True
        for a, b in zip(expected, found):
            if key_of(a.get("passed")) != key_of(b.get("passed")):
                return True
    return False


def cause_differs(case, report):
    rows = rows_of(case, report)
    if rows is None:
        return False
    left, right = grouped(rows[0]), grouped(rows[1])
    for key, expected in left.items():
        for a, b in zip(expected, right.get(key, [])):
            if key_of(a.get("cause")) != key_of(b.get("cause")):
                return True
    return False


def classify(case, report):
    if report is None:
        return 3
    if verdict_differs(case, report):
        return 1
    if cause_differs(case, report):
        return 2
    return 3


def sort_cases(ids, cases, reports):
    result = {1: [], 2: [], 3: []}
    missing = []
    for case_id in ids:
        found = cases.get(case_id)
        if found is None:
            missing.append(case_id)
            continue
        report = reports.get(case_id)
        if report is None:
            missing.append(case_id)
        result[classify(found[2], report)].append(case_id)
    return result, missing


def known_names(path):
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except OSError:
        return None
    return [line for line in (l.strip() for l in lines) if line]


def known_differences(path):
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except OSError:
        return None
    names = []
    inside = False
    for line in lines:
        if line.startswith("known_differences := {"):
            inside = True
        elif inside and line.startswith("}"):
            break
        elif inside and line.startswith('\t"'):
            names.append(json.loads(line.strip().rstrip(",")))
    return names


def run_rust(root, folder):
    env = dict(os.environ, ERGO_DUMP=folder)
    subprocess.run(
        ["cargo", "test", "--locked", "-q", "-p", "ergo-policy-engine", "--test", "cases", "every_case_passes_unless_known_to_fail"],
        cwd=os.path.join(root, "engines", "rust"),
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


QUERY = """{n: r |
    some n in input.names
    t := split(n, " / ")[0]
    some group in data.ergo_test._topic_cases(t)
    some c in group.cases
    concat(" / ", [t, group.description, c.description]) == n
    r := data.ergo_test._report(group, c)
}"""


def run_rego(root, names, cases, folder):
    dist = os.path.join(root, "dist")
    if not os.path.isfile(os.path.join(dist, "ergo.rego")):
        raise SystemExit("diff-types.py: dist/ergo.rego is missing, run .github/build-ergo.sh first")
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({"names": names}, f)
        path = f.name
    try:
        run = subprocess.run(
            ["opa", "eval", "--format", "json", "--input", path, "-d", os.path.join(root, "engines", "rego"), "-d", dist, "-d", "spec:" + os.path.join(root, "spec"), "--ignore", "src", QUERY],
            capture_output=True,
            text=True,
        )
    finally:
        os.unlink(path)
    if run.returncode != 0:
        raise SystemExit("diff-types.py: opa failed: " + run.stderr.strip())
    reports = json.loads(run.stdout)["result"][0]["expressions"][0]["value"]
    for name, report in reports.items():
        topic, number, _ = cases[name]
        os.makedirs(os.path.join(folder, topic), exist_ok=True)
        with open(os.path.join(folder, topic, "%d.json" % number), "w", encoding="utf-8") as f:
            json.dump(report, f)
        with open(os.path.join(folder, topic, "index.txt"), "a", encoding="utf-8") as f:
            f.write("%d\t%s\n" % (number, name))


def section(title, ids, sorted_ids, missing, summary):
    out = ["## " + title, ""]
    for number, label in TYPES:
        out.append("- %s: %d" % (label, len(sorted_ids[number])))
    families = {}
    for number in sorted_ids:
        for case_id in sorted_ids[number]:
            families.setdefault(case_id.split(" / ")[0], {1: 0, 2: 0, 3: 0})[number] += 1
    if families:
        out.append("- by family (type 1 / type 2 / type 3):")
        for family in sorted(families):
            counts = families[family]
            out.append("  - %s: %d / %d / %d" % (family, counts[1], counts[2], counts[3]))
    if missing:
        out.append("- no report to compare for %d case(s), counted as type 3" % len(missing))
    if not summary:
        for number in (1, 2):
            if sorted_ids[number]:
                out.append("")
                out.append("%s cases:" % ("Type %d" % number))
                out.append("")
                out += ["- " + case_id for case_id in sorted(sorted_ids[number])]
    out.append("")
    return out


def main():
    parser = argparse.ArgumentParser(prog="diff-types.py")
    parser.add_argument("--root")
    parser.add_argument("--dump")
    parser.add_argument("--rego", action="store_true")
    parser.add_argument("--rego-dump")
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--require-no-type-1", action="store_true")
    args = parser.parse_args()
    root = args.root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for folder in (args.dump, args.rego_dump):
        if folder is not None and not os.path.isdir(folder):
            parser.error("%s is not a folder" % folder)
    cases = load_cases(root)
    temporary = []
    out = []
    type_1 = False

    dump = args.dump
    known = known_names(os.path.join(root, "engines", "rust", "known-failures.txt"))
    if known is None:
        known = []
    if dump is None:
        dump = tempfile.mkdtemp()
        temporary.append(dump)
        run_rust(root, dump)
    reports = read_dump(dump, cases)
    sorted_ids, missing = sort_cases(known, cases, reports)
    type_1 = type_1 or bool(sorted_ids[1])
    out += section("Rust engine: known failures: %d" % len(known), known, sorted_ids, missing, args.summary)

    names = known_differences(os.path.join(root, "engines", "rego", "tests", "spec_test.rego"))
    if names is None:
        out += ["## ergo.rego: known_differences rows: not found", ""]
    elif names and not args.rego and args.rego_dump is None:
        out += ["## ergo.rego: known_differences rows: %d, not classified (pass --rego)" % len(names), ""]
    else:
        rego_dump = args.rego_dump
        if rego_dump is None and names:
            rego_dump = tempfile.mkdtemp()
            temporary.append(rego_dump)
            run_rego(root, names, cases, rego_dump)
        rego_reports = read_dump(rego_dump, cases) if rego_dump else {}
        sorted_ids, missing = sort_cases(names, cases, rego_reports)
        type_1 = type_1 or bool(sorted_ids[1])
        out += section("ergo.rego: known_differences rows: %d" % len(names), names, sorted_ids, missing, args.summary)

    for folder in temporary:
        shutil.rmtree(folder, ignore_errors=True)
    print("\n".join(out).rstrip("\n"))
    if args.require_no_type_1 and type_1:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
