#!/bin/sh
set -eu
if [ $# -ne 5 ]; then
  echo "usage: status-block.sh RESULT GRID PAIRS TYPES FACTS" >&2
  exit 2
fi
exec python3 -I - "$@" << 'PY'
import datetime
import os
import re
import sys

result, grid, pairs, types, facts = sys.argv[1:6]


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def type_lines(text):
    return re.findall(r"^(?:- )?(type [123] \([^)]*\): \d+)$", text, re.M)


def sweep(label, text):
    found = re.search(r"^(\d+ of \d+ (?:cells|pairs) differ)$", text, re.M)
    out = ["**%s: %s**" % (label, found.group(1) if found else "not found")]
    out += ["- " + line for line in type_lines(text)]
    listed = re.search(r"^Type 1 cells:\n\n((?:- .*\n?)+)", text, re.M)
    if listed:
        out.append("- type 1 cells:")
        out += ["  " + line for line in listed.group(1).strip().split("\n")]
    return out + [""]


def sections(text):
    parts = re.split(r"^## ", text, flags=re.M)
    return {part.split("\n", 1)[0]: part for part in parts[1:]}


def engine(label, noun, text):
    out = []
    head = None
    for title, body in sections(text).items():
        if title.startswith(label[1]):
            head = (title, body)
    if head is None:
        return ["**%s: not found**" % label[0], ""]
    count = re.search(r": (\d+)$", head[0])
    out.append("**%s: %s %s**" % (label[0], count.group(1) if count else "?", noun))
    out += ["- " + line for line in type_lines(head[1])]
    families = []
    for name, a, b, c in re.findall(r"^  - (\S+): (\d+) / (\d+) / (\d+)$", head[1], re.M):
        families.append((int(a) + int(b) + int(c), name))
    families.sort(key=lambda f: (-f[0], f[1]))
    if families:
        out.append("- biggest families: " + ", ".join("%s %d" % (name, total) for total, name in families[:5]))
    return out + [""]


def open_entries(text):
    branch = re.split(r"^### ", text, flags=re.M)
    block = ""
    for part in branch:
        if part.startswith("Branch"):
            block = part
    found = re.search(r"- entries in `spec/OPEN.md`:\n((?:  - .*\n?)+)", block)
    out = ["**Entries in spec/OPEN.md**"]
    if not found:
        return out[:1] + ["- not found", ""]
    out += [line.replace("  - ", "- ", 1) for line in found.group(1).rstrip("\n").split("\n")]
    return out + [""]


date = os.environ.get("STATUS_DATE") or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
types_text = read(types)
lines = ["### Status on %s (UTC)" % date, "", "Nightly run: %s" % result, ""]
lines += engine(("Rust engine against the cases", "Rust engine"), "known failures", types_text)
lines += engine(("ergo.rego against the cases", "ergo.rego"), "known differences", types_text)
lines += sweep("Engine against engine, grid", read(grid))
lines += sweep("Engine against engine, fixed pairs", read(pairs))
lines += open_entries(read(facts))
print("\n".join(lines).rstrip("\n"))
PY
