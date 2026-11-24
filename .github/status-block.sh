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


def counts(text):
    found = {}
    for number in "123":
        match = re.search(r"^(?:- )?type %s \([^)]*\): (\d+)$" % number, text, re.M)
        found[number] = match.group(1) if match else "?"
    return found


def listed(text, heading):
    found = re.search(r"^%s:\n\n((?:- .*\n?)+)" % heading, text, re.M)
    if not found:
        return []
    return [line[2:] for line in found.group(1).strip().split("\n")]


def table(header, rows):
    widths = [max(len(str(row[i])) for row in [header] + rows) for i in range(len(header))]

    def line(row):
        return "| " + " | ".join(str(cell).ljust(widths[i]) for i, cell in enumerate(row)) + " |"

    return [line(header), "| " + " | ".join("-" * width for width in widths) + " |"] + [line(row) for row in rows] + [""]


def sections(text):
    parts = re.split(r"^## ", text, flags=re.M)
    return {part.split("\n", 1)[0]: part for part in parts[1:]}


def engine(prefix, text):
    for title, body in sections(text).items():
        if title.startswith(prefix):
            count = re.search(r": (\d+)", title)
            return {"known": count.group(1) if count else "?", "body": body}
    return None


def families(body):
    found = []
    for name, a, b, c in re.findall(r"^  - (\S+): (\d+) / (\d+) / (\d+)$", body, re.M):
        found.append((int(a) + int(b) + int(c), name, a, b, c))
    found.sort(key=lambda f: (-f[0], f[1]))
    return found


def sweep(text, noun):
    found = re.search(r"^(\d+) of (\d+) %s differ$" % noun, text, re.M)
    return {"known": "%s of %s" % found.groups() if found else "not found", "body": text}


def open_entries(text):
    block = ""
    for part in re.split(r"^### ", text, flags=re.M):
        if part.startswith("Branch"):
            block = part
    found = re.search(r"- entries in `spec/OPEN.md`:\n((?:  - .*\n?)+)", block)
    if not found:
        return None
    rows = []
    for line in found.group(1).rstrip("\n").split("\n"):
        name, count = line[4:].rsplit(": ", 1)
        rows.append([name, count])
    return rows


def clusters(cells):
    tally = {}
    for cell in cells:
        name = cell.split(" | ")[0]
        tally[name] = tally.get(name, 0) + 1
    return sorted(tally.items(), key=lambda t: (-t[1], t[0]))


def bullets(items):
    return ["- " + item for item in items] if items else ["- none"]


date = os.environ.get("STATUS_DATE") or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
types_text = read(types)
grid_text = read(grid)
pairs_text = read(pairs)
rust = engine("Rust engine", types_text)
rego = engine("ergo.rego", types_text)
grid_found = sweep(grid_text, "cells")
pairs_found = sweep(pairs_text, "pairs")

rows = []
for label, found in (
    ("Rust engine against the cases", rust),
    ("ergo.rego against the cases", rego),
    ("Engine against engine, grid", grid_found),
    ("Engine against engine, fixed pairs", pairs_found),
):
    if found is None:
        rows.append([label, "not found", "?", "?", "?"])
        continue
    kinds = counts(found["body"])
    rows.append([label, found["known"], kinds["1"], kinds["2"], kinds["3"]])

lines = ["### Status on %s (UTC)" % date, "", "Nightly run: %s" % result, ""]
lines += ["**What differs**", ""]
lines += table(["Compared", "Known, or cells that differ of all", "Type 1", "Type 2", "Type 3"], rows)

lines += ["**Biggest families, Rust engine against the cases**", ""]
family_rows = [[name, a, b, c, total] for total, name, a, b, c in families(rust["body"] if rust else "")[:8]]
lines += table(["Family", "Type 1", "Type 2", "Type 3", "Total"], family_rows) if family_rows else ["- not found", ""]

lines += ["**Entries in spec/OPEN.md**", ""]
entries = open_entries(read(facts))
lines += table(["Section", "Entries"], entries) if entries else ["- not found", ""]

type_1 = []
for label, found in (("Rust engine", rust), ("ergo.rego", rego)):
    type_1 += ["%s: %s" % (label, i) for i in listed(found["body"], "Type 1 cases") ] if found else []
type_1 += ["grid: " + i for i in listed(grid_text, "Type 1 cells")]
type_1 += ["pairs: " + i for i in listed(pairs_text, "Type 1 cells")]
lines += ["**Type 1 cells**", ""] + bullets(type_1) + [""]

lines += ["**Type 2 to fix first**", ""]
lines += ["Rust engine against the cases:", ""] + bullets(listed(rust["body"], "Type 2 cases") if rust else []) + [""]
lines += ["ergo.rego against the cases:", ""] + bullets(listed(rego["body"], "Type 2 cases") if rego else []) + [""]
top = clusters(listed(grid_text, "Type 2 cells"))[:5]
lines += ["Grid, top 5 clusters of type 2 cells:", ""] + bullets(["%s: %d" % (name, n) for name, n in top])
print("\n".join(lines).rstrip("\n"))
PY
