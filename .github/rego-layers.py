#!/usr/bin/env python3
import glob
import os
import re
import sys

ORDER = ["shared", "reading", "sentences", "policy", "checks", "lines", "messages", "report"]
KEYWORDS = {"else", "default", "import", "package", "if", "contains", "in", "some", "every", "not", "with", "as", "true", "false", "null", "input", "data"}
HEAD = re.compile(r"^(?:default\s+)?([A-Za-z_][A-Za-z0-9_]*)")
IDENT = re.compile(r"(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)")


def strip(line):
    line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    return re.sub(r"`[^`]*`", "``", line)


def read_parts(root):
    parts = []
    for path in sorted(glob.glob(os.path.join(root, "*", "*.rego"))):
        folder = os.path.basename(os.path.dirname(path))
        if folder not in ORDER:
            sys.exit(f"{path}: {folder} is not in the folder order")
        parts.append((path, folder))
    return parts


def split_rules(path):
    rules = []
    current = None
    for number, raw in enumerate(open(path).read().split("\n"), 1):
        if raw[:1] not in ("", " ", "\t", "}", ")", "]"):
            match = HEAD.match(raw)
            if match and match.group(1) not in ("else", "package", "import"):
                current = {"name": match.group(1), "line": number, "body": []}
                rules.append(current)
        if current is not None:
            current["body"].append((number, strip(raw)))
    return rules


def references(rule):
    found = []
    for number, text in rule["body"]:
        for match in IDENT.finditer(text):
            name = match.group(1)
            if name in KEYWORDS:
                continue
            before = text[: match.start()]
            if before.endswith(".") and not before.endswith("data.ergo."):
                continue
            found.append((number, name))
    return found


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "engines/rego/src"
    known_path = sys.argv[2] if len(sys.argv) > 2 else "engines/rego/layers-known.txt"
    folder_of = {}
    problems = []
    all_rules = []
    for path, folder in read_parts(root):
        for rule in split_rules(path):
            all_rules.append((path, folder, rule))
            seen = folder_of.setdefault(rule["name"], folder)
            if seen != folder:
                problems.append(f"{path}:{rule['line']} {rule['name']} is defined in {seen} and in {folder}")
    found = {}
    for path, folder, rule in all_rules:
        for number, name in references(rule):
            target = folder_of.get(name)
            if target is None or name == rule["name"]:
                continue
            if ORDER.index(target) > ORDER.index(folder):
                found.setdefault(f"{rule['name']} -> {name}", (f"{path}:{number}", folder, target))
    known = set()
    if os.path.exists(known_path):
        known = {line.strip() for line in open(known_path) if line.strip()}
    for key in sorted(set(found) - known):
        where, folder, target = found[key]
        problems.append(f"{where} {key} ({folder} -> {target})")
    for key in sorted(known - set(found)):
        problems.append(f"{known_path}: {key} is listed but no longer exists, remove it")
    pairs = {}
    for _, folder, target in found.values():
        pairs[(folder, target)] = pairs.get((folder, target), 0) + 1
    for (folder, target), count in sorted(pairs.items()):
        print(f"{folder} -> {target}: {count}")
    for line in problems:
        print(line)
    if problems:
        print(f"{len(problems)} problem(s). A rule may only call rules in its own folder or an earlier one: {', '.join(ORDER)}.")
        return 1
    print(f"ok: {len(found)} known backward calls")
    return 0


sys.exit(main())
