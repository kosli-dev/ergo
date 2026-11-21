import glob
import json
import os
import re
import sys

USAGE = """usage: .github/rules.sh [--any] WORD...
       .github/rules.sh --name RULE

Always check the spec rules first, before a question or a decision. This prints the rules of spec/semantics.md and spec/syntax.md
whose name or text contains every WORD (any of them with --any), with how many spec
cases cite each. --name prints one rule in full and the cases that cite it."""

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = os.environ.get("RULES_SPEC_DIR") or os.path.join(root, "spec")


def read_rules():
    rules = {}
    for file in ["semantics.md", "syntax.md"]:
        path = os.path.join(spec, file)
        if not os.path.exists(path):
            continue
        heading = ""
        lines = open(path).read().split("\n")
        for i, line in enumerate(lines):
            h = re.match(r"^#+\s+(.*)$", line)
            if h:
                heading = h.group(1).strip()
                continue
            m = re.match(r"^\*\*\[([a-z_.]+)\]\*\*\s*(.*)$", line)
            if m:
                body = [m.group(2)]
                for rest in lines[i + 1:]:
                    if rest.strip() == "" or rest.startswith("#"):
                        break
                    body.append(rest)
                rules[m.group(1)] = {"file": file, "heading": heading, "text": " ".join(body).strip()}
    return rules


def read_cases():
    cited = {}
    for path in sorted(glob.glob(os.path.join(spec, "cases", "*", "cases.json"))):
        folder = os.path.basename(os.path.dirname(path))
        for group in json.load(open(path)):
            for case in group["cases"]:
                for name in case["rules"]:
                    cited.setdefault(name, []).append((folder, group["description"], case["description"]))
    return cited


def first_sentences(text, n=2):
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z`$])", text)
    return " ".join(parts[:n])


def has_word(word, haystack):
    return re.search(r"(?<![A-Za-z0-9_])" + re.escape(word) + r"(?![A-Za-z0-9_])", haystack, re.I) is not None


def squash(text):
    return re.sub(r"[-_ ]+", " ", text)


def has_any_spelling(word, haystack):
    return has_word(word, haystack) or has_word(squash(word), squash(haystack))


def main(argv):
    any_mode = False
    if argv and argv[0] == "--any":
        any_mode = True
        argv = argv[1:]
    if not argv or argv[0] in ("-h", "--help"):
        print(USAGE, file=sys.stderr)
        return 2
    rules = read_rules()
    cited = read_cases()
    if argv[0] == "--name":
        if len(argv) != 2 or argv[1] not in rules:
            print("no rule named: " + " ".join(argv[1:]), file=sys.stderr)
            return 1
        name = argv[1]
        rule = rules[name]
        print(f"{name}  ({rule['file']}, {rule['heading']})")
        print(rule["text"])
        cases = cited.get(name, [])
        print(f"cited by {len(cases)} cases:")
        for folder, group, case in cases:
            print(f"  {folder}: {group} / {case}")
        return 0
    found = []
    for name, rule in rules.items():
        searchable = name.replace(".", " ").replace("_", " ") + " " + name + " " + rule["text"]
        matched = sum(1 for w in argv if has_any_spelling(w, searchable))
        if matched == len(argv) or (any_mode and matched > 0):
            found.append((-matched, name))
    if not found:
        print("no rule contains: " + " ".join(argv))
        return 1
    for _, name in sorted(found):
        rule = rules[name]
        cases = cited.get(name, [])
        folders = []
        for folder, _, _ in cases:
            if folder not in folders:
                folders.append(folder)
        shown = ", ".join(folders[:5]) + (", ..." if len(folders) > 5 else "")
        print(f"{name}  ({rule['file']}, {rule['heading']})")
        print("  " + first_sentences(rule["text"]))
        print(f"  cited by {len(cases)} cases" + (f": {shown}" if folders else ""))
        print()
    return 0


try:
    status = main(sys.argv[1:])
    sys.stdout.flush()
except BrokenPipeError:
    os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
    status = 0
sys.exit(status)
