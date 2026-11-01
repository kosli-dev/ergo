import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "../../../../.."))
STRING = r'"((?:[^"\\]|\\.)*)"'
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}
HIDDEN = "\u0085   　﻿"


def unrust(s):
    out, i = [], 0
    while i < len(s):
        if s[i] != "\\":
            out.append(s[i])
            i += 1
        elif s[i + 1] == "u":
            j = s.index("}", i)
            out.append(chr(int(s[i + 3 : j], 16)))
            i = j + 1
        else:
            out.append(ESCAPES[s[i + 1]])
            i += 2
    return "".join(out)


def rust(s):
    out = []
    for c in s:
        if c in '\\"':
            out.append("\\" + c)
        elif c == "\n":
            out.append("\\n")
        elif c == "\t":
            out.append("\\t")
        elif ord(c) < 32 or c in HIDDEN:
            out.append("\\u{%x}" % ord(c))
        else:
            out.append(c)
    return '"' + "".join(out) + '"'


def rust_list(items):
    return "&[" + ", ".join(rust(x) for x in items) + "]"


def strings(text):
    return [unrust(x) for x in re.findall(STRING, text)]


def table(src, name):
    start = src.index(f"pub const {name}:")
    return src[start : src.index("\n];", start) + 3]


def add(rows, kind, line, row):
    if line in rows[kind]:
        sys.exit(f"{line!r} is in the oracle twice")
    rows[kind][line] = row


def oracle():
    src = open(os.path.join(HERE, "checks.rs")).read()
    rows = {"checks": {}, "fors": {}}
    ok = r"\(\s*" + STRING + r",\s*" + STRING + r",\s*&\[(.*?)\],\s*&\[(.*?)\],?\s*\)"
    rejected = r"\(\s*" + STRING + r",\s*&\[(.*?)\],?\s*\)"
    for kind, prefix in [("checks", "CHECK"), ("fors", "FOR")]:
        for m in re.finditer(ok, table(src, prefix + "_OK"), re.S):
            add(rows, kind, unrust(m.group(1)), {
                "kind": "ok",
                "printed": unrust(m.group(2)),
                "plain": strings(m.group(3)),
                "aliases": strings(m.group(4)),
            })
        for suffix in ["_ERRORS", "_WRITTEN_WRONG"]:
            for m in re.finditer(rejected, table(src, prefix + suffix), re.S):
                add(rows, kind, unrust(m.group(1)), {"kind": "rejected", "problems": strings(m.group(2))})
    src = open(os.path.join(HERE, "mod.rs")).read()
    rows["froms"], rows["paths"] = {}, {}
    pair = r"\(\s*" + STRING + r",\s*" + STRING + r",?\s*\)"
    for m in re.finditer(pair, table(src, "FROM_OK"), re.S):
        add(rows, "froms", unrust(m.group(1)), {"kind": "ok", "printed": unrust(m.group(2))})
    for name in ["FROM_ERRORS", "FROM_WRITTEN_WRONG", "FROM_PARTIAL"]:
        for m in re.finditer(rejected, table(src, name), re.S):
            add(rows, "froms", unrust(m.group(1)), {"kind": "rejected", "problems": strings(m.group(2))})
    for m in re.finditer(pair, table(src, "PATH_OK"), re.S):
        add(rows, "paths", unrust(m.group(1)), {"kind": "ok", "printed": unrust(m.group(2))})
    for line in strings(table(src, "PATH_ERRORS").split("= &[", 1)[1]):
        add(rows, "paths", line, {"kind": "rejected"})
    return rows


def strings_in(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [s for x in value for s in strings_in(x)]
    return []


def collect(value, lines):
    if isinstance(value, dict):
        for key, inner in value.items():
            if key == "assert":
                lines["checks"].extend(strings_in(inner))
            elif key == "for":
                lines["fors"].extend(strings_in(inner))
            elif key in ("checks", "any_of") and isinstance(inner, dict):
                for item in inner.values():
                    lines["checks"].extend(strings_in(item))
            collect(inner, lines)
    elif isinstance(value, list):
        for item in value:
            collect(item, lines)


def string_of(value):
    return [value] if isinstance(value, str) else []


def subject_lines(subjects, lines):
    for subject in subjects.values():
        if not isinstance(subject, dict):
            continue
        lines["froms"].extend(string_of(subject.get("from")))
        lines["paths"].extend(string_of(subject.get("identified_by")))
        parts = subject.get("has")
        if not isinstance(parts, dict):
            continue
        for part in parts.values():
            lines["froms"].extend(string_of(part))
            lines["paths"].extend(string_of(part))
            if isinstance(part, dict):
                lines["froms"].extend(string_of(part.get("from")))
                lines["paths"].extend(string_of(part.get("from")))
                lines["paths"].extend(string_of(part.get("identified_by")))


def case_lines():
    lines = {"checks": [], "fors": [], "froms": [], "paths": []}
    folder = os.path.join(ROOT, "spec/cases")
    for topic in sorted(os.listdir(folder)):
        for group in json.load(open(os.path.join(folder, topic, "cases.json"))):
            if not isinstance(group["policy"], dict):
                continue
            collect(group["policy"], lines)
            subjects = group["policy"].get("subjects")
            if isinstance(subjects, dict):
                subject_lines(subjects, lines)
    return lines


def ergo_rego(opa, lines):
    query = [
        "eval", "-d", "engines/rego/ergo.rego", "-d", os.path.relpath(os.path.join(HERE, "oracle_test.rego"), ROOT),
        "-I", "--format", "json", "data.oracle.out",
    ]
    run = subprocess.run(opa + query, input=json.dumps(lines), capture_output=True, text=True, cwd=ROOT)
    if run.returncode:
        sys.exit(run.stderr)
    return json.loads(run.stdout)["result"][0]["expressions"][0]["value"]


def main():
    opa = sys.argv[1:] or ["opa"]
    want = oracle()
    cases = case_lines()
    lines = {k: sorted(set(want[k]) | set(cases[k])) for k in want}
    got = ergo_rego(opa, lines)
    differ = 0
    for kind in want:
        for line, row in want[kind].items():
            mine = {k: v for k, v in got[kind][line].items() if k != "unsupported"}
            if mine != row:
                differ += 1
                print(f"differs: {line!r}\n  oracle:   {row}\n  ergo.rego: {mine}")
    print(
        f"{len(want['checks'])} checks, {len(want['fors'])} for lines, {len(want['froms'])} from lines"
        f" and {len(want['paths'])} paths in the oracle, {differ} differ from ergo.rego"
    )
    for kind, prefix in [("checks", "CHECK"), ("fors", "FOR")]:
        for line in sorted(set(cases[kind]) - set(want[kind])):
            row = got[kind][line]
            if row["kind"] == "ok":
                print(f"{prefix}_OK: ({rust(line)}, {rust(row['printed'])}, {rust_list(row['plain'])}, {rust_list(row['aliases'])}),")
            else:
                print(f"{prefix}_ERRORS or {prefix}_WRITTEN_WRONG: ({rust(line)}, {rust_list(row['problems'])}),")
    for line in sorted(set(cases["froms"]) - set(want["froms"])):
        row = got["froms"][line]
        if row["kind"] == "ok":
            print(f"FROM_OK: ({rust(line)}, {rust(row['printed'])}),")
        else:
            print(f"FROM_ERRORS, FROM_WRITTEN_WRONG or FROM_PARTIAL: ({rust(line)}, {rust_list(row['problems'])}),")
    for line in sorted(set(cases["paths"]) - set(want["paths"])):
        row = got["paths"][line]
        if row["kind"] == "ok":
            print(f"PATH_OK: ({rust(line)}, {rust(row['printed'])}),")
        else:
            print(f"PATH_ERRORS: {rust(line)},")
    sys.exit(1 if differ else 0)


main()
